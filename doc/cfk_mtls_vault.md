# 1. Install vault
kubectl create namespace hashicorp
helm install vault hashicorp/vault \
  --namespace hashicorp \
  --set "server.dev.enabled=true"

# 2. Enable kubernetes vault access
kubectl exec -it vault-0 --namespace hashicorp -- /bin/sh
vault auth enable kubernetes
vault write auth/kubernetes/config \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
vault secrets enable -path=internal kv-v2
cat <<EOF | vault policy write app -
path "secret*" {
  capabilities = ["read"]
}
EOF
vault write auth/kubernetes/role/confluent-operator \
    bound_service_account_names=confluent-sa \
    bound_service_account_namespaces=confluent \
    policies=app \
    ttl=24h

# 3. Create CA and server certs
./create_ca.sh
./confluent_certs.sh

# 4. Create JKS keystore for each component
* uses the scripts from confluent-kubernetes-examples/scripts.
* modification: specify the output file

./create_component_keystores.sh


# 5. Create a truststore for our CA
* uses the scripts from confluent-kubernetes-examples/scripts.
* modification: work in the /generated directory
./create-truststore.sh  \
    generated/cacerts.pem \
    mystorepassword    

# 6. Load jks files into vault
./load_jks_files_into_vault.sh

# 7. MDS 
https://docs.confluent.io/platform/current/kafka/configure-mds/index.html#create-a-pem-key-pair

openssl genrsa --traditional -out credentials/rbac/mds-tokenkeypair.txt 2048
openssl rsa -in credentials/rbac/mds-tokenkeypair.txt -outform PEM -pubout -out credentials/rbac/mds-publickey.txt



# 7. Load password for jks keystore into vault
kubectl exec -it vault-0 --namespace hashicorp -- vault kv put secret/jksPassword.txt password=jksPassword=mystorepassword

# 8. Load inter-broker credentials

kubectl -n hashicorp cp credentials vault-0:/tmp

Open an interactive shell session in the Vault container:

```
$ kubectl exec -it vault-0 -n hashicorp -- /bin/sh
```

Write the credentials to Vault:

```
/ $
cat /tmp/credentials/controlcenter/basic-server.txt | base64 | vault kv put /secret/controlcenter/basic.txt basic=-
cat /tmp/credentials/connect/basic-server.txt | base64 | vault kv put /secret/connect/basic.txt basic=-
cat /tmp/credentials/connect/basic-client.txt | base64 | vault kv put /secret/connect-client/basic.txt basic=-
cat /tmp/credentials/schemaregistry/basic-server.txt | base64 | vault kv put /secret/schemaregistry/basic.txt basic=-
cat /tmp/credentials/schemaregistry/basic-client.txt | base64 | vault kv put /secret/schemaregistry-client/basic.txt basic=-
cat /tmp/credentials/ksqldb/basic-server.txt | base64 | vault kv put /secret/ksqldb/basic.txt basic=-
cat /tmp/credentials/ksqldb/basic-client.txt | base64 | vault kv put /secret/ksqldb-client/basic.txt basic=-
cat /tmp/credentials/zookeeper-server/digest-jaas.conf | base64 | vault kv put /secret/zookeeper/digest-jaas.conf digest=-
cat /tmp/credentials/kafka-client/plain-jaas.conf | base64 | vault kv put /secret/kafka-client/plain-jaas.conf plainjaas=-
cat /tmp/credentials/kafka-server/plain-jaas.conf | base64 | vault kv put /secret/kafka-server/plain-jaas.conf plainjaas=-
cat /tmp/credentials/kafka-server/apikeys.json | base64 | vault kv put /secret/kafka-server/apikeys.json apikeys=-
cat /tmp/credentials/kafka-server/digest-jaas.conf | base64 | vault kv put /secret/kafka-server/digest-jaas.conf digestjaas=-
cat /tmp/credentials/license.txt | base64 | vault kv put /secret/license.txt license=-
```

more secrets...
```
cat /tmp/credentials/rbac/mds-publickey.txt | base64 | vault kv put /secret/mds-publickey.txt mdspublickey=-
cat /tmp/credentials/rbac/mds-tokenkeypair.txt | base64 | vault kv put /secret/mds-tokenkeypair.txt mdstokenkeypair=-
cat /tmp/credentials/rbac/ldap.txt | base64 | vault kv put /secret/ldap.txt ldapsimple=-
cat /tmp/credentials/rbac/mds-client-connect.txt | base64 | vault kv put /secret/connect/bearer.txt bearer=-
cat /tmp/credentials/rbac/mds-client-controlcenter.txt | base64 | vault kv put /secret/controlcenter/bearer.txt bearer=-
cat /tmp/credentials/rbac/mds-client-kafka-rest.txt | base64 | vault kv put /secret/kafka/bearer.txt bearer=-
cat /tmp/credentials/rbac/mds-client-ksql.txt | base64 | vault kv put /secret/ksqldb/bearer.txt bearer=-
cat /tmp/credentials/rbac/mds-client-schemaregistry.txt | base64 | vault kv put /secret/schemaregistry/bearer.txt bearer=-
```


