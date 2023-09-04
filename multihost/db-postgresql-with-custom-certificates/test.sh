#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   runtest.sh of /keylime_server-role-tests/multihost/db-postgresql-with-custom-certificates
#   Description: Test basic keylime attestation scenario using multiple hosts and setting attestation server via keylime roles
#   Author: Patrik Koncity <pkoncity@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2023 Red Hat, Inc.
#
#   This program is free software: you can redistribute it and/or
#   modify it under the terms of the GNU General Public License as
#   published by the Free Software Foundation, either version 2 of
#   the License, or (at your option) any later version.
#
#   This program is distributed in the hope that it will be
#   useful, but WITHOUT ANY WARRANTY; without even the implied
#   warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
#   PURPOSE.  See the GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program. If not, see http://www.gnu.org/licenses/.
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

# Include Beaker environment
#. /usr/bin/rhts-environment.sh || exit 1
. /usr/share/beakerlib/beakerlib.sh || exit 1

# when manually troubleshooting multihost test in Restraint environment
# you may want to export XTRA variable to a unique number each team
# to make user that sync events have unique names and there are not
# collisions with former test runs

# define KEYLIME_SERVER_ANSIBLE_ROLE if not set already
# rhel-system-roles.keylime_server = legacy ansible role format
# redhat.rhel_system_roles.keylime_server = collection ansible role format
[ -z "${KEYLIME_SERVER_ANSIBLE_ROLE}" ] && KEYLIME_SERVER_ANSIBLE_ROLE="rhel-system-roles.keylime_server"

function assign_server_roles() {
    if [ -f ${TMT_TOPOLOGY_BASH} ]; then
        # assign roles based on tmt topology data
        cat ${TMT_TOPOLOGY_BASH}
        . ${TMT_TOPOLOGY_BASH}

        export ATTESTATION_SERVER=${TMT_GUESTS["attestation_server.hostname"]}
        export AGENT=${TMT_GUESTS["agent.hostname"]}
        export CONTROLLER=${TMT_GUESTS["controller.hostname"]}

    elif [ -n "$SERVERS" ]; then
        # assign roles using SERVERS and CLIENTS variables
        export ATTESTATION_SERVER=$( echo "$SERVERS $CLIENTS $CLIENTS" | awk '{ print $1 }')
        export AGENT=$( echo "$SERVERS $CLIENTS $CLIENTS" | awk '{ print $2 }')
        export CONTROLLER=$( echo "$SERVERS $CLIENTS $CLIENTS" | awk '{ print $3 }')
    fi

    MY_IP=$( hostname -I | awk '{ print $1 }' )
    [ -n "$ATTESTATION_SERVER" ] && export ATTESTATION_SERVER_IP=$( get_IP $ATTESTATION_SERVER )
    [ -n "$AGENT" ] && export AGENT_IP=$( get_IP ${AGENT} )
    [ -n "$CONTROLLER" ] && export CONTROLLER_IP=$( get_IP ${CONTROLLER} )
}

function get_IP() {
    if echo $1 | grep -E -q '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
        echo $1
    else
        host $1 | sed -n -e 's/.*has address //p' | head -n 1
    fi
}

