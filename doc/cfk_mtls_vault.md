# CFK MTLS VAULT RBAC + K3D/K3S

## Prequestites
* K3D
* K3S
* Openssl
* JDK (for `keytool`)
* Big laptop to run this on. Recommend at least 32GB RAM and at least 64GB swap


## Cluster setup

* K3D built-in servicelb grabs ports on every node and breaks our load balancers, traefik takes port 443
  * Disable servicelb and traefik
  * Use metallb instead

```
k3d cluster create multiserver --servers 3 --k3s-arg "--no-deploy=traefik@server:*" --k3s-arg "--no-deploy=servicelb@server:*"
```

### MetalLB
* Instruction source:
  1. https://metallb.universe.tf/installation/
  2. https://github.com/keunlee/k3d-metallb-starter-kit

**Preparation**

```
# see what changes would be made, returns nonzero returncode if different
kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
kubectl diff -f - -n kube-system

# actually apply the changes, returns nonzero returncode on errors only
kubectl get configmap kube-proxy -n kube-system -o yaml | \
sed -e "s/strictARP: false/strictARP: true/" | \
kubectl apply -f - -n kube-system
```

**Installation**

```
for cluster_name in $(docker network list --format "{{ .Name}}" | grep k3d); do

cidr_block=$(docker network inspect $cluster_name | jq '.[0].IPAM.Config[0].Subnet' | tr -d '"')
cidr_base_addr=${cidr_block%???}
ingress_first_addr=$(echo $cidr_base_addr | awk -F'.' '{print $1,$2,255,0}' OFS='.')
ingress_last_addr=$(echo $cidr_base_addr | awk -F'.' '{print $1,$2,255,255}' OFS='.')
ingress_range=$ingress_first_addr-$ingress_last_addr

# switch context to current cluster
kubectl config use-context $cluster_name

# deploy metallb
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.10.2/manifests/namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.10.2/manifests/metallb.yaml

# configure metallb ingress address range
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  namespace: metallb-system
  name: config
data:
  config: |
    address-pools:
    - name: default
      protocol: layer2
      addresses:
      - $ingress_range
EOF
done
```

## Vault and secrets setup

### 1. Install vault

```
kubectl create namespace hashicorp
helm install vault hashicorp/vault \
  --namespace hashicorp \
  --set "server.dev.enabled=true"
```

### 2. Create CA and server certs

> **Note**
> One-time task!

```
./create_ca.sh
./confluent_certs.sh
```

### 3. Create JKS keystore for each component

> **Note**
> One-time task!

* uses the scripts from confluent-kubernetes-examples/scripts.
* modification: specify the output file

```
./create_component_keystores.sh
```

### 4. Create a truststore for our CA

> **Note**
> One-time task!

* uses the scripts from confluent-kubernetes-examples/scripts.
* modification: work in the /generated directory

```
./create-truststore.sh  \
    generated/cacerts.pem \
    mystorepassword    
```

### 5. Load jks files into vault

```
./load_jks_files_into_vault.sh
```

### 6. Copy the basic credentials from confluent-kubernetes-examples


> **Note**
> One-time task!

```
cp confluent-kubernetes-examples/security/configure-with-vault/credentials/ . -R
```

### 7. generate keypair for MDS 

> **Note**
> One-time task!

https://docs.confluent.io/platform/current/kafka/configure-mds/index.html#create-a-pem-key-pair

```
openssl genrsa --traditional -out credentials/rbac/mds-tokenkeypair.txt 2048
openssl rsa -in credentials/rbac/mds-tokenkeypair.txt -outform PEM -pubout -out credentials/rbac/mds-publickey.txt
```

### 8. Load password for jks keystore into vault

```
kubectl exec -it vault-0 --namespace hashicorp -- vault kv put secret/jksPassword.txt password=jksPassword=mystorepassword
```

### 9. Copy credentials to vault pod

