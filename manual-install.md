# Quick Start - Kong Enterprise

This instruction enables Kong enterprise install on a single vm instance on k3d cluster

## Pre-requisite tools/libraries install before executing the install
    ```bash
    sudo apt update
    sudo apt-get install git -y
    sudo apt-get install jq -y
    sudo apt-get install kubectl -y
    sudo apt-get install helm -y
    sudo apt-get install wget -y

    sudo wget https://github.com/mikefarah/yq/releases/download/v4.28.2/yq_linux_amd64.tar.gz -O - | tar xz && sudo mv yq_linux_amd64 /usr/bin/yq

    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
    ```

## Pre-requisite download source

The location the project is cloned
cd kong-enterprise-quickstart
export KONG_ENTERPRISE_QUICKSTART_HOME=$(pwd)

## Create cluster for control-plane and data-plane

### Delete (if already exists) and Create cluster 
k3d cluster delete kong-enterprise

k3d cluster create -p "8001:8001" -p "8002:8002" -p "8080:80@loadbalancer" kong-enterprise --registry-create docker-registry
KUBECONFIG=$(k3d kubeconfig write kong-enterprise); export KUBECONFIG

kubectl create namespace kong
kubectl create namespace kong-dp

alias k=kubectl
alias kc="kubectl -n kong"
alias kd="kubectl -n kong-dp"

### Create certs
    ```bash
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

    ```

### Deploy control-plane
    ```bash
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

    kubectl wait deploy kong-kong -n kong --for="jsonpath=.status.readyReplicas=1" --timeout=120s; if [[ $? == "0" ]]; then echo "ready"; else echo ""; echo "install not ready, stop and dont proceed, until this is fixed"; fi

    #Check the status of install
    kubectl -n kong get all

    curl -s http://localhost:8001 | jq .version

    kubectl patch deployment -n kong kong-kong -p "{\"spec\": { \"template\" : { \"spec\" : {\"containers\":[{\"name\":\"proxy\",\"env\": [{ \"name\" : \"KONG_ADMIN_API_URI\", \"value\": \"localhost:8001\" }]}]}}}}"

    echo "Access the manger ui on browser http://localhost:8002/overview"
    
    ```

### Deploy data-plane
    ```bash
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

    kubectl wait deploy kong-dataplane-kong -n kong-dp --for="jsonpath=.status.readyReplicas=1" --timeout=120s; if [[ $? == "1" ]]; then echo "data-plane ready"; else echo "data-plane install not ready, stop and dont proceed, until this is fixed"; fi

    kubectl get all -n kong-dp

    curl localhost:8001/clustering/status

    ```

### Create kong api proxy, create HTTPbin as the target endpoint deployed in kong-dp namespace 
    ```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: httpbin
  namespace: kong-dp
  labels:
    app: httpbin
spec:
  type: ClusterIP
  ports:
  - name: http
    port: 8000
    targetPort: 80
  selector:
    app: httpbin
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin
  namespace: kong-dp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: httpbin
      version: v1
  template:
    metadata:
      labels:
        app: httpbin
        version: v1
    spec:
      containers:
      - image: docker.io/kong/httpbin
        imagePullPolicy: IfNotPresent
        name: httpbin
        ports:
        - containerPort: 8000
EOF
    ```

### Testing the apiproxy, we use curl container deployed in the namespace as kube proxy and test the Route (kube proxy endpoint)
    ```bash
    kubectl run testcurl --image=curlimages/curl -i --tty -- sh
    kubectl exec testcurl --tty -i -- sh
    # After you get the command prompt, issue the curl targetting the kube proxy
    curl http://httpbin.kong-dp.svc.cluster.local:8000/get
    kubectl exec testcurl --tty -i -- curl http://httpbin.kong-dp.svc.cluster.local:8000/get
    ```

### Create kong api proxy, Register the backend service (to the target httpbin endpoint) 
    ```bash
    curl -i -s -X POST localhost:8001/services \
        --data name=httpservice \
        --data url='http://httpbin.kong-dp.svc.cluster.local:8000'
    ```

### Create kong api proxy, Register the proxy route(to the kong backend service)
    ```bash
    curl -i -s -X POST localhost:8001/services/httpservice/routes \
        --data name='httpbinroute' \
        --data 'paths[]=/httpbin'
    ```

