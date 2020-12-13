#!/bin/bash
# put-common-configuration-to-aws-parameter-store
# common.put-config-to-aws-ssm.sh
# export COMPANY_NAME_SHORT="abc" && export ENV_TYPE="test" && export IP_2ND_OCTET="16" && export NSPACE="nspace60" && export APP_NAME="app-http-content-from-git" && bash -c "./common.put-config-to-aws-ssm.sh"
################################################################################
# Functions
################################################################################

################################################################################
# MAIN
################################################################################

printf "\nINFO: common.put-config-to-aws-ssm.sh started\n\n"

source ./configurations/include.put-config-to-aws-ssm.sh

printf "INFO: \${AWS_SSM_BASE_PATH} : ${AWS_SSM_BASE_PATH}\n"
printf "INFO: \${AWS_SSM_CONF_PATH} : ${AWS_SSM_CONF_PATH}\n"

f_ssm_put_parameter  "String"  "/${COMPANY_NAME_SHORT}/test/infra/ip-2nd-octets/list" "16"
# f_ssm_put_parameter  "String"  "/${COMPANY_NAME_SHORT}/qa/infra/ip-2nd-octets/list" ""
# f_ssm_put_parameter  "String"  "/${COMPANY_NAME_SHORT}/prod/infra/ip-2nd-octets/list" ""

# f_ssm_put_parameter  "String"  "/${COMPANY_NAME_SHORT}/${ENV_TYPE}/common/domain/fdqn"  "${ROUTE53_ZONE_DOMAIN}"

f_ssm_put_parameter  "String"  "/${COMPANY_NAME_SHORT}/${ENV_TYPE}/infra/aws/default-region" "eu-west-1"

f_ssm_put_parameter  "String"  "/${COMPANY_NAME_SHORT}/${ENV_TYPE}/infra/aws/default-region" "eu-west-1"

f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/${NSPACE}/name" "${NSPACE}"

f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/instance_key_pair1/name"  "${COMPANY_NAME_SHORT}-${ENV_TYPE}-all"
f_ssm_put_parameter  "SecureString"  "${AWS_SSM_BASE_PATH}/infra/instance_key_pair1/privateKey"  "$(cat ${HOME}/.ssh/${COMPANY_NAME_SHORT}/${COMPANY_NAME_SHORT}-${ENV_TYPE}-all.priv.key)"
f_ssm_put_parameter  "SecureString"  "${AWS_SSM_BASE_PATH}/infra/instance_key_pair1/publicKey"  "$(cat ${HOME}/.ssh/${COMPANY_NAME_SHORT}/${COMPANY_NAME_SHORT}-${ENV_TYPE}-all.pub.key)"

f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/0/name"  "main"

f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/aws/albs/list"  "alb1-public"
f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/aws/alb/1/name"  "alb1-public"
f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/aws/alb/1/dependency/apps"  "None"
# f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/aws/alb/1/dependency/trusted-ip-cidr"  "1.2.3.4/32"

printf "\nINFO: common.put-config-to-aws-ssm.sh finished\n\n"
