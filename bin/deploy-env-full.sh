#!/bin/bash
# === Deploy app-http-content-from-git pod on AWS EKS deployment
# export COMPANY_NAME_SHORT="abc" && export ENV_TYPE="test" && export IP_2ND_OCTET="16" && export NSPACE="nspace60" && export APP_NAME="app-http-content-from-git" && export CI_CD_DEPLOY=false && bash -c "./bin/deploy-env-full.sh"
# export COMPANY_NAME_SHORT="abc" && export ENV_TYPE="test" && export IP_2ND_OCTET="16" && export NSPACE="nspace60" && export APP_NAME="app-http-content-from-git" && export APP_VERSION="0.0.2" && bash -c "./bin/deploy-env-full.sh"

################################################################################
# Functions
################################################################################
function f_include_lib() {
  if [[ -f ./bin/lib.sh ]]; then
    if [[ "${QUIET}" == "" ]] || [[ ${QUIET} -eq 0 ]]; then
      printf "INFO: including ./bin/lib.sh\n"
    fi
    source ./bin/lib.sh
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

function f_usage()
{
    BASE=$(basename -- "$0")
    echo "Deploy name space to AWS EKS (Kubernetes) 
Usage:
    $BASE <namespace>(optional)
    bash -c "export ENV_TYPE="qa" && export IP_2ND_OCTET="56" && export NSPACE="nspace30" && export CI_CD_DEPLOY=false && ./deploy-env-full.sh"
"
    exit 32
}

################################################################################
# MAIN
################################################################################

printf "\nINFO: deploy-env-full.sh started $(date +%Y%m%d-%H%M)\n\n"

export ENV_TYPE="${ENV_TYPE:-test}"
export IP_2ND_OCTET="${IP_2ND_OCTET:-16}"
export APP_VERSION="${APP_VERSION:-latest}"

# export NSPACE="${1:-${NSPACE}}"
APP_NAME=${APP_NAME:-"app-http-content-from-git"}

if [ -z ${APP_NAME} ] || [ -z ${NSPACE} ] ; then
  f_printf_err_exit "$BASE argument(s) is empty."
  f_usage
fi

export APP_W_DEPENDENCIES="false"
export APP_VER_TYPE="last_master_number"

f_include_lib

f_common_configuration_deploy

# We need variables from init.sh script
f_include_init ${APP_NAME} && INIT_BATCH_MODE=true

f_include_lib_cfn && \
if [[ "${NSPACE}" == "nspace60" ]]; then
  deployServiceRole && \
  deployVPC3x3x3x3 && \
  deploySecurityGroups && \
  deployPolicies && \
  deployCluster && \
  f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/0/name" EKS_NODE_GROUP_MAIN_NAME stop && \
  deployNodesGroupPolicy ${EKS_NODE_GROUP_MAIN_NAME} && \
  f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/infra/instance_key_pair1/name" AWS_KEY_PAIR_NAME stop &&\
  f_awsKeyPair "${AWS_KEY_PAIR_NAME}" "${COMPANY_NAME_SHORT}/" && \
  deployNodesGroupMain && \
  authNodesGroupAll && \
  kubectl get nodes --show-labels
fi

f_create_k8s_namespace "${NSPACE}" && \
deployNodesGroupPolicy ${EKS_NODE_GROUP01_NAME} && \
deployNodesGroup01 ${EKS_NODE_GROUP01_NAME} && \
authNodesGroupAll

if [[ "${NSPACE}" == "nspace60" ]]; then
deployAlbSecurityGroup alb1 && \
deployEcrRepositories && \
printf "INFO: ECR repositories are ready. Please build applications."
deploySnsTopics && \
# deployRdsSecurityGroup rds2 && \
# deployRdsCluster rds2
fi

kubectl get nodes
printf "INFO: kubectl get nodes --show-labels\n"
kubectl get nodes --show-labels

. ./bin/cluster-autoscaler.sh && \
. ./bin/cwagent-fluentd.sh && \
. ./bin/hpa-deploy.sh && \
. ./bin/alb-ingress-controller.sh && \

f_log "\nINFO: Deploying certificates\n"
# for ITEM in nspace60; do
for ITEM in $(f_ssm_get_parameter ${AWS_SSM_BASE_PATH}/nspaces/list); do
  f_log "\nINFO: Processing certificates for Name space ${ITEM}"
  # export AWS_REGION="us-east-1" && deployNspaceCertificates "${ITEM}" && \
  export AWS_REGION="${AWS_DEFAULT_REGION}" && deployNspaceCertificates "${ITEM}"
  # deleteStackWait "${ENV_NAME}-${NSPACE}-certificates"
done
 
# # choose 1 of
# # Deploying applications to ${NSPACE}
# # or
# # Deploying applications

# # f_log "\nINFO: Deploying applications to ${NSPACE}\n"
# f_app_nspace_deploy ${NSPACE}

# f_log "\nINFO: Deploying applications\n"
# # choose 1 of for ITEM
# # for ITEM in app-http-content-from-git test; do
# for ITEM in $(f_ssm_get_parameter ${AWS_SSM_BASE_PATH}/${NSPACE}/apps/list); do
#   f_log "\nINFO: Processing application ${ITEM}"
#   f_app_configuration_deploy ${ITEM}
#   f_application_deploy ${ITEM}
# done

f_log "\nINFO: Deploying ALBs\n"
# choose 1 of f_albs_deploy
f_albs_deploy $(f_ssm_get_parameter ${AWS_SSM_BASE_PATH}/infra/aws/albs/list)
# f_albs_deploy alb3-internal alb2-mgmt alb1-public
# f_albs_deploy alb1-public

# for ITEM in $(f_ssm_get_parameter ${AWS_SSM_BASE_PATH}/${NSPACE}/apps/list); do
# # for ITEM in app-http-content-from-git communications notification api-gateway mis; do
#   f_log "INFO: deployCloudWatchAlert ${ITEM}"
#   deployCloudWatchAlert ${ITEM}
# done

# f_app_nspace_info

printf "\nINFO: deploy-env-full.sh finished $(date +%Y%m%d-%H%M)\n\n"
