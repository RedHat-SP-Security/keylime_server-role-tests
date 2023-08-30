#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
. /usr/share/beakerlib/beakerlib.sh || exit 1

[ -n "$DOCKERFILE_AGENT" ] || DOCKERFILE_AGENT=Dockerfile.agent
[ -n "$DOCKERFILE_SYSTEMD" ] || DOCKERFILE_SYSTEMD=Dockerfile.systemd

#Machine should have /dev/tpm0 or /dev/tpmrm0 device
AGENT_ID="d432fbb3-d2f1-4a97-9ef7-75bd81c00000"

rlJournalStart

    rlPhaseStartSetup "Do the keylime setup"

        rlRun 'rlImport "keylime-tests/test-helpers"'|| rlDie "cannot import /keylime-tests/test-helpers library"

        rlAssertRpm keylime
        # update /etc/keylime.conf
        limeBackupConfig
        CONT_NETWORK_NAME="container_network"
        IP_ATTESTATION_SERVER="172.18.0.4"
        IP_AGENT="172.18.0.12"
        #create network for containers
        rlRun "limeconCreateNetwork ${CONT_NETWORK_NAME} 172.18.0.0/16"

        #preparation for ssh access
        rlRun "rlFileBackup --clean ~/.ssh/"
        rlRun 'rm -f /root/.ssh/id_rsa* && ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa'
        rlRun "cp /root/.ssh/id_*.pub ."

        #build verifier container
        TAG_ATTESTATION_SERVER="keylime_server_image"
        rlRun "limeconPrepareImage ${limeLibraryDir}/${DOCKERFILE_SYSTEMD} ${TAG_ATTESTATION_SERVER}"

        # if TPM emulator is present
        if limeTPMEmulated; then
            # start tpm emulator
            rlRun "limeStartTPMEmulator"
            rlRun "limeWaitForTPMEmulator"
            rlRun "limeCondStartAbrmd"
            # start ima emulator
            rlRun "limeInstallIMAConfig"
            rlRun "limeStartIMAEmulator"
        fi
        sleep 5

        #mandatory for access agent containers to tpm
        rlRun "chmod o+rw /dev/tpmrm0"

        #run verifier container
        CONT_ATTESTATION_SERVER="attestation_container"
        rlRun "limeconRunSystemd $CONT_ATTESTATION_SERVER $TAG_ATTESTATION_SERVER $IP_ATTESTATION_SERVER $CONT_NETWORK_NAME"
        rlRun "echo 172.18.0.4" > inventory
        rlRun "cat > playbook.yml <<EOF
- hosts: all
  vars:
    keylime_server_verifier_ip: \"{{ ansible_host }}\"
    keylime_server_registrar_ip: \"{{ ansible_host }}\"

  roles:
    - rhel-system-roles.keylime_server
EOF"
        rlRun 'ansible-playbook -v --ssh-common-args "-o StrictHostKeychecking=no" -i inventory playbook.yml'
        sleep 5
        rlRun "rm -f /var/lib/keylime/cv_ca/*"
        rlRun "podman cp $CONT_ATTESTATION_SERVER:/var/lib/keylime/cv_ca /var/lib/keylime/"

        rlRun "limeWaitForVerifier 8881 $IP_ATTESTATION_SERVER"
        rlRun "limeWaitForRegistrar 8891 $IP_ATTESTATION_SERVER"

        # tenant
        rlRun "limeUpdateConf tenant require_ek_cert False"
        rlRun "limeUpdateConf tenant verifier_ip $IP_ATTESTATION_SERVER"
        rlRun "limeUpdateConf tenant registrar_ip $IP_ATTESTATION_SERVER"
        # set client_key_password to match the value on verifier
        rlRun "limeUpdateConf tenant client_key_password default"

        #setup of agent
        rlRun "cp -r /var/lib/keylime/cv_ca ."
        TAG_AGENT="agent_image"
        CONT_AGENT="agent_container"
        rlRun "limeconPrepareImage ${limeLibraryDir}/${DOCKERFILE_AGENT} ${TAG_AGENT}"
        rlRun "limeUpdateConf agent registrar_ip '\"$IP_ATTESTATION_SERVER\"'"
        rlRun "limeconPrepareAgentConfdir $AGENT_ID $IP_AGENT confdir_$CONT_AGENT"

        # create runtime policy
        TESTDIR=`limeCreateTestDir`
        rlRun "limeCreateTestPolicy"

        rlRun "limeconRunAgent $CONT_AGENT $TAG_AGENT $IP_AGENT $CONT_NETWORK_NAME $TESTDIR keylime_agent $PWD/confdir_$CONT_AGENT $PWD/cv_ca"
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
        if limeTPMEmulated; then
            rlRun "limeStopIMAEmulator"
            rlRun "limeStopTPMEmulator"
            rlRun "limeCondStopAbrmd"
        fi
        limeExtendNextExcludelist $TESTDIR
        limeSubmitCommonLogs
        limeClearData
        limeRestoreConfig
        rlRun "rlFileRestore"
    rlPhaseEnd

rlJournalEnd

