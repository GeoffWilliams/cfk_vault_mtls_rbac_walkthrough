#!/bin/bash

CANAME=democa
WORKDIR=generated

mkdir -p $WORKDIR

echo "create ca key"
openssl genrsa -out $WORKDIR/rootCAkey.pem 2048

echo "create ca cert"
openssl req -x509  -new -nodes \
  -key $WORKDIR/rootCAkey.pem \
  -days 3650 \
  -out $WORKDIR/cacerts.pem \
  -subj "/C=US/ST=CA/L=MVT/O=TestOrg/OU=Cloud/CN=TestCA"

echo "validate ca"
openssl x509 -in $WORKDIR/cacerts.pem -text -noout