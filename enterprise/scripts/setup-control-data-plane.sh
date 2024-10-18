#!/bin/bash

set -e

# Setup certs

export KONG_ENTERPRISE_INSTALL_HOME=$KONG_ENTERPRISE_QUICKSTART_HOME/home
rm -R $KONG_ENTERPRISE_INSTALL_HOME
mkdir $KONG_ENTERPRISE_INSTALL_HOME
cd $KONG_ENTERPRISE_INSTALL_HOME
mkdir $KONG_ENTERPRISE_INSTALL_HOME/certs
cd $KONG_ENTERPRISE_INSTALL_HOME/certs

openssl req -new -x509 -nodes -newkey ec:<(openssl ecparam -name secp384r1) \
-keyout ./cluster.key -out ./cluster.crt \
-days 1095 -subj "/CN=kong_clustering"

kubectl create secret tls kong-cluster-cert --cert=./cluster.crt --key=./cluster.key -n kong
kubectl create secret tls kong-cluster-cert --cert=./cluster.crt --key=./cluster.key -n kong-dp

# Install control plane 

helm repo add kong https://charts.konghq.com
helm repo update

#If re-installing control plane on existing cluster, run the below. If not skip it.
helm uninstall kong -n kong; kubectl delete pvc data-kong-postgresql-0 -n kong

helm install kong kong/kong -n kong \
    --set ingressController.enabled=true \
    --set ingressController.installCRDs=false \
    --set ingressController.image.repository=kong/kubernetes-ingress-controller \
    --set ingressController.image.tag=2.11 \
    --set image.repository=kong/kong-gateway \
    --set image.tag=3.4 \
    --set env.database=postgres \
    --set env.role=control_plane \
    --set env.cluster_cert=/etc/secrets/kong-cluster-cert/tls.crt \
    --set env.cluster_cert_key=/etc/secrets/kong-cluster-cert/tls.key \
    --set cluster.enabled=true \
    --set cluster.tls.enabled=true \
    --set cluster.tls.servicePort=8005 \
    --set cluster.tls.containerPort=8005 \
    --set clustertelemetry.enabled=true \
    --set clustertelemetry.tls.enabled=true \
    --set clustertelemetry.tls.servicePort=8006 \
    --set clustertelemetry.tls.containerPort=8006 \
    --set proxy.enabled=false \
    --set admin.enabled=true \
    --set admin.http.enabled=true \
    --set admin.type=LoadBalancer \
    --set enterprise.enabled=false \
    --set enterprise.portal.enabled=false \
    --set enterprise.rbac.enabled=false \
    --set enterprise.smtp.enabled=false \
    --set enterprise.license_secret=kong-enterprise-license \
    --set manager.enabled=true \
    --set manager.type=LoadBalancer \
    --set secretVolumes={kong-cluster-cert} \
    --set postgresql.enabled=true \
    --set postgresql.auth.username=kong \
    --set postgresql.auth.database=kong \
    --set postgresql.auth.password=kong \
    --set admin.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="nlb" \
    --set manager.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="nlb"

echo "Waiting 30s for the control plane to initiated...."
sleep 30;

kubectl wait deploy kong-kong -n kong --for="jsonpath=.status.readyReplicas=1" --timeout=120s; 
if [[ $? == "0" ]]; then 
    echo "ready"; 
else 
    echo ""; 
    echo "install not ready, stop and dont proceed, until this is fixed"; 
fi

VERSION_OUTPUT=$(curl -s http://localhost:8001 | jq .version)
if [[ $VERSION_OUTPUT != null ]]; then 
    echo "ready"; 
else 
    echo ""; echo "post install not ready, stop and dont proceed, until this is fixed"; 
fi

kubectl patch deployment -n kong kong-kong -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"proxy\",\"env\": [{ \"name\" : \"KONG_ADMIN_API_URI\", \"value\": \"localhost:8001\" }]}]}}}}"

echo "Access the manger ui on browser http://localhost:8002/overview"

# Install Data plane

helm install kong-dataplane kong/kong -n kong-dp \
    --set ingressController.enabled=false \
    --set image.repository=kong/kong-gateway \
    --set image.tag=3.4 \
    --set env.database=off \
    --set env.role=data_plane \
    --set env.cluster_cert=/etc/secrets/kong-cluster-cert/tls.crt \
    --set env.cluster_cert_key=/etc/secrets/kong-cluster-cert/tls.key \
    --set env.lua_ssl_trusted_certificate=/etc/secrets/kong-cluster-cert/tls.crt \
    --set env.cluster_control_plane=kong-kong-cluster.kong.svc.cluster.local:8005 \
    --set env.cluster_telemetry_endpoint=kong-kong-clustertelemetry.kong.svc.cluster.local:8006 \
    --set proxy.enabled=true \
    --set proxy.type=LoadBalancer \
    --set enterprise.enabled=false \
    --set enterprise.portal.enabled=false \
    --set enterprise.rbac.enabled=false \
    --set enterprise.smtp.enabled=false \
    --set manager.enabled=false \
    --set portal.enabled=false \
    --set portalapi.enabled=false \
    --set secretVolumes={kong-cluster-cert} \
    --set proxy.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="nlb"

echo "Waiting 30s for the data plane to initiated...."
sleep 30;

kubectl wait deploy kong-dataplane-kong -n kong-dp --for="jsonpath=.status.readyReplicas=1" --timeout=120s; 
if [[ $? == "1" ]]; then 
    echo "data-plane ready"; 
else 
    echo "";
    echo "data-plane install not ready, stop and dont proceed, until this is fixed"; 
fi

kubectl get all -n kong-dp

curl localhost:8001/clustering/status
