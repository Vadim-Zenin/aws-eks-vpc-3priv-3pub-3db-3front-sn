#!/bin/bash
# Usage:
# . ./bin/lib.sh

################################################################################
# Functions
################################################################################
function f_echo_error() { 
  echo "ERROR: $@" 1>&2 | tee -a ${DEPLOYMENT_LOG}
}

function f_echo_err_exit() { 
  echo "ERROR: $@" 1>&2 | tee -a ${DEPLOYMENT_LOG}
  exit 32
}

function f_printf_error() { 
  printf "ERROR: $@\n" 1>&2 | tee -a ${DEPLOYMENT_LOG}
}

function f_printf_err_exit() { 
  printf "ERROR: $@\n" 1>&2 | tee -a ${DEPLOYMENT_LOG}
  exit 32
}

function f_printf_warning() { 
  printf "WARNING: $@\n" | tee -a ${DEPLOYMENT_LOG}
}

function f_log() {
  logger "${PROGNAME}: $@"
  if [[ "${QUIET}" == "" ]] || [[ ${QUIET} -eq 0 ]]; then
    printf "$@\n"
  fi
}

function f_check_if_installed_2() {
  # Arguments
  # ${1} program name
  # ${2} package name, that contain the program
  if [ $(which ${1}) ]; then
    f_log "INFO: ${1} found: $(which ${1})"
  else
    sudo apt-get update -qq && apt-get install -y ${2}
    if [ $? -ne 0 ] || [ ! $(which ${1}) ]; then
      f_printf_error "missing ${1} in PATH" | f_log
      exit 16
    else
      f_log "INFO: ${1} found: $(which ${1})"
    fi
  fi
}

function f_check_if_installed() {
  if [ $(which ${1}) ]; then
    f_log "INFO: ${1} found: $(which ${1})" | tee -a ${DEPLOYMENT_LOG}
  else
    f_printf_error "missing ${1} in PATH" | f_log
    exit 1
  fi
}

function f_include_lib_cfn() {
  if [[ -f ./bin/lib_cfn.sh ]]; then
    f_log "INFO: including ./bin/lib_cfn.sh\n"
    source ./bin/lib_cfn.sh
  elif [[ -f ./lib_cfn.sh ]]; then
    f_log "INFO: including ./lib_cfn.sh\n"
    source ./lib_cfn.sh
  elif [[ -f ../lib_cfn.sh ]]; then
    f_log "INFO: including ../lib_cfn.sh\n"
    pushd ..
    source ./lib_cfn.sh
    popd
  else
    f_log "ERROR: Could not find lib_cfn.sh to include\n" 1>&2
    exit 32
  fi
}

function f_include_init() {
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
  else
    printf "ERROR: Could not find init.sh to include\n" 1>&2
    exit 32
  fi
}

f_installAwsEksCli() {
  curl -LO https://s3-us-west-2.amazonaws.com/amazon-eks/1.10.3/2018-06-05/eks-2017-11-01.normal.json
  mkdir -p $HOME/.aws/models/eks/2017-11-01/
  mv eks-2017-11-01.normal.json $HOME/.aws/models/eks/2017-11-01/
  aws configure add-model  --service-name eks --service-model file://$HOME/.aws/models/eks/2017-11-01/eks-2017-11-01.normal.json --profile ${AWS_PROFILE}
}

setKubeconfig() {
  # aws eks update-kubeconfig --name ${EKS_NAME} --role-arn ${EKS_SERVICE_ROLE_NAME}
  aws eks update-kubeconfig --name ${EKS_NAME}
  kubectl config use-context ${EKS_ARN}
  kubectl config view | grep current-context:
}

function f_awsKeyPair() {
  # Arguments
  # ${1} SSH key name # example ${AWS_KEY_PAIR_NAME}
  # ${2} SSH key folder # example "mydir/"
  if [[ -f "${HOME}/.ssh/${2}${1}.pub.key" ]]; then
    printf "INFO: Reusing key-pair ${2}${1}\n"
  else
    printf "INFO: Creating key-pair ${1}\n"
    f_mySshKeysGeneration ${1} ${2}
  fi

  if ! aws ec2 describe-key-pairs --profile ${AWS_PROFILE} | grep ${1} > /dev/null; then
    printf "INFO: Uploading ${1} key to AWS\n"
    # DONE: An error occurred (InvalidKeyPair.Duplicate) when calling the ImportKeyPair operation: The keypair 'vsm-qa-all' already exists.
    aws ec2 import-key-pair --key-name ${1} --public-key-material file://${HOME}/.ssh/${2}${1}.pub.key --profile ${AWS_PROFILE}
  else
    printf "INFO: ${1} key-pair exists in AWS: $(aws ec2 describe-key-pairs --profile ${AWS_PROFILE} | grep ${1})\n"
  fi
}

function f_mySshKeysGeneration() {
  # Arguments
  # ${1} SSH key name
  # ${2} SSH key folder # example "mydir/"
  KEYNAME="${1}"
  if [[ ! -z ${KEYNAME} ]]; then
    EMAIL="${1}@example.com"
    pushd ${HOME}/.ssh/${2}
      if [[ -f ${HOME}/.ssh/${2}${KEYNAME} ]]; then
        f_printf_err_exit "file ${HOME}/.ssh/${2}${KEYNAME} exists." | f_log
      else
        ssh-keygen -t rsa -b 4096 -f ${KEYNAME}.priv.key -N '' -C "${KEYNAME}__${EMAIL}"
        mv ${KEYNAME}.priv.key.pub ${KEYNAME}.pub.key
        chmod 400 ${KEYNAME}.priv.key
        chmod 444 ${KEYNAME}.pub.key
        ls -la ${KEYNAME}*
        cat ${KEYNAME}*
      fi
    popd
  else
    f_printf_err_exit "f_mySshKeysGeneration argument is empty." | f_log
  fi
}

function f_create_k8s_namespace() {
  local ns=${1}
  echo "INFO: Namespace is ${1}" | tee -a $DEPLOYMENT_LOG
  # verify that the namespace exists
  ns=`kubectl get namespace ${1} --no-headers --output=go-template={{.metadata.name}} 2>/dev/null`
  if [ -z "${ns}" ]; then
    echo "INFO: Namespace ${1} not found, creating..." | tee -a $DEPLOYMENT_LOG
    kubectl create ns "${1}"
    kubectl get ns ${1}
  fi
}

function f_kubectl_delete_deployment() {
  echo "INFO: Deleting deployment by kubectl delete -f ..." | tee -a ${DEPLOYMENT_LOG}
  # echo "DEBUG: pwd: $(pwd);"
  # printenv | sort | sed 's~^AWS_ACCESS_KEY=.*$~AWS_ACCESS_KEY=<skipped>~;s~^AWS_SECRET_KEY=.*$~AWS_SECRET_KEY=<skipped>~'
  # echo "aws configs:"
  # ls -l ~/.aws/
  echo "INFO: kubectl delete -f ${WORK_DIR}/${ENV_NAME}-${NSPACE}-${APP_NAME}/${APP_NAME}-deployment.yaml" | tee -a ${DEPLOYMENT_LOG}
  kubectl delete -f ${WORK_DIR}/${ENV_NAME}-${NSPACE}-${APP_NAME}/${APP_NAME}-deployment.yaml
  echo "INFO: waiting 5s" | tee -a ${DEPLOYMENT_LOG}
  sleep 5
}

