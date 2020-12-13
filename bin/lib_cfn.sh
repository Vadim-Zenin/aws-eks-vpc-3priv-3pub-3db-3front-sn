#!/bin/bash
# Usage:
# . ./bin/lib_cfn.sh
# 
# Deployment
# export COMPANY_NAME_SHORT="abc" && export ENV_TYPE="test" && export IP_2ND_OCTET="16" && export NSPACE="nspace60" && export APP_NAME="app-http-content-from-git" && export CI_CD_DEPLOY=false && bash -c "./bin/deploy-env-full.sh"
#
# CleanUp
# export COMPANY_NAME_SHORT="abc" && export ENV_TYPE="test" && export IP_2ND_OCTET="16" && export NSPACE="nspace60" && export APP_NAME="app-http-content-from-git" && bash -c ". ./bin/lib_cfn.sh && eksCleanup"

################################################################################
# Functions
################################################################################
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
f_log "\nINFO: lib_cfn.sh started\n\n"

f_include_init ${APP_NAME} && INIT_BATCH_MODE=true

declare -A SubnetGW

getStackOutput() {
  declare desc=""
  declare stack=${1:?required stackName} outputKey=${2:? required outputKey}

  aws cloudformation describe-stacks \
  --stack-name $stack \
  --query 'Stacks[].Outputs[? OutputKey==`'$outputKey'`].OutputValue' \
  --out text \
  --region ${AWS_REGION} \
  --profile ${AWS_PROFILE}
}

# # waitStackState() {
# #   declare desc=""
# #   declare stack=${1:? required stackName} state=${2:? required stackStatePattern}

# #   echo "Deleting stack: ${stack}. Please take cup of tea."
# #   while ! aws cloudformation describe-stacks --stack-name ${stack} --query  Stacks[].StackStatus --out text --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE} | grep -q "${state}"; do
# #     sleep ${SLEEP:=3}
# #     echo -n .
# #   done
# # }

# waitCreateStack() {
#   declare stack=${1:? required stackName}
#   echo "Creating stack: ${stack}. Please take cup of tea."
#   aws cloudformation wait stack-create-complete --stack-name $stack --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE}
# }

# waitUpdateStack() {
#   declare stack=${1:? required stackName}
#   echo "Updating stack: ${stack}. Please wait."
#   aws cloudformation wait stack-update-complete --stack-name $stack --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE}
# }

# deleteStackWait() {
#   declare stack=${1:? required stackName}
#   aws cloudformation delete-stack --stack-name $stack --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE}
#   echo "Deleting stack: ${stack}. Please take cup of tea."
#   aws cloudformation wait stack-delete-complete --stack-name $stack --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE}
# }

# # # TODO function duplicate
# # deleteStackWait() {
# #   declare stack=${1:? required stackName}
# #   aws cloudformation stack-exists --stack-name $stack --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE}
# # }

deployServiceRole() {
  local STACK_NAME="${EKS_SERVICE_ROLE_NAME}"
  if  ! aws cloudformation describe-stacks --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE} --stack-name ${STACK_NAME} >/dev/null 2>&1 ; then
    printf "INFO: Creating stack ${STACK_NAME};\n"
  else
    printf "INFO: Updating stack ${STACK_NAME};\n"
  fi
  aws cloudformation deploy \
    --stack-name ${STACK_NAME} \
    --template-file ./cfn/amazon-eks-service-role.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
      EksName=${EKS_NAME} \
      RoleName=${EKS_SERVICE_ROLE_NAME} \
      EnvironmentName=${ENV_NAME} \
      SsmBasePath=${AWS_SSM_BASE_PATH} \
      LogGroupRetentionInDays=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/infra/eks/logs/loggroup/RetentionInDays") \
    --no-fail-on-empty-changeset \
    --region ${AWS_DEFAULT_REGION} \
    --profile ${AWS_PROFILE}
  if [[ ! "$?" == "0" ]]; then
    exit 8
  fi
  getoutput-deployServiceRole
}

getoutput-deployServiceRole() {
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/eks/service-role/arn"  "EKS_SERVICE_ROLE" exit
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/eks/service-role/name" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/eks/name" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/eks/logs/loggroup/RetentionInDays" none stop
  # f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/CfOriginAccessIdentity" none stop
}

deployVPC3x3x3x3() {
  local STACK_NAME="${ENV_NAME}-vpc"
  if  ! aws cloudformation describe-stacks --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE} --stack-name ${STACK_NAME} >/dev/null 2>&1 ; then
    printf "INFO: Creating stack ${STACK_NAME};\n"
  else
    printf "INFO: Updating stack ${STACK_NAME};\n"
  fi
  aws cloudformation deploy \
    --stack-name ${STACK_NAME} \
    --template-file ./cfn/amazon-eks-vpc-3priv-3pub-3db-3front-sn.yaml \
    --parameter-overrides \
      EksName=${EKS_NAME} \
      EnvironmentName=${ENV_NAME} \
      SsmBasePath=${AWS_SSM_BASE_PATH} \
      VpcCidr=10.${IP_2ND_OCTET}.0.0/16 \
      Subnet2octet=${IP_2ND_OCTET} \
      SubnetPublicAcidr=10.${IP_2ND_OCTET}.0.0/20 \
      SubnetPublicBcidr=10.${IP_2ND_OCTET}.16.0/20 \
      SubnetPublicCcidr=10.${IP_2ND_OCTET}.32.0/20 \
      SubnetFrontAcidr=10.${IP_2ND_OCTET}.64.0/22 \
      SubnetFrontBcidr=10.${IP_2ND_OCTET}.68.0/22 \
      SubnetFrontCcidr=10.${IP_2ND_OCTET}.72.0/22 \
      SubnetDbAcidr=10.${IP_2ND_OCTET}.96.0/22 \
      SubnetDbBcidr=10.${IP_2ND_OCTET}.100.0/22 \
      SubnetDbCcidr=10.${IP_2ND_OCTET}.104.0/22 \
      SubnetPrivateAcidr=10.${IP_2ND_OCTET}.128.0/19 \
      SubnetPrivateBcidr=10.${IP_2ND_OCTET}.160.0/19 \
      SubnetPrivateCcidr=10.${IP_2ND_OCTET}.192.0/19 \
    --no-fail-on-empty-changeset \
    --region ${AWS_DEFAULT_REGION} \
    --profile ${AWS_PROFILE}
  if [[ ! "$?" == "0" ]]; then
    exit 8
  fi
  getoutput-deployVPC3x3x3x3
}

getoutput-deployVPC3x3x3x3() {
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/env/name" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/id" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/cidr" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/nat-gateway/elastic-ip/a" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/nat-gateway/elastic-ip/b" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/nat-gateway/elastic-ip/c" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/all/ids" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/public/ids" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/frond/ids" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/private/ids" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/k8s/ids" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/public/a/id" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/public/a/cidr" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/public/b/id" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/public/b/cidr" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/public/c/id" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/public/c/cidr" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/front/a/id" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/front/a/cidr" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/front/b/id" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/front/b/cidr" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/front/c/id" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/front/c/cidr" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/db/a/id" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/db/a/cidr" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/db/b/id" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/db/b/cidr" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/db/c/id" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/db/c/cidr" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/private/a/id" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/private/a/cidr" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/private/b/id" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/private/b/cidr" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/private/c/id" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/subnets/private/c/cidr" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/route/public/table/id" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/route/private/table/a/id" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/route/private/table/b/id" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/route/private/table/c/id" none stop
}