```
kubectl -n hashicorp cp credentials vault-0:/tmp
```

### 10. Enable kubernetes vault access
Best/easiest way to do this is to login to vault via `kubectl` and run commands directly in the container. This is what all the docs say. Don't try to be smart and do all this from outside the container!

```
kubectl exec -it vault-0 --namespace hashicorp -- /bin/sh
```

```
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
```


### 11. Load copied credentials to vault

```
kubectl exec -it vault-0 -n hashicorp -- /bin/sh
```

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

## LDAP server

```
kubectl create namespace confluent
helm upgrade --install -f confluent-kubernetes-examples/assets/openldap/ldaps-rbac.yaml test-ldap confluent-kubernetes-examples/assets/openldap -n confluent
```

## Install CFK

```
kubectl create serviceaccount confluent-sa -n confluent
kubectl config set-context --current --namespace confluent
helm upgrade -f confluent/values.yaml --install confluent-operator confluentinc/confluent-for-kubernetes
```

> **Warning**
> Check confluent-operator-xxx pod came up ok before proceeding

```
kubectl get pods --no-headers | grep ^confluent-operator
kubectl describe pod $(kubectl get pods --no-headers | awk '/^confluent-operator/ {print $1}')
kubectl logs --all-containers $(kubectl get pods --no-headers | awk '/^confluent-operator/ {print $1}')
```

* sometimes this can take a while to come up - give it a few minutes


## Install CP

Kafka rest class can't use vault so use kubernetes secret:

```
kubectl -n confluent create secret generic rest-credential --from-file=bearer.txt=credentials/rbac/kafkarestclass/bearer.txt
```

```
kubectl apply -f confluent/cp.yaml
```

Check CP pods come up - this takes a while...

```
kubectl get pods
kubectl logs --all-containers $(kubectl get pods --no-headers | awk '/^confluent-operator/ {print $1}')
```

Enable `testadmin` to access control center:

```
kubectl apply -f confluent/controlcenter-testadmin-rolebindings.yaml
```

### Add cluster load balancers to /etc/hosts

Paste output into /etc/hosts

```
kubectl get services --no-headers | awk '/-lb/ {sub("-lb", "", $1) ; print $4 " "  $1".mydomain.example"}'
```

## Test each service

### Zookeeper

```
kubectl exec -ti zookeeper-0 -- bash -c "echo ruok | nc localhost 2181"
```

### Kafka

#### Inside the cluster
```
kubectl exec -ti kafka-0 -- sh
```

```

cat <<EOF > /tmp/kafka.properties
security.protocol=SSL
ssl.truststore.location=/vault/secrets/truststore.jks
ssl.truststore.password=mystorepassword
ssl.keystore.location=/vault/secrets/keystore.jks
ssl.keystore.password=mystorepassword
ssl.key.password=mystorepassword
EOF

# check can list topics
kafka-topics --command-config /tmp/kafka.properties --bootstrap-server kafka.confluent.svc.cluster.local:9071  --list
```

#### Outside the cluster

```
kafka-topics --command-config kafka.properties --bootstrap-server kafka-bootstrap.mydomain.example:9092  --list
```


### Schema registry
```
kubectl exec -ti schemaregistry-0 -- curl -k https://testadmin:testadmin@localhost:8081
kubectl exec -ti schemaregistry-0 -- curl -k https://sr:sr-secret@localhost:8081/permissions
```

### KSQL

```
kubectl port-forward service/ksqldb 8088:8088
```

```
cat <<EOF > ksql-cli.properties
ssl.truststore.location=generated/truststore.jks
ssl.truststore.password=mystorepassword
ssl.keystore.location=generated/ksqldb-keystore.jks
ssl.keystore.password=mystorepassword
ssl.key.password=mystorepassword
ssl.keystore.alias=testservice
EOF
```

/etc/hosts

```
127.0.0.1 ksql-server broker ksql
```

