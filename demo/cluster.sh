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
        wget https://github.com/mikefarah/yq/releases/download/${VERSION}/${BINARY} -O yq && chmod +x yq
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


function global_install {
   if [[ $(kubectl get ns lbns)  ]]; then
      echo "Namespace lbns exists"
   else
      kubectl create ns lbns
      echo "Namespace lbns created"
   fi
   helm install istio-ingressgateway-lb -n lbns istio/gateway
}


function install_cluster_packages {
  install_yq_locally
  wget https://github.com/hairyhenderson/gomplate/releases/download/v3.11.2/gomplate_linux-amd64
  sudo mv gomplate_linux-amd64 /usr/local/bin/gomplate
  sudo chmod +x /usr/local/bin/gomplate
  sudo apt-get install jq
  kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.9.1/cert-manager.yaml
  apply_cluster -f ./controllers/kncc.yaml

   wget https://get.helm.sh/helm-v3.9.1-linux-amd64.tar.gz
tar -zxvf helm-v3.9.1-linux-amd64.tar.gz
sudo mv linux-amd64/helm /usr/local/bin/helm

   #Create cluster wide issure
   openssl req -x509 -sha256 -nodes -days 3650 -newkey rsa:2048 -subj '/O=myorg/CN=myorg' -keyout ca.key -out ca.crt
   kubectl create secret tls my-ca --key ca.key --cert ca.crt -n cert-manager
   apply_cluster   ./certs/clusterissuer.yaml
   # add oauth2
   helm repo add oauth2-proxy https://oauth2-proxy.github.io/manifests
   helm repo update
}

case "$1" in
     "prepare" )
        global_install;;
      "packages" )
        install_cluster_packages;;
      "keycloak_idp" )
      install_keycloak_idp;;
esac