deploySecurityGroups() {
  local STACK_NAME="${EKS_NAME}-security-groups"
  if  ! aws cloudformation describe-stacks --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE} --stack-name ${STACK_NAME} >/dev/null 2>&1 ; then
    printf "INFO: Creating stack ${STACK_NAME};\n"
  else
    printf "INFO: Updating stack ${STACK_NAME};\n"
  fi
  f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/infra/aws/alb/1/dependency/trusted-ip-cidr" TRUSTED_IP_CIDR stop
  aws cloudformation deploy \
    --stack-name ${STACK_NAME} \
    --template-file ./cfn/amazon-security-groups.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
      EnvironmentName=${ENV_NAME} \
      TrustedIpCidr=${TRUSTED_IP_CIDR} \
    --no-fail-on-empty-changeset \
    --region ${AWS_DEFAULT_REGION} \
    --profile ${AWS_PROFILE}
  if [[ ! "$?" == "0" ]]; then
    exit 8
  fi
  getoutput-deploySecurityGroups
}


getoutput-deploySecurityGroups() {
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/security-group/controlplane/name" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/security-group/controlplane/id" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/security-group/adminaccess/name" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/security-group/adminaccess/id" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/security-group/officeaccess/name" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/security-group/officeaccess/id" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/security-group/extperformancetests/name" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/security-group/extperformancetests/id" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/security-group/route53-health-checkers/name" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/security-group/route53-health-checkers/id" none stop
}

deployCluster() {
  local STACK_NAME="${EKS_NAME}-cluster"
  if  ! aws cloudformation describe-stacks --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE} --stack-name ${STACK_NAME} >/dev/null 2>&1 ; then
    printf "INFO: Creating stack ${STACK_NAME};\n"
  else
    printf "INFO: Updating stack ${STACK_NAME};\n"
  fi
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/eks/version" EKS_VERSION stop
  aws cloudformation deploy \
    --stack-name ${STACK_NAME} \
    --template-file ./cfn/amazon-eks-cluster.yaml \
    --parameter-overrides \
      EnvironmentName=${ENV_NAME} \
      EksVersion=${EKS_VERSION} \
    --no-fail-on-empty-changeset \
    --region ${AWS_DEFAULT_REGION} \
    --profile ${AWS_PROFILE}
  if [[ ! "$?" == "0" ]]; then
    exit 8
  else
    aws eks describe-cluster --name ${ENV_NAME}-eks --profile ${AWS_PROFILE}
  fi
  getoutput-deployCluster
}

getoutput-deployCluster() {
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/eks/endpoint"  EKS_ENDPOINT exit
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/eks/arn"  EKS_ARN exit
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/eks/cert" none stop
}

deployPolicies() {
  local STACK_NAME="${ENV_NAME}-policies"
  if  ! aws cloudformation describe-stacks --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE} --stack-name ${STACK_NAME} >/dev/null 2>&1 ; then
    printf "INFO: Creating stack ${STACK_NAME};\n"
  else
    printf "INFO: Updating stack ${STACK_NAME};\n"
  fi
  aws cloudformation deploy \
    --stack-name ${STACK_NAME} \
    --template-file ./cfn/amazon-policies.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
      EnvironmentName=${ENV_NAME} \
    --no-fail-on-empty-changeset \
    --region ${AWS_DEFAULT_REGION} \
    --profile ${AWS_PROFILE}
  if [[ ! "$?" == "0" ]]; then
    exit 8
  fi
  getoutput-deployPolicies
}

getoutput-deployPolicies() {
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/policies/ClusterAutoscalerPolicy/name" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/policies/ClusterAutoscalerPolicy/arn" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/policies/AlbIngressPolicy/name" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/policies/AlbIngressPolicy/arn" none stop
}

# deployEnvironmentResources() {
#   # Arguments
#   # ${1} Environment name Optional # example qa54 or qa56 or prod250
#   ENV_NAME="${1:-${ENV_NAME}}"
#   local STACK_NAME="${ENV_NAME}-resources"
#   if  ! aws cloudformation describe-stacks --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE} --stack-name ${STACK_NAME} >/dev/null 2>&1 ; then
#     printf "INFO: Creating stack ${STACK_NAME};\n"
#   else
#     printf "INFO: Updating stack ${STACK_NAME};\n"
#   fi
#   aws cloudformation deploy \
#     --stack-name ${STACK_NAME} \
#     --template-file ./cfn/env-resources.yaml \
#     --capabilities CAPABILITY_NAMED_IAM \
#     --parameter-overrides \
#       EnvironmentType=${ENV_TYPE} \
#       EnvironmentName=${ENV_NAME} \
#     --no-fail-on-empty-changeset \
#     --region ${AWS_DEFAULT_REGION} \
#     --profile ${AWS_PROFILE}
#   if [[ ! "$?" == "0" ]]; then
#     exit 8
#   fi
#   getoutput-deployEnvironmentResources
# }

# getoutput-deployEnvironmentResources() {
#   # Arguments
#   # ${1} Environment name Optional # example qa54 or qa56 or prod250
#   f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/s3bucket1/name" none stop
# }

deployNodesGroupPolicy() {
  # Arguments
  # ${1} EKS node group name (main or namespace) # example ${EKS_NODE_GROUP01_NAME} or ${EKS_NAME}-nodes-policy-${EKS_NODE_GROUP01_NAME}
  local STACK_NAME="${EKS_NAME}-nodes-policy-${1}"
  if  ! aws cloudformation describe-stacks --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE} --stack-name ${STACK_NAME} >/dev/null 2>&1 ; then
    printf "INFO: Creating stack ${STACK_NAME};\n"
  else
    printf "INFO: Updating stack ${STACK_NAME};\n"
  fi
  if [[ "${1}" == "main" ]]; then
    TEMPLATE_FILE="cfn/amazon-eks-policy-main.yaml"
  else
    TEMPLATE_FILE="cfn/amazon-eks-policy-nspace.yaml"
  fi
  aws cloudformation deploy \
    --stack-name ${STACK_NAME} \
    --template-file ${TEMPLATE_FILE} \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
      EnvironmentName=${ENV_NAME} \
      EksName=${EKS_NAME} \
      NameSpace=${NSPACE} \
    --no-fail-on-empty-changeset \
    --region ${AWS_DEFAULT_REGION} \
    --profile ${AWS_PROFILE}
  if [[ ! "$?" == "0" ]]; then
    exit 8
  fi
  getoutput-deployNodesGroupPolicy "${1}"
}

getoutput-deployNodesGroupPolicy() {
  # Arguments
  # ${1} EKS node group name (namespace) # example ${EKS_NODE_GROUP01_NAME} or ${EKS_NAME}-nodes-policy-${EKS_NODE_GROUP01_NAME}
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/policies/${1}/name" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/policies/${1}/arn" none stop
}

