#!/bin/bash
# === $1 on AWS EKS deployment and roll-out 
# ENV_NAME="test16"; NSPACE="nspace60"
# Using examples:
# bash -c "export ENV_NAME="${ENV_NAME}" && export CI_CD_DEPLOY=false && ./bin/deploy-k8s.sh test ${NSPACE} 11222 11222 1"
# bash -c "export ENV_NAME="${ENV_NAME}" && export CI_CD_DEPLOY=false && ./bin/deploy-k8s.sh echo ${NSPACE} 58080 58080 2"
#
# bash -c "export ENV_NAME="${ENV_NAME}" && export CI_CD_DEPLOY=false && ./bin/deploy-k8s.sh alb1-public ${NSPACE} 12345 12345 1"
# bash -c "export ENV_NAME="${ENV_NAME}" && export CI_CD_DEPLOY=false && export APP_VERSION="latest" && ./bin/deploy-k8s.sh app-http-content-from-git ${NSPACE} 80 80 2"
#
################################################################################
# Functions
################################################################################
function f_usage()
{
    BASE=$(basename -- "$0")
    echo "Deploy application to AWS EKS (Kubernetes) 
Usage:
    $BASE <application_name> <namespace> <application_port> <container_port> <replicas>
    $BASE testapp nspace20 111 222 2
    $BASE my-notifications nspace10 111 222 3
"
    exit 32
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

################################################################################
# MAIN
################################################################################
export APP_NAME="${1}"
export NSPACE="${2}"
MY_APP_PORT="${3}"
MY_CONTAINER_PORT="${4}"
MY_REPLICAS=${5:-2}
export KNS="-n ${NSPACE}"
export APP_VERSION="${APP_VERSION:-latest}"

# We need variables from init.sh script
f_include_init ${1}

if [ -z ${APP_NAME} ] || [ -z ${NSPACE} ] ; then
  f_printf_err_exit "$BASE argument(s) is empty."
  f_usage
fi

printf "INFO: \${APP_NAME}: ${APP_NAME}; \${NSPACE}: ${NSPACE};\n"
printf "INFO: \${MY_APP_PORT}: ${MY_APP_PORT}; \${MY_CONTAINER_PORT}: ${MY_CONTAINER_PORT}; \${MY_REPLICAS}: ${MY_REPLICAS};\n"
printf "INFO: Deploying ${ENV_NAME}-${NSPACE}-${APP_NAME} ...\n" | tee -a ${DEPLOYMENT_LOG}
mkdir -p ${WORK_DIR}/${ENV_NAME}-${NSPACE}-${APP_NAME} | tee -a ${DEPLOYMENT_LOG}

if [[ "${CI_CD_DEPLOY}" == "true" ]]; then
  if [[ ! -f ~/.aws/credentials ]]; then 
    f_aws_set_credentials
  fi
fi

f_create_k8s_namespace "${NSPACE}"

# printf "INFO: Template process of ${APP_NAME}\n" | tee -a ${DEPLOYMENT_LOG}
# eval "cat <<EOF
# $(<./k8s_templates/${APP_NAME}.ytmpl)
# EOF
# " 2> /dev/null | tee ${WORK_DIR}/${ENV_NAME}-${NSPACE}-${APP_NAME}/${APP_NAME}.yaml

if [[ -f ./k8s_templates/${APP_NAME}-svc.ytmpl ]]; then
  printf "INFO: Services and Ingress template process of ${APP_NAME}\n" | tee -a ${DEPLOYMENT_LOG}
eval "cat <<EOF
$(<./k8s_templates/${APP_NAME}-svc.ytmpl)
EOF
" 2> /dev/null | tee ${WORK_DIR}/${ENV_NAME}-${NSPACE}-${APP_NAME}/${APP_NAME}-svc.yaml
else
  f_printf_err_exit "file ./k8s_templates/${APP_NAME}-svc.ytmpl does not exist."
  exit 16
fi

if [[ ! ${APP_NAME} =~ ^.*?alb.* ]]; then
printf "INFO: Deployment template process of ${APP_NAME}\n" | tee -a ${DEPLOYMENT_LOG}
eval "cat <<EOF
$(<./k8s_templates/${APP_NAME}-deployment.ytmpl)
EOF
" 2> /dev/null | tee ${WORK_DIR}/${ENV_NAME}-${NSPACE}-${APP_NAME}/${APP_NAME}-deployment.yaml
fi

printf "INFO: Deploy ${ENV_NAME}-${NSPACE}-${APP_NAME} to Kubernetes\n" | tee -a ${DEPLOYMENT_LOG}
if kubectl get pods -A | grep -q ${ENV_NAME}-${NSPACE}-${APP_NAME}; then
  echo .
  printf "INFO: ${ENV_NAME}-${NSPACE}-${APP_NAME} pods exist.\n" | tee -a ${DEPLOYMENT_LOG}

  if [ "${APP_NAME}" == "rabbitmq" ] || [ "${APP_NAME}" == "redis-single" ]; then
    MY_DEPLOY_TYPE="statefulset"
  else
    MY_DEPLOY_TYPE="deployment"
  fi

  printf "INFO: kubectl describe ${MY_DEPLOY_TYPE}.apps/${ENV_NAME}-${NSPACE}-${APP_NAME} ${KNS}\n"
  kubectl describe ${MY_DEPLOY_TYPE}.apps/${ENV_NAME}-${NSPACE}-${APP_NAME} ${KNS}

  printf "INFO: kubectl get ${MY_DEPLOY_TYPE} ${ENV_NAME}-${NSPACE}-${APP_NAME} -o yaml ${KNS}\n"
  kubectl get ${MY_DEPLOY_TYPE} ${ENV_NAME}-${NSPACE}-${APP_NAME} -o yaml ${KNS}

  printf "INFO: kubectl get pods,deploy,rs,sts,ds,svc,endpoints,ing,pv,pvc,hpa -o wide ${KNS} | grep ${ENV_NAME}-${NSPACE}-${APP_NAME}\n"
  kubectl get pods,deploy,rs,sts,ds,svc,endpoints,ing,pv,pvc,hpa -o wide ${KNS} | grep ${ENV_NAME}-${NSPACE}-${APP_NAME}

  f_kubectl_delete_deployment
  f_kubectl_apply
else
  f_kubectl_apply
fi

sleep 3
printf "INFO: kubectl get pods,deploy,rs,sts,ds,svc,endpoints,ing,pv,pvc,hpa -o wide ${KNS} | grep ${ENV_NAME}-${NSPACE}-${APP_NAME}\n"
f_k8s_pods_namespace_run_check "${ENV_NAME}-${NSPACE}-${APP_NAME}" "${NSPACE}"

if [[ ! ${APP_NAME} =~ ^.*?alb.* ]]; then

  if [ "${APP_NAME}" == "rabbitmq" ] || [ "${APP_NAME}" == "redis-single" ]; then
    MY_DEPLOY_TYPE="statefulset"
  else
    MY_DEPLOY_TYPE="deployment"
  fi

  printf "INFO: kubectl describe ${MY_DEPLOY_TYPE}.apps/${ENV_NAME}-${NSPACE}-${APP_NAME} ${KNS}\n"
  kubectl describe ${MY_DEPLOY_TYPE}.apps/${ENV_NAME}-${NSPACE}-${APP_NAME} ${KNS}

  printf "INFO: kubectl get ${MY_DEPLOY_TYPE} ${ENV_NAME}-${NSPACE}-${APP_NAME} -o yaml ${KNS}\n"
  kubectl get ${MY_DEPLOY_TYPE} ${ENV_NAME}-${NSPACE}-${APP_NAME} -o yaml ${KNS}
fi

kubectl get pods,deploy,rs,sts,ds,svc,endpoints,ing,pv,pvc,hpa -o wide ${KNS} | grep ${ENV_NAME}-${NSPACE}-${APP_NAME}
printf "INFO: kubectl get pods,deploy,rs,sts,ds,svc,endpoints,ing,pv,pvc,hpa -o wide ${KNS} | grep ${ENV_NAME}-${NSPACE}-${APP_NAME}\n"

if [[ ! ${1} =~ ^.*?test.* ]] && [[ ! ${1} =~ ^.*?alb.* ]]; then
  f_k8s_horizontal_pod_autoscale "${APP_NAME}"
fi

if [ "${CI_CD_DEPLOY}" = false ]; then
  sleep 5
  kubectl get events -A | grep -i "error\|warning\|failed" | grep -i ${APP_NAME}
fi
