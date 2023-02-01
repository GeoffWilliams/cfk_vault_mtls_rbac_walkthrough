# certs and secrets generator and examples

## 0. Requirements
* openssl
* cfssl (cloudflare ssl) `apt install golang-cfssl`

optional:
* [vault](doc/vault_k8s.md)

## 1. Generate a CA

```
./create_ca.sh
```

## 2. Generate mTLS component certs for confluent

```
./confluent_certs.sh
```