### Testing the apiproxy, we use curl container deployed in the namespace as kube proxy and test the Route (kube proxy endpoint)
    ```bash
    kubectl run testcurl --image=curlimages/curl -i --tty -- sh
    kubectl exec pod testcurl --tty -i -- sh
    # After you get the command prompt, issue the curl targetting the kube proxy
    curl http://kong-dataplane-kong-proxy.kong-dp.svc.cluster.local:80/httpbin/get
    kubectl exec testcurl --tty -i -- curl http://kong-dataplane-kong-proxy.kong-dp.svc.cluster.local:80/httpbin/get
    ```

### Create rate limiting - mgmt api
    ```bash
    curl -i -s -X POST localhost:8001/plugins \
        --data name=rate-limiting \
        --data instance_name=rl1 \
        --data config.minute=5 \
        --data config.policy=local -v
    ```

### Create rate limiting - via CRDs
    ```bash
    cat <<EOF | kubectl apply -f -
apiVersion: configuration.konghq.com/v1
kind: KongPlugin
metadata:
  name: rl1
  namespace: kong-dp
config:
  minute: 5
  policy: local
plugin: rate-limiting
EOF
    ```

### Create Ingress
    ```bash
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: httpbinroute
  namespace: kong-dp
  annotations:
    konghq.com/strip-path: "true"
spec:
  ingressClassName: kong
  rules:
  - http:
      paths:
      - path: /httpbin
        pathType: ImplementationSpecific
        backend:
          service:
            name: httpbin
            port:
              number: 8000
EOF
    ```

### Attach the plugin to the Ingress
    ```bash
    kubectl annotate ingress httpbinroute -n kong-dp konghq.com/plugins=rl1
    ```

### Testing the apiproxy, we use curl container deployed in the namespace as kube proxy and test the Route (kube proxy endpoint)
    ```bash
    kubectl run testcurl --image=curlimages/curl -i --tty -- sh
    # After you get the command prompt, issue the curl targetting the kube proxy
    curl http://kong-dataplane-kong-proxy.kong-dp.svc.cluster.local:80/httpbin/get
    kubectl exec testcurl --tty -i -- curl http://kong-dataplane-kong-proxy.kong-dp.svc.cluster.local:80/httpbin/get
    ```

### Clean up plugin
    ```bash
    kd delete KongPlugin rl1
    kd delete Ingress httpbinroute
    curl -i -s -X DELETE localhost:8001/plugins/rl1 
    ```

### Create kongmap - Kong visualizer
    ```bash
    git clone https://github.com/yesinteractive/kong-map.git
    cd kong-map-main
    
    # get the ip address from below command and update the kong-cluster-config.json
    ifconfig|grep en0 -A1

    # update the content of the file kong-cluster-config.json with the ip address from the above command

    export KONG_CLUSTERS=$(jq -r tostring kong-cluster-config.json)

    docker run -d \
    -e "KONGMAP_CLUSTERS_JSON=$KONG_CLUSTERS" \
    -e "KONGMAP_URL=http://localhost:8100" \
    -p 8100:8100 \
    -p 8143:8143 \
    yesinteractive/kongmap

    # For cleaning up the container for kongmap
    docker ps -a
    container_id=025a090c9a8f
    docker rm -f $container_id
    docker exec -it $container_id sh    
    ```

### decK for command line Kong configuration
    ```bash
    # Installation
    brew tap kong/deck
    brew install deck

    # Getting started
    deck gateway ping
    deck gateway dump -o kong.yaml

    # Demo (run the gateway sync with option '-w demo.workspace' in Enterprise Kong)
    cd demo

    # For reference 
    # https://github.com/mikaello/openapi-2-kong
    # https://docs.konghq.com/gateway/latest/admin-api/

    cat httpbin-oas.yaml | deck file openapi2kong --inso-compatible  > httpbin_kong_service.yaml
    # change the path in httpbin_kong_service to be exact (without regular expression)
    deck gateway sync httpbin_kong_service.yaml --config deck.yaml

    cat httpbin-oas-with-plugin.yaml | deck file openapi2kong --inso-compatible  > httpbin_kong_service.yaml
    # change the path in httpbin_kong_service to be exact (without regular expression)
    deck gateway sync httpbin_kong_service.yaml --config deck.yaml

    #For testing
    kubectl run testcurl --image=curlimages/curl -i --tty -- sh
    kubectl exec testcurl --tty -i -- sh
    # After you get the command prompt, issue the curl targetting the kube proxy
    curl http://kong-dataplane-kong-proxy.kong-dp.svc.cluster.local:80/httpbin/get

    kubectl exec testcurl --tty -i -- curl http://kong-dataplane-kong-proxy.kong-dp.svc.cluster.local:80/httpbin/get
    ```