Attestation_server() {
    rlPhaseStartSetup "Attestation server setup"
        AGENT_ID="d432fbb3-d2f1-4a97-9ef7-75bd81c00000"
        CERTDIR=/var/lib/keylime/certs
        # generate TLS certificates for all
        # we are going to use 4 certificates
        # verifier = webserver cert used for the verifier server
        # verifier-client = webclient cert used for the verifier's connection to registrar server
        # registrar = webserver cert used for the registrar server
        # tenant = webclient cert used (twice) by the tenant, running on AGENT server
        rlRun "x509KeyGen ca" 0 "Preparing RSA CA certificate"
        rlRun "x509KeyGen intermediate-ca" 0 "Generating Intermediate CA RSA key pair"
        rlRun "x509KeyGen verifier" 0 "Preparing RSA verifier certificate"
        rlRun "x509KeyGen verifier-client" 0 "Preparing RSA verifier-client certificate"
        rlRun "x509KeyGen registrar" 0 "Preparing RSA registrar certificate"
        rlRun "x509KeyGen tenant" 0 "Preparing RSA tenant certificate"
        rlRun "x509KeyGen agent" 0 "Preparing RSA agent certificate"
        rlRun "x509SelfSign ca" 0 "Selfsigning CA certificate"
        rlRun "x509CertSign --CA ca --DN 'CN = $ATTESTATION_SERVER' -t CA --subjectAltName 'IP = ${ATTESTATION_SERVER_IP}' intermediate-ca" 0 "Signing intermediate CA certificate with our Root CA key"
        rlRun "x509CertSign --CA ca --DN 'CN = $ATTESTATION_SERVER' -t webserver --subjectAltName 'IP = ${ATTESTATION_SERVER_IP}' verifier" 0 "Signing verifier certificate with our CA certificate"
        rlRun "x509CertSign --CA ca --DN 'CN = $ATTESTATION_SERVER' -t webclient --subjectAltName 'IP = ${ATTESTATION_SERVER_IP}' verifier-client" 0 "Signing verifier-client certificate with our CA certificate"
        rlRun "x509CertSign --CA ca --DN 'CN = $ATTESTATION_SERVER' -t webserver --subjectAltName 'IP = ${ATTESTATION_SERVER_IP}' registrar" 0 "Signing registrar certificate with our CA certificate"
        # remember, we are running tenant on attestation server
        rlRun "x509CertSign --CA ca --DN 'CN = ${ATTESTATION_SERVER}' -t webclient --subjectAltName 'IP = ${ATTESTATION_SERVER_IP}' tenant" 0 "Signing tenant certificate with our CA"
        rlRun "x509SelfSign --DN 'CN = ${AGENT}' -t webserver agent" 0 "Self-signing agent certificate"

        # copy verifier certificates to proper location
        rlRun "mkdir -p $CERTDIR"
        rlRun "cp $(x509Cert ca) $CERTDIR/cacert.pem"
        rlRun "cp $(x509Cert intermediate-ca) $CERTDIR/intermediate-cacert.pem"
        rlRun "cp $(x509Cert verifier) $CERTDIR/verifier-cert.pem"
        rlRun "cp $(x509Key verifier) $CERTDIR/verifier-key.pem"
        rlRun "cp $(x509Key verifier-client) $CERTDIR/verifier-client-key.pem"
        rlRun "cp $(x509Cert verifier-client) $CERTDIR/verifier-client-cert.pem"
        rlRun "cp $(x509Cert registrar) $CERTDIR/registrar-cert.pem"
        rlRun "cp $(x509Key registrar) $CERTDIR/registrar-key.pem"
        rlRun "cp $(x509Cert tenant) $CERTDIR/tenant-cert.pem"
        rlRun "cp $(x509Key tenant) $CERTDIR/tenant-key.pem"
        # assign cert ownership to keylime user if it exists
        id keylime && rlRun "chown -R keylime:keylime $CERTDIR"
        rlRun "mkdir -p /var/lib/keylime/cv_ca/"
        rlRun "cp $CERTDIR/cacert.pem /var/lib/keylime/cv_ca/"

        rlServiceStop postgresql
        rlRun "cat > setup.psql <<_EOF
create database verifierdb;
create user verifier with encrypted password 'fire';
grant all privileges on database verifierdb to verifier;
create database registrardb;
create user registrar with encrypted password 'regi';
grant all privileges on database registrardb to registrar;
\connect verifierdb;
grant all privileges on schema public to verifier;
\connect registrardb;
grant all privileges on schema public to registrar;
_EOF"

        rlRun "chmod a+x setup.psql"
        #need set up permission for running postgres
        rlRun "chmod a+x /tmp/tmp.*"
        rlFileBackup --clean --missing-ok /var/lib/pgsql /etc/postgresql-setup
        rlRun "rm -rf /var/lib/pgsql/data"
        rlRun "postgresql-setup --initdb --unit postgresql"
        # configure user authentication with md5 and pgsql listening address
        rlRun "sed -i \"s|^host.*all.*all.*127.0.0.1.*ident|host all all 0.0.0.0/0 md5|\" /var/lib/pgsql/data/pg_hba.conf"
        rlRun "sed -i \"s|^#listen_addresses.*|listen_addresses = '0.0.0.0'|\" /var/lib/pgsql/data/postgresql.conf"
        rlServiceStart postgresql
        sleep 3
        rlRun "sudo -u postgres psql -f setup.psql"
        rlRun "sync-set ATTESTATION_SERVER_GENERATE_CERTS_DONE"
        rlRun "sync-block AGENT_SSH_SETUP_DONE ${AGENT_IP}" 0 "Wait for start machine where will be agent."

        #copy cert to agent machine
        rlRun "scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/id_rsa_multihost $CERTDIR/cacert.pem root@$AGENT_IP:/var/lib/keylime"
        rlRun "sync-block ANSIBLE_SETUP_DONE ${CONTROLLER_IP}" 0 "Waiting for ansible setup of system roles."

        # tenant config
        rlRun "limeUpdateConf tenant require_ek_cert False"
        rlRun "limeUpdateConf tenant verifier_ip $ATTESTATION_SERVER_IP"
        rlRun "limeUpdateConf tenant registrar_ip $ATTESTATION_SERVER_IP"
        rlRun "limeUpdateConf tenant tls_dir $CERTDIR"
        rlRun "limeUpdateConf tenant trusted_server_ca '[\"cacert.pem\"]'"
        rlRun "limeUpdateConf tenant client_cert tenant-cert.pem"
        rlRun "limeUpdateConf tenant client_key tenant-key.pem"

        sleep 5
        rlRun "limeWaitForVerifier"
        rlRun "limeWaitForRegistrar"

        #confirm that verifier and registrar accessed and modified databases
        rlRun -s "sudo -u postgres psql -c 'SELECT datname FROM pg_database;'"
        rlAssertGrep "verifierdb" $rlRun_LOG
        rlAssertGrep "registrardb" $rlRun_LOG

        rlRun "sync-set ATTESTATION_SERVER_START"
        rlRun "sync-block AGENT_STARTS ${AGENT_IP}" 0 "Waiting for starting agent."
        rlRun "limeWaitForAgentRegistration ${AGENT_ID}"
    rlPhaseEnd

    rlPhaseStartTest "keylime attestation test: Add Agent"
        # register AGENT and confirm it has passed validation
        rlRun "cat > script.expect <<_EOF
set timeout 20
spawn keylime_tenant -v ${ATTESTATION_SERVER_IP} -t ${AGENT_IP} -u ${AGENT_ID} --runtime-policy /var/tmp/policy.json --include payload-${REVOCATION_SCRIPT_TYPE} --cert default -c add
expect \"Please enter the password to decrypt your keystore:\"
send \"keylime\n\"
expect eof
_EOF"
        rlRun "expect script.expect"
        rlRun "limeWaitForAgentStatus $AGENT_ID 'Get Quote'"
        rlRun -s "keylime_tenant -c cvlist"
        rlAssertGrep "{'code': 200, 'status': 'Success', 'results': {'uuids':.*'$AGENT_ID'" $rlRun_LOG -E
        rlRun "sync-set AGENT_ADD_DONE"
    rlPhaseEnd

    rlPhaseStartTest "Agent attestation test: Fail keylime agent"
        rlRun "sync-block AGENT_CORRUPTED ${AGENT_IP}" 0 "Waiting for the agent fail."
        rlRun "limeWaitForAgentStatus $AGENT_ID '(Failed|Invalid Quote)'"
        rlRun "sync-set AGENT_FAILED"
    rlPhaseEnd

    rlPhaseStartTest "Verifier test"
        # check that the AGENT failed verification
        rlAssertGrep "WARNING - File not found in allowlist: .*/keylime-bad-script.sh" $(limeVerifierLogfile) -E
        rlRun "cat $(limeVerifierLogfile)"
        AGENT_ID="d432fbb3-d2f1-4a97-9ef7-75bd81c00000"
        rlAssertGrep "WARNING - Agent $AGENT_ID failed, stopping polling" $(limeVerifierLogfile)
    rlPhaseEnd

    rlPhaseStartCleanup "Attestation server cleanup"
        rlRun "limeStopVerifier"
        rlRun "limeStopRegistrar"
        limeSubmitCommonLogs
    rlPhaseEnd
}

