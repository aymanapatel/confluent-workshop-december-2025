## Step 1 - Set up playground


### 1.1 Clone the repository

```
workshop-validate
```

### 1.2 Get free trial for Confluent Cloud 

Got to cnfl.io/workshop-cloud
Use CONFLUENTDEV1


### 1.3 Authenticate CLI

```
workshop-login
```

### 1.4 Create and use a separate environment

```
confluent environment create "cc-workshop-env"
```
```
export CC_ENV_ID=
```
``` confluent environment use $CC_ENV_ID```

### 1.5 Create and use a new cluster

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

### 1.6 Create API keys 

For the cluster

For the schema registry

For Tableflow

## 2 Bring the data in!

### 2.1 Create Kafka topic

### 2.2 