# 1. Install CFK
kubectl create namespace confluent
kubectl create serviceaccount confluent-sa -n confluent
kubectl config set-context --current --namespace confluent
helm upgrade -f confluent/values.yaml --install confluent-operator confluentinc/confluent-for-kubernetes


# 5. Load TLS data into vault

read data from vault
vault kv get -format=json -field=data secret/ksqldb/bearer.txt


# 5. setup fake ldap server
helm upgrade --install -f confluent-kubernetes-examples/assets/openldap/ldaps-rbac.yaml test-ldap confluent-kubernetes-examples/assets/openldap -n confluent



# 5. Deploy confluent components



# Get logs from kubernetes
kubectl logs -n confluent  confluent-operator-847d9fdcdd-9bnll
kubectl get crd
kubectl describe crd zookeepers.platform.confluent.io
kubectl get zookeepers.platform.confluent.io
kubectl describe zookeepers.platform.confluent.io

# testing

## Kafka ACLs

cat <<EOF > client.properties
bootstrap.servers=kafka.confluent.svc.cluster.local:9071
security.protocol=SSL
ssl.truststore.location=/vault/secrets/truststore.jks
ssl.truststore.password=mystorepassword
ssl.keystore.location=/vault/secrets/keystore.jks
ssl.keystore.password=mystorepassword
ssl.key.password=mystorepassword
EOF

kafka-acls --command-config client.properties --bootstrap-server kafka.confluent.svc.cluster.local:9071 --list

kafka-topics --command-config client.properties --bootstrap-server kafka.confluent.svc.cluster.local:9071 --list



## Kafka RBAC
Use confluent cli - reference https://docs.confluent.io/confluent-cli/current/command-reference/confluent_login.html#flags

/etc/hosts
127.0.0.1 kafka kafka-0.kafka.confluent-dev.svc.cluster.local kafka-0

kubectl port-forward service/kafka 8090:8090
confluent login --url https://kafka:8090 --ca-cert-path generated/cacerts.pem --save
username: kafka
password: kafka-secret

confluent iam rbac role list

### rbac audit logs
cd /tmp
wget https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 -O jq
chmod +x jq

denied access
kafka-console-consumer --bootstrap-server kafka.confluent.svc.cluster.local:9071 --consumer.config client.properties --topic confluent-audit-log-events | ./jq 'select(.data.authorizationInfo.granted == false)'

# Print the rbac roles
confluent iam rbac role list -o json | jq -r .[].name
Operator
ResourceOwner
DeveloperManage
DeveloperRead
DeveloperWrite
AuditAdmin
ClusterAdmin
SecurityAdmin
SystemAdmin
UserAdmin

# get the cluster id
kubectl describe kafkarestclasses.platform.confluent.io default |grep "Kafka Cluster ID"

confluent cluster describe --url https://kafka:8090 --ca-cert-path generated/cacerts.pem | awk '/kafka-cluster/ { print $3}'
confluent iam rbac role-binding list --kafka-cluster-id hRRbitJaQZuYbGxuvZ29mA --role DeveloperRead --resource Topic:_confluent-license


## Schema registry
kubectl exec -ti schemaregistry-0 -- curl -k https://testadmin:testadmin@localhost:8081
kubectl exec -ti schemaregistry-0 -- curl -k https://sr:sr-secret@localhost:8081/permissions

## Connect
kubectl exec -ti connect-0  -- curl -k https://connect:connect-secret@localhost:8083/connectors

## Control center
kubectl port-forward service/controlcenter 9021:9021
kubectl exec -ti controlcenter-0 -- curl -k https://c3:c3-secret@localhost:9021/2.0/clusters/connect


in browser
https://localhost:9021 

c3:c3-secret
testadmin:testadmin
kafka:kafka-secret

kubectl exec -ti controlcenter-0 -- bash


## KSQL
kubectl port-forward service/ksqldb 8088:8088

cat <<EOF > ksql-cli.properties
ssl.truststore.location=generated/truststore.jks
ssl.truststore.password=mystorepassword
ssl.keystore.location=generated/ksqldb-keystore.jks
ssl.keystore.password=mystorepassword
ssl.key.password=mystorepassword
ssl.keystore.alias=testservice
EOF

/etc/hosts
127.0.0.1 ksql-server broker ksql


ksql --config-file ksql-cli.properties --user ksql --password ksql-secret https://ksql:8088



# secret for kafka rest
kubectl -n confluent create secret generic rest-credential --from-file=bearer.txt=credentials/rbac/kafkarestclass/bearer.txt


# delete all rbac role bindings
for RULE in $(kubectl get confluentrolebindings.platform.confluent.io --no-headers | awk '{print $1}') ; do 
  kubectl delete confluentrolebindings.platform.confluent.io $RULE
done