function f_kubectl_apply() {
  echo "INFO: Deploying by kubectl apply -f ..." | tee -a ${DEPLOYMENT_LOG}
  # echo "DEBUG: pwd: $(pwd);"
  # printenv | sort | sed 's~^AWS_ACCESS_KEY=.*$~AWS_ACCESS_KEY=<skipped>~;s~^AWS_SECRET_KEY=.*$~AWS_SECRET_KEY=<skipped>~'
  echo "aws configs:"
  ls -l ~/.aws/
  echo "INFO: kubectl apply -f ${WORK_DIR}/${ENV_NAME}-${NSPACE}-${APP_NAME}/${APP_NAME}-svc.yaml" | tee -a ${DEPLOYMENT_LOG}
  kubectl apply -f ${WORK_DIR}/${ENV_NAME}-${NSPACE}-${APP_NAME}/${APP_NAME}-svc.yaml
  if [[ ! ${APP_NAME} =~ ^.*?alb.* ]]; then
    echo "INFO: kubectl apply -f ${WORK_DIR}/${ENV_NAME}-${NSPACE}-${APP_NAME}/${APP_NAME}-deployment.yaml" | tee -a ${DEPLOYMENT_LOG}
    kubectl apply -f ${WORK_DIR}/${ENV_NAME}-${NSPACE}-${APP_NAME}/${APP_NAME}-deployment.yaml
  else
    echo "INFO: ${APP_NAME}-deployment.yaml skipped." | tee -a ${DEPLOYMENT_LOG} 
  fi
}

function f_k8s_pod_log() {
kubectl logs --namespace=${NSPACE} $(kubectl get pods --namespace=${NSPACE} | egrep -o "${ENV_NAME}-${NSPACE}-${APP_NAME}[a-zA-Z0-9-]+") > logs/${ENV_NAME}-${NSPACE}-${APP_NAME}-$(date +%Y%m%d-%H%M).log
}

# Checking if pods running $1: pod_name
function f_k8s_pods_run_check() {
  if [[ ! ${APP_NAME} =~ ^.*?alb.* ]]; then
    echo "INFO: Checking if pod(s) ${1} running." | tee -a ${DEPLOYMENT_LOG}
    # echo "DEBUG: pwd: $(pwd);"
    TRIES=0
    OLDSTATE=$(set +o)
    OLDSTATE="${OLDSTATE};$(shopt -p)"
    set +x
    while true;
    do
      echo -n .
      sleep 5
      if kubectl get pods -A | grep ${1} | grep Running | grep -q "1/1"; then
        sleep 3s
        echo .
        echo "INFO: ${1} pod(s) STATUS is Running" | tee -a $DEPLOYMENT_LOG
        kubectl get pods -A | grep ${1}
        break
      elif kubectl get pods -A | grep ${1} | grep -q Error; then
        echo .
        f_printf_err_exit "${1} pod(s) STATUS contains Error"
        kubectl get pods -A | grep ${1}
        f_k8s_pod_log
        exit 1
      elif kubectl get pods -A | grep ${1} | grep -q ImagePullBackOff; then
        echo .
        f_printf_err_exit "${1} pod(s) STATUS is ImagePullBackOff"
        kubectl get pods -A | grep ${1}
        f_k8s_pod_log
        exit 1
      elif kubectl get pods -A | grep ${1} | grep -q CrashLoopBackOff; then
        echo .
        f_printf_err_exit "${1} pod(s) STATUS is CrashLoopBackOff"
        kubectl get pods -A | grep ${1}
        f_k8s_pod_log
        exit 1
      fi
      if [ $TRIES -eq 60 ]
        then
          f_printf_err_exit "${1} deployment timeout"
          exit 1
        fi
      TRIES=$((TRIES+1))
      sleep ${SLEEP:=3}
    done
    eval "${OLDSTATE}"
  fi
}

# Checking if pods running in namespace $1: pod_name $2: namespace
function f_k8s_pods_namespace_run_check() {
  if [[ ! ${APP_NAME} =~ ^.*?alb.* ]]; then
    echo "INFO: Checking if pod(s) ${1} running in ${2} namespace." | tee -a ${DEPLOYMENT_LOG}
    # echo "DEBUG: pwd: $(pwd);"
    TRIES=0
    OLDSTATE=$(set +o)
    OLDSTATE="${OLDSTATE};$(shopt -p)"
    set +x
    while true;
    do
      echo -n .
      sleep 5
      if kubectl get pods -n ${2} | grep ${1} | grep Running | grep -q "1/1"; then
        sleep 3s
        echo .
        echo "INFO: ${1} pod(s) STATUS is Running" | tee -a $DEPLOYMENT_LOG
        kubectl get pods -n ${2} | grep ${1}
        break
      elif kubectl get pods -n ${2} | grep ${1} | grep -q Error; then
        echo .
        f_printf_err_exit "${1} pod(s) STATUS contains Error"
        kubectl get pods -n ${2} | grep ${1}
        exit 1
      elif kubectl get pods -n ${2} | grep ${1} | grep -q ImagePullBackOff; then
        echo .
        f_printf_err_exit "${1} pod(s) STATUS is ImagePullBackOff"
        kubectl get pods -n ${2} | grep ${1}
        exit 1
      elif kubectl get pods -n ${2} | grep ${1} | grep -q CrashLoopBackOff; then
        echo .
        f_printf_err_exit "${1} pod(s) STATUS is CrashLoopBackOff"
        kubectl get pods -n ${2} | grep ${1}
        exit 1
      fi
      if [ $TRIES -eq 60 ]
        then
          f_printf_err_exit "${1} deployment timeout"
          exit 1
        fi
      TRIES=$((TRIES+1))
      sleep ${SLEEP:=3}
    done
    eval "${OLDSTATE}"
  fi
}

function f_ssm_put_parameter() {
  # Arguments
  # ${1} Parameter Store type
  # ${2} Parameter Store key
  # ${3} Parameter Store value
  # OLDSTATE=$(set +o)
  # OLDSTATE="${OLDSTATE};$(shopt -p)"
  set +e
  AWS_VALUE="$(aws ssm get-parameter --region ${AWS_SSM_REGION} --profile ${AWS_PROFILE} --name ${2} --query Parameter.Value --output text --with-decryption 2> /dev/null)"
  if [ "$?" -ne 0 ] | [ "${3}" != "${AWS_VALUE}" ]; then
    if [[ "${2}" =~ ^(.*)(privateKey)(.*) ]]; then
      echo "INFO: Writing into Key: ${2}; Value: ${3:0:40}<skipped>;"
    elif [[ "${2}" =~ ^(.*)(Secret)(.*) ]] || [[ "${2}" =~ ^(.*)(AccessKey)(.*) ]] || [[ "${2}" =~ ^(.*)(password)(.*) ]]; then
      f_log "INFO: Key: ${1}; Value: ${SSM_PARAM:0:5}<skipped>; Assigned: ${2};"
    else
      echo "INFO: Writing into Key: ${2}; Value: ${3};"
    fi
    aws ssm put-parameter --region ${AWS_SSM_REGION} --profile ${AWS_PROFILE} --overwrite --name "${2}" --value "${3}" --type "${1}"
  else
    if [[ "${2}" =~ ^(.*)(privateKey)(.*) ]]; then
      echo "INFO: not changes, skipping Key: ${2}; Value: ${3:0:40}<skipped>;"
    elif [[ "${2}" =~ ^(.*)(Secret)(.*) ]] || [[ "${2}" =~ ^(.*)(AccessKey)(.*) ]]; then
      f_log "INFO: Key: ${1}; Value: ${SSM_PARAM:0:5}<skipped>; Assigned: ${2};"
    else
      echo "INFO: not changes, skipping Key: ${2}; Value: ${3};"
    fi
  fi
  set -e
  # eval "${OLDSTATE}"
}

function f_ssm_get_parameter() {
  # Arguments
  # ${1} Parameter Store key
  # ${2} Result Pointer (optional)
  # example: ParameterValue=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/infra/policies/${EKS_NODE_GROUP01_NAME}/arn")
  # use for call from script
  local RES_PTR=${2}
  local SSM_PARAM="$(aws ssm get-parameter --region ${AWS_SSM_REGION} --profile ${AWS_PROFILE} --name ${1} --query Parameter.Value --output text --with-decryption)"
  if [[ -z ${SSM_PARAM} ]]; then
    f_printf_error "Key ${1} value is empty: ${SSM_PARAM}; \${AWS_SSM_REGION}: ${AWS_SSM_REGION}; \${AWS_PROFILE}: ${AWS_PROFILE}"
  else
    if [ "${RES_PTR}" ]; then
      eval export ${RES_PTR}="'${SSM_PARAM}'"
    else 
      printf "${SSM_PARAM}"
    fi
  fi
}

