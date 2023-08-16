#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
. /usr/share/beakerlib/beakerlib.sh || exit 1

[ -n "$DOCKERFILE_AGENT" ] || DOCKERFILE_AGENT=Dockerfile.agent
[ -n "$DOCKERFILE_SYSTEMD" ] || DOCKERFILE_SYSTEMD=Dockerfile.systemd

AGENT_ID="d432fbb3-d2f1-4a97-9ef7-75bd81c00000"
HOSTNAME=$( hostname )

rlJournalStart

    rlPhaseStartSetup "Do the keylime setup"

        rlRun 'rlImport "keylime-tests/test-helpers"'|| rlDie "cannot import /keylime-tests/test-helpers library"
        rlRun 'rlImport "certgen/certgen"' || rlDie "cannot import openssl/certgen library"
        rlAssertRpm keylime
        # update /etc/keylime.conf
        limeBackupConfig

        CONT_NETWORK_NAME="container_network"
        IP_ATTESTATION_SERVER="172.18.0.4"
        CONT_ATTESTATION_SERVER="attestation_container"
        IP_AGENT="172.18.0.12"
        #create network for containers
        rlRun "limeconCreateNetwork ${CONT_NETWORK_NAME} 172.18.0.0/16"

        # generate TLS certificates for all
        # we are going to use 4 certificates
        # verifier = webserver cert used for the verifier server
        # verifier-client = webclient cert used for the verifier's connection to registrar server
        # registrar = webserver cert used for the registrar server
        # tenant = webclient cert used (twice) by the tenant, running on AGENT server
        # btw, we could live with just one key instead of generating multiple keys.. but that's just how openssl/certgen works
        rlRun "x509KeyGen ca" 0 "Generating Root CA RSA key pair"
        rlRun "x509KeyGen intermediate-ca" 0 "Generating Intermediate CA RSA key pair"
        rlRun "x509KeyGen verifier" 0 "Generating verifier RSA key pair"
        rlRun "x509KeyGen verifier-client" 0 "Generating verifier-client RSA key pair"
        rlRun "x509KeyGen registrar" 0 "Generating registrar RSA key pair"
        rlRun "x509KeyGen tenant" 0 "Generating tenant RSA key pair"
        rlRun "x509SelfSign ca" 0 "Selfsigning Root CA certificate"
        rlRun "x509CertSign --CA ca --DN 'CN = ${HOSTNAME}' -t CA --subjectAltName 'IP = 127.0.0.1' intermediate-ca" 0 "Signing intermediate CA certificate with our Root CA key"
        rlRun "x509CertSign --CA intermediate-ca --DN 'CN = ${CONT_ATTESTATION_SERVER}' -t webserver --subjectAltName 'IP = ${IP_ATTESTATION_SERVER}' verifier" 0 "Signing verifier certificate with intermediate CA key"
        rlRun "x509CertSign --CA intermediate-ca --DN 'CN = ${CONT_ATTESTATION_SERVER}' -t webclient --subjectAltName 'IP = ${IP_ATTESTATION_SERVER}' verifier-client" 0 "Signing verifier-client certificate with intermediate CA key"
        rlRun "x509CertSign --CA intermediate-ca --DN 'CN = ${CONT_ATTESTATION_SERVER}' -t webserver --subjectAltName 'IP = ${IP_ATTESTATION_SERVER}' registrar" 0 "Signing registrar certificate with intermediate CA key"
        rlRun "x509CertSign --CA intermediate-ca --DN 'CN = ${HOSTNAME}' -t webclient --subjectAltName 'IP = 127.0.0.1' tenant" 0 "Signing tenant certificate with intermediate CA key"

        # copy verifier certificates to proper location
        CERTDIR=/var/lib/keylime/certs
        rlRun "mkdir -p $CERTDIR"
        rlRun "cp $(x509Cert ca) $CERTDIR/cacert.pem"
        rlRun "cp $(x509Cert intermediate-ca) $CERTDIR/intermediate-cacert.pem"
        rlRun "cp $(x509Cert verifier) $CERTDIR/verifier-cert.pem"
        rlRun "cp $(x509Key verifier) $CERTDIR/verifier-key.pem"
        rlRun "cp $(x509Cert verifier-client) $CERTDIR/verifier-client-cert.pem"
        rlRun "cp $(x509Key verifier-client) $CERTDIR/verifier-client-key.pem"
        rlRun "cp $(x509Cert registrar) $CERTDIR/registrar-cert.pem"
        rlRun "cp $(x509Key registrar) $CERTDIR/registrar-key.pem"
        rlRun "cp $(x509Cert tenant) $CERTDIR/tenant-cert.pem"
        rlRun "cp $(x509Key tenant) $CERTDIR/tenant-key.pem"
        # assign cert ownership to keylime user if it exists
        id keylime && rlRun "chown -R keylime:keylime $CERTDIR"

        #build verifier container
        TAG_ATTESTATION_SERVER="keylime_server_image"
        rlRun "limeconPrepareImage ${limeLibraryDir}/${DOCKERFILE_SYSTEMD} ${TAG_ATTESTATION_SERVER}"

        #mandatory for access agent containers to tpm
        rlRun "chmod o+rw /dev/tpmrm0"

        #run attestation server container
        rlRun "limeconRunSystemd $CONT_ATTESTATION_SERVER $TAG_ATTESTATION_SERVER $IP_ATTESTATION_SERVER $CONT_NETWORK_NAME '--hostname $CONT_ATTESTATION_SERVER --volume /var/lib/keylime/certs:/var/lib/keylime/certs:z'"

        rlRun "echo 172.18.0.4" > inventory
        rlRun "cat > playbook.yml <<EOF
