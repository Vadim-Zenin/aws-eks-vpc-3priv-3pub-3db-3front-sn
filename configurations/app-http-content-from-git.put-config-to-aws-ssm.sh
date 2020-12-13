#!/bin/bash
# put-configuration-to-aws-parameter-store
# app-http-content-from-git.put-config-to-aws-ssm.sh
################################################################################
# Functions
################################################################################

################################################################################
# MAIN
################################################################################

APP_NAME="app-http-content-from-git"

printf "\nINFO: ${APP_NAME}.put-config-to-aws-ssm.sh started\n\n"

echo "INFO: \${APP_NAME} : ${APP_NAME}"
source ./configurations/include.put-config-to-aws-ssm.sh
echo "INFO: \${AWS_SSM_CONF_PATH} : ${AWS_SSM_CONF_PATH}"

if [[ "${ENV_TYPE}" == "prod" ]]; then
  K8S_REPLICAS="2"
  CPU_PERCENT="90"
  HPA_MIN="2"
  HPA_MAX="10"
else
  K8S_REPLICAS="2"
  CPU_PERCENT="90"
  HPA_MIN="2"
  HPA_MAX="5"
fi

f_ssm_put_parameter  "String"  "${AWS_SSM_CONF_PATH}/${APP_NAME}/port" "80"
f_ssm_put_parameter  "String"  "${AWS_SSM_CONF_PATH}/${APP_NAME}/containerPort" "80"
f_ssm_put_parameter  "String"  "${AWS_SSM_CONF_PATH}/${APP_NAME}/k8sReplicas" "${K8S_REPLICAS}"
f_ssm_put_parameter  "String"  "${AWS_SSM_CONF_PATH}/${APP_NAME}/hpa/cpu-percent" "${CPU_PERCENT}"
f_ssm_put_parameter  "String"  "${AWS_SSM_CONF_PATH}/${APP_NAME}/hpa/min" "${HPA_MIN}"
f_ssm_put_parameter  "String"  "${AWS_SSM_CONF_PATH}/${APP_NAME}/hpa/max" "${HPA_MAX}"
f_ssm_put_parameter  "String"  "${AWS_SSM_CONF_PATH}/${APP_NAME}/${ENV_NAME}-${NSPACE}-docker/internal_url" "${ENV_NAME}-${NSPACE}-${APP_NAME}-svc"
f_ssm_put_parameter  "String"  "${AWS_SSM_CONF_PATH}/${APP_NAME}/dependency/apps" "None"
f_ssm_put_parameter  "String"  "${AWS_SSM_CONF_PATH}/${APP_NAME}/dependency/albs" "alb1-public"

printf "\nINFO: ${APP_NAME}.put-config-to-aws-ssm.sh finished\n\n"
