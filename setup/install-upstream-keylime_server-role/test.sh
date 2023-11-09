#!/bin/bash
# vim: dict+=/usr/share/beakerlib/dictionary.vim cpt=.,w,b,u,t,i,k
. /usr/share/beakerlib/beakerlib.sh || exit 1

[ -n "${KEYLIME_SERVER_ROLE_UPSTREAM_URL}" ] || KEYLIME_SERVER_ROLE_UPSTREAM_URL="https://github.com/linux-system-roles/keylime_server.git"
[ -n "${KEYLIME_SERVER_ROLE_UPSTREAM_BRANCH}" ] || KEYLIME_SERVER_ROLE_UPSTREAM_BRANCH="main"

SOURCE_DIR=/var/tmp/keylime_server-role-sources
INSTALL_DIR=/usr/share/ansible/roles/rhel-system-roles.keylime_server

rlJournalStart
    rlPhaseStartTest
        # remove all install keylime packages
        rlRun "yum remove -y rhel-system-roles\*"
        # build and install dummy rpm package
        rlRun -s "rpmbuild -bb rhel-system-roles-keylime_server.spec"
        RPMPKG=$( awk '/Wrote:/ { print $2 }' $rlRun_LOG )
        # replace installed keylime with our newly built dummy package
        rlRun "rpm -Uvh $RPMPKG"
        if [ -d $SOURCE_DIR ]; then
            rlLogInfo "Using already downloaded sources in $SOURCE_DIR"
        else
            rlRun "mkdir -p $SOURCE_DIR"
            rlLogInfo "Downloading keylime_server role sources from ${KEYLIME_SERVER_ROLE_UPSTREAM_URL} branch ${KEYLIME_SERVER_ROLE_UPSTREAM_BRANCH}"
            rlRun "GIT_SSL_NO_VERIFY=1 git clone -b ${KEYLIME_SERVER_ROLE_UPSTREAM_BRANCH} ${KEYLIME_SERVER_ROLE_UPSTREAM_URL} $SOURCE_DIR"
        fi
        rlRun "rm -f $INSTALL_DIR"
        rlRun "cp -rv $SOURCE_DIR $INSTALL_DIR"
        # install collection requirements, see https://github.com/linux-system-roles/keylime_server/pull/24
        [ -f "$SOURCE_DIR/meta/collection-requirements.yml" ] && rlRun "ansible-galaxy collection install -vv -r $SOURCE_DIR/meta/collection-requirements.yml"
        rlRun "restorecon -Rv $INSTALL_DIR"
    rlPhaseEnd
rlJournalEnd

