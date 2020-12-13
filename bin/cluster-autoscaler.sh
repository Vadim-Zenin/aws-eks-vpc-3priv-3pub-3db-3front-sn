#!/bin/bash
# Usage:
# . ./bin/cluster-autoscaler.sh

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

# === Cluster Autoscaler
printf "\nINFO: cluster-autoscaler.sh started\n\n"

f_include_init
f_ssm_get_verbose_parameter "${AWS_SSM_BASE_PATH}/infra/eks/version" EKS_VERSION stop

# https://docs.aws.amazon.com/eks/latest/userguide/cluster-autoscaler.html
mkdir -p -m 775 ${DOWNLOAD_DIR}/clusterAutoscaler/
# . ./cluster-autoscaler-policy.sh

# https://github.com/kubernetes/autoscaler/releases
# Open the Cluster Autoscaler releases page in a web browser and find the Cluster Autoscaler version that matches your cluster's Kubernetes major and minor version. For example, if your cluster's Kubernetes version is 1.14, find the Cluster Autoscaler release that begins with 1.14. Record the semantic version number (1.14.n) for that release to use in the next step.

AUTOSCALER_VERSION=$(curl --silent https://api.github.com/repos/kubernetes/autoscaler/releases \
 | jq -r ".[].tag_name" | grep "cluster-autoscaler-${EKS_VERSION}" \
 | grep -v "alpha\|beta" | sed "s/cluster-autoscaler-//g" | sort -Vr | head -n1)
 printf "\nINFO: \${AUTOSCALER_VERSION}: ${AUTOSCALER_VERSION};\n"
wget -q -O ${DOWNLOAD_DIR}/clusterAutoscaler/cluster-autoscaler-autodiscover.yaml "https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/aws/examples/cluster-autoscaler-autodiscover.yaml"
perl -pi -e 's/^(.*?)(<YOUR CLUSTER NAME>)(.*?)/${1}'${EKS_NAME}'\n            - --balance-similar-node-groups\n            - --skip-nodes-with-system-pods=false/' ${DOWNLOAD_DIR}/clusterAutoscaler/cluster-autoscaler-autodiscover.yaml
perl -pi -e 's/^(.*?)(k8s.gcr.io\/autoscaling\/cluster-autoscaler:v)(.*)/${1}${2}'${AUTOSCALER_VERSION}'/' ${DOWNLOAD_DIR}/clusterAutoscaler/cluster-autoscaler-autodiscover.yaml
cat ${DOWNLOAD_DIR}/clusterAutoscaler/cluster-autoscaler-autodiscover.yaml | grep "cluster-autoscaler:v\|node-group-auto-discovery"
kubectl apply -f ${DOWNLOAD_DIR}/clusterAutoscaler/cluster-autoscaler-autodiscover.yaml
sleep 2
kubectl -n kube-system annotate deployment.apps/cluster-autoscaler cluster-autoscaler.kubernetes.io/safe-to-evict="false"
sleep 3
f_k8s_pods_namespace_run_check "cluster-autoscaler" "kube-system"
printf "INFO: kubectl get pods,deploy,rs,sts,ds,svc,endpoints,ing,pv,pvc,hpa -o wide -A | grep cluster-autoscaler\n"
kubectl get pods,deploy,rs,sts,ds,svc,endpoints,ing,pv,pvc,hpa -o wide -A | grep cluster-autoscaler
sleep 2
kubectl -n kube-system logs deployment.apps/cluster-autoscaler | tail -n 20

printf "\nINFO: cluster-autoscaler.sh finished\n\n"
