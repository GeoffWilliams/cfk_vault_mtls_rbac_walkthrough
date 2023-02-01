# vault k8s setup

Adapted from:
https://www.confluent.io/blog/manage-secrets-with-kubernetes-and-hashicorp-vault/

```
kubectl create namespace hashicorp
helm install vault hashicorp/vault \
  --namespace hashicorp \
  --set "server.dev.enabled=true"
```

# get a shell
```
kubectl exec -it vault-0 --namespace hashicorp -- /bin/sh
```

! due to reading shell variables and files from the pod, run the commands in interactive shell!


## Enable kubernetes
```
vault auth enable kubernetes

vault write auth/kubernetes/config \
    token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
    kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
    kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
```

# Enable kv-v2
```
vault secrets enable -path=internal kv-v2
```

## Create a secret policy
```

vault kv put internal/github \
    accesstoken="<your-GitHub-access-token>"



vault policy write gh-read - <<EOF
path "internal/data/github" {
  capabilities = ["read"]
}
EOF

vault write auth/kubernetes/role/connect \
    bound_service_account_names=connect \
    bound_service_account_namespaces=confluent \
    policies=gh-read \
    ttl=24h


```

