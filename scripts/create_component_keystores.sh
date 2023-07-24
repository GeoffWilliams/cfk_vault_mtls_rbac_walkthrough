#!/bin/bash

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
    echo "keystore for $COMPONENT"
    $(dirname $0)/create-keystore.sh  \
        $WORKDIR/$COMPONENT.pem \
        $WORKDIR/$COMPONENT-key.pem \
        $WORKDIR/$COMPONENT-keystore.jks \
        mystorepassword
done