deployNodesGroupMain() {
  f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/0/name" EKS_NODE_GROUP_MAIN_NAME stop
  local STACK_NAME="${EKS_NAME}-nodes-${EKS_NODE_GROUP_MAIN_NAME}"
  if  ! aws cloudformation describe-stacks --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE} --stack-name ${STACK_NAME} >/dev/null 2>&1 ; then
    printf "INFO: Creating stack ${STACK_NAME};\n"
  else
    printf "INFO: Updating stack ${STACK_NAME};\n"
  fi
  f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/infra/eks/version" EKS_VERSION stop
  f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/infra/instance_key_pair1/name" AWS_KEY_PAIR_NAME stop
  aws cloudformation deploy \
    --stack-name ${STACK_NAME} \
    --template-file ./cfn/amazon-eks-nodegroup-main.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
      EnvironmentName=${ENV_NAME} \
      EksName=${EKS_NAME} \
      NodeImageId=$(aws ssm get-parameter --name /aws/service/eks/optimized-ami/${EKS_VERSION}/amazon-linux-2/recommended/image_id --region ${AWS_DEFAULT_REGION} --query Parameter.Value --output text) \
      NodeGroupName=${EKS_NODE_GROUP_MAIN_NAME} \
      BootstrapArgumentsOpts="--kubelet-extra-args --node-labels=nodesgroup=${EKS_NODE_GROUP_MAIN_NAME}" \
    --no-fail-on-empty-changeset \
    --region ${AWS_DEFAULT_REGION} \
    --profile ${AWS_PROFILE}
  if [[ ! "$?" == "0" ]]; then
    exit 8
  fi
  getoutput-deployNodesGroupMain
}

getoutput-deployNodesGroupMain() {
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/0/node-group/name" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/0/instance-role/arn" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/0/security-group/id" none stop
}

deployNodesGroup01() {
  # Arguments
  # ${1} EKS node group name (namespace) # example ${EKS_NODE_GROUP01_NAME} or ${NSPACE}
  local STACK_NAME="${EKS_NAME}-nodes-${1}"
  if  ! aws cloudformation describe-stacks --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE} --stack-name ${STACK_NAME} >/dev/null 2>&1 ; then
    printf "INFO: Creating stack ${STACK_NAME};\n"
  else
    printf "INFO: Updating stack ${STACK_NAME};\n"
  fi
  local NSPACE_LAST_DIGIT=$(echo "${1}" | sed 's/[^0-9]*//g' | sed 's/.*\(.\)/\1/')
  printf "INFO: \${NSPACE_LAST_DIGIT} : ${NSPACE_LAST_DIGIT};\n"
  local NSPACE_DIGITS=$(echo "${1}" | sed 's/[^0-9]*//g' | sed 's/^0*//')
  printf "INFO: \${NSPACE_DIGITS} : ${NSPACE_DIGITS};\n"
  f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/infra/eks/version" EKS_VERSION stop
  f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/infra/instance_key_pair1/name" AWS_KEY_PAIR_NAME stop
  # printf "DEBUG: \${EKS_VERSION} : ${EKS_VERSION};\n"
  aws cloudformation deploy \
    --stack-name ${STACK_NAME} \
    --template-file ./cfn/amazon-eks-nodegroup-03.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
      NodeInstanceType=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/${NSPACE_DIGITS}/instance-type") \
      NodeImageId=$(aws ssm get-parameter --name /aws/service/eks/optimized-ami/${EKS_VERSION}/amazon-linux-2/recommended/image_id --region ${AWS_DEFAULT_REGION} --query Parameter.Value --output text) \
      NodeGroupName=${1} \
      NodeGroupPolicyArn=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/infra/policies/${NSPACE}/arn") \
      NodeAutoScalingGroupMinSize=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/${NSPACE_DIGITS}/min") \
      NodeAutoScalingGroupDesiredSize=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/${NSPACE_DIGITS}/desired") \
      NodeAutoScalingGroupMaxSize=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/${NSPACE_DIGITS}/max") \
      InstanceTypesOverride=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/${NSPACE_DIGITS}/instance-types-override") \
      EksName=${EKS_NAME} \
      KeyName=${AWS_KEY_PAIR_NAME} \
      Subnet2octet=${IP_2ND_OCTET} \
      EnvironmentName=${ENV_NAME} \
      NameSpace=${1} \
      AutoScalingGroupMonitoringDetailed=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/${NSPACE_DIGITS}/autoscaling-group-monitoring-detailed") \
      BootstrapArgumentsOpts="--kubelet-extra-args --node-labels=nodesgroup=${1}" \
      OnDemandBaseCapacity=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/${NSPACE_DIGITS}/on-demand-base-capacity") \
      OnDemandPercentageAboveBaseCapacity=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/${NSPACE_DIGITS}/on-demand-percentage-above-base-capacity") \
      SpotInstancePools=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/${NSPACE_DIGITS}/spot-instance-pools") \
    --no-fail-on-empty-changeset \
    --region ${AWS_DEFAULT_REGION} \
    --profile ${AWS_PROFILE}
  if [[ ! "$?" == "0" ]]; then
    exit 8
  fi
  getoutput-deployNodesGroup01 "${1}"
}

getoutput-deployNodesGroup01() {
  # Arguments
  # ${1} EKS node group name (namespace) # example ${EKS_NODE_GROUP01_NAME} or ${NSPACE}
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/${1}/instance-profile/arn" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/${1}/instance-role/arn" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/${1}/security-group/id" none stop
}

# # authNodesGroup01() {
# #   aws eks update-kubeconfig --name ${EKS_NAME} --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE}
# # # EKS_NODE_GROUP_MAIN_INSTANCE_ROLE="MAIN_INSTANCE_ROLE-example"
# # EKS_NODE_GROUP_MAIN_INSTANCE_ROLE=$(getStackOutput ${EKS_NAME}-nodes-${EKS_NODE_GROUP_MAIN_NAME} NodeInstanceRoleArn)
# # f_log "INFO: \${EKS_NODE_GROUP_MAIN_INSTANCE_ROLE}: ${EKS_NODE_GROUP_MAIN_INSTANCE_ROLE}"
# # # EKS_NODE_GROUP01_INSTANCE_ROLE="GROUP01_INSTANCE_ROLE-example"
# # EKS_NODE_GROUP01_INSTANCE_ROLE=$(getStackOutput ${EKS_NAME}-nodes-${EKS_NODE_GROUP01_NAME} NodeInstanceRoleArn)
# # f_log "INFO: \${EKS_NODE_GROUP01_INSTANCE_ROLE}: ${EKS_NODE_GROUP01_INSTANCE_ROLE}"

