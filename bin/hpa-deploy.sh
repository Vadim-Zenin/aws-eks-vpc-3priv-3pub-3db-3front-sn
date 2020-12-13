#!/bin/bash
# Horizontal Pod Autoscaler - Amazon EKS installation
# Usage:
# . ./bin/hpa-deploy.sh

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

# === AWS Horizontal Pod Autoscaler

printf "\nINFO: hpa-deploy.sh started\n\n"

f_include_init

DOWNLOAD_URL=$(curl --silent "https://api.github.com/repositories/92132038/releases/latest" | jq -r .tarball_url)
DOWNLOAD_VERSION=$(grep -o '[^/v]*$' <<< ${DOWNLOAD_URL})
mkdir -p ${DOWNLOAD_DIR}/metrics-server-${DOWNLOAD_VERSION}/
wget -O "${DOWNLOAD_DIR}/metrics-server-${DOWNLOAD_VERSION}/components.yaml" "https://github.com/kubernetes-sigs/metrics-server/releases/download/v${DOWNLOAD_VERSION}/components.yaml"
kubectl apply -f ${DOWNLOAD_DIR}/metrics-server-${DOWNLOAD_VERSION}/components.yaml
sleep 5
printf "INFO: kubectl get deployment metrics-server -n kube-system\n"
kubectl get deployment metrics-server -n kube-system

printf "\nINFO: hpa-deploy.sh finished\n\n"