Controller() {
    rlPhaseStartTest "Role setup"
        CERTDIR=/var/lib/keylime/certs
        rlRun "sync-block ATTESTATION_SERVER_GENERATE_CERTS_DONE ${ATTESTATION_SERVER_IP}" 0 "Waiting for generating certs on attestation server."

        rlRun "echo $ATTESTATION_SERVER_IP" > inventory
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
    
    keylime_server_verifier_database_url: \"postgresql://verifier:fire@${ATTESTATION_SERVER_IP}/verifierdb\"
    keylime_server_registrar_database_url: \"postgresql://registrar:regi@${ATTESTATION_SERVER_IP}/registrardb\"

  roles:
    - ${KEYLIME_SERVER_ANSIBLE_ROLE}
EOF"

        rlRun 'ansible-playbook -v --ssh-common-args "-o StrictHostKeychecking=no -i ~/.ssh/id_rsa_multihost" -i inventory playbook.yml'
        rlRun "sync-set ANSIBLE_SETUP_DONE"
    rlPhaseEnd

}

Agent() {
    rlPhaseStartSetup "Agent setup"
        AGENT_ID="d432fbb3-d2f1-4a97-9ef7-75bd81c00000"
        rlRun "sync-set AGENT_SSH_SETUP_DONE"
        CV_CA=/var/lib/keylime/cv_ca
        rlRun "mkdir -p $CV_CA"
        rlRun "sync-block ATTESTATION_SERVER_START ${ATTESTATION_SERVER_IP}" 0 "Waiting for the attestation server finish to start"
        rlRun "cp /var/lib/keylime/cacert.pem /var/lib/keylime/cv_ca/"
        id keylime && rlRun "chown -R keylime:keylime ${CV_CA}"

        rlRun "limeUpdateConf agent ip '\"${AGENT_IP}\"'"
        rlRun "limeUpdateConf agent contact_ip '\"${AGENT_IP}\"'"
        rlRun "limeUpdateConf agent registrar_ip '\"${ATTESTATION_SERVER_IP}\"'"
        rlRun "limeUpdateConf agent trusted_client_ca '\"/var/lib/keylime/cv_ca/cacert.pem\"'"
        rlRun "limeUpdateConf agent revocation_notification_ip '\"${ATTESTATION_SERVER_IP}\"'"

        if [ -n "$KEYLIME_TEST_DISABLE_REVOCATION" ]; then
            rlRun "limeUpdateConf agent enable_revocation_notifications False"
        fi

        # Delete other components configuration files
        for comp in verifier registrar tenant; do
            rlRun "rm -rf /etc/keylime/$comp.conf*"
        done

        # if TPM emulator is present
        if limeTPMEmulated; then
            # start tpm emulator
            rlRun "limeStartTPMEmulator"
            rlRun "limeWaitForTPMEmulator"
            rlRun "limeCondStartAbrmd"
            # start ima emulator
            limeInstallIMAConfig
            rlRun "limeStartIMAEmulator"
        fi
        sleep 5
        limeCreateTestPolicy
        #copy policy.json to tenant for keylime tenant add
        rlRun "scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i ~/.ssh/id_rsa_multihost policy.json root@$ATTESTATION_SERVER_IP:/var/tmp/"
        rlRun "limeStartAgent"
        rlRun "sync-set AGENT_STARTS"
    rlPhaseEnd

    rlPhaseStartTest "keylime attestation test: Check if agent is added"
        rlRun "sync-block AGENT_ADD_DONE ${ATTESTATION_SERVER_IP}" 0 "Waiting for adding agent."
        rlWaitForFile /var/tmp/test_payload_file -t 30 -d 1  # we may need to wait for it to appear a bit
        rlAssertExists /var/tmp/test_payload_file
    rlPhaseEnd


    rlPhaseStartTest "Agent attestation test: Fail keylime agent"
        # fail AGENT and confirm it has failed validation
        TESTDIR=`limeCreateTestDir`
        limeExtendNextExcludelist $TESTDIR
        rlRun "echo -e '#!/bin/bash\necho boom' > $TESTDIR/keylime-bad-script.sh && chmod a+x $TESTDIR/keylime-bad-script.sh"
        rlRun "$TESTDIR/keylime-bad-script.sh"
        rlRun "sync-set AGENT_CORRUPTED"
        rlRun "sync-block AGENT_FAILED ${ATTESTATION_SERVER_IP}" 0 "Waiting for failed agent attestation."
        if [ -z "$KEYLIME_TEST_DISABLE_REVOCATION" ]; then
            # give the revocation notifier a bit more time to contact the agent
            rlRun "rlWaitForCmd 'tail \$(limeAgentLogfile) | grep -q \"A node in the network has been compromised: ${AGENT_IP}\"' -m 20 -d 1 -t 20"
            rlRun "tail $(limeAgentLogfile) | grep 'Executing revocation action local_action_modify_payload'"
            rlRun "tail $(limeAgentLogfile) | grep 'A node in the network has been compromised: ${AGENT_IP}'"
            rlAssertNotExists /var/tmp/test_payload_file
        fi
    rlPhaseEnd

    rlPhaseStartCleanup "Agent cleanup"
        rlRun "sync-set AGENT_ALL_TESTS_DONE"
        rlRun "limeStopAgent"
        if limeTPMEmulated; then
            rlRun "limeStopIMAEmulator"
            rlRun "limeStopTPMEmulator"
            rlRun "limeCondStopAbrmd"
        fi
        limeSubmitCommonLogs
        limeExtendNextExcludelist $TESTDIR
        rlRun "rm -f /var/tmp/test_payload_file"
    rlPhaseEnd
}

