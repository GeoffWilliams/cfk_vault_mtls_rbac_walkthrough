#!/bin/bash

WORKDIR="generated"
COMPONENTS="
    zookeeper
    kafka
    controlcenter
    schemaregistry
    connect
    ksqldb
    kafkarestproxy"

for COMPONENT in $COMPONENTS ; do
    echo "Load vaul SSL for $COMPONENT"
    kubectl exec -it vault-0 --namespace hashicorp -- vault kv put secret/tls-${COMPONENT} pem="$(cat generated/${COMPONENT}-key.pem)"
done