- hosts: all
  vars:
    keylime_server_verifier_ip: \"{{ ansible_host }}\"
    keylime_server_registrar_ip: \"{{ ansible_host }}\"

    keylime_server_verifier_tls_dir: ${CERTDIR}
    keylime_server_verifier_trusted_server_ca: [ intermediate-cacert.pem, cacert.pem]
    keylime_server_verifier_trusted_client_ca: [ intermediate-cacert.pem, cacert.pem]
    keylime_server_verifier_server_cert: verifier-cert.pem
    keylime_server_verifier_server_key: verifier-key.pem
    keylime_server_verifier_client_cert: ${CERTDIR}/verifier-client-cert.pem
    keylime_server_verifier_client_key:  ${CERTDIR}/verifier-client-key.pem

    keylime_server_registrar_tls_dir: ${CERTDIR}
    keylime_server_registrar_trusted_client_ca: [ intermediate-cacert.pem, cacert.pem]
    keylime_server_registrar_server_cert: registrar-cert.pem
    keylime_server_registrar_server_key: registrar-key.pem


  roles:
    - rhel-system-roles.keylime_server
EOF"

        rlRun 'ansible-playbook -v --ssh-common-args "-o StrictHostKeychecking=no" -i inventory playbook.yml'
        sleep 5

        rlRun "limeWaitForVerifier 8881 $IP_ATTESTATION_SERVER"
        rlRun "limeWaitForRegistrar 8891 $IP_ATTESTATION_SERVER"

        # tenant
        rlRun "limeUpdateConf tenant require_ek_cert False"
        rlRun "limeUpdateConf tenant verifier_ip $IP_ATTESTATION_SERVER"
        rlRun "limeUpdateConf tenant registrar_ip $IP_ATTESTATION_SERVER"
        rlRun "limeUpdateConf tenant tls_dir $CERTDIR"
        rlRun "limeUpdateConf tenant trusted_server_ca '[\"intermediate-cacert.pem\", \"cacert.pem\"]'"
        rlRun "limeUpdateConf tenant client_cert tenant-cert.pem"
        rlRun "limeUpdateConf tenant client_key tenant-key.pem"

        rlRun "cp $CERTDIR/cacert.pem /var/lib/keylime/cv_ca"
        rlRun "cp -r /var/lib/keylime/cv_ca ."
        #setup of agent
        TAG_AGENT="agent_image"
        CONT_AGENT="agent_container"
        rlRun "limeconPrepareImage ${limeLibraryDir}/${DOCKERFILE_AGENT} ${TAG_AGENT}"
        rlRun "limeUpdateConf agent registrar_ip '\"$IP_ATTESTATION_SERVER\"'"
        rlRun "limeUpdateConf agent trusted_client_ca '\"/var/lib/keylime/cv_ca/cacert.pem\"'"
        rlRun "limeconPrepareAgentConfdir $AGENT_ID $IP_AGENT confdir_$CONT_AGENT"

        # create runtime policy
        TESTDIR=`limeCreateTestDir`
        rlRun "limeCreateTestPolicy ${TESTDIR}/*"

        rlRun "limeconRunAgent $CONT_AGENT $TAG_AGENT $IP_AGENT $CONT_NETWORK_NAME $PWD/confdir_$CONT_AGENT $TESTDIR"
        rlRun "limeWaitForAgentRegistration ${AGENT_ID}"
    rlPhaseEnd

    rlPhaseStartTest "Add keylime agent"
        rlRun -s "keylime_tenant -v $IP_ATTESTATION_SERVER  -t $IP_AGENT -u $AGENT_ID --runtime-policy policy.json -f /etc/hostname -c add"
        rlRun "limeWaitForAgentStatus $AGENT_ID 'Get Quote'"
        rlRun -s "keylime_tenant -c cvlist"
        rlAssertGrep "{'code': 200, 'status': 'Success', 'results': {'uuids':.*'$AGENT_ID'" $rlRun_LOG -E
    rlPhaseEnd

    rlPhaseStartCleanup "Do the keylime cleanup"
        limeconSubmitLogs
        rlRun "limeconStop $CONT_ATTESTATION_SERVER $CONT_AGENT"
        rlRun "limeconDeleteNetwork $CONT_NETWORK_NAME"
        #set tmp resource manager permission to default state
        rlRun "chmod o-rw /dev/tpmrm0"
        limeExtendNextExcludelist $TESTDIR
        limeSubmitCommonLogs
        limeClearData
        limeRestoreConfig
    rlPhaseEnd

rlJournalEnd

