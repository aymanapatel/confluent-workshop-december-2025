
## Step 1 - Set up playground
Clone the repository

``
workshop-validate
```


```
workshop-login
```

```
confluent environment create "cc-workshop-env"
```
```
export CC_ENV_ID=
```
``` confluent environment use $CC_ENV_ID```

```
confluent kafka cluster create workshop-cluster \
  --cloud aws \
  --region us-east-1 \
  --type basic
```

```
export CC_KAFKA_CLUSTER=
```

```
confluent kafka cluster use $CC_KAFKA_CLUSTER
```