# #   if [ -z ${EKS_NODE_GROUP_MAIN_INSTANCE_ROLE} ] || [ -z ${NSPACE} ] ; then
# #     f_printf_err_exit "\${EKS_NODE_GROUP_MAIN_INSTANCE_ROLE} argument(s) is empty."
# #   elif [ -z ${EKS_NODE_GROUP01_INSTANCE_ROLE} ]; then
# #     f_printf_err_exit "\${EKS_NODE_GROUP01_INSTANCE_ROLE} argument(s) is empty."
# #   elif [ -z ${AWS_ACCOUNT_ID} ]; then
# #     f_printf_err_exit "\${AWS_ACCOUNT_ID} argument(s) is empty."
# #   elif [ -z ${EKS_ADMIN_01} ]; then
# #     f_printf_err_exit "\${EKS_ADMIN_01} argument(s) is empty."
# #   elif [ -z ${EKS_ADMIN_02} ]; then
# #     f_printf_err_exit "\${EKS_ADMIN_02} argument(s) is empty."
# #   elif [ -z ${EKS_ADMIN_03} ]; then
# #     f_printf_err_exit "\${EKS_ADMIN_03} argument(s) is empty."
# #   elif [ -z ${EKS_ADMIN_04} ]; then
# #     f_printf_err_exit "\${EKS_ADMIN_04} argument(s) is empty."
# #   else
# #     cat > ${WORK_DIR}/aws-auth-cm-group-01.yaml <<EOF
# # apiVersion: v1
# # kind: ConfigMap
# # metadata:
# #   name: aws-auth
# #   namespace: kube-system
# # data:
# #   mapRoles: |
# #     - rolearn: ${EKS_NODE_GROUP_MAIN_INSTANCE_ROLE}
# #       username: system:node:{{EC2PrivateDNSName}}
# #       groups:
# #         - system:bootstrappers
# #         - system:nodes
# #     - rolearn: ${EKS_NODE_GROUP01_INSTANCE_ROLE}
# #       username: system:node:{{EC2PrivateDNSName}}
# #       groups:
# #         - system:bootstrappers
# #         - system:nodes
# #   mapUsers: |
# #     - userarn: arn:aws:iam::${AWS_ACCOUNT_ID}:user/${EKS_ADMIN_01}
# #       username: ${EKS_ADMIN_01}
# #       groups:
# #         - system:masters
# #     - userarn: arn:aws:iam::${AWS_ACCOUNT_ID}:user/${EKS_ADMIN_02}
# #       username: ${EKS_ADMIN_02}
# #       groups:
# #         - system:masters
# #     - userarn: arn:aws:iam::${AWS_ACCOUNT_ID}:user/${EKS_ADMIN_03}
# #       username: ${EKS_ADMIN_03}
# #       groups:
# #         - system:masters
# #     - userarn: arn:aws:iam::${AWS_ACCOUNT_ID}:user/${EKS_ADMIN_04}
# #       username: ${EKS_ADMIN_04}
# #       groups:
# #         - system:masters
# # EOF
# #     cat ${WORK_DIR}/aws-auth-cm-group-01.yaml && \
# #     kubectl apply -f ${WORK_DIR}/aws-auth-cm-group-01.yaml && \
# #     printf "INFO: kubectl describe configmap -n kube-system aws-auth\n" && \
# #     kubectl describe configmap -n kube-system aws-auth
# #   fi
# # }

