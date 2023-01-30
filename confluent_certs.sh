#!/bin/bash

WORKDIR="generated"
CONFLUENT_SETTINGS_DIR="confluent"
COMPONENTS="
    zookeeper-server
    kafka-server
    controlcenter-server
    schemaregistry-server
    connect-server
    ksqldb-server
    kafkarestproxy-server"

for COMPONENT in $COMPONENTS ; do
    echo "SSL cert for $COMPONENT"

    # cfssljson generates the keys and certificates from json output of cfssl
    cfssl gencert -ca=$WORKDIR/cacerts.pem \
        -ca-key=$WORKDIR/rootCAkey.pem \
        -config=$CONFLUENT_SETTINGS_DIR/ca-config.json \
        -profile=server $CONFLUENT_SETTINGS_DIR/$COMPONENT-domain.json | cfssljson -bare $WORKDIR/$COMPONENT

done