```
ksql --config-file ksql-cli.properties --user ksql --password ksql-secret https://ksql:8088
```

```
show all topics
```

### connect

```
kubectl exec -ti connect-0  -- curl -k https://connect:connect-secret@localhost:8083/connectors
```


### Control center

```
kubectl port-forward service/controlcenter 9021:9021
```

Now try to login:

|Username|Password|Access|
|--- | --- | --- |
| `c3` | `c3-secret` | can admin the cluster but not see KSQL/Schema Registry/Connect |
| `testadmin` | `testadmin` | God user once `controlcenter-testadmin-rolebindings.yaml` applied |
| `kafka` | `kafka-secret` | Can login but see no clusters |

[https://localhost:9021](https://localhost:9021)


kubectl exec -ti controlcenter-0 -- curl -k https://c3:c3-secret@localhost:9021/2.0/clusters/connect

** KSQL select queries need the following fix **

```
kubectl port-forward service/ksqldb 8088:8088
```

/etc/hosts
```
127.0.0.1 ksql-server ksql ksqldb.confluent.svc.cluster.local
```

Browse to 
[https://ksqldb.confluent.svc.cluster.local:8088](https://ksqldb.confluent.svc.cluster.local:8088) and accept certificate


## Cluster internals

### Confluent CLI setup
Use confluent cli reference https://docs.confluent.io/confluent-cli/current/command-reference/confluent_login.html#flags

/etc/hosts
```
127.0.0.1 kafka kafka-0.kafka.confluent-dev.svc.cluster.local kafka-0
```

```
kubectl port-forward service/kafka 8090:8090
```

```
confluent login --url https://kafka:8090 --ca-cert-path generated/cacerts.pem --save
username: kafka
password: kafka-secret
```

### get the cluster id
```
kubectl describe kafkarestclasses.platform.confluent.io default |grep "Kafka Cluster ID"
```

```
confluent cluster describe --url https://kafka:8090 --ca-cert-path generated/cacerts.pem | awk '/kafka-cluster/ { print $3}'
```

### Kafka ACLs

```
kubectl exec -ti kafka-0 -- sh
```

```
cat <<EOF > /tmp/kafka.properties
bootstrap.servers=kafka.confluent.svc.cluster.local:9071
security.protocol=SSL
ssl.truststore.location=/vault/secrets/truststore.jks
ssl.truststore.password=mystorepassword
ssl.keystore.location=/vault/secrets/keystore.jks
ssl.keystore.password=mystorepassword
ssl.key.password=mystorepassword
EOF
```

```
kafka-acls --command-config /tmp/kafka.properties --bootstrap-server kafka.confluent.svc.cluster.local:9071 --list
```


### Kafka RBAC

```
confluent iam rbac role list
```

#### Print the rbac roles
```
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
```


#### rbac audit logs

```
kubectl port-forward service/kafka 9071:9071
```

/etc/hosts
```
127.0.0.1 kafka kafka.confluent.svc.cluster.local kafka-0
```

```
cat <<EOF > kafka.properties
bootstrap.servers=kafka.confluent.svc.cluster.local:9071
security.protocol=SSL
ssl.truststore.location=generated/truststore.jks
ssl.truststore.password=mystorepassword
ssl.keystore.location=generated/kafka-keystore.jks
ssl.keystore.password=mystorepassword
ssl.key.password=mystorepassword
EOF


kafka-console-consumer --bootstrap-server kafka.confluent.svc.cluster.local:9071 --consumer.config kafka.properties --topic confluent-audit-log-events | ./jq 'select(.data.authorizationInfo.granted == false)'
```

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


confluent iam rbac role-binding list --kafka-cluster-id hRRbitJaQZuYbGxuvZ29mA --role DeveloperRead --resource Topic:_confluent-license




## Troubleshooting

### Some or all pods missing
Describe the CRD and you will normally find a missing dependency that failed to init the pod, eg:

```
kubectl describe zookeepers.platform.confluent.io zookeeper
kubectl logs --all-containers schemaregistry-1
```

### Permission errors in logs

```
kubectl get confluentrolebindings.platform.confluent.io
```

Output should look like this:
```
NAME                        STATUS    KAFKACLUSTERID           PRINCIPAL      ROLE             KAFKARESTCLASS      AGE
internal-controlcenter-0    CREATED   MrXMxerpRWO-7q_L4_oEzQ   User:c3        SystemAdmin      confluent/default   2m8s
internal-connect-0          CREATED   MrXMxerpRWO-7q_L4_oEzQ   User:connect   SecurityAdmin    confluent/default   2m8s
internal-schemaregistry-1   CREATED   MrXMxerpRWO-7q_L4_oEzQ   User:sr        ResourceOwner    confluent/default   2m8s
internal-connect-1          CREATED   MrXMxerpRWO-7q_L4_oEzQ   User:connect   ResourceOwner    confluent/default   2m8s
internal-connect-2          CREATED   MrXMxerpRWO-7q_L4_oEzQ   User:connect   DeveloperWrite   confluent/default   2m7s
internal-ksqldb-0           CREATED   MrXMxerpRWO-7q_L4_oEzQ   User:ksql      ResourceOwner    confluent/default   2m7s
internal-ksqldb-1           CREATED   MrXMxerpRWO-7q_L4_oEzQ   User:ksql      ResourceOwner    confluent/default   2m7s
internal-schemaregistry-0   CREATED   MrXMxerpRWO-7q_L4_oEzQ   User:sr        SecurityAdmin    confluent/default   2m7s
internal-ksqldb-2           CREATED   MrXMxerpRWO-7q_L4_oEzQ   User:ksql      DeveloperWrite   confluent/default   2m7s
```

Force re-create of all rolebindings
```
for RULE in $(kubectl get confluentrolebindings.platform.confluent.io --no-headers | awk '{print $1}') ; do 
  kubectl delete confluentrolebindings.platform.confluent.io $RULE
done
```

### Force all pods recreate for a service

```
kubectl delete schemaregistries.platform.confluent.io schemaregistry
kubectl apply -f confluent/cp.yaml
```

### How to debug SSL certs from a service?

```
openssl s_client -showcerts kafka-bootstrap-lb:9092| openssl x509 -text
```

### Restart the whole cluster

**Kafka**

Docs: https://docs.confluent.io/operator/current/co-roll-cluster.html#restart-cp

1. increment value `kafkacluster-manual-roll: "n"` in confluent/cp.yaml
2. `kubectl apply -f confluent/cp.yaml`

**Compoenents**

```
for COMPONENT in $(kubectl -n confluent get statefulset -o wide --no-headers | awk '/confluentinc/ {print $1}') ; do
  kubectl rollout restart statefulset/$COMPONENT --namespace confluent
done
```

# ========================


# 5. Load TLS data into vault

read data from vault
vault kv get -format=json -field=data secret/ksqldb/bearer.txt






# 5. Deploy confluent components



# Get logs from kubernetes
kubectl logs -n confluent  confluent-operator-847d9fdcdd-9bnll
kubectl get crd
kubectl describe crd zookeepers.platform.confluent.io
kubectl get zookeepers.platform.confluent.io
kubectl describe zookeepers.platform.confluent.io

# testing



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




# ksql 
-- table with declared columns: 
CREATE TABLE users (
     id BIGINT PRIMARY KEY,
     usertimestamp BIGINT,
     gender VARCHAR,
     region_id VARCHAR
   ) WITH (
     KAFKA_TOPIC = 'my-users-topic', 
     VALUE_FORMAT = 'JSON',
     PARTITIONS= 1
   );

INSERT INTO users VALUES (1,1,'m','a');
CREATE TABLE QUERYABLE_USERS AS SELECT * FROM USERS;
SELECT * FROM QUERYABLE_USERS;