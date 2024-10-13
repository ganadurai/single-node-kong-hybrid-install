# Quick Start - Kong Enterprise

This instruction enables Kong enterprise install on a single vm instance on k3d cluster

## Pre-requisite tools/libraries install

1. Installation
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

1. The location the project is cloned
    ```bash
    cd kong-enterprise-quickstart
    export KONG_ENTERPRISE_QUICKSTART_HOME=$(pwd)
    
    cd $KONG_ENTERPRISE_QUICKSTART_HOME/enterprise/scripts
    ```

## Installation

1. Create cluster
    ```bash
    ./seup-cluster.sh
    ```

2. Create control data plane cluster
    ```bash
    ./seup-control-data-plane.sh
    ```

3. Deploy httpbin
    ```bash
    ./deploy-httpbin.sh
    ```

4. Deploy kong service and route
    ```bash
    ./deploy-service-route.sh
    ```

