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

# Describe cluster to verify settings

```
confluent kafka cluster describe $CC_KAFKA_CLUSTER
```


### 1.6 Create API keys 



For the cluster
```
confluent api-key create --resource $CC_KAFKA_CLUSTER --description "Workshop API Key for Kafka Cluster"
```

```
# export KAFKA_API_KEY=
# export KAFKA_API_SECRET=
```

```
confluent api-key use $KAFKA_API_KEY --resource $CC_KAFKA_CLUSTER
```

For the schema registry

```
confluent schema-registry cluster describe
```

```
export SCHEMA_REGISTRY_CLUSTER_ID=
```

```
confluent api-key create --resource $SCHEMA_REGISTRY_CLUSTER_ID --description "Workshop API Key for Schema Registry"
```

```
export SCHEMA_REGISTRY_API_KEY=
```

```
export SCHEMA_REGISTRY_API_SECRET=
```
For Tableflow

```
confluent api-key create --resource tableflow --description "Workshop API Key for Tableflow"
```

```
export TABLEFLOW_API_KEY=
```

```
export TABLEFLOW_API_SECRET=
```

```
# Test Tableflow access by listing topics (should be empty initially)
confluent tableflow topic list
```

## 2 Bring the data in!

### 2.1 Create Kafka topic


Create topic for cryptocurrency prices

```
confluent kafka topic create crypto-prices \
  --partitions 3 \
  --config retention.ms=604800000 \
  --config cleanup.policy=delete
```

Create compacted topic for latest prices

```
confluent kafka topic create latest-prices \
  --partitions 3 \
  --config cleanup.policy=compact \
  --config min.cleanable.dirty.ratio=0.01
```

```
# List all topics
confluent kafka topic list

# Describe the crypto-prices topic
confluent kafka topic describe crypto-prices

# List topic configurations
confluent kafka topic configuration list crypto-prices
```

### 2.2 Deploy connector

```cd scripts/kafka ```
```./deploy-connector.sh```


## 3 Configure access via Iceberg tables and connect DuckDB for analytics

### 3.1 Enable tableflow
```
confluent tableflow topic enable crypto-prices \
  --cluster $CC_KAFKA_CLUSTER \
  --storage-type MANAGED \
  --table-formats ICEBERG \
  --retention-ms 604800000
```

### 3.2

```
print $TABLEFLOW_API_KEY
```
```
print $TABLEFLOW_API_SECRET
```

```sql
CREATE SECRET iceberg_secret (
    TYPE ICEBERG,
    CLIENT_ID 'your-tableflow-api-key',
    CLIENT_SECRET 'your-tableflow-api-secret',
    ENDPOINT 'https://tableflow.us-east-1.aws.confluent.cloud/iceberg/catalog/organizations/your-org-id/environments/your-env-id',
    OAUTH2_SCOPE 'catalog'
);
```

```duckdb --ui workshop_analytics.db```









