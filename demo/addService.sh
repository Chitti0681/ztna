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

function apply_cluster_namespace {
#    local kubeconfig=$1
    local file=$1
    local namespace=$2
    echo "Applying to cluster: $file"
    kubectl apply -f $file -n $namespace
}

function delete_cluster {
#    local kubeconfig=$1
    local file=$1
    echo "Deleting from cluster: $file"
    kubectl delete -f $file
}

function delete_cluster_namespace {
#    local kubeconfig=$1
    local file=$1
    local namespace=$2
    echo "Deleting from cluster: $file"
    kubectl delete -f $file -n $namespace
}


function create_service {
   local name=$1
   local destinationHost=$2
   local destinationHostPort=$3
   local destinationHostPortInternal=$4
   local address=$5

   cat << NET > $WORKING_DIR/$name-service-data.yaml
name: $name
destinationHost: $destinationHost
destinationHostPort: $destinationHostPort
destinationHostPortInternal: $destinationHostPortInternal
address: $address
NET
   gomplate -d data=$WORKING_DIR/$name-service-data.yaml -f ./istio/service-entry-template.yaml > $WORKING_DIR/$name-se-istio.yaml

    # Apply app istio resources including authorization
    apply_cluster   $WORKING_DIR/$name-se-istio.yaml
}

function delete_service {
    local name=$1
    delete_cluster $WORKING_DIR/$name-se-istio.yaml
    rm $WORKING_DIR/$name-se-istio.yaml
}


name="oops"
destination_host="oops"
destination_host_port="oops"
destination_host_port_internal="oops"
address="oops"

while getopts ":v:" flag
do
    case "${flag}" in
        v) values=${OPTARG}
           name=$(./yq eval '.name' $values)
           destination_host=$(./yq eval '.host' $values)
           destination_host_port=$(./yq eval '.port' $values)
           destination_host_port_internal=$(./yq eval '.internal' $values)
           address=$(./yq eval '.address' $values) ;;
    esac
done
shift $((OPTIND-1))

WORKING_DIR=/tmp/
case "$1" in
    "create" )
        create_service $name $destination_host $destination_host_port $destination_host_port_internal $address
    ;;
    "delete" )
        delete_service $name
    ;;
    *)
    usage ;;
esac
