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
vault kv put secret/github \
    accesstoken="<your-GitHub-access-token>"



# 5. Deploy confluent components



# Get logs from kubernetes
kubectl logs -n confluent  confluent-operator-847d9fdcdd-9bnll
kubectl get crd
kubectl describe crd zookeepers.platform.confluent.io
kubectl get zookeepers.platform.confluent.io
kubectl describe zookeepers.platform.confluent.io