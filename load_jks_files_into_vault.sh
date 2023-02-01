#!/bin/bash

WORKDIR=generated

WORKDIR="generated"
CONFLUENT_SETTINGS_DIR="confluent"
COMPONENTS="
    zookeeper
    kafka
    controlcenter
    schemaregistry
    connect
    ksqldb
    kafkarestproxy"

for COMPONENT in $COMPONENTS ; do
    JKS_FILE=${COMPONENT}-keystore.jks
    echo "copy $JKS_FILE to vault pod"
    kubectl -n hashicorp cp $WORKDIR/$JKS_FILE vault-0:/tmp

    echo "load keystore for $COMPONENT into vault"
    kubectl exec -it vault-0 --namespace hashicorp -- sh -c "cat /tmp/$JKS_FILE | base64 | vault kv put /secret/${COMPONENT}-keystore.jks keystore=-"
done

echo "copy truststore to vault pod"
kubectl -n hashicorp cp $WORKDIR/$JKS_FILE vault-0:/tmp

echo "load truststore into vault"
kubectl exec -it vault-0 --namespace hashicorp -- sh -c "cat /tmp/truststore.jks | base64 | vault kv put /secret/truststore.jks truststore=-"