### Adding plugins via Docker - https://docs.konghq.com/gateway/latest/plugin-development/distribution/#via-a-dockerfile-or-docker-run-install-and-load
    ```bash
    cd plugins/myheader
    docker ps -a | grep registry
    export DOCKER_REGISTRY_PORT=50242

    export DOCKER_TAG="3.4-0.0.4"

    docker build -t localhost:"$DOCKER_REGISTRY_PORT"/kong-gateway_myheader:"$DOCKER_TAG" .

    docker push localhost:"$DOCKER_REGISTRY_PORT"/kong-gateway_myheader:"$DOCKER_TAG"

    helm upgrade kong kong/kong --reuse-values --set image.repository=docker-registry:"$DOCKER_REGISTRY_PORT"/kong-gateway_myheader --set image.tag="$DOCKER_TAG" -n kong

    helm upgrade kong-dataplane kong/kong --reuse-values --set image.repository=docker-registry:"$DOCKER_REGISTRY_PORT"/kong-gateway_myheader --set image.tag="$DOCKER_TAG" -n kong-dp

    curl -X DELETE http://localhost:8001/services/httpservice/routes/httpbinroute -v
    curl -X DELETE http://localhost:8001/services/httpservice 

    curl -i -s -X POST localhost:8001/services \
        --data name=httpservice \
        --data url='http://httpbin.kong-dp.svc.cluster.local:8000'
    
    curl -i -s -X POST localhost:8001/services/httpservice/routes \
        --data name='httpbinroute' \
        --data 'paths[]=/httpbin'

    curl -is -X POST http://localhost:8001/services/httpservice/plugins \
        --data 'name=myheader'

    kubectl exec testcurl --tty -i -- curl http://kong-dataplane-kong-proxy.kong-dp.svc.cluster.local:80/httpbin/get -v

    ```

### Adding plugins via ConfigMap - 
    ```bash
    cd plugins/viaconfigmap
    kubectl create configmap plugin-viaconfigmap --from-file=source -n kong
    kubectl create configmap plugin-viaconfigmap --from-file=source -n kong-dp

    kubectl get configmap plugin-viaconfigmap -o yaml -n kong

    export POSTGRES_PASSWORD=$(kubectl get secret --namespace "kong" kong-postgresql \
        -o jsonpath="{.data.postgres-password}" | base64 -d)
    
    #Validate the 
    helm upgrade kong kong/kong -n kong --reuse-values --values values.yaml  \
        --set global.postgresql.auth.postgresPassword=$POSTGRES_PASSWORD --dry-run=true

    helm upgrade kong kong/kong -n kong --reuse-values --values values.yaml  \
        --set global.auth.existingSecret=kong-postgresql
        --set image.repository=docker-registry:"$DOCKER_REGISTRY_PORT"/kong-gateway_myheader \
        --set image.tag="$DOCKER_TAG"

        --set global.auth.existingSecret=kong-postgresql
        --set global.auth.postgresPassword=$POSTGRES_PASSWORD

    helm upgrade kong-dataplane kong/kong -n kong-dp --reuse-values --values values.yaml --dry-run=true | grep viaconfigmap

    curl -i -s -X POST localhost:8001/services \
        --data name=httpservice \
        --data url='http://httpbin.kong-dp.svc.cluster.local:8000'
    
    curl -i -s -X POST localhost:8001/services/httpservice/routes \
        --data name='httpbinroute' \
        --data 'paths[]=/httpbin'

    curl -is -X POST http://localhost:8001/services/httpservice/plugins \
        --data 'name=viaconfigmap'

    kubectl exec testcurl --tty -i -- curl http://kong-dataplane-kong-proxy.kong-dp.svc.cluster.local:80/httpbin/get -v


    ```