authNodesGroupAll() {
  # Arguments
  # @{1} mapRoles:
  # example declare -a A_MAP_ROLES=(${EKS_NODE_GROUP02_INSTANCE_ROLE} ${EKS_NODE_GROUP01_INSTANCE_ROLE} ${EKS_NODE_GROUP_MAIN_INSTANCE_ROLE})
  # @{2} mapUsers:
  # example declare -a A_MAP_USERS=(${EKS_ADMIN_01} ${EKS_ADMIN_02} ${EKS_ADMIN_03} ${EKS_ADMIN_04})
  f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/infra/eks/admins/accounts" none stop
  declare -a A_MAP_ROLES=($(aws ssm get-parameters-by-path --region ${AWS_SSM_REGION} --profile ${AWS_PROFILE} --recursive --path "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/" --query "Parameters[*].{Name:Name,Value:Value}" --output text --with-decryption | grep "\/instance-role\/arn" | awk '{print $2}'))
  declare -a A_MAP_USERS=($(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/infra/eks/admins/accounts"))
  if [ -z ${AWS_ACCOUNT_ID} ] ; then
    f_printf_err_exit "\${AWS_ACCOUNT_ID} argument(s) is empty."
  elif [ -z ${NSPACE} ]; then
    f_printf_err_exit "\${NSPACE} argument(s) is empty."
  elif [ -z ${A_MAP_ROLES[0]} ]; then
    f_printf_err_exit "\${A_MAP_ROLES[0]} argument(s) is empty."
  elif [ -z ${A_MAP_USERS[0]} ]; then
    f_printf_err_exit "\${A_MAP_USERS[0]} argument(s) is empty."
  else

    if $(f_is_cluster_exists ${EKS_NAME}) ; then
      aws eks update-kubeconfig --name ${EKS_NAME}
      kubectl config use-context arn:aws:eks:${AWS_DEFAULT_REGION}:${AWS_ACCOUNT_ID}:cluster/${EKS_NAME}
      f_log "INFO: kubectl $(kubectl config view | grep current-context:)"
    else
      f_printf_err_exit "EKS cluster ${EKS_NAME} does not exists"
    fi

    cat > ${WORK_DIR}/aws-auth-cm-all.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
EOF

    for AITEM in ${A_MAP_ROLES[@]} ; do
    cat >> ${WORK_DIR}/aws-auth-cm-all.yaml <<EOF
    - rolearn: ${AITEM}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
EOF
    done

    cat >> ${WORK_DIR}/aws-auth-cm-all.yaml <<EOF
  mapUsers: |
EOF

  for AITEM in ${A_MAP_USERS[@]} ; do
    cat >> ${WORK_DIR}/aws-auth-cm-all.yaml <<EOF
    - userarn: arn:aws:iam::${AWS_ACCOUNT_ID}:user/${AITEM}
      username: ${AITEM}
      groups:
        - system:masters
EOF
    done

    cat ${WORK_DIR}/aws-auth-cm-all.yaml
    kubectl apply -f ${WORK_DIR}/aws-auth-cm-all.yaml
  fi
}

# deployRdsSecurityGroup() {
#   # Arguments
#   # ${1} RDS Security Group # example rds1 or rds2 or rds3
#   local STACK_NAME="${ENV_NAME}-security-group-${1}"
#   if  ! aws cloudformation describe-stacks --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE} --stack-name ${STACK_NAME} >/dev/null 2>&1 ; then
#     printf "INFO: Creating stack ${STACK_NAME};\n"
#   else
#     printf "INFO: Updating stack ${STACK_NAME};\n"
#   fi
#   aws cloudformation deploy \
#     --stack-name ${STACK_NAME} \
#     --template-file ./cfn/amazon-security-group-${1}.yaml \
#     --capabilities CAPABILITY_NAMED_IAM \
#     --parameter-overrides \
#       EnvironmentName=${ENV_NAME} \
#       NameSuffix=${1} \
#       RdsDatabaseName=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/${1}/name") \
#       RdsDatabasePort=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/${1}/db_port") \
#       AccessCidrIp1=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/${1}/access_cidr_ip/1") \
#     --no-fail-on-empty-changeset \
#     --region ${AWS_DEFAULT_REGION} \
#     --profile ${AWS_PROFILE}
#   if [[ ! "$?" == "0" ]]; then
#     exit 8
#   fi
#   getoutput-deployRdsSecurityGroup ${1}
# }

# getoutput-deployRdsSecurityGroup() {
#   # Arguments
#   # ${1} RDS Security Group # example rds1 or rds2 or rds3
#   f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/security-group/${1}/name" none stop
#   f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/security-group/${1}/id" none stop
#   f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/${1}/access_cidr_ip/1" none stop
# }

deployAlbSecurityGroup() {
  # Arguments
  # ${1} Alb Security Group # example alb1 or alb2 or alb3
  local STACK_NAME="${EKS_NAME}-security-group-${1}"
  if  ! aws cloudformation describe-stacks --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE} --stack-name ${STACK_NAME} >/dev/null 2>&1 ; then
    printf "INFO: Creating stack ${STACK_NAME};\n"
  else
    printf "INFO: Updating stack ${STACK_NAME};\n"
  fi
  f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/infra/aws/alb/1/dependency/trusted-ip-cidr" TRUSTED_IP_CIDR stop
  aws cloudformation deploy \
    --stack-name ${STACK_NAME} \
    --template-file ./cfn/amazon-security-group-${1}.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
      EnvironmentType=${ENV_TYPE} \
      EnvironmentName=${ENV_NAME} \
      EksName=${EKS_NAME} \
      NameSpace=${NSPACE} \
      NameSuffix=${1} \
      TrustedIpCidr=${TRUSTED_IP_CIDR} \
    --no-fail-on-empty-changeset \
    --region ${AWS_DEFAULT_REGION} \
    --profile ${AWS_PROFILE}
  if [[ ! "$?" == "0" ]]; then
    exit 8
  fi
  getoutput-deployAlbSecurityGroup ${1}
}

getoutput-deployAlbSecurityGroup() {
  # Arguments
  # ${1} Alb Security Group # example alb1 or alb2 or alb3
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/security-group/${1}/name" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/infra/vpc/security-group/${1}/id" none stop
}

deployEcrRepositories() {
  local STACK_NAME="${ENV_TYPE}-ecr-repositories"
  if  ! aws cloudformation describe-stacks --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE} --stack-name ${STACK_NAME} >/dev/null 2>&1 ; then
    printf "INFO: Creating stack ${STACK_NAME};\n"
  else
    printf "INFO: Updating stack ${STACK_NAME};\n"
  fi
  f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/infra/ecr/ImagesNumberToKeep" IMAGES_NUMBER_TO_KEEP stop
  f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/infra/ecr/DaysToRetainUntaggedImages" DAYS_TO_RETAIN_UNTAGGED_IMAGES stop
  f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/infra/ecr/DaysToRetainFeatureBranchImages" DAYS_TO_RETAIN_FEATURE_BRANCH_IMAGES stop
  f_ssm_get_verbose_parameter "/${COMPANY_NAME_SHORT}/${ENV_TYPE}/infra/ecr/push-principal/01" PUSH_PRINCIPAL_01 stop
  f_ssm_get_verbose_parameter "/${COMPANY_NAME_SHORT}/${ENV_TYPE}/infra/ecr/push-principal/02" PUSH_PRINCIPAL_02 stop
  f_ssm_get_verbose_parameter "/${COMPANY_NAME_SHORT}/${ENV_TYPE}/infra/ecr/push-principal/03" PUSH_PRINCIPAL_03 stop
  f_ssm_get_verbose_parameter "/${COMPANY_NAME_SHORT}/${ENV_TYPE}/infra/ecr/push-principal/04" PUSH_PRINCIPAL_04 stop
  f_ssm_get_verbose_parameter "/${COMPANY_NAME_SHORT}/${ENV_TYPE}/infra/ecr/push-principal/05" PUSH_PRINCIPAL_05 stop
  f_ssm_get_verbose_parameter "/${COMPANY_NAME_SHORT}/${ENV_TYPE}/infra/ecr/push-principal/06" PUSH_PRINCIPAL_06 stop
  f_ssm_get_verbose_parameter "/${COMPANY_NAME_SHORT}/${ENV_TYPE}/infra/ecr/pull-principal/01" PULL_PRINCIPAL_01 stop
  f_ssm_get_verbose_parameter "/${COMPANY_NAME_SHORT}/${ENV_TYPE}/infra/ecr/pull-principal/02" PULL_PRINCIPAL_02 stop
  aws cloudformation deploy \
    --stack-name ${STACK_NAME} \
    --template-file ./cfn/app-docker-repositories.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
      EnvironmentType=${ENV_TYPE} \
      ImagesNumberToKeep=${IMAGES_NUMBER_TO_KEEP} \
      DaysToRetainUntaggedImages=${DAYS_TO_RETAIN_UNTAGGED_IMAGES} \
      DaysToRetainFeatureBranchImages=${DAYS_TO_RETAIN_FEATURE_BRANCH_IMAGES} \
      PushPrincipal01=${PUSH_PRINCIPAL_01} \
      PushPrincipal02=${PUSH_PRINCIPAL_02} \
      PushPrincipal03=${PUSH_PRINCIPAL_03} \
      PushPrincipal04=${PUSH_PRINCIPAL_04} \
      PushPrincipal05=${PUSH_PRINCIPAL_05} \
      PushPrincipal06=${PUSH_PRINCIPAL_06} \
      PullPrincipal01=${PULL_PRINCIPAL_01} \
      PullPrincipal02=${PULL_PRINCIPAL_02} \
    --no-fail-on-empty-changeset \
    --region ${AWS_DEFAULT_REGION} \
    --profile ${AWS_PROFILE}
  if [[ ! "$?" == "0" ]]; then
    exit 8
  fi
  getoutput-deployEcrRepositories
}

getoutput-deployEcrRepositories() {
  getStackOutput ${ENV_TYPE}-ecr-repositories appHttpContentFromGitRepositoryUri
}

# deployRdsCluster() {
#   # Arguments
#   # ${1} RDS Cluster NameSuffix # example rds1 or rds2 or rds3
#   local STACK_NAME="${ENV_NAME}-${1}"
#   if  ! aws cloudformation describe-stacks --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE} --stack-name ${STACK_NAME} >/dev/null 2>&1 ; then
#     printf "INFO: Creating stack ${STACK_NAME};\n"
#   else
#     printf "INFO: Updating stack ${STACK_NAME};\n"
#   fi
#   #TODO check if snapshot exists
#   if [[ "${ENV_NAME}" == "qa56" ]]; then
#     RDS_DB_SNAPSHOT_NAME=""
#   else
#     RDS_DB_SNAPSHOT_NAME="${ENV_NAME}-${1}-cluster-last"
#   fi
#   printf "DEBUG: \${RDS_DB_SNAPSHOT_NAME}: ${RDS_DB_SNAPSHOT_NAME};\n"
#   aws cloudformation deploy \
#     --stack-name ${STACK_NAME} \
#     --template-file ./cfn/amazon-db-${1}.yaml \
#     --capabilities CAPABILITY_NAMED_IAM \
#     --parameter-overrides \
#       EnvironmentType=${ENV_TYPE} \
#       EnvironmentName=${ENV_NAME} \
#       NameSpace=${NSPACE} \
#       NameSuffix=${1} \
#       RdsMasterUsername=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/${1}/db_masterusername") \
#       RdsMasterUserPassword=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/${1}/db_masteruserpassword") \
#       RdsDatabaseName=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/${1}/name") \
#       RdsDatabasePort=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/${1}/db_port") \
#       RdsDbEngineVersion=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/${1}/db_engine_version") \
#       RdsInstanceClass=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/${1}/instance-class") \
#       DomainName=$(f_ssm_get_parameter "/${COMPANY_NAME_SHORT}/${ENV_TYPE}/common/domain/fdqn") \
#       RdsKmsKeyArn=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/kms/1/arn") \
#       RdsDbMaxConnections=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/${1}/max_connections") \
#       RdsDbSnapshotName=${RDS_DB_SNAPSHOT_NAME} \
#     --no-fail-on-empty-changeset \
#     --region ${AWS_DEFAULT_REGION} \
#     --profile ${AWS_PROFILE}
#   if [[ ! "$?" == "0" ]]; then
#     exit 8
#   fi
#   getoutput-deployRdsCluster ${1}
#     # --no-execute-changeset \
# }

