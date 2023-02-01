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
vault policy write confluent-read - <<EOF
path "secret" {
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