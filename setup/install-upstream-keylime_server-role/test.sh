#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
. /usr/share/beakerlib/beakerlib.sh || exit 1

[ -n "${KEYLIME_SERVER_ROLE_UPSTREAM_URL}" ] || KEYLIME_SERVER_ROLE_UPSTREAM_URL="https://github.com/linux-system-roles/keylime_server.git"
[ -n "${KEYLIME_SERVER_ROLE_UPSTREAM_BRANCH}" ] || KEYLIME_SERVER_ROLE_UPSTREAM_BRANCH="main"

SOURCE_DIR=/var/tmp/keylime_server-role-sources
INSTALL_DIR=/usr/share/ansible/roles/keylime_server

rlJournalStart
    rlPhaseStartTest
        if [ -d $SOURCE_DIR ]; then
            rlLogInfo "Using already downloaded sources in $SOURCE_DIR"
        else
            rlRun "mkdir -p $SOURCE_DIR"
            rlLogInfo "Downloading keylime_server role sources from ${KEYLIME_SERVER_ROLE_UPSTREAM_URL} branch ${KEYLIME_SERVER_ROLE_UPSTREAM_BRANCH}"
            rlRun "GIT_SSL_NO_VERIFY=1 git clone -b ${KEYLIME_SERVER_ROLE_UPSTREAM_BRANCH} ${KEYLIME_SERVER_ROLE_UPSTREAM_URL} $SOURCE_DIR"
        fi
        rlRun "rm -f $INSTALL_DIR"
        rlRun "cp -rv $SOURCE_DIR $INSTALL_DIR"
        rlRun "restorecon -Rv $INSTALL_DIR"
    rlPhaseEnd
rlJournalEnd