function f_ssm_get_verbose_parameter() {
  # Arguments
  # ${1} Parameter Store key
  # ${2} Result Pointer (optional)
  # ${3} Exit if value empty (optional) # Example: stop
  # example: f_ssm_get_verbose_parameter <my/path> <my_value>|none stop
  if [[ ! "${2}" == "none" ]]; then
    local RES_PTR=${2}
  fi
  local SSM_PARAM="$(aws ssm get-parameter --region ${AWS_SSM_REGION} --profile ${AWS_PROFILE} --name ${1} --query Parameter.Value --output text --with-decryption)"
  if [[ -z ${SSM_PARAM} ]] &&  [[ "${3}" == "stop" ]]; then
    f_printf_err_exit "Key ${1} value is empty: ${SSM_PARAM}; \${AWS_SSM_REGION}: ${AWS_SSM_REGION}; \${AWS_PROFILE}: ${AWS_PROFILE}"
  elif [[ -z ${SSM_PARAM} ]]; then
    f_printf_warning "Key ${1} value is empty: ${SSM_PARAM}; \${AWS_SSM_REGION}: ${AWS_SSM_REGION}; \${AWS_PROFILE}: ${AWS_PROFILE}"
  else
    if [ "${RES_PTR}" ]; then
      eval export ${RES_PTR}="'${SSM_PARAM}'"
      if [[ "${2}" =~ ^(.*)(privateKey)(.*) ]]; then
        f_log "INFO: Key: ${1}; Value: ${SSM_PARAM:0:40}<skipped>; Assigned: ${2};"
      elif [[ "${2}" =~ ^(.*)(Secret)(.*) ]] || [[ "${2}" =~ ^(.*)(AccessKey)(.*) ]] || [[ "${2}" =~ ^(.*)(password)(.*) ]]; then
        f_log "INFO: Key: ${1}; Value: ${SSM_PARAM:0:2}<skipped>; Assigned: ${2};"
      else
        f_log "INFO: Key: ${1}; Value: ${SSM_PARAM}; Assigned: ${2};"
      fi
    else
      if [[ "${2}" =~ ^(.*)(privateKey)(.*) ]]; then
        f_log "INFO: Key: ${1}; Value: ${SSM_PARAM:0:40}<skipped>;"
      elif [[ "${2}" =~ ^(.*)(Secret)(.*) ]] || [[ "${2}" =~ ^(.*)(AccessKey)(.*) ]] || [[ "${2}" =~ ^(.*)(password)(.*) ]]; then
        f_log "INFO: Key: ${1}; Value: ${SSM_PARAM:0:2}<skipped>; Assigned: ${2};"
      else
        f_log "INFO: Key: ${1}; Value: ${SSM_PARAM};"
      fi
    fi
  fi
}

function f_is_cluster_exists() {
  # Arguments
  # ${1} EKS name # example ${EKS_NAME} or qa54-eks
  if [ -z $(aws eks describe-cluster --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE} --name ${1} --query cluster.arn 2> /dev/null) ];then
    # f_log "INFO: EKS cluster ${1} does not exists"
    return 1
  else
    # f_log "INFO: EKS cluster ${1} exists"
    return 0
  fi
}

function f_aws_set_credentials() {
  if [[ "${CI_CD_DEPLOY}" == "true" ]]; then
    export OPTIONS_SSM=""
  else
    export OPTIONS_SSM="AWS_PROFILE=vsm-tools"
  fi
  AWS_SSM_REGION="${AWS_SSM_REGION:-eu-west-1}"

  mkdir -p ~/.aws/
  if [[ -f ~/.aws/config ]]; then
    cp ~/.aws/config ~/.aws/config.$(date +%Y%m%d-%H%M)
  fi
  cp config/aws-config ~/.aws/config
  f_log "\nINFO: cat ~/.aws/config"
  f_log ~/.aws/config

  if [[ ! -f ./templates/aws-credentials.tmpl ]]; then
    f_printf_error "File ./templates/aws-credentials.tmpl does not exists."
    exit 16
  fi

  f_log "\nINFO: AWS credentials template process of ${APP_NAME}" | tee -a ${DEPLOYMENT_LOG}
  if [[ -f ~/.aws/credentials ]]; then
    cp ~/.aws/credentials ~/.aws/credentials.$(date +%Y%m%d-%H%M)
  fi
eval "cat <<EOF
$(<./templates/aws-credentials.tmpl)
EOF
" 2> /dev/null > ~/.aws/credentials
  f_log "\nINFO: ~/.aws/credentials\n"
  f_log ~/.aws/credentials | sed -e 's~^aws_access_key_id = .*$~aws_access_key_id = <skipped>~;s~^aws_secret_access_key = .*$~aws_secret_access_key = <skipped>~'
}

function f_aws_ecr_login() {
  f_log "INFO: \$(aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin ${AWS_ECR_REGISTRY_URL}/${APP_NAME})"
  AWS_ECR_LOGIN="$(aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | docker login --username AWS --password-stdin ${AWS_ECR_REGISTRY_URL}/${APP_NAME})"
  f_log "INFO: \${AWS_ECR_LOGIN}: ${AWS_ECR_LOGIN}"
}

function f_app_health_check() {
  # Arguments
  # ${1} Application name # example config-service communications notification api-gateway
  # curl -s -o /dev/null -I -w "%{http_code}" https://${1}.${DNS_NAME_FQDN}/actuator/health
  f_log "INFO: curl -s -o /dev/null -I -w "%%{http_code}" https://${1}.${DNS_NAME_FQDN}/actuator/health"
  if [ "$(curl -s -o /dev/null -I -w "%{http_code}" https://${1}.${DNS_NAME_FQDN}/actuator/health)" == "200" ];then
    f_log "INFO: Application ${1} is healthy"
    return 0
  else
    f_log "WARNING: Application ${1} is unhealthy"
    return 1
  fi
}

function f_app_health_check_w_timeout() {
  # Arguments
  # ${1} Application name # example config-service communications notification api-gateway
  # curl -s -o /dev/null -I -w "%{http_code}" https://${1}.${DNS_NAME_FQDN}/actuator/health
  f_log "\nINFO: Checking if application ${1} is healthy."
  echo "INFO: curl -s -o /dev/null -I -w "%{http_code}" https://${1}.${DNS_NAME_FQDN}/actuator/health"
  f_log "DEBUG: pwd: $(pwd);"
  SLEEP=5
  TRIES=0
  # OLDSTATE=$(set +o)
  # OLDSTATE="${OLDSTATE};$(shopt -p)"
  # set +x
  while true;
  do
    if f_app_health_check ${1}; then
      f_log "INFO: Application ${1} is UP"
      break
    fi
    sleep 5
    echo -n .
    if [ $TRIES -eq 60 ]
      then
        f_printf_err_exit "Application ${1} health check timeout"
        exit 1
      fi
    TRIES=$((TRIES+1))
    sleep ${SLEEP:=5}
  done
  # eval "${OLDSTATE}"
}

function f_app_info_check_w_timeout() {
  # Arguments
  # ${1} Application name # example config-service communications notification api-gateway
  # curl -s -o /dev/null -I -w "%{http_code}" https://${1}.${DNS_NAME_FQDN}/actuator/info
  f_log "\n\nINFO: Checking if application ${1} info is available."
  # f_log "DEBUG: \${DNS_NAME_FQDN}: ${DNS_NAME_FQDN};"
  f_log "INFO: curl -s -o /dev/null -I -w "%%{http_code}" https://${1}.${DNS_NAME_FQDN}/actuator/info"
  SLEEP=5
  TRIES=0
  # OLDSTATE=$(set +o)
  # OLDSTATE="${OLDSTATE};$(shopt -p)"
  # set +x
  while true;
  do
    QUIET=1
    if f_app_health_check ${1}; then
      QUIET=0
      curl -sS --connect-timeout 3 "https://${1}.${DNS_NAME_FQDN}/actuator/info"
      break
    fi
    sleep 5
    echo -n .
    if [ $TRIES -eq 60 ]
      then
        QUIET=0
        f_printf_err_exit "Application ${1} info check time-out"
        exit 1
      fi
    TRIES=$((TRIES+1))
    sleep ${SLEEP:=5}
  done
  # eval "${OLDSTATE}"
}

