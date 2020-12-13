#!/bin/bash
#=== SSH keys generation
# Tested on Ubuntu 14.04, 16.04, 18.04, 20.04
# Version=202012121737

# Ubuntu 18.04 LTS
# adduser: Please enter a username matching the regular expression configured
# via the NAME_REGEX[_SYSTEM] configuration variable.  Use the `--force-badname'
# option to relax this check or reconfigure NAME_REGEX.
# kevin.t --> kevint

# Mac OS: bash abc-ssh-keys-generation.sh

MYLOGIN="all"
# MYLOGIN="abc-sysadmin"
COMPANY_NAME_SHORT="abc"
# EMAIL="${MYLOGIN}@mydomain.com"
EMAIL="vadims.zenins+jobs@gmail.com"
if [[ ! -d ${HOME}/.ssh/${COMPANY_NAME_SHORT} ]]; then
	mkdir ${HOME}/.ssh/${COMPANY_NAME_SHORT}
fi
pushd ${HOME}/.ssh/${COMPANY_NAME_SHORT}
# declare -a ENVLIST=("dev" "test" "qa" "stg" "prod" "biz" "dop" "git")
declare -a ENVLIST=("test")
for ITEM in "${ENVLIST[@]}"; do
	KEYNAME="${COMPANY_NAME_SHORT}-${ITEM}-${MYLOGIN}"
	ssh-keygen -t rsa -b 4096 -f ${KEYNAME}.priv.key -N '' -C "${KEYNAME}__${EMAIL}"
	mv ${KEYNAME}.priv.key.pub ${KEYNAME}.pub.key
	chmod 400 ${KEYNAME}.priv.key
	chmod 444 ${KEYNAME}.pub.key
	ls -la ${KEYNAME}*
	cat ${KEYNAME}*
done
popd

# Environments:
# prod - Production
# stg - Staging
# uat - User Acceptance Test
# qa  - QA
# test  - Test
# dev - Development
# dop - DevOps
# biz - Business, office
# git - GitLab
