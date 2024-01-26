#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Description: Test that keylime service start failure is reported by ansible role
#   Author: Karel Srot <ksrot@redhat.com>
#
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#
#   Copyright (c) 2024 Red Hat, Inc.
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

. /usr/share/beakerlib/beakerlib.sh || exit 1

#can be overriden by ENV variable in plan
[ -n "$DOCKERFILE_SYSTEMD" ] || DOCKERFILE_SYSTEMD=Dockerfile.systemd


rlJournalStart

    rlPhaseStartTest "Setup"
        ###############
        # common setup
        ###############

        #TESTDIR=$PWD
        rlRun "TmpDir=\$(mktemp -d)" 0 "Creating tmp directory"
        rlRun "pushd $TmpDir"
        # import keylime library
        rlRun 'rlImport "keylime-tests/test-helpers"' || rlDie "cannot import keylime-tests/test-helperss library"
        rlRun "rpm -qa | grep rhel-system-roles" 0,1
        limeBackupConfig
        rlFileBackup --missing-ok --clean /etc/ansible/hosts

        CONT_NETWORK_NAME="container_network"
        IP_ATTESTATION_SERVER="172.18.0.4"
        CONT_ATTESTATION_SERVER="attestation_container"
        rlRun "limeconCreateNetwork ${CONT_NETWORK_NAME} 172.18.0.0/16"
        #preparation for ssh access
        rlRun "rlFileBackup --clean ~/.ssh/"
        rlRun 'rm -f /root/.ssh/id_rsa* && ssh-keygen -t rsa -N "" -f /root/.ssh/id_rsa'
        rlRun "cp /root/.ssh/id_*.pub ."
	rlRun "echo -e 'Host *\n  StrictHostKeyChecking no' > /root/.ssh/config"
        rlRun "chmod 400 /root/.ssh/config"

        #build verifier container
        TAG_ATTESTATION_SERVER="keylime_server_image"
        rlRun "limeconPrepareImage ${limeLibraryDir}/${DOCKERFILE_SYSTEMD} ${TAG_ATTESTATION_SERVER}"

        rlRun "echo '$IP_ATTESTATION_SERVER' > /etc/ansible/hosts"
        # shorten limeTIMEOUT so we won't be waiting too long
        export limeTIMEOUT=10
    rlPhaseEnd

    rlPhaseStartTest "Incorrect verifier setup"
        rlRun "limeconRunSystemd $CONT_ATTESTATION_SERVER $TAG_ATTESTATION_SERVER $IP_ATTESTATION_SERVER $CONT_NETWORK_NAME '--hostname $CONT_ATTESTATION_SERVER'"
        rlRun "limeWaitForRemotePort 22 $IP_ATTESTATION_SERVER"
        rlRun "cat > keylime-playbook.yml <<_EOF
---
- name: Manage keylime servers
  hosts: all
  vars:
    keylime_server_verifier_ip:  \"1.2.3.4\"
    keylime_server_registrar_ip: \"{{ ansible_host }}\"
  roles:
    - rhel-system-roles.keylime_server
_EOF"
        rlRun "ansible-playbook -vvv keylime-playbook.yml" 2
        # verify that the verifier is not running
        rlRun "limeWaitForVerifier 8881 $IP_ATTESTATION_SERVER" 1
        rlRun "limeconStop $CONT_ATTESTATION_SERVER"
	sleep 3
    rlPhaseEnd

    rlPhaseStartTest "Incorrect registrar setup"
        rlRun "limeconRunSystemd $CONT_ATTESTATION_SERVER $TAG_ATTESTATION_SERVER $IP_ATTESTATION_SERVER $CONT_NETWORK_NAME '--hostname $CONT_ATTESTATION_SERVER'"
        rlRun "limeWaitForRemotePort 22 $IP_ATTESTATION_SERVER"
        rlRun "cat > keylime-playbook.yml <<_EOF
---
- name: Manage keylime servers
  hosts: all
  vars:
    keylime_server_verifier_ip:  \"{{ ansible_host }}\"
    keylime_server_registrar_ip: \"1.2.3.4\"
  roles:
    - rhel-system-roles.keylime_server
_EOF"
        rlRun "ansible-playbook -vvv keylime-playbook.yml" 2
        # verify that only the verifier is running
        rlRun "limeWaitForVerifier 8881 $IP_ATTESTATION_SERVER"
        rlRun "limeWaitForRegistrar 8891 $IP_ATTESTATION_SERVER" 1
        rlRun "limeconStop $CONT_ATTESTATION_SERVER"
    rlPhaseEnd

    rlPhaseStartCleanup
        limeconSubmitLogs
        rlRun "limeconDeleteNetwork $CONT_NETWORK_NAME"
        limeSubmitCommonLogs
        limeClearData
        limeRestoreConfig
        rlRun "rlFileRestore"
        rlRun "popd"
        rlRun "rm -r $TmpDir" 0 "Removing tmp directory"
    rlPhaseEnd

rlJournalPrintText
rlJournalEnd