# getoutput-deployRdsCluster() {
#   # Arguments
#   # ${1} RDS Cluster NameSuffix # example rds1 or rds2 or rds3
#   f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/${1}/cluster/id" none stop
#   f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/${1}/cluster/endpoint" none stop
#   f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/${1}/cluster/endpoint-read" none stop
#   f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/${1}/cluster/subnet-group" none stop
#   f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/${1}/cluster/parameter-group" none stop
#   f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/${1}/db/parameter-group" none stop
# }

# deployAppResources() {
#   # Arguments
#   # ${1} Application or ALB # example communications or alb2
#   # deleteStackWait ${ENV_NAME}-${NSPACE}-app-${1}-resources
#   local STACK_NAME="${ENV_NAME}-${NSPACE}-app-${1}-resources"
#   AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION}}"
#   if  ! aws cloudformation describe-stacks --region ${AWS_REGION} --profile ${AWS_PROFILE} --stack-name ${STACK_NAME} >/dev/null 2>&1 ; then
#     printf "INFO: Creating stack ${STACK_NAME};\n"
#   else
#     printf "INFO: Updating stack ${STACK_NAME};\n"
#   fi
#   f_log "DEBUG: \${AWS_DEFAULT_REGION}: ${AWS_DEFAULT_REGION}; \${AWS_REGION}: ${AWS_REGION}; \${AWS_PROFILE}: ${AWS_PROFILE};"
#   aws cloudformation deploy \
#     --stack-name ${STACK_NAME} \
#     --template-file ./cfn/app-${1}-resources.yaml \
#     --parameter-overrides \
#       EnvironmentName=${ENV_NAME} \
#       NameSpace=${NSPACE} \
#       AppName=${1} \
#     --no-fail-on-empty-changeset \
#     --region ${AWS_REGION} \
#     --profile ${AWS_PROFILE}
#   if [[ ! "$?" == "0" ]]; then
#     exit 8
#   fi
#   getoutput-deployAppResources "${1}"
# }

# getoutput-deployAppResources() {
#   # Arguments
#   # ${1} Application or ALB # example communications or alb2
#   # echo "getoutput-deployAppResources"
#   if [[ ${1} == "communications" ]] || [[ ${1} == "notification" ]]; then
#     f_ssm_get_verbose_parameter  "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/queue_name" none stop
#     f_ssm_get_verbose_parameter  "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/queue_url" none stop
#     f_ssm_get_verbose_parameter  "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/queue_arn" none stop
#   fi
#   if [[ ${1} == "notification" ]]; then
#     f_ssm_get_verbose_parameter  "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/sms_priority_sqs_name" none stop
#     f_ssm_get_verbose_parameter  "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/sms_priority_sqs_url" none stop
#     f_ssm_get_verbose_parameter  "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/sms_priority_sqs_arn" none stop
#   elif [[ ${1} == "frontend" ]]; then
#     f_ssm_get_verbose_parameter  "${AWS_SSM_CONF_PATH}/${1}/s3bucketName" none stop
#   fi
# }

# # deployApp() {
# #   # Arguments
# #   # ${1} Application or ALB # example communications or alb2
# #   # deleteStackWait ${ENV_NAME}-app-${1}
# #   local STACK_NAME="${ENV_NAME}-${NSPACE}-app-${1}"
# #   if  ! aws cloudformation describe-stacks --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE} --stack-name ${STACK_NAME} >/dev/null 2>&1 ; then
# #     printf "INFO: Creating stack ${STACK_NAME};\n"
# #   else
# #     printf "INFO: Updating stack ${STACK_NAME};\n"
# #   fi
# #   aws cloudformation deploy \
# #     --stack-name ${STACK_NAME} \
# #     --template-file ./cfn/app-${1}.yaml \
# #     --parameter-overrides \
# #       EnvironmentName=${ENV_NAME} \
# #       NameSpace=${NSPACE} \
# #       AppName=${1} \
# #     --no-fail-on-empty-changeset \
# #     --region ${AWS_DEFAULT_REGION} \
# #     --profile ${AWS_PROFILE}
# #   if [[ ! "$?" == "0" ]]; then
# #     exit 8
# #   fi
# #   getoutput-deployApp "${1}"
# # }

# # getoutput-deployApp() {
# #   # Arguments
# #   # ${1} Application or ALB # example communications or alb2
# #   if [[ ${1} == "communications" ]] || [[ ${1} == "notification" ]]; then
# #     f_ssm_get_verbose_parameter  "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/queue_name" none stop
# #     f_ssm_get_verbose_parameter  "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/queue_url" none stop
# #     f_ssm_get_verbose_parameter  "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/queue_arn" none stop
# #   fi
# #   if [[ ${1} == "notification" ]]; then
# #     f_ssm_get_verbose_parameter  "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/sms_priority_sqs_name" none stop
# #     f_ssm_get_verbose_parameter  "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/sms_priority_sqs_url" none stop
# #     f_ssm_get_verbose_parameter  "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/sms_priority_sqs_arn" none stop
# #   fi
# # }

