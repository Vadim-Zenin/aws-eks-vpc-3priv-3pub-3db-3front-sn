#!/bin/bash
# Usage:
# . ./bin/cwagent-fluentd.sh

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
printf "\nINFO: cwagent-fluentd.sh started\n\n"

f_include_init

# === Container Insights on Amazon EKS
# https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/Container-Insights-setup-EKS-quickstart.html
mkdir -p -m 775 ${DOWNLOAD_DIR}/cwagent-fluentd/

curl -sSL https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluentd-quickstart.yaml | sed "s^{{cluster_name}}^${EKS_NAME}^;s^{{region_name}}^${AWS_DEFAULT_REGION}^" | tee ${DOWNLOAD_DIR}/cwagent-fluentd/cwagent-fluentd-deployment.yaml

cat ${DOWNLOAD_DIR}/cwagent-fluentd/cwagent-fluentd-deployment.yaml | grep configHash
printf "INFO: updating configHash\n"
perl -pi -e 's/^([ \t].*?)(configHash: )(.*)/${1}${2}'$(cat ${DOWNLOAD_DIR}/cwagent-fluentd/cwagent-fluentd-deployment.yaml | sha256sum | cut -d' ' -f1)'/' ${DOWNLOAD_DIR}/cwagent-fluentd/cwagent-fluentd-deployment.yaml
cat ${DOWNLOAD_DIR}/cwagent-fluentd/cwagent-fluentd-deployment.yaml | grep configHash:

cat ${DOWNLOAD_DIR}/cwagent-fluentd/cwagent-fluentd-deployment.yaml | grep image:
perl -pi -e 's/^([ \t].*?)(image: amazon\/cloudwatch-agent:)(.*)/${1}${2}'$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/infra/eks/docker/amazon/cloudwatch-agent/version")'/' ${DOWNLOAD_DIR}/cwagent-fluentd/cwagent-fluentd-deployment.yaml
perl -pi -e 's/^([ \t].*?)(image: fluent\/fluentd-kubernetes-daemonset:)(.*)/${1}${2}'$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/infra/eks/docker/fluent/fluentd-kubernetes-daemonset/version")'/' ${DOWNLOAD_DIR}/cwagent-fluentd/cwagent-fluentd-deployment.yaml
cat ${DOWNLOAD_DIR}/cwagent-fluentd/cwagent-fluentd-deployment.yaml | grep image:

kubectl apply -f ${DOWNLOAD_DIR}/cwagent-fluentd/cwagent-fluentd-deployment.yaml
sleep 5
printf "INFO: kubectl get pods,deploy,rs,sts,ds,svc,endpoints,ing,pv,pvc,hpa -o wide -A | grep cloudwatch\n"
kubectl get pods,deploy,rs,sts,ds,svc,endpoints,ing,pv,pvc,hpa -o wide -A | grep cloudwatch
printf "INFO: kubectl get pods,deploy,rs,sts,ds,svc,endpoints,ing,pv,pvc,hpa -o wide -A | grep cloudwatch\n"

printf "\nINFO: cwagent-fluentd.sh finished\n\n"