####################
# Common script part
####################

export TESTSOURCEDIR=`pwd`

rlJournalStart
    rlPhaseStartSetup
        # import keylime library
        if rpm -q keylime 2>/dev/null;then
            rlRun 'rlImport "keylime-tests/test-helpers"' || rlDie "cannot import keylime-tests/test-helpers library"
        fi
        rlRun 'rlImport "keylime-tests/sync"' || rlDie "cannot import keylime-tests/sync library"
        rlRun 'rlImport "certgen/certgen"' || rlDie "cannot import openssl/certgen library"

        assign_server_roles

        rlLog "ATTESTATION_SERVER: $ATTESTATION_SERVER ${ATTESTATION_SERVER_IP}"
        rlLog "AGENT: ${AGENT} ${AGENT_IP}"
        rlLog "CONTROLLER: ${CONTROLLER} ${CONTROLLER_IP}"
        rlLog "This system is: $(hostname) ${MY_IP}"
        ###############
        # common setup
        ###############

        rlRun "rlFileBackup --clean ~/.ssh/"
        #preparing ssh keys for mutual connection
        #in future can moved to new sync lib func
        rlRun "cp ssh_keys/* ~/.ssh/"
        rlRun "cat ~/.ssh/id_rsa_multihost.pub >> ~/.ssh/authorized_keys"
        rlRun "chmod 700 ~/.ssh/id_rsa_multihost.pub ~/.ssh/id_rsa_multihost"

        rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
        if rpm -q keylime 2>/dev/null;then
            rlAssertRpm keylime
            # backup files
            limeBackupConfig
        fi
        # load REVOCATION_SCRIPT_TYPE
        REVOCATION_SCRIPT_TYPE=script
        rlRun "cp -rf payload-${REVOCATION_SCRIPT_TYPE} $TmpDir"

        rlRun "pushd $TmpDir"
    rlPhaseEnd

    if echo " $HOSTNAME $MY_IP " | grep -q " ${ATTESTATION_SERVER} "; then
        Attestation_server
    elif echo " $HOSTNAME $MY_IP " | grep -q " ${AGENT} "; then
        Agent
    elif echo " $HOSTNAME $MY_IP " | grep -q " ${CONTROLLER} "; then
        Controller
    else
        rlPhaseStartTest
            rlFail "Unknown role"
        rlPhaseEnd
    fi

    rlPhaseStartCleanup
        rlRun "popd"
        rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
        if rpm -q keylime 2>/dev/null;then
            #################
            # common cleanup
            #################
            limeClearData
            limeRestoreConfig
        fi
        rlRun "rlFileRestore"
    rlPhaseEnd

rlJournalPrintText
rlJournalEnd
