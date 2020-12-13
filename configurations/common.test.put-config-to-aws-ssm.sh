#!/bin/bash
# put-common-configuration-to-aws-parameter-store
# common.test.put-config-to-aws-ssm.sh
# export COMPANY_NAME_SHORT="abc" && export ENV_TYPE="test" && export IP_2ND_OCTET="16" && export NSPACE="nspace60" && export APP_NAME="app-http-content-from-git" && bash -c "./common.test.put-config-to-aws-ssm.sh"
################################################################################
# Functions
################################################################################

################################################################################
# MAIN
################################################################################

printf "\nINFO: common.test.put-config-to-aws-ssm.sh started\n\n"
source ./configurations/include.put-config-to-aws-ssm.sh
f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/aws-default-region"  "eu-west-1"
echo "INFO: \${AWS_SSM_BASE_PATH} : ${AWS_SSM_BASE_PATH}"
echo "INFO: \${AWS_SSM_CONF_PATH} : ${AWS_SSM_CONF_PATH}"

f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/ip-2nd-octet"     "${IP_2ND_OCTET}"

if [[ "${NSPACE}" == "nspace60" ]]; then
  # eks-node-group-main
  f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/0/instance-type"     "t3a.small"
  # eks-node-group-main-min <= eks-node-group-main-desired <= eks-node-group-main-max
  f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/0/min"     "2"
  f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/0/desired"  "2"
  f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/0/max"     "3"
  f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/0/volume-size"     "100"
  # Description: Indicates whether detailed instance monitoring is enabled for the Auto Scaling group. By default, this property is set to true (enabled). true = monitor every 1 minute. false = monitor every 5 minutes. (true or false). Default: false
  f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/0/autoscaling-group-monitoring-detailed"  "true"
fi

if [[ "${ENV_NAME}" == "test16" ]] ; then
  f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/version"     "1.18"
  # TODO migrate to version 2 on https://github.com/kubernetes-sigs/aws-load-balancer-controller later
  f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/alb-ingress-controller/version"  "v1.1.8"
  # https://github.com/kubernetes-sigs/external-dns/releases
  f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/external-dns/version"  "0.7.1"

  f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/nspaces/list"  "nspace60"

  f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/01/name"  "nspace60"

  # f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/60/name"  "nspace60"
  # f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/60/min" "1"
  # f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/60/desired" "1"
  # f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/60/max" "5"
  # f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/60/autoscaling-group-monitoring-detailed"  "true"
  # f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/60/instance-type" "t3a.xlarge"
  # f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/60/on-demand-base-capacity"  "0"
  # # Description: "on-demand percentage above base capacity(0-100)"
  # f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/60/on-demand-percentage-above-base-capacity"  "0"
  # # Description: "spot instance pools(1-20)"
  # f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/60/spot-instance-pools"  "2"
  # # Description: "multiple spot instances to override (separated by comma)"
  # # f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/60/instance-types-override"  "a1.large,t3a.large,t3.large,m5a.large,c5.large,c5d.large,c4.large,c3.large,r5a.large"
  # f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/60/instance-types-override"  "t3a.xlarge,t3.xlarge,m5a.xlarge,c5.xlarge,c5d.xlarge,c4.xlarge,c3.xlarge,r5a.xlarge,t3a.2xlarge"

  for ITEM in nspace60; do
    f_log "INFO: Congiguring name space ${ITEM}"
    NSPACE_DIGITS=$(echo "${ITEM}" | sed 's/[^0-9]*//g' | sed 's/^0*//')
    printf "INFO: \${NSPACE_DIGITS} : ${NSPACE_DIGITS};\n"
    f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/${NSPACE_DIGITS}/name"  "${ITEM}"
    f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/${NSPACE_DIGITS}/min" "2"
    f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/${NSPACE_DIGITS}/desired" "2"
    f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/${NSPACE_DIGITS}/max" "5"
    f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/${NSPACE_DIGITS}/autoscaling-group-monitoring-detailed"  "true"
    f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/${NSPACE_DIGITS}/instance-type" "t3a.xlarge"
    f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/${NSPACE_DIGITS}/on-demand-base-capacity"  "0"
    f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/${NSPACE_DIGITS}/on-demand-percentage-above-base-capacity"  "0"
    f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/${NSPACE_DIGITS}/spot-instance-pools"  "2"
    f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/nodes-group/${NSPACE_DIGITS}/instance-types-override"  "t3a.xlarge,t3.xlarge,m5a.xlarge,c5.xlarge,c5d.xlarge,c4.xlarge,c3.xlarge,r5a.xlarge,t3a.2xlarge"
  done
fi

# https://hub.docker.com/r/amazon/cloudwatch-agent/tags
f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/docker/amazon/cloudwatch-agent/version"  "1.237768.0"
# https://hub.docker.com/r/fluent/fluentd-kubernetes-daemonset
f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/docker/fluent/fluentd-kubernetes-daemonset/version"  "v1.10.2-debian-cloudwatch-1.0"
# f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/docker/amazon/cloudwatch-agent/version"  "latest"
# f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/docker/fluent/fluentd-kubernetes-daemonset/version"  "v1.9-debian-cloudwatch-1"
f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/eks/logs/loggroup/RetentionInDays"  "5"

f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/ecr/ImagesNumberToKeep"  "20"
f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/ecr/DaysToRetainUntaggedImages"  "3"
f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/infra/ecr/DaysToRetainFeatureBranchImages"  "21"

for ITEM2 in $(f_ssm_get_parameter ${AWS_SSM_BASE_PATH}/nspaces/list); do
  printf "\nINFO: processing ${ITEM2} from ${AWS_SSM_BASE_PATH}/nspaces/list\n\n"
  if [[ "${ITEM2}" == "nspace60" ]]; then
    f_ssm_put_parameter  "String"  "${AWS_SSM_BASE_PATH}/${ITEM2}/apps/list" "app-http-content-from-git echo"
  fi
done

printf "\nINFO: common.test.put-config-to-aws-ssm.sh finished\n\n"
