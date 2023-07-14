#!/bin/bash

WORKDIR="generated"
CONFLUENT_SETTINGS_DIR="cfssl_profiles"
COMPONENTS="
    zookeeper
    kafka
    controlcenter
    schemaregistry
    connect
    ksqldb
    kafkarestproxy"

for COMPONENT in $COMPONENTS ; do
    echo "SSL cert for $COMPONENT"

    # cfssljson generates the keys and certificates from json output of cfssl
    cfssl gencert -ca=$WORKDIR/cacerts.pem \
        -ca-key=$WORKDIR/rootCAkey.pem \
        -config=$CONFLUENT_SETTINGS_DIR/ca-config.json \
        -profile=server $CONFLUENT_SETTINGS_DIR/$COMPONENT-server-domain.json | cfssljson -bare $WORKDIR/$COMPONENT

done
