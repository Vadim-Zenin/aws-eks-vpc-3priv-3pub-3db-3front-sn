#!/bin/bash
# Usage:
# export COMPANY_NAME_SHORT="abc" && export ENV_TYPE="test" && export IP_2ND_OCTET="16" && export NSPACE="nspace60" && export APP_NAME="app-http-content-from-git" && bash -c ". ./bin/init.sh app-http-content-from-git"
# export COMPANY_NAME_SHORT="abc" && export ENV_TYPE="test" && export IP_2ND_OCTET="16" && export NSPACE="nspace60" && export APP_NAME="app-http-content-from-git" && . ./bin/init.sh app-http-content-from-git
# Usage:
# . ./bin/init.sh app-http-content-from-git

################################################################################
# Functions
################################################################################
function f_usage() {
    BASE=$(basename -- "$0")
    echo "Init variables 
Usage:
    $BASE <application_name>
    $BASE app-http-content-from-git
    $BASE 
"
    exit 32
}
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
f_include_lib

f_log "\nINFO: init.sh started\n\n"

if [[ ${INIT_BATCH_MODE} != true ]]; then

  declare -A AIP_2ND_OCTET

  if [[ ${QUIET} == 1 ]]; then
    OUTPUT_OPTIONS=">/dev/null 2>&1"
  fi

  f_check_if_installed aws && f_log "INFO: aws version : $(aws --version)"
  f_check_if_installed aws-iam-authenticator
  f_check_if_installed kubectl && f_log "INFO: kubectl version : $(kubectl version --client=true)"

  APP_NAME="${1:-${APP_NAME}}"
  if [[ -z ${APP_NAME} ]]; then
    f_printf_err_exit "applications name is empty \${APP_NAME}: ${APP_NAME}"
    f_usage
  else
    f_log "INFO: \${APP_NAME}: ${APP_NAME};\n"
  fi

  export COMPANY_NAME_SHORT="${COMPANY_NAME_SHORT:-abc}"
  # Next line is used in continuous integration and continuous delivery tool. Do not change without changes in continuous integration and continuous delivery tool as well.
  # export ENV_TYPE="qa"
  export ENV_TYPE="${ENV_TYPE:-qa}"
  export IP_2ND_OCTET="${IP_2ND_OCTET:-54}"
  REGEX='^[0-9]+$'
  if ! [[ ${IP_2ND_OCTET} =~ ${REGEX} ]] ; then
    f_printf_err_exit "\${IP_2ND_OCTET} is not a number : ${IP_2ND_OCTET}"
  fi
  export AWS_SSM_REGION="${AWS_SSM_REGION:-eu-west-1}"
  export AWS_PROFILE="${AWS_PROFILE:-${COMPANY_NAME_SHORT}-${ENV_TYPE}}"

  export ENV_NAME="${ENV_TYPE}${IP_2ND_OCTET}"
  # Next line is used in continuous integration and continuous delivery tool. Do not change without changes in continuous integration and continuous delivery tool as well.
  # export APP_ENVIRONMENT="qa"
  export APP_ENVIRONMENT="${ENV_NAME:-test16}"
  export EKS_NAME="${ENV_NAME}-eks"

  # export AWS_SSM_BASE_PATH="/${COMPANY_NAME_SHORT}/${ENV_TYPE}/${ENV_NAME}/${NSPACE}"
  export AWS_SSM_BASE_PATH="/${COMPANY_NAME_SHORT}/${ENV_TYPE}/${ENV_NAME}"
  export GIT_FQDN="gitlab.mydomain.com"
  export NEXUS_FQDN="nexus-int.mydomain.com"

  f_log "INFO: getting variables from AWS Parameter Store"
  # NameSpace (example: nspace20; nspace21; nspace10; nspace60)
  # TODO check logic for the first EKS namespace per environment
  f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/01/name" EKS_NODE_GROUP01_NAME
  export NSPACE="${NSPACE:-${EKS_NODE_GROUP01_NAME}}"
  export AWS_SSM_CONF_PATH="${AWS_SSM_BASE_PATH}/${NSPACE}/configs"
  f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/infra/aws-default-region" AWS_DEFAULT_REGION_KV
  # export AWS_DEFAULT_REGION="$(aws ssm get-parameter --region ${AWS_SSM_REGION} --profile ${AWS_PROFILE} --name "${AWS_SSM_BASE_PATH}/infra/aws-default-region" --query Parameter.Value --output text)"
  export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION_KV:-eu-west-1}"
  # export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE})"
  export AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION}}" # It uses for cross region operations
  export AWS_ACCOUNT_ID="$(f_ssm_get_parameter /${COMPANY_NAME_SHORT}/${ENV_TYPE}/aws/account/id)"
  # export DNS_NAME_FQDN="$(f_ssm_get_parameter /${COMPANY_NAME_SHORT}/${ENV_TYPE}/common/domain/fdqn)"
  # export DNS_NAME_FQDN="$(aws ssm get-parameter --region ${AWS_SSM_REGION} --profile ${AWS_PROFILE} --name ${AWS_SSM_CONF_PATH}/common/domain/fdqn --query 'Parameter.Value' --output text)"
  export AWS_ECR_REGISTRY_URL="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_SSM_REGION}.amazonaws.com"
  if [[ "${ENV_TYPE}" == "test" ]]; then
    f_ssm_get_verbose_parameter "/${COMPANY_NAME_SHORT}/${ENV_TYPE}/common/domain/fdqn" ROUTE53_ZONE_DOMAIN stop
    export ROUTE53_ZONE_DOMAIN="${ROUTE53_ZONE_DOMAIN}"
    export DNS_NAME_FQDN="${ENV_NAME}-${NSPACE}.${ROUTE53_ZONE_DOMAIN}"
  fi

  export ROUTE53_ZONE_ID="$(aws ssm get-parameter --region ${AWS_SSM_REGION} --profile ${AWS_PROFILE} --name "${AWS_SSM_BASE_PATH}/infra/dns/1/route53_zone_id" --query Parameter.Value --output text)"

  # export GIT_PROJECT2_PREFIX="performance_tests/"
  # export GIT_PROJECT2_NAME="performance_tests"
  export GIT_PROJECT2_PREFIX=""
  export GIT_PROJECT2_NAME=""

  EKS_SERVICE_ROLE_NAME="${EKS_NAME}-service-role"
  EKS_ARN="arn:aws:eks:${AWS_DEFAULT_REGION}:${AWS_ACCOUNT_ID}:cluster/${EKS_NAME}"

  if [[ "${ENV_TYPE}" == "qa" ]] ; then
    # export EKS_NODE_GROUP02_NAME="$(f_ssm_get_parameter ${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/2/name)"
    # f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/02/name" EKS_NODE_GROUP02_NAME
    export EKS_NODE_GROUP02_NAME="${NSPACE:-$(f_ssm_get_parameter ${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/02/name)}"
  fi

  declare -A A_AWS_PROFILE=( 
    [test]="${COMPANY_NAME_SHORT}-test"
    [qa]="${COMPANY_NAME_SHORT}-qa"
    [prod]="${COMPANY_NAME_SHORT}-prod"
  )

  declare -A A_AWS_ACCOUNT_ID=( 
    [test]="$(f_ssm_get_parameter /${COMPANY_NAME_SHORT}/test/aws/account/id)"
    [qa]="$(f_ssm_get_parameter /${COMPANY_NAME_SHORT}/qa/aws/account/id)"
    [prod]="$(f_ssm_get_parameter /${COMPANY_NAME_SHORT}/prod/aws/account/id)"
  )

  declare -A A_AWS_ECR_REGISTRY_URL=( 
    [test]="${A_AWS_ACCOUNT_ID[test]}.dkr.ecr.${AWS_SSM_REGION}.amazonaws.com"
    [qa]="${A_AWS_ACCOUNT_ID[qa]}.dkr.ecr.${AWS_SSM_REGION}.amazonaws.com"
    [prod]="${A_AWS_ACCOUNT_ID[prod]}.dkr.ecr.${AWS_SSM_REGION}.amazonaws.com"
  )

  LOGS_DIR="$(pwd)/logs/${NSPACE}"
  DEPLOYMENT_LOG="${LOGS_DIR}/deployment-$(date +%Y%m%d-%H%M).log"
  WORK_DIR="$(pwd)/work/${NSPACE}"
  DOWNLOAD_DIR="$(pwd)/download"

  # Next line is used in continuous integration and continuous delivery tool. Do not change without changes in continuous integration and continuous delivery tool as well.
  export CI_CD_DEPLOY=${CI_CD_DEPLOY:-false}

  if [[ "${CI_CD_DEPLOY}" == "true" ]]; then
    export DEPLOYMENT_TEMP_DIR="../.."
    # export TF_IN_AUTOMATION=true
    # export APP_VERSION=${TC_BUILD_NUMBER:="latest"}
    f_log "DEBUG: set -e"
    set -e
  else
    # export APP_VERSION="latest"
    DEPLOYMENT_TEMP_DIR="/tmp/deployment"
  fi

  mkdir -p ${LOGS_DIR}
  # if [[ -d ${WORK_DIR} ]]; then
  #   rm -rf ${WORK_DIR}/* 2> /dev/null
  # fi
  mkdir -p ${WORK_DIR}
  mkdir -p ${DOWNLOAD_DIR}

  if $(f_is_cluster_exists ${EKS_NAME}) ; then
    eval aws eks update-kubeconfig --name ${EKS_NAME} ${OUTPUT_OPTIONS}
    kubectl config use-context arn:aws:eks:${AWS_DEFAULT_REGION}:${AWS_ACCOUNT_ID}:cluster/${EKS_NAME} | f_log
    f_log "INFO: kubectl $(kubectl config view | grep current-context:)"
  # else
  #   f_log "INFO: EKS cluster ${EKS_NAME} does not exists"
  fi

  f_log "INFO: \${COMPANY_NAME_SHORT}: ${COMPANY_NAME_SHORT}"
  f_log "INFO: \${ENV_TYPE}: ${ENV_TYPE}"
  f_log "INFO: \${APP_ENVIRONMENT}: ${APP_ENVIRONMENT}"
  f_log "INFO: \${IP_2ND_OCTET}: ${IP_2ND_OCTET}"
  f_log "INFO: \${ENV_NAME}: ${ENV_NAME}"
  f_log "INFO: \${AWS_ACCOUNT_ID}: ${AWS_ACCOUNT_ID}"
  f_log "INFO: \${AWS_ECR_REGISTRY_URL}: ${AWS_ECR_REGISTRY_URL}"
  f_log "INFO: \${AWS_DEFAULT_REGION}: ${AWS_DEFAULT_REGION}"
  f_log "INFO: \${AWS_REGION}: ${AWS_REGION}"
  f_log "INFO: \${AWS_PROFILE}: ${AWS_PROFILE}"
  f_log "INFO: \${AWS_SSM_REGION}: ${AWS_SSM_REGION}"
  f_log "INFO: \${AWS_SSM_BASE_PATH}: ${AWS_SSM_BASE_PATH}"
  f_log "INFO: \${AWS_SSM_CONF_PATH}: ${AWS_SSM_CONF_PATH}"
  f_log "INFO: \${A_AWS_PROFILE[qa]}: ${A_AWS_PROFILE[qa]}"
  f_log "INFO: \${A_AWS_PROFILE[prod]}: ${A_AWS_PROFILE[prod]}"
  f_log "INFO: \${A_AWS_ACCOUNT_ID[qa]}: ${A_AWS_ACCOUNT_ID[qa]}"
  f_log "INFO: \${A_AWS_ECR_REGISTRY_URL[qa]}: ${A_AWS_ECR_REGISTRY_URL[qa]}"
  f_log "INFO: \${A_AWS_ACCOUNT_ID[prod]}: ${A_AWS_ACCOUNT_ID[prod]}"
  f_log "INFO: \${A_AWS_ECR_REGISTRY_URL[prod]}: ${A_AWS_ECR_REGISTRY_URL[prod]}"

  f_log "INFO: \${EKS_NAME}: ${EKS_NAME}"
  f_log "INFO: \${EKS_SERVICE_ROLE_NAME}: ${EKS_SERVICE_ROLE_NAME}"
  f_log "INFO: \${EKS_ARN}: ${EKS_ARN}"
  f_log "INFO: \${EKS_NODE_GROUP01_NAME}: ${EKS_NODE_GROUP01_NAME}"
  f_log "INFO: \${EKS_NODE_GROUP02_NAME}: ${EKS_NODE_GROUP02_NAME}"
  f_log "INFO: \${GIT_FQDN}: ${GIT_FQDN}"
  f_log "INFO: \${GIT_PROJECT2_PREFIX}: ${GIT_PROJECT2_PREFIX}"
  f_log "INFO: \${GIT_PROJECT2_NAME}: ${GIT_PROJECT2_NAME}"
  f_log "INFO: \${NEXUS_FQDN}: ${NEXUS_FQDN}"
  f_log "INFO: \${NSPACE}: ${NSPACE}"
  f_log "INFO: \${ROUTE53_ZONE_DOMAIN}: ${ROUTE53_ZONE_DOMAIN}"
  f_log "INFO: \${ROUTE53_ZONE_ID}: ${ROUTE53_ZONE_ID}"
  f_log "INFO: \${DNS_NAME_FQDN}: ${DNS_NAME_FQDN}"
  f_log "INFO: \${CI_CD_DEPLOY}: ${CI_CD_DEPLOY}"
  f_log "INFO: \${WORK_DIR}: ${WORK_DIR}"
  f_log "INFO: \${LOGS_DIR}: ${LOGS_DIR}"
  f_log "INFO: \${DOWNLOAD_DIR}: ${DOWNLOAD_DIR}"

  f_log "\nINFO: init.sh finished\n\n"
else
  f_log "\nINFO: init.sh skipped in INIT_BATCH_MODE\n\n"
fi