deployNspaceCertificates() {
  # Arguments
  # ${1} EKS Name Space # example nspace10, nspace20, nspace21, nspace60
  NSPACE=${1:-${NSPACE}}
  local STACK_NAME="${ENV_NAME}-${NSPACE}-certificates-${AWS_REGION}"
  if  ! aws cloudformation describe-stacks --region ${AWS_REGION} --profile ${AWS_PROFILE} --stack-name ${STACK_NAME} >/dev/null 2>&1 ; then
    printf "\nINFO: $(date +%Y%m%d-%H%M%S) : Creating stack ${STACK_NAME};\n"
  else
    printf "\nINFO: $(date +%Y%m%d-%H%M%S) : Updating stack ${STACK_NAME};\n"
  fi
  f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/infra/dns/1/route53_zone_id" ROUTE53_ZONE_ID stop
  # if [[ "${ENV_TYPE}" == "qa" ]]; then
  #   DOMAIN_NAME="${ENV_NAME}-${NSPACE}.${DNS_NAME_FQDN}"
  # elif [[ "${ENV_TYPE}" == "prod" ]]; then
  #   DOMAIN_NAME="${DNS_NAME_FQDN}"
  # fi
  DOMAIN_NAME="${DNS_NAME_FQDN}"
  CERT_CNAMES="*.app.${DNS_NAME_FQDN}, *.${DNS_NAME_FQDN}"
  f_log "INFO: \${NSPACE}: ${NSPACE}; \${DOMAIN_NAME}: ${DOMAIN_NAME}; \${CERT_CNAMES}: ${CERT_CNAMES};"
  f_log "DEBUG: \${AWS_DEFAULT_REGION}: ${AWS_DEFAULT_REGION}; \${AWS_REGION}: ${AWS_REGION}; \${AWS_PROFILE}: ${AWS_PROFILE};"
  aws cloudformation deploy \
    --stack-name ${STACK_NAME} \
    --template-file ./cfn/amazon-certificates-nspace.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
      EnvironmentName=${ENV_NAME} \
      NameSpace=${NSPACE} \
      SsmBasePath=${AWS_SSM_BASE_PATH} \
      DomainName=${DOMAIN_NAME} \
      Cnames="${CERT_CNAMES}" \
      Route53ZoneId=${ROUTE53_ZONE_ID} \
    --no-fail-on-empty-changeset \
    --region ${AWS_REGION} \
    --profile ${AWS_PROFILE}
  if [[ ! "$?" == "0" ]]; then
    exit 8
  fi
  # getoutput-deployCloudWatchAlert ${1}
  f_log "INFO: $(date +%Y%m%d-%H%M%S) : Copying the certificate Arn to ${AWS_SSM_REGION} region Parameter Store"
  f_ssm_put_parameter "String" "${AWS_SSM_BASE_PATH}/${NSPACE}/infra/certs/${AWS_REGION}/1/arn" "$(getStackOutput ${STACK_NAME} CertificateArn)"
}

# deployCloudFrontApp() {
#   # Arguments
#   # ${1} Application # example frontend
#   local STACK_NAME="${ENV_NAME}-${NSPACE}-app-${1}-cloudfront"
#   # deleteStackWait ${STACK_NAME}
#   if  ! aws cloudformation describe-stacks --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE} --stack-name ${STACK_NAME} >/dev/null 2>&1 ; then
#     printf "\nINFO: $(date +%Y%m%d-%H%M%S) : Creating stack ${STACK_NAME};\n"
#   else
#     printf "\nINFO: $(date +%Y%m%d-%H%M%S) : Updating stack ${STACK_NAME};\n"
#   fi
#   # if [[ "${ENV_TYPE}" == "qa" ]]; then
#   #   DOMAIN_NAME="${NSPACE}.${DNS_NAME_FQDN}"
#   # elif [[ "${ENV_TYPE}" == "prod" ]]; then
#   #   DOMAIN_NAME="${DNS_NAME_FQDN}"
#   # fi
#   DOMAIN_NAME="${DNS_NAME_FQDN}"
#   CERT_CNAMES="*.app.${DNS_NAME_FQDN}"
#   f_log "INFO: \${NSPACE}: ${NSPACE}; \${DOMAIN_NAME}: ${DOMAIN_NAME}; \${CERT_CNAMES}: ${CERT_CNAMES}; \${ROUTE53_ZONE_ID}: ${ROUTE53_ZONE_ID};"
#   f_log "DEBUG: \${AWS_DEFAULT_REGION}: ${AWS_DEFAULT_REGION}; \${AWS_REGION}: ${AWS_REGION}; \${AWS_PROFILE}: ${AWS_PROFILE};"
#   aws cloudformation deploy \
#     --stack-name ${STACK_NAME} \
#     --template-file ./cfn/app-${1}-cloudfront.yaml \
#     --parameter-overrides \
#       EnvironmentName=${ENV_NAME} \
#       NameSpace=${NSPACE} \
#       AppName=${1} \
#       DomainName=${DOMAIN_NAME} \
#       Cnames="${CERT_CNAMES}" \
#       Route53ZoneId=${ROUTE53_ZONE_ID} \
#       AcmCertificateArn=$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/${NSPACE}/infra/certs/us-east-1/1/arn") \
#     --no-fail-on-empty-changeset \
#     --region ${AWS_DEFAULT_REGION} \
#     --profile ${AWS_PROFILE}
#   if [[ ! "$?" == "0" ]]; then
#     exit 8
#   fi
#   sleep 1
#   aws cloudfront create-invalidation --distribution-id $(aws cloudformation describe-stacks --stack-name ${ENV_NAME}-${NSPACE}-app-${1}-cloudfront --query "Stacks[0].Outputs[?OutputKey=='CloudFrontDistributionId'] | [0].OutputValue" --output text) --paths "/*"
#   # getoutput-deployCloudFrontApp "${1}"
# }

# # getoutput-deployCloudFrontApp() {
# #   # Arguments
# #   # ${1} Application or ALB # example communications or alb2
# #   if [[ ${1} == "communications" ]] || [[ ${1} == "notification" ]]; then
# #     f_ssm_get_verbose_parameter  "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/queue_name" none stop
# #     f_ssm_get_verbose_parameter  "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/queue_url" none stop
# #     f_ssm_get_verbose_parameter  "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/queue_arn" none stop
# #   fi
# #   if [[ ${1} == "notification" ]]; then
# #     f_ssm_get_verbose_parameter  "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/sms_priority_sqs_name" none stop
# #     f_ssm_get_verbose_parameter  "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/sms_priority_sqs_url" none stop
# #     f_ssm_get_verbose_parameter  "${AWS_SSM_CONF_PATH}/${1}/${ENV_NAME}-${NSPACE}-docker/sms_priority_sqs_arn" none stop
# #   fi
# # }

deploySnsTopics() {
  local STACK_NAME="${ENV_NAME}-${NSPACE}-sns-topics"
  if  ! aws cloudformation describe-stacks --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE} --stack-name ${STACK_NAME} >/dev/null 2>&1 ; then
    printf "INFO: Creating stack ${STACK_NAME};\n"
  else
    printf "INFO: Updating stack ${STACK_NAME};\n"
  fi
  aws cloudformation deploy \
    --stack-name ${STACK_NAME} \
    --template-file ./cfn/amazon-sns-topics.yaml \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides \
      EnvironmentName=${ENV_NAME} \
      NameSpace=${NSPACE} \
    --no-fail-on-empty-changeset \
    --region ${AWS_DEFAULT_REGION} \
    --profile ${AWS_PROFILE} 
  if [[ ! "$?" == "0" ]]; then
    exit 8
  fi
  getoutput-deploySnsTopics
}

getoutput-deploySnsTopics() {
  f_ssm_get_verbose_parameter  "${AWS_SSM_CONF_PATH}/sns/1/name" none stop
  f_ssm_get_verbose_parameter  "${AWS_SSM_CONF_PATH}/sns/1/arn" none stop
}

