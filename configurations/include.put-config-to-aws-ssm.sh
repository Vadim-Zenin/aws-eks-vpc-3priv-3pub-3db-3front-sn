#!/bin/bash
# put-common-configuration-to-aws-parameter-store
# include.put-config-to-aws-ssm.sh
# requirements: init.sh must be run before
################################################################################
# Functions
################################################################################

################################################################################
# MAIN
################################################################################

printf "\nINFO: include.put-config-to-aws-ssm.sh started\n\n"

export INIT_BATCH_MODE=${INIT_BATCH_MODE:-false}
if [[ -f ./bin/init.sh ]]; then
  printf "INFO: including ./bin/init.sh\n"
  source ./bin/init.sh
elif [[ -f ./init.sh ]]; then
  printf "INFO: including ./init.sh\n"
  source ./init.sh
elif [[ -f ../init.sh ]]; then
  printf "INFO: including ../init.sh\n"
  pushd ..
  source ./init.sh
  popd
elif [[ -f ../../init.sh ]]; then
  printf "INFO: including ../../init.sh\n"
  pushd ../../
  source ./init.sh
  popd
else
  printf "ERROR: Could not find init.sh to include\n" 1>&2
  exit 32
fi
export INIT_BATCH_MODE=${INIT_BATCH_MODE:-true}

printf "INFO: \${AWS_SSM_CONF_PATH} : ${AWS_SSM_CONF_PATH}\n"

printf "\nINFO: include.put-config-to-aws-ssm.sh finished\n\n"
