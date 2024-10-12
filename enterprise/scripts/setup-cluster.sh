#!/bin/bash

set -e

k3d cluster delete kong-enterprise

k3d cluster create -p "8001:8001" -p "8002:8002" -p "8080:80@loadbalancer" kong-enterprise --registry-create docker-registry
KUBECONFIG=$(k3d kubeconfig write kong-enterprise); export KUBECONFIG

kubectl create namespace kong
kubectl create namespace kong-dp

alias k=kubectl
alias kc="kubectl -n kong"
alias kd="kubectl -n kong-dp"

kubectl get pods
