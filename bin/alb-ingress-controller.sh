#!/bin/bash
# Usage:
# . ./bin/alb-ingress-controller.sh

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
printf "\nINFO: alb-ingress-controller.sh started\n\n"

f_include_init

# === alb-ingress-controller on EKS
# https://github.com/kubernetes-sigs/aws-alb-ingress-controller/releases

mkdir -p -m 775 ${DOWNLOAD_DIR}/alb-ingress-controller

ALB_INGRESS_CONTROLLER_VERSION="$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/infra/eks/alb-ingress-controller/version")"
f_log "INFO: \${ALB_INGRESS_CONTROLLER_VERSION}: ${ALB_INGRESS_CONTROLLER_VERSION}"
EXTERNAL_DNS_VERSION="$(f_ssm_get_parameter "${AWS_SSM_BASE_PATH}/infra/eks/external-dns/version")"
f_log "INFO: \${EXTERNAL_DNS_VERSION}: ${EXTERNAL_DNS_VERSION}"

# === The policy ${DOWNLOAD_DIR}/alb-ingress-controller/iam-policy.json manually integrated to cfn/amazon-policies.yaml
# and deployed by command . ./bin/lib_cfn.sh && f_include_lib_cfn && createNodesPolicies
printf "\nINFO: deploying alb-ingress-controller\n\n"
# TODO migrate to v2
# wget -q -O ${DOWNLOAD_DIR}/alb-ingress-controller/alb-rbac-role.yaml "https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/${ALB_INGRESS_CONTROLLER_VERSION}/docs/examples/rbac-role.yaml"
kubectl apply -f ${DOWNLOAD_DIR}/alb-ingress-controller/alb-rbac-role.yaml
# kubectl apply -f ${DOWNLOAD_DIR}/alb-ingress-controller/alb-rbac-role-client01.yaml

# wget -q -O ${DOWNLOAD_DIR}/alb-ingress-controller/alb-ingress-controller.yaml "https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/${ALB_INGRESS_CONTROLLER_VERSION}/docs/examples/alb-ingress-controller.yaml"
perl -pi -e 's/^(.*?)(image: )(.*?)(aws-alb-ingress-controller:)(.*)$/${1}${2}${3}${4}'${ALB_INGRESS_CONTROLLER_VERSION}'/' ${DOWNLOAD_DIR}/alb-ingress-controller/alb-ingress-controller.yaml
perl -pi -e 's/^(.*?)(# - --cluster-name=)(.*)/${1}- --cluster-name='${EKS_NAME}'${3}/' ${DOWNLOAD_DIR}/alb-ingress-controller/alb-ingress-controller.yaml
perl -pi -e 's/^(.*?)(- --cluster-name=)(.*)/${1}- --cluster-name='${EKS_NAME}'/' ${DOWNLOAD_DIR}/alb-ingress-controller/alb-ingress-controller.yaml

cat ${DOWNLOAD_DIR}/alb-ingress-controller/alb-ingress-controller.yaml | grep -v "# *\|^$"

kubectl delete -f ${DOWNLOAD_DIR}/alb-ingress-controller/alb-ingress-controller.yaml 2> /dev/null; sleep 1 && \
kubectl apply -f ${DOWNLOAD_DIR}/alb-ingress-controller/alb-ingress-controller.yaml

# https://github.com/kubernetes-sigs/external-dns/releases
printf "\nINFO: deploying external-dns\n\n"
# wget -q -O ${DOWNLOAD_DIR}/alb-ingress-controller/external-dns.yaml "https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/${ALB_INGRESS_CONTROLLER_VERSION}/docs/examples/external-dns.yaml"
wget -q -O ${DOWNLOAD_DIR}/alb-ingress-controller/external-dns.yaml "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/examples/external-dns.yaml"
perl -pi -e 's/^(.*?)(- --domain-filter=)(.*)/${1}# ${2}${3}/' ${DOWNLOAD_DIR}/alb-ingress-controller/external-dns.yaml
# perl -pi -e 's/^(.*?)(- --policy=)(.*)/${1}# ${2}${3}/' ${DOWNLOAD_DIR}/alb-ingress-controller/external-dns.yaml
perl -pi -e 's/^(.*?)(- --txt-owner-id=)(.*)/${1}${2}deploy-svc/' ${DOWNLOAD_DIR}/alb-ingress-controller/external-dns.yaml
perl -pi -e 's/^(.*?)(- --aws-zone-type=)(.*?)( #.*)/${1}${2}\n        ${4}/' ${DOWNLOAD_DIR}/alb-ingress-controller/external-dns.yaml
perl -pi -e 's/^(.*?)(image: )(.*?)(external-dns:)(.*)$/${1}${2}${3}${4}'${EXTERNAL_DNS_VERSION}'/' ${DOWNLOAD_DIR}/alb-ingress-controller/external-dns.yaml
cat ${DOWNLOAD_DIR}/alb-ingress-controller/external-dns.yaml | grep -v "^# *\|^$"
kubectl delete -f ${DOWNLOAD_DIR}/alb-ingress-controller/external-dns.yaml 2> /dev/null; sleep 1 && \
kubectl apply -f ${DOWNLOAD_DIR}/alb-ingress-controller/external-dns.yaml && sleep 5

f_k8s_pods_namespace_run_check "alb-ingress-controller" "kube-system"
printf "INFO: kubectl get pods,deploy,rs,svc,pv,pvc,jobs,endpoints,ing -A | grep \"alb-ingress-controller\"\n"
kubectl get pods,deploy,rs,svc,pv,pvc,jobs,endpoints,ing -A | grep "alb-ingress-controller"
kubectl get events -A | grep "alb-ingress-controller" | grep -i "error\|warning\|failed"
kubectl logs -n kube-system $(kubectl get pods -A | egrep -o "alb-ingress[a-zA-Z0-9-]+") | grep -i "error\|warning\|failed"

f_k8s_pods_namespace_run_check "external-dns" "default"
printf "INFO: kubectl get pods,deploy,rs,svc,pv,pvc,jobs,endpoints,ing -A | grep \"external-dns\"\n"
kubectl get pods,deploy,rs,svc,pv,pvc,jobs,endpoints,ing -A | grep "external-dns"
kubectl get events -A | grep "external-dns" | grep -i "error\|warning\|failed"
kubectl logs -n default $(kubectl get pods -A | egrep -o "external-dns[a-zA-Z0-9-]+") | grep -i "error\|warning\|failed"

printf "\nINFO: alb-ingress-controller.sh finished\n\n"
