#!/bin/bash
# Initial usage:
# export ENV_TYPE="test" && export IP_2ND_OCTET="16" && . ./bin/deploy-app-from-jenkins.sh
# Usage:
# . ./bin/deploy-app-from-jenkins.sh

################################################################################
# Functions
################################################################################

function f_include_lib() {
  if [[ -f ./bin/lib.sh ]]; then
    if [[ "${QUIET}" == "" ]] || [[ ${QUIET} -eq 0 ]]; then
      printf "INFO: including ./bin/lib.sh\n"
    fi
    source ./bin/lib.sh
  elif [[ -f ../bin/lib.sh ]]; then
    if [[ "${QUIET}" == "" ]] || [[ ${QUIET} -eq 0 ]]; then
      printf "INFO: including ../bin/lib.sh\n"
    fi
    source ../bin/lib.sh
  elif [[ -f ./lib.sh ]]; then
    if [[ "${QUIET}" == "" ]] || [[ ${QUIET} -eq 0 ]]; then
      printf "INFO: including ./lib.sh\n"
    fi
    source ./lib.sh
  elif [[ -f ../lib.sh ]]; then
    if [[ "${QUIET}" == "" ]] || [[ ${QUIET} -eq 0 ]]; then
      printf "INFO: including ../lib.sh\n"
    fi
    pushd ..
    source ./lib.sh
    popd
  else
    printf "ERROR: Could not find lib.sh to include\n" 1>&2
    exit 32
  fi
}

################################################################################
# MAIN
################################################################################

printf "\nINFO: deploy-app-from-jenkins.sh started\n\n"

f_include_lib

pwd

if [[ "${CI_CD_DEPLOY}" == "true" ]]; then
  f_aws_set_credentials
fi

f_include_lib_cfn

# f_app_version_nspace_check

f_aws_ecr_login

f_application_deploy ${APP_NAME}

printf "\nINFO: deploy-app-from-jenkins.sh finished\n\n"