function f_common_configuration_deploy() {
  f_log "INFO: Creating or updating ${NSPACE} values in AWS Parameter Store ..."
  . ./configurations/common.put-config-to-aws-ssm.sh
  if [[ -f ./configurations/common.${ENV_TYPE}.put-config-to-aws-ssm.sh ]]; then
  . ./configurations/common.${ENV_TYPE}.put-config-to-aws-ssm.sh
  fi
  if [[ -f ./configurations/certificate.put-config-to-aws-ssm.sh ]]; then
  . ./configurations/certificate.put-config-to-aws-ssm.sh
  fi
  for ITEM in $(f_ssm_get_parameter ${AWS_SSM_BASE_PATH}/${NSPACE}/apps/list); do
    f_app_configuration_deploy ${ITEM}
  done
}

function f_app_configuration_deploy() {
  # Arguments
  # ${1} Application name # example config-service communications notification api-gateway
  if [[ -f ./configurations/${1}.put-config-to-aws-ssm.sh ]]; then
    f_log "INFO: Creating or updating ${1} values in AWS Parameter Store ..."
    . ./configurations/${1}.put-config-to-aws-ssm.sh
  else
    f_log "INFO: Skipping. ./configurations/${1}.put-config-to-aws-ssm.sh does not exists."
  fi
  # f_log "DEBUG: output: $?;"
}

function f_alb_deploy() {
  # Arguments
  # ${1} ALB # example alb1 or alb2 or alb3
  f_log "INFO: Processing ALB ${1}"
  f_log "INFO: . ./bin/deploy-k8s.sh ${1} ${NSPACE} 12345 12345 1
  "
  . ./bin/deploy-k8s.sh ${1} ${NSPACE} 12345 12345 1
  f_log "INFO: kubectl get ing -n ${NSPACE}"
  kubectl get ing -n ${NSPACE}
}

function f_albs_deploy() {
  # Arguments
  # $@ ALBs # example alb1 alb2 alb3
  f_log "INFO: Processing ALBs $@"
  for ITEM in $@; do
    f_alb_deploy ${ITEM}
  done
}

function f_app_dependencies_apps_deploy() {
  # Arguments
  # ${1} Application name # example config-service communications notification api-gateway
  DEPENDENCY="$(f_ssm_get_parameter ${AWS_SSM_CONF_PATH}/${1}/dependency/apps 2> /dev/null)"
  f_log "DEBUG: \${DEPENDENCY}: ${DEPENDENCY}"
  if [[ -z ${DEPENDENCY} ]] || [[ "${DEPENDENCY}" == "None" ]]; then
    f_log "INFO: Application ${1} does not have app dependencies"
  else
    f_log "INFO: Application ${1} has app dependency: ${DEPENDENCY};"
    for ITEM in ${DEPENDENCY}; do
      f_log "INFO: Checking application ${1} dependency ${ITEM} app health"
      if ! f_app_health_check_w_timeout ${ITEM}; then
        f_app_configuration_deploy ${ITEM}
        f_application_deploy ${ITEM}
      fi
      f_app_health_check_w_timeout ${ITEM}
    done
  fi
}

function f_app_dependencies_albs_deploy() {
  # Arguments
  # ${1} Application name # example config-service communications notification api-gateway
  ALB_TO_DEPLOY="$(f_ssm_get_parameter ${AWS_SSM_CONF_PATH}/${1}/dependency/albs 2> /dev/null)"
  f_log "DEBUG: \${ALB_TO_DEPLOY}: ${ALB_TO_DEPLOY}"
  if [[ -z ${ALB_TO_DEPLOY} ]] || [[ "${ALB_TO_DEPLOY}" == "None" ]]; then
    f_log "INFO: Application ${1} does not have ALB dependencies"
  else
    f_log "INFO: Application ${1} has ALB dependency: ${ALB_TO_DEPLOY};"
    f_albs_deploy ${ALB_TO_DEPLOY}
  fi
}

function f_function_exists() {
  declare -f -F ${1} > /dev/null
  ERRORLEVEL=$?
  (( ! ERRORLEVEL )) && f_log "INFO: Errorlevel ${ERRORLEVEL} says ${1} exists"
  return ${ERRORLEVEL}
}

function f_app_version_nspace_check() {
  # TODO
    f_log "DEBUG: \${NSPACE}: ${NSPACE}; \${APP_NAME}: ${APP_NAME}; \${APP_VERSION}: ${APP_VERSION};"
  # if [[ "${NSPACE}" == "nspace10" ]] || [[ "${NSPACE}" == "nspace20" ]] || [[ "${NSPACE}" == "nspace30" ]]; then
  #   # if [[ "${APP_VERSION}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  #   if [[ ${APP_VERSION} =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] && [[ "${APP_NAME}" == "frontend" ]]; then
  #     f_log "INFO: frontend APP_VERSION is correct for ${NSPACE}"
  #   elif [[ "${APP_VERSION}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || [[ "${APP_VERSION}" == "latest" ]]; then
  #     f_log "INFO: APP_VERSION is correct for ${NSPACE}"
  #   else
  #     f_printf_err_exit "APP_VERSION is incorrect for ${NSPACE}. Please use master branch version."
  #   fi
  # fi
}

function f_nexus_npm_repo() {
  # TODO
  NSPACE_LAST_DIGIT=$(echo "${NSPACE}" | sed 's/[^0-9]*//g' | sed 's/.*\(.\)/\1/')
  f_log "DEBUG: \${NSPACE_LAST_DIGIT}: ${NSPACE_LAST_DIGIT};"
  local NSPACE_DIGITS=$(echo "${NSPACE}" | sed 's/[^0-9]*//g' | sed 's/^0*//')
  f_log "INFO: \${NSPACE_DIGITS}: ${NSPACE_DIGITS};"
  if [[ ${ENV_TYPE} == "prod" ]]; then
    ARTIFACT_SOURCE="npm-release"
    # if [[ "${ARTIFACT_SOURCE}" != "npm-release" ]]; then
    #   f_printf_err_exit "\${ARTIFACT_SOURCE} in ${NSPACE} must be npm-release."
    # fi
  # elif [[ ${ENV_TYPE} == "qa" ]] && [[ "${NSPACE_LAST_DIGIT}" == "0" ]]; then
  #   ARTIFACT_SOURCE="${ARTIFACT_SOURCE:-npm-master}"
  #   if [[ "${ARTIFACT_SOURCE}" == "npm-snapshot" ]]; then
  #     f_printf_err_exit "\${ARTIFACT_SOURCE} in ${NSPACE} cannot be npm-snapshot."
  #   fi
  else
    ARTIFACT_SOURCE="${ARTIFACT_SOURCE:-npm-snapshot}"
  fi
  f_log "DEBUG: \${ARTIFACT_SOURCE}: ${ARTIFACT_SOURCE};"
}

