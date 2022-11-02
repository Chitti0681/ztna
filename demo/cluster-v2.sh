#!/bin/bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2022 Intel Corporation

set -o errexit
set -o nounset
set -o pipefail

KUBE_PATH=/home/vagrant/.kube/config
WORKING_DIR=/tmp


function apply_cluster {
#    local kubeconfig=$1
    local file=$1
    echo "Applying to cluster: $file"
    kubectl apply -f $file

}
function install_yq_locally {
    if [ ! -x ./yq ]; then
        echo 'Installing yq locally'
        VERSION=v4.12.0
        BINARY=yq_linux_amd64
        sudo wget https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY} -O yq && sudo chmod +x yq
fi
}

WORKING_DIR=/tmp

function install_keycloak_idp {

   kubectl create cm -n default keycloak-configmap --from-file=keycloak/realm_idp.json -o yaml --dry-run=client > $WORKING_DIR/keycloak-cm.yaml
   cat << NET > $WORKING_DIR/data.yaml
namespace: default
NET
   gomplate -d data=$WORKING_DIR/data.yaml -f ./keycloak/keycloak.yaml > $WORKING_DIR/keycloak.yaml
   #Install Keycloak cm
   apply_cluster   $WORKING_DIR/keycloak-cm.yaml
   #Install Keycloak
   apply_cluster   $WORKING_DIR/keycloak.yaml
}

function install_docker {
   sudo apt-get update
   sudo apt-get install docker.io
   sudo systemctl enable docker
   sudo systemctl start docker
}

function configure_metallb {

read -p 'IPAddr1: ' ipAddr1
read -p 'IPAddr2: ' ipAddr2

   cat << NET > ipaddresspool1.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - $ipAddr1-$ipAddr2

NET

cat << NET > l2advertisement.yaml
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: example
  namespace: metallb-system
spec:
  ipAddressPools:
  - first-pool
NET

kubectl apply -f ipaddresspool1.yaml
sudo sleep 5
kubectl apply -f l2advertisement.yaml
}

function global_install {
   if [[ $(kubectl get ns lbns)  ]]; then
      echo "Namespace lbns exists"
   else
      kubectl create ns lbns
      echo "Namespace lbns created"
   fi


   helm repo add istio https://istio-release.storage.googleapis.com/charts
   helm repo update
   helm install istio-ingressgateway-lb -n lbns istio/gateway

   echo "==== Configure Metallb ===="
   configure_metallb
   echo "==== Metallb Configured ===="
}


function install_cluster_packages {

  install_yq_locally
  sudo wget https://github.com/hairyhenderson/gomplate/releases/download/v3.11.2/gomplate_linux-amd64
  sudo mv gomplate_linux-amd64 /usr/local/bin/gomplate
  sudo chmod +x /usr/local/bin/gomplate
  sudo apt-get install jq
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.9.1/cert-manager.yaml
  apply_cluster ./controllers/kncc.yaml


   echo "===== Installing Helm ====="
   sudo curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
   bash get_helm.sh -v v3.2.4
   echo "===== Helm installed ====="

   #Create cluster wide issure
   sudo openssl req -x509 -sha256 -nodes -days 3650 -newkey rsa:2048 -subj '/O=myorg/CN=myorg' -keyout ca.key -out ca.crt
   sudo kubectl create secret tls my-ca --key ca.key --cert ca.crt -n cert-manager
   apply_cluster ./certs/clusterissuer.yaml

   # add oauth2
   helm repo add oauth2-proxy https://oauth2-proxy.github.io/manifests
   helm repo update

}


function install_metallb {

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.7/config/manifests/metallb-native.yaml

}


function install_kubernetes {
   kubernetes_version="1.23.1"
   pod_network_cidr="192.168.0.0/16"
   node_name="edge7"

   sudo apt-get update -y
   sudo apt-get install apt-transport-https -y
   sudo apt-get install ca-certificates -y
   sudo apt-get install curl -y
   sudo curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
   echo "deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] \
      https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list

   sudo apt-get update -y


   sudo apt-get install kubectl=1.23.0-00 -y #install kubectl first
   sudo apt-get install kubelet=1.23.0-00 -y
   sudo apt-get install kubeadm=1.23.0-00 -y
   sudo apt-mark hold kubelet kubeadm kubectl
   sudo systemctl stop kubelet

   cgroup=$(sudo docker info | grep -i "cgroup driver" | cut -d ':' -f 2)

   echo "====cgroup : $cgroup=========="

   sudo echo "Environment="KUBELET_EXTRA_ARGS=--cgroup-driver=cgroupfs"" |sudo tee -a /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
   sudo systemctl daemon-reload
   sudo sleep 5
   sudo apt-get upgrade -y

   sudo kubeadm init --node-name=$node_name --kubernetes-version=$kubernetes_version --pod-network-cidr=$pod_network_cidr
   sudo sleep 5

   sudo mkdir -p $HOME/.kube
   sudo cp -f /etc/kubernetes/admin.conf $HOME/.kube/config
   sudo ls -l /etc/kubernetes/
   sudo ls -l $HOME/.kube/

   export KUBECONFIG=$HOME/.kube/config
   sudo chown $(id -u):$(id -g) $HOME/.kube/config

   echo "get nodes"

   kubectl get node

   sudo sleep 5

   kubectl taint node $node_name node-role.kubernetes.io/master:NoSchedule-

   echo "done"
}

function install_calico {
   kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.24.3/manifests/tigera-operator.yaml
   kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.24.3/manifests/custom-resources.yaml

}


case "$1" in
     "prepare" )
        global_install;;
      "packages" )
        install_cluster_packages;;
      "keycloak_idp" )
      install_keycloak_idp;;
      "install_metallb" )
      install_metallb;;
      "install_kubernetes" )
      install_kubernetes;;
      "install_calico" )
      install_calico;;
      "install_docker" )
      install_docker;;
      "configure_metallb" )
      configure_metallb;;
      "install_helm" )
      install_helm


esac
