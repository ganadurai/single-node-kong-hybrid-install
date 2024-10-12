#!/bin/bash

set -e

echo "Creating service to the sample proxy deployed in the dataplane"
curl -i -s -X POST localhost:8001/services \
    --data name=httpservice \
    --data url='http://httpbin.kong-dp.svc.cluster.local:8000'

echo "waiting 10secs for the service creation complete"
sleep 10;

echo "Creating route for the kong service"
curl -i -s -X POST localhost:8001/services/httpservice/routes \
        --data name='httpbinroute' \
        --data 'paths[]=/httpbin'

echo "Testing deployed kong route (proxy)"
                                     
kubectl run testcurl --image=curlimages/curl --rm -it --restart=Never -- http://kong-dataplane-kong-proxy.kong-dp.svc.cluster.local:80/httpbin/get