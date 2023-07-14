#!/usr/bin/env bash
set -C -e -o pipefail

server=$1
serverKey=$2
outputFile=$3
password=$4
[ $# -ne 4 ] && { echo "Usage: $0 <fullchain_pem_file> <private_key> <output_file> <jks_password>"; exit 1; }

tempFile=pkcs.p12

if [ -e $outputFile ];then
  rm  $outputFile
fi

if [ -e $tempFile ];then
  rm  $tempFile
fi

echo "Check $server certificate"
openssl x509 -in "${server}" -text -noout
openssl pkcs12 -export \
	-in "${server}" \
	-inkey "${serverKey}" \
	-out "${tempFile}" \
	-name testService \
	-passout pass:mykeypassword

keytool -importkeystore \
	-deststorepass "${password}" \
	-destkeypass "${password}" \
	-destkeystore "${outputFile}" \
	-deststoretype pkcs12 \
	-srckeystore "${tempFile}" \
	-srcstoretype PKCS12 \
	-srcstorepass mykeypassword

echo "Validate Keystore"
keytool -list -v -keystore "${outputFile}" -storepass "${password}"