function f_deploy_frontend() {
  f_log "INFO: Deploying frontend"
  if [[ "${APP_VERSION}" == "null" ]] ||  [[ "${APP_VERSION}" == "latest" ]] || [[ -z ${APP_VERSION} ]]; then
    export APP_VERSION="$(source ./bin/app-version-list.sh frontend ${ENV_TYPE} ${NSPACE} | head -n1)"
  fi
  export ARTIFACT_EXTENTION="${ARTIFACT_EXTENTION:-tgz}"
  f_app_version_nspace_check
  f_log "DEBUG: \${APP_VERSION}: ${APP_VERSION}"
  if [[ -d ${WORK_DIR}/${APP_NAME}/package/ ]]; then
    rm -fr ${WORK_DIR}/${APP_NAME}/package
  else
    mkdir -p -m 775 ${WORK_DIR}/${APP_NAME}/package/
  fi
  f_nexus_npm_repo
  echo "DEBUG: wget -q -O ${WORK_DIR}/${APP_NAME}/artifact.${ARTIFACT_EXTENTION} http://${NEXUS_FQDN}/repository/${ARTIFACT_SOURCE}/%40vsw/${APP_NAME}/-/${APP_NAME}-${APP_VERSION}.${ARTIFACT_EXTENTION}"
  wget -q -O ${WORK_DIR}/${APP_NAME}/artifact.${ARTIFACT_EXTENTION} "http://${NEXUS_FQDN}/repository/${ARTIFACT_SOURCE}/%40vsw/${APP_NAME}/-/${APP_NAME}-${APP_VERSION}.${ARTIFACT_EXTENTION}"
  if [[ -f ${WORK_DIR}/${APP_NAME}/artifact.${ARTIFACT_EXTENTION} ]]; then
    tar -xzf ${WORK_DIR}/${APP_NAME}/artifact.${ARTIFACT_EXTENTION} -C ${WORK_DIR}/${APP_NAME}/
    f_log "\nINFO: ${WORK_DIR}/${APP_NAME}/package/ contains\n"
    ls -l ${WORK_DIR}/${APP_NAME}/package/*
    if [[ -f ${WORK_DIR}/${APP_NAME}/package/build/index.html ]]; then
      f_log "\nINFO: ${WORK_DIR}/${APP_NAME}/package/build/index.html contains\n"
      cat ${WORK_DIR}/${APP_NAME}/package/build/index.html
      if [[ "${ENV_TYPE}" == "prod" ]]; then
        S3_STORAGE_CLASS="STANDARD"
      else
        S3_STORAGE_CLASS="STANDARD_IA"
      fi
      # TODO fix next errors during initial deployment
      # fatal error: An error occurred (404) when calling the HeadObject operation: Key "index.html" does not exist
      # fatal error: An error occurred (404) when calling the HeadObject operation: Key "manifest.json" does not exist
      # fatal error: An error occurred (404) when calling the HeadObject operation: Key "QkhGgYR47SqZ6wdEx9zcp2sujvrQVPN5T/info.json" does not exist
      set +e
      aws s3 mv s3://${ENV_NAME}-${NSPACE}-${APP_NAME}-${AWS_ACCOUNT_ID}/index.html s3://${ENV_NAME}-${NSPACE}-${APP_NAME}-${AWS_ACCOUNT_ID}/index-old.html --profile ${AWS_PROFILE} --only-show-errors
      aws s3 mv s3://${ENV_NAME}-${NSPACE}-${APP_NAME}-${AWS_ACCOUNT_ID}/manifest.json s3://${ENV_NAME}-${NSPACE}-${APP_NAME}-${AWS_ACCOUNT_ID}/manifest-old.json --profile ${AWS_PROFILE} --only-show-errors
      aws s3 mv s3://${ENV_NAME}-${NSPACE}-${APP_NAME}-${AWS_ACCOUNT_ID}/QkhGgYR47SqZ6wdEx9zcp2sujvrQVPN5T/info.json s3://${ENV_NAME}-${NSPACE}-${APP_NAME}-${AWS_ACCOUNT_ID}/QkhGgYR47SqZ6wdEx9zcp2sujvrQVPN5T/info-old.json --profile ${AWS_PROFILE} --only-show-errors
      set -e

      # f_log "DEBUG: aws s3 sync"
      aws s3 sync ${WORK_DIR}/${APP_NAME}/package/build/ s3://${ENV_NAME}-${NSPACE}-${APP_NAME}-${AWS_ACCOUNT_ID} --storage-class ${S3_STORAGE_CLASS} --profile ${AWS_PROFILE} --delete --only-show-errors
      if [ $? -ne 0 ]; then
        sleep 3
        aws s3 sync ${WORK_DIR}/${APP_NAME}/package/build/ s3://${ENV_NAME}-${NSPACE}-${APP_NAME}-${AWS_ACCOUNT_ID} --storage-class ${S3_STORAGE_CLASS} --profile ${AWS_PROFILE} --delete --only-show-errors
        if [ $? -ne 0 ]; then
          f_printf_err_exit "Previous aws s3 ls command has failed."
        fi
      fi
      # f_log "DEBUG: aws s3 ls"
      # aws s3 ls s3://${ENV_NAME}-${NSPACE}-${APP_NAME}-${AWS_ACCOUNT_ID}/index.html
      f_log "\nINFO: https://s3.console.aws.amazon.com/s3/buckets/${ENV_NAME}-${NSPACE}-${APP_NAME}-${AWS_ACCOUNT_ID}/ contains\n"
      aws s3 ls s3://${ENV_NAME}-${NSPACE}-${APP_NAME}-${AWS_ACCOUNT_ID}/
      if [ $? -ne 0 ]; then
        f_printf_err_exit "Previous aws s3 ls command has failed."
      fi
    else
      f_printf_err_exit "${WORK_DIR}/${APP_NAME}/package/build/index.html does not exists."
    fi
  else
    f_printf_err_exit "${WORK_DIR}/${APP_NAME}/artifact.${ARTIFACT_EXTENTION} does not exists."
  fi
}

function f_application_deploy() {
  # if ${APP_W_DEPENDENCIES} = true OR ${ENV_TYPE} = qa deploy the app dependencies
  # Arguments
  # ${1} Application name # examples config-service communications notification api-gateway
  f_log "\nINFO: Processing application ${1}\n"
  f_app_version_nspace_check
  f_log "DEBUG: \${APP_VERSION}: ${APP_VERSION}; \${APP_W_DEPENDENCIES}: ${APP_W_DEPENDENCIES};"
  if [[ ${APP_W_DEPENDENCIES} != false ]] && ([[ ${APP_W_DEPENDENCIES} == true ]] || [[ "${ENV_TYPE}" == "qa" ]]); then
    f_app_dependencies_apps_deploy ${1}
  fi
  # f_log "INFO: Processing ${1} resources template if exists ..."
  if [[ -f "cfn/app-${1}-resources.yaml" ]]; then
    f_log "INFO: Deploying cfn/app-${1}-resources.yaml"
    deployAppResources ${1}
  else
    f_log "INFO: Skipping. cfn/app-${1}-resources.yaml template does not exist ..."
  fi

  if [[ $(f_function_exists f_deploy_${1}) ]]; then
    f_log "INFO: Processing f_deploy_${1}"
    f_deploy_${1}
  else
    f_log "INFO: Skipping. f_deploy_${1} function does not exist ..."
  fi

  if [[ -f "cfn/app-${1}-cloudfront.yaml" ]]; then
    f_log "INFO: Deploying cfn/app-${1}-cloudfront.yaml"
    deployCloudFrontApp ${1}
  else
    f_log "INFO: Skipping. cfn/app-${1}-cloudfront.yaml template does not exist ..."
  fi

  if [[ ${1} == "frontend" ]]; then
    f_log "INFO: Skipping ports configuration for ${1}"
  elif [[ ! ${1} =~ ^.*?alb.* ]]; then
    PORT=$(f_ssm_get_parameter  "${AWS_SSM_CONF_PATH}/${1}/port")
    CONTAINER_PORT=$(f_ssm_get_parameter  "${AWS_SSM_CONF_PATH}/${1}/containerPort")
    K8S_REPLICAS=$(f_ssm_get_parameter  "${AWS_SSM_CONF_PATH}/${1}/k8sReplicas")
  else
    PORT='12345'
    CONTAINER_PORT='12345'
    K8S_REPLICAS='1'
  fi

  if [[ ! ${1} == "frontend" ]]; then
    f_log "INFO: source ./bin/deploy-k8s.sh ${1} ${NSPACE} ${PORT} ${CONTAINER_PORT} ${K8S_REPLICAS}
    "
    source ./bin/deploy-k8s.sh ${1} ${NSPACE} ${PORT} ${CONTAINER_PORT} ${K8S_REPLICAS}
  fi

  if [[ ! ${1} =~ ^.*?test.* ]] && [[ ! ${1} =~ ^.*?alb.* ]] && [[ ! ${1} == "frontend" ]]; then
    deployCloudWatchAlert "${1}"
  fi

  if [[ ${APP_W_DEPENDENCIES} != false ]] && ([[ ${APP_W_DEPENDENCIES} == true ]] || [[ "${ENV_TYPE}" == "qa" ]]); then
    f_app_dependencies_albs_deploy ${1}
  fi
}

function f_app_nspace_deploy() {
  # Arguments
  # ${1} name space name # example nspace10, nspace20, nspace21
  APP_W_DEPENDENCIES=false
  deploySnsTopics
  f_log "\nINFO: Deploying applications to ${1}\n"
  # for ITEM in config-service notification communications api-gateway authentication; do
  # for ITEM in config-service notification communications api-gateway mis authentication frontend; do
  for ITEM in $(f_ssm_get_parameter ${AWS_SSM_BASE_PATH}/${NSPACE}/apps/list); do
    f_log "\nINFO: Processing application ${ITEM} to ${1}"
    export APP_NAME="${ITEM}"
    if [[ "${APP_VER_TYPE}" == "latest" ]]; then
      export APP_VERSION="latest"
    else
      f_log "export APP_VERSION=\$(source ./bin/app-version-list.sh ${APP_NAME} ${ENV_TYPE} ${1} | grep -v INT | sed -e "/^\s*$/d" | head -n1)"
      export APP_VERSION="$(source ./bin/app-version-list.sh ${APP_NAME} ${ENV_TYPE} ${1} | grep -v INT | sed -e "/^\s*$/d" | head -n1)"
    fi
    f_log "DEBUG: f_app_nspace_deploy: \${APP_NAME}: ${APP_NAME}; \${APP_VERSION}: ${APP_VERSION}"
    f_app_configuration_deploy ${APP_NAME}
    if [[ "${APP_NAME}" == "mis" || "${APP_NAME}" == "communications" || "${APP_NAME}" == "authentication" || "${APP_NAME}" == "ptm" ]]; then
      f_app_database_update ${APP_NAME} ${APP_VERSION}
    else
      f_log "INFO: f_app_nspace_deploy: Skipping Update Database for ${APP_NAME} application."
    fi
    f_application_deploy ${APP_NAME}
  done
  f_log "\nINFO: Deploying ALBs\n"
  # choose 1 of f_albs_deploy
  f_albs_deploy $(f_ssm_get_parameter ${AWS_SSM_BASE_PATH}/infra/aws/albs/list)
  # f_albs_deploy alb3-internal alb2-mgmt alb1-public
  # f_albs_deploy alb3-internal alb1-public
}

function f_s3_bucket_delete() {
  # Arguments
  # ${1} AWS s3 bucket name to delete
  BUCKET_TO_DELETE="${1:-${ENV_NAME}-${NSPACE}-${ITEM}-${AWS_ACCOUNT_ID}}"
  f_log "INFO: Deleting s3 objects in bucket ${BUCKET_TO_DELETE}"
  aws s3 rm s3://${BUCKET_TO_DELETE} --recursive --profile ${AWS_PROFILE} | head -n5
  if [[ ! -d ${WORK_DIR}/${ENV_NAME}-${NSPACE}-${APP_NAME} ]]; then
    mkdir -p -m 775 "${WORK_DIR}/${ENV_NAME}-${NSPACE}-${APP_NAME}/"
  fi
  TEMP_SCRIPT="${WORK_DIR}/${ENV_NAME}-${NSPACE}-${APP_NAME}/deleteBucketScript.sh"
  f_log "INFO: Deleting s3 version objects in bucket ${BUCKET_TO_DELETE}"
  echo '#!/bin/bash' > ${TEMP_SCRIPT}
  aws --output text s3api list-object-versions --bucket ${BUCKET_TO_DELETE} --profile ${AWS_PROFILE} \
  | grep -E "^VERSIONS" | \
  awk '{print "aws s3api delete-object --bucket ${BUCKET_TO_DELETE} --key "$4" --version-id "$8" --profile ${AWS_PROFILE};"}' >> ${TEMP_SCRIPT}
  cat ${TEMP_SCRIPT} | head -n5
  chmod +x ${TEMP_SCRIPT}
  source ${TEMP_SCRIPT}
  f_log "INFO: Deleting s3 markers in bucket ${BUCKET_TO_DELETE}"
  echo '#!/bin/bash' > ${TEMP_SCRIPT}
  aws --output text s3api list-object-versions --bucket ${BUCKET_TO_DELETE} --profile ${AWS_PROFILE} \
  | grep -E "^DELETEMARKERS" \
  | awk '{print "aws s3api delete-object --bucket ${BUCKET_TO_DELETE} --key "$3" --version-id "$5" --profile ${AWS_PROFILE};"}' >> \
  ${TEMP_SCRIPT}
  cat ${TEMP_SCRIPT} | head -n5
  chmod +x ${TEMP_SCRIPT}
  source ${TEMP_SCRIPT}
  rm -f ${TEMP_SCRIPT}
  aws s3 rb s3://${BUCKET_TO_DELETE} --force --profile ${AWS_PROFILE}
}

function f_app_nspace_clean() {
  # Arguments
  # ${1} name space name # example nspace10, nspace20, nspace21
  NSPACE="${1:-${NSPACE}}"
  f_log "\nINFO: Cleaning name space ${NSPACE}\n"
  f_log "INFO: \${CLEAN_NSPACE_ALL_PODS}: ${CLEAN_NSPACE_ALL_PODS};"
  # OLDSTATE=$(set +o)
  # OLDSTATE="${OLDSTATE};$(shopt -p)"
  set +ex
  for ITEM in test $(f_ssm_get_parameter ${AWS_SSM_BASE_PATH}/${NSPACE}/apps/list); do
    if [[ "${ITEM}" == "config-service" ]] && [[ "${CLEAN_NSPACE_ALL_PODS}" != true ]]; then
      continue
    fi
    if [[ "${ITEM}" == "frontend" ]]; then
      # aws s3 rm s3://$(f_ssm_get_parameter ${AWS_SSM_CONF_PATH}/${ITEM}/s3bucketName) --recursive
      
      deleteStackWait ${ENV_NAME}-${NSPACE}-app-${ITEM}-cloudfront
      f_s3_bucket_delete ${ENV_NAME}-${NSPACE}-${ITEM}-${AWS_ACCOUNT_ID}
    else
      f_log "INFO: Processing application ${ITEM}"
      deleteStackWait ${ENV_NAME}-${NSPACE}-${ITEM}-CloudWatchAlert
      kubectl delete deployment.apps/${ENV_NAME}-${NSPACE}-${ITEM} service/${ENV_NAME}-${NSPACE}-${ITEM}-svc horizontalpodautoscaler.autoscaling/${ENV_NAME}-${NSPACE}-${ITEM} -n ${NSPACE} 2> /dev/null
    fi
    deleteStackWait ${ENV_NAME}-${NSPACE}-app-${ITEM}-resources
  done
  f_log "INFO: \${CLEAN_NSPACE_ALL_ALBS}: ${CLEAN_NSPACE_ALL_ALBS};"
  for ITEM in $(f_ssm_get_parameter ${AWS_SSM_BASE_PATH}/infra/aws/albs/list); do
    if [[ "${ITEM}" == "alb2-mgmt" ]] && [[ ${CLEAN_NSPACE_ALL_ALBS} != true ]]; then
      continue
    fi
    f_log "INFO: Processing alb ${ITEM}"
    kubectl delete ingress.extensions/${ENV_NAME}-${NSPACE}-${ITEM}-ingress -n ${NSPACE} 2> /dev/null
  done
  # eval "${OLDSTATE}"
  if [[ "${ENV_TYPE}" == "qa" ]]; then
    SQL_BIN="mysql"
    f_ssm_get_verbose_parameter "${AWS_SSM_CONF_PATH}/notification/${ENV_NAME}-${NSPACE}-docker/db_host" SQL_HOST
    f_ssm_get_verbose_parameter "${AWS_SSM_CONF_PATH}/notification/${ENV_NAME}-${NSPACE}-docker/db_port" SQL_PORT
    f_ssm_get_verbose_parameter "${AWS_SSM_CONF_PATH}/notification/${ENV_NAME}-${NSPACE}-docker/db_username" SQL_USER
    f_ssm_get_parameter "${AWS_SSM_CONF_PATH}/notification/${ENV_NAME}-${NSPACE}-docker/db_password" SQL_PWD
    f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/rds2/db_engine_version" RdsDbEngineVersion
    # https://hub.docker.com/_/mysql?tab=description&page=1&name=5.7.12
    docker pull mysql:${RdsDbEngineVersion}
    CMD1="docker run --rm --name mysql_client_${RdsDbEngineVersion} mysql:${RdsDbEngineVersion} mysql -h ${SQL_HOST} -P ${SQL_PORT} -u ${SQL_USER} --password="${SQL_PWD}" -Bse 'show databases'"
    f_log "$(echo "INFO: Executing: ${CMD1}" | sed -E 's|(^.+--password)(=.+ )(-Bse.*)$|\1=skipped \3|g')"
    DBS="$(bash -c "${CMD1}")"
    for ITEM in ${DBS}; do
      if [[ "${ITEM}" =~ ^.*?_${1}_.* ]]; then
        f_log "INFO: Deleting database ${ITEM}"
        CMD2="docker run --rm --name mysql_client_${RdsDbEngineVersion} mysql:${RdsDbEngineVersion} mysql -h ${SQL_HOST} -P ${SQL_PORT} -u ${SQL_USER} --password="${SQL_PWD}" -Bse 'drop database ${ITEM}'"
        # f_log "DEBUG: Executing: ${CMD2}"
        bash -c "${CMD2}"
        if [ $? -ne 0 ]; then
          f_printf_err_exit "Previous command has failed."
        fi
      fi
    done
  fi
  if [ "${NSPACE}" == "nspace10" ] || [ "${NSPACE}" == "nspace20" ] || [ "${NSPACE}" == "nspace21" ]; then
    f_log "INFO: Skipping ${ENV_NAME}-${NSPACE}-sns-topics stack."
  else
    f_log "INFO: deleteStackWait ${ENV_NAME}-${NSPACE}-sns-topics"
    deleteStackWait ${ENV_NAME}-${NSPACE}-sns-topics
  fi
  set -e
}

function f_app_nspace_info() {
  # Arguments
  # ${1} name space name # example nspace10, nspace20, nspace21
  NSPACE="${1:-${NSPACE}}"
  APP_W_DEPENDENCIES=false
  f_log "\n# ============================================================ #\n"
  f_log "INFO: Applications info in ${NSPACE}\n"
  for ITEM in $(f_ssm_get_parameter ${AWS_SSM_BASE_PATH}/${NSPACE}/apps/list); do
    # f_log "\n\nINFO: curl -sS --connect-timeout 3 https://${ENV_NAME}-${NSPACE}-${ITEM}.${DNS_NAME_FQDN}/actuator/info"
    # curl -sS --connect-timeout 3 "https://${ENV_NAME}-${NSPACE}-${ITEM}.${DNS_NAME_FQDN}/actuator/info"
    f_app_info_check_w_timeout ${ITEM}
  done
  f_log "\n\nINFO: kubectl get pods,deploy,rs,sts,ds,svc,endpoints,ing,pv,pvc,hpa -n ${NSPACE}\n"
  kubectl get pods,deploy,rs,sts,ds,svc,endpoints,ing,pv,pvc,hpa -n ${NSPACE}
}

function f_if_file_exists_in_s3_bucket() {
  # Arguments
  # ${1} s3 bucket
  # ${2} a full file name # example folder1/file.txt
  aws s3api head-object --bucket ${1} --key ${2} 2> /dev/null || not_exist=true
  if [ $not_exist ]; then
    f_log "DEBUG: ${2} it does not exist in s3 bucket ${1}"
    return 1
  else
    f_log "DEBUG: ${2} it exists in s3 bucket ${1}"
    return 0
  fi
}

function f_k8s_horizontal_pod_autoscale() {
  # Arguments
  # ${1} Application name # examples config-service communications notification api-gateway
  printf "INFO: kubectl get deployment metrics-server -n kube-system\n"
  kubectl get deployment metrics-server -n kube-system
  if [[ -f "k8s_templates/${1}-horizontal-pod-autoscaler.ytmpl" ]]; then
    f_log "INFO: Processing k8s_templates/${1}-horizontal-pod-autoscaler.ytmpl" | tee -a ${DEPLOYMENT_LOG}
eval "cat <<EOF
$(<./k8s_templates/${APP_NAME}-horizontal-pod-autoscaler.ytmpl)
EOF
" 2> /dev/null | tee ${WORK_DIR}/${ENV_NAME}-${NSPACE}-${APP_NAME}/${APP_NAME}-horizontal-pod-autoscaler.yaml

  echo "INFO: kubectl apply -f ${WORK_DIR}/${ENV_NAME}-${NSPACE}-${APP_NAME}/${APP_NAME}-horizontal-pod-autoscaler.yaml" | tee -a ${DEPLOYMENT_LOG}
  kubectl apply -f ${WORK_DIR}/${ENV_NAME}-${NSPACE}-${APP_NAME}/${APP_NAME}-horizontal-pod-autoscaler.yaml
  else
    if [[ ! ${1} =~ ^.*?test.* ]] && [[ ! ${1} =~ ^.*?alb.* ]]; then
      f_ssm_get_verbose_parameter "${AWS_SSM_CONF_PATH}/${1}/hpa/cpu-percent" HPA_CPU_PERCENT
      f_ssm_get_verbose_parameter "${AWS_SSM_CONF_PATH}/${1}/hpa/min" HPA_MIN
      f_ssm_get_verbose_parameter "${AWS_SSM_CONF_PATH}/${1}/hpa/max" HPA_MAX
      # kubectl autoscale deployment httpd --cpu-percent=50 --min=2 --max=10 --namespace=stgspace1
      printf "INFO: kubectl delete hpa ${ENV_NAME}-${NSPACE}-${1} --namespace=${NSPACE} 2> /dev/null\n"
      # OLDSTATE=$(set +o)
      # OLDSTATE="${OLDSTATE};$(shopt -p)"
      # set +e
      kubectl delete hpa ${ENV_NAME}-${NSPACE}-${1} --namespace=${NSPACE} 2> /dev/null
      # eval "${OLDSTATE}"
      printf "INFO: kubectl autoscale deployment ${ENV_NAME}-${NSPACE}-${1} --cpu-percent=${HPA_CPU_PERCENT} --min=${HPA_MIN} --max=${HPA_MAX} --namespace=${NSPACE}\n"
      kubectl autoscale deployment ${ENV_NAME}-${NSPACE}-${1} --cpu-percent=${HPA_CPU_PERCENT} --min=${HPA_MIN} --max=${HPA_MAX} --namespace=${NSPACE} 
      sleep 3
      printf "INFO: kubectl get hpa --namespace=${NSPACE} -o wide | grep ${ENV_NAME}-${NSPACE}-${1}\n"
      kubectl get hpa --namespace=${NSPACE} -o wide | grep ${ENV_NAME}-${NSPACE}-${1}
      printf "INFO: kubectl describe hpa/${ENV_NAME}-${NSPACE}-${1} --namespace=${NSPACE}\n"
      kubectl describe hpa/${ENV_NAME}-${NSPACE}-${1} --namespace=${NSPACE}
    else
      printf "INFO: Horizontal Pod Autoscaler configuration of ${1} skipped\n"
    fi
  fi
}

function f_app_database_update() {
  # Arguments
  # ${1} Application name # examples config-service communications notification api-gateway
  # ${2} Application version # examples 1.0.37 INT-1000.1.0.64 
  printf "\nINFO: f_app_database_update started $(date +%Y%m%d-%H%M)\n\n"

  if [[ -z ${1} ]] || [[ -z ${2} ]]; then
    f_printf_err_exit "Argument(s) is empty. \${1}: ${1}; \${2}: ${2};"
  fi

  # if [[ "${1}" == "authentication" ]]; then
  if [[ "${1}" == "mis" || "${1}" == "communications" || "${1}" == "authentication"  || "${1}" == "ptm" ]]; then
    # if [[ "${CI_CD_DEPLOY}" == "true" ]]; then
    #   f_aws_set_credentials
    # fi

    f_include_init ${1} && INIT_BATCH_MODE=true

    LIQUIBASE_DOCKER_IMG="${LIQUIBASE_DOCKER_IMG:-liquibase/liquibase}"
    LIQUIBASE_DOCKER_VER="${LIQUIBASE_DOCKER_VER:-3.10.x}"
    LIQUIBASE_PROJECTS_DIR="${WORK_DIR}/liquibase"

    f_app_configuration_deploy ${1}

    f_ssm_get_verbose_parameter "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/db_host" SQL_HOST
    f_ssm_get_verbose_parameter "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/db_port" SQL_PORT
    f_ssm_get_verbose_parameter "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/db_username" SQL_USER
    f_ssm_get_verbose_parameter "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/db_password" SQL_PWD
    SQL_URL="jdbc:mysql://${SQL_HOST}:${SQL_PORT}"

    # if [[ "${ENV_TYPE}" == "prod" ]]; then
    #   ARTIFACT_REPO="http://nexus-int.tools.vsware.ie/repository/maven-release"
    # el
    if [[ "${2}" =~ ^INT.* ]]; then
      ARTIFACT_REPO="http://nexus-int.tools.vsware.ie/repository/maven-snapshot"
    else
      ARTIFACT_REPO="http://nexus-int.tools.vsware.ie/repository/maven-master"
    fi

    LIQUIBASE_CHANGELOGS_DIR='/opt/liquibase/${1}'
    if [[ "${1}" == "mis" ]]; then
      f_ssm_get_verbose_parameter "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/db_schema" SQL_DEFAULT_SCHEMA
    else
      if [[ ${2} =~ ^INT.*$ ]]; then
        DB_SCHEMA_POSTFIX="$(echo ${2} | sed -e 's/[.].*$//' -e 's/-/_/g')"
        SQL_DEFAULT_SCHEMA="${1}_${NSPACE}_${DB_SCHEMA_POSTFIX}"
      elif [[ "${2}" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        SQL_DEFAULT_SCHEMA="${1}_${NSPACE}_master"
      else
        f_printf_err_exit "${2} does not match naming convention."
      fi
    fi
    f_log "DEBUG: \${SQL_DEFAULT_SCHEMA}: ${SQL_DEFAULT_SCHEMA}"
    f_log "DEBUG: \${LIQUIBASE_CHANGELOGS_DIR}: ${LIQUIBASE_CHANGELOGS_DIR}"

    f_log "\nINFO: Downloading ${ARTIFACT_REPO}/com/vsware/services/${1}/${2}/${1}-${2}-liquibase-ddl.zip"
    wget -qS -O ${1}-${2}-liquibase-ddl.zip "${ARTIFACT_REPO}/com/vsware/services/${1}/${2}/${1}-${2}-liquibase-ddl.zip"
    ls -l "${1}-${2}-liquibase-ddl.zip"
    mkdir -p ${LIQUIBASE_PROJECTS_DIR}/
    unzip -quo -d ${LIQUIBASE_PROJECTS_DIR}/ ${1}-${2}-liquibase-ddl.zip
    if [[ -d ${LIQUIBASE_PROJECTS_DIR}/${1}-${2} ]]; then
      mv ${LIQUIBASE_PROJECTS_DIR}/${1}-${2} ${LIQUIBASE_PROJECTS_DIR}/${1}
    elif [[ -d ${LIQUIBASE_PROJECTS_DIR}/${1}-app-${2} ]]; then
      mv ${LIQUIBASE_PROJECTS_DIR}/${1}-app-${2} ${LIQUIBASE_PROJECTS_DIR}/${1}
    elif [[ -d ${LIQUIBASE_PROJECTS_DIR}/${1}-liquibase-ddl-${2} ]]; then
      mv ${LIQUIBASE_PROJECTS_DIR}/${1}-liquibase-ddl-${2} ${LIQUIBASE_PROJECTS_DIR}/${1}
    elif [[ -d ${LIQUIBASE_PROJECTS_DIR}/liquibase-${2} ]]; then
      mv ${LIQUIBASE_PROJECTS_DIR}/liquibase-${2} ${LIQUIBASE_PROJECTS_DIR}/${1}
    else
      ls -l ${LIQUIBASE_PROJECTS_DIR}/
      f_printf_err_exit "Could not recognise extracted folder name in ${LIQUIBASE_PROJECTS_DIR}." 
    fi
    f_log "\nINFO: ${LIQUIBASE_PROJECTS_DIR}/${1}/ 20 lines"
    ls -lRr ${LIQUIBASE_PROJECTS_DIR}/${1}/* | head -20

    if [[ ! -f ${LIQUIBASE_PROJECTS_DIR}/${1}/changelog.xml ]]; then
      f_printf_err_exit "File ${LIQUIBASE_PROJECTS_DIR}/${1}/changelog.xml does not exist."
    else
      docker pull ${LIQUIBASE_DOCKER_IMG}:${LIQUIBASE_DOCKER_VER}

      CMD="docker run --rm --name liquibase-${ENV_TYPE} -v ~/.aws:/root/.aws -v ${LIQUIBASE_PROJECTS_DIR}/${1}:${LIQUIBASE_CHANGELOGS_DIR} -e AWS_PROFILE=${AWS_PROFILE} ${LIQUIBASE_DOCKER_IMG}:${LIQUIBASE_DOCKER_VER} /bin/bash -c 'ls -lRr ${LIQUIBASE_CHANGELOGS_DIR}/* | head -20'"
      f_log "\nINFO: Executing: ${CMD}"
      bash -c "${CMD}"

      CMD="docker run --rm --name liquibase-${ENV_TYPE} -v ~/.aws:/root/.aws -v ${LIQUIBASE_PROJECTS_DIR}/${1}:${LIQUIBASE_CHANGELOGS_DIR} -e AWS_PROFILE=${AWS_PROFILE} ${LIQUIBASE_DOCKER_IMG}:${LIQUIBASE_DOCKER_VER} --url=${SQL_URL}/${SQL_DEFAULT_SCHEMA}?createDatabaseIfNotExist=true --changeLogFile=changelog.xml --classpath=${LIQUIBASE_CHANGELOGS_DIR} --username=${SQL_USER} --password=${SQL_PWD} --logLevel=warning update"
      f_log "\nINFO: Executing:"
      echo "${CMD}" | sed -e 's~^.*--password=.? --logLevel.*$~^.*--password=<skipped> --logLevel.*$~'
      bash -c "${CMD}"
      if [ $? -ne 0 ]; then
        f_printf_err_exit "Previous command has failed."
      fi
    fi
  else
    f_log "INFO: f_app_database_update: Skipping Update Database for ${1} application."
  fi

  printf "\nINFO: f_app_database_update finished $(date +%Y%m%d-%H%M)\n\n"
}


export AWS_SSM_REGION="${AWS_SSM_REGION:-eu-west-1}"