deployCloudWatchAlert() {
  # Arguments
  # ${1} Application # example communications or notification
  # deleteStackWait ${ENV_NAME}-app-${1}
  printf "INFO: TODO deployCloudWatchAlert;\n"
  # local STACK_NAME="${ENV_NAME}-${NSPACE}-${1}-CloudWatchAlert"
  # f_ssm_get_verbose_parameter  "${AWS_SSM_BASE_PATH}/url_sid" URL_PATH_FRONTEND stop
  # URL_PATH_FRONTEND="/${URL_PATH_FRONTEND}/info.json"
  # if  ! aws cloudformation describe-stacks --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE} --stack-name ${STACK_NAME} >/dev/null 2>&1 ; then
  #   printf "INFO: Creating stack ${STACK_NAME};\n"
  # else
  #   printf "INFO: Updating stack ${STACK_NAME};\n"
  # fi
  # printf "DEBUG: \${DNS_NAME_FQDN}: ${DNS_NAME_FQDN}; \${URL_PATH_FRONTEND}: ${URL_PATH_FRONTEND};\n"
  # aws cloudformation deploy \
  #   --stack-name ${STACK_NAME} \
  #   --template-file ./cfn/amazon-cloudwatch-event-route53.yaml \
  #   --capabilities CAPABILITY_NAMED_IAM \
  #   --parameter-overrides \
  #     EnvironmentName=${ENV_NAME} \
  #     NameSpace=${NSPACE} \
  #     AppName=${1} \
  #     DnsNameFqdn=${DNS_NAME_FQDN} \
  #     ClientName=client01 \
  #     UrlPathApps=/actuator/health \
  #     UrlPathFrontend=${URL_PATH_FRONTEND} \
  #   --no-fail-on-empty-changeset \
  #   --region ${AWS_DEFAULT_REGION} \
  #   --profile ${AWS_PROFILE}
  # if [[ ! "$?" == "0" ]]; then
  #   exit 8
  # fi
  # getoutput-deployCloudWatchAlert ${1}
}

eksCleanup() {
  echo "INFO: Cleanup started $(date +%Y%m%d-%H%M)"
  if [[ "${ENV_NAME}" == "qa56" ]]; then
    # f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/nspaces/list" # DEBUG
    # for ITEM2 in $(f_ssm_get_parameter ${AWS_SSM_BASE_PATH}/nspaces/list); do
    deleteStackWait ${ENV_NAME}-rds2
    deleteStackWait ${ENV_NAME}-security-group-rds2
    for ITEM2 in nspace30; do
      export NSPACE="${ITEM2}"
      f_log "\nINFO: ==== Cleaning NameSpace ${ITEM2} in ${ENV_NAME} ====\n"
      export CLEAN_NSPACE_ALL_PODS=true && export CLEAN_NSPACE_ALL_ALBS=true
      f_app_nspace_clean ${NSPACE}
    done
    deleteStackWait ${EKS_NAME}-security-group-alb3
    deleteStackWait ${EKS_NAME}-security-group-alb2
    deleteStackWait ${EKS_NAME}-security-group-alb1
    deleteStackWait ${EKS_NAME}-nodes-${EKS_NODE_GROUP02_NAME}
    deleteStackWait ${EKS_NAME}-nodes-policy-${EKS_NODE_GROUP02_NAME}
    deleteStackWait ${EKS_NAME}-nodes-${EKS_NODE_GROUP01_NAME}
    f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/0/name" EKS_NODE_GROUP_MAIN_NAME stop
    deleteStackWait ${EKS_NAME}-nodes-${EKS_NODE_GROUP_MAIN_NAME}
    deleteStackWait ${EKS_NAME}-nodes-policy-${EKS_NODE_GROUP_MAIN_NAME}
    deleteStackWait ${EKS_NAME}-nodes-policy-${EKS_NODE_GROUP01_NAME}
    echo "Deleting EKS cluster: ${EKS_NAME}. Please take your lunch."
    deleteStackWait ${EKS_NAME}-cluster
    
    # deleteStackWait ${ENV_NAME}-vpc-peering-cross-id-2
    # deleteStackWait ${ENV_NAME}-vpc-peering-1
    deleteStackWait ${ENV_NAME}-policies
    deleteStackWait ${EKS_NAME}-security-groups
    deleteStackWait ${ENV_NAME}-vpc
    deleteStackWait ${EKS_SERVICE_ROLE_NAME}
  fi
  echo "INFO: Cleanup finished $(date +%Y%m%d-%H%M)"
}

eksCreateCluster() {

echo "INFO: Deploying stack name: ${ENV_NAME} ..."
echo "$(date +%Y%m%d-%H%M)"

  deployServiceRole

  deployVPC3x3x3x3

  deploySecurityGroups

  deployCluster

  aws eks update-kubeconfig --name ${EKS_NAME} --region ${AWS_DEFAULT_REGION} --profile ${AWS_PROFILE}
  kubectl config use-context ${EKS_ARN}

  f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/infra/instance_key_pair1/name" AWS_KEY_PAIR_NAME stop
  f_awsKeyPair "${AWS_KEY_PAIR_NAME}" "${COMPANY_NAME_SHORT}/"

  deployPolicies
  deployNodesGroupPolicy ${EKS_NODE_GROUP_MAIN_NAME}

  deployNodesGroupMain
  authNodesGroupAll

  . ./helm-cli-install.sh

  deployNodesGroupPolicy ${EKS_NODE_GROUP01_NAME}

  sleep 20
  kubectl get nodes --show-labels
  sleep 5
  kubectl get nodes

  f_create_k8s_namespace ${NSPACE}

  deployNodesGroup01 ${NSPACE}
  authNodesGroupAll 

  # createNodesGroup02
  # authNodesGroupAll

  deployRdsSecurityGroup rds2

  deployAlbSecurityGroup alb3
  deployAlbSecurityGroup alb2
  deployAlbSecurityGroup alb1

  . ./app-docker-repositories.sh && createEcrRepositories

  . ./helm-aws-node-termination-handler.sh
  . ./cluster-autoscaler.sh
  . ./hpa-deploy.sh
  
  sleep 20
  kubectl get nodes
  sleep 20
  kubectl get nodes --show-labels

  . ./alb-ingress-controller.sh

  . ./bin/deploy-k8s.sh test ${NSPACE} 58190 58190 1


  # bash -c "export ENV_NAME="${ENV_NAME}" && export CI_CD_DEPLOY=true && ./bin/deploy-k8s.sh alb2-mgmt ${NSPACE} 12345 12345 1"

  echo "$(date +%Y%m%d-%H%M)"

}

getOutput-all() {
  getoutput-deployServiceRole
  getoutput-createVPC3x3x3x3
  getoutput-createSecurityGroups
  getoutput-createCluster
  getoutput-createPolicies
  f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/0/name" EKS_NODE_GROUP_MAIN_NAME stop
  getoutput-createNodesGroupPolicy ${EKS_NODE_GROUP_MAIN_NAME}
  getoutput-createNodesGroupPolicy ${EKS_NODE_GROUP01_NAME}
  getoutput-deployAlbSecurityGroup alb2
  # getoutput-deployAlbSecurityGroup alb1
  getoutput-deployNodesGroupMain
  getoutput-deployNodesGroup01
  # getoutput-createNodesGroup02
}

f_log "\nINFO: lib_cfn.sh finished\n\n"
