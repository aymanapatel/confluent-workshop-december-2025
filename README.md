# Hands-On with Confluent Cloud: Apache Kafka®, Apache Flink®, and Tableflow

Confluent Cloud is a fully managed platform for Apache Kafka, designed to simplify real-time data streaming and processing. It integrates Kafka for data ingestion, Flink for stream processing, and Tableflow for converting streaming data into analytics-ready Apache Iceberg tables. DuckDB, a lightweight analytical database, supports querying these Iceberg tables, making it an ideal tool for the workshop’s analytics component. The workshop is designed for developers with basic programming knowledge, potentially new to Kafka, Flink, or Tableflow, and aims to provide hands-on experience within a condensed time frame.

🚨 CRITICAL - COST PREVENTION: After completing this workshop, immediately follow the teardown guide to prevent unexpected charges from Flink compute pools and Tableflow catalog integrations.

### What you'll learn
- Set up a Kafka cluster and manage topics in Confluent Cloud.
- Write and run a Flink job to process streaming data.
- Use Tableflow to materialize Kafka topics as Iceberg tables and query them with DuckDB.

### Prerequisites
GitHub Account: Required for accessing GitHub Codespaces or cloning the workshop repository.
[Create a free GitHub account](https://github.com/join) if you don’t have one.

This is simplified flow. For more information and extra activities check detailed [guides](./guides). The flow below skips and simplifies some sections.

## Step 1. Set up playground

### 1.1 Open the repository in GitHub Codespace

[![Open in GitHub Codespaces](https://github.com/codespaces/badge.svg)](
https://github.com/codespaces/new/anelook/cc-workshop-cryptocurrency-analytics-pipeline)

Alternatively, select the `<> Code` button, go to `Codespaces` and click to `Create codespace on main`. 

The environment will install all necessary dependencies and tools. This will take around 10 minutes.

Once the environment is ready, validate that everything is set up by running
```
workshop-validate
```

### 1.2 Get free trial for Confluent Cloud 
Register for Confluent Cloud and get free credits by going to [cnfl.io/workshop-cloud](cnfl.io/workshop-cloud).
Once registered, go to Billing and Payment and set the code ``CONFLUENTDEV1``.

### 1.3 Authenticate Confluent CLI
Use your email and password to authenticate [Confluent CLI](https://docs.confluent.io/confluent-cli/current/install.html)
```
workshop-login
```

### 1.4 Create an Apache Kafka cluster

Create a new basic cluster:
```
confluent kafka cluster create workshop-cluster \
  --cloud aws \
  --region us-east-1 \
  --type basic
```
The output will give you additional information, including the id of the cluster. We'll need this id for later. For convenience export it to ``CC_KAFKA_CLUSTER``:
```
export CC_KAFKA_CLUSTER=
```
Set the cluster as the active one:
```
confluent kafka cluster use $CC_KAFKA_CLUSTER
```

You can also check at any time the list of your enviroments with
```
confluent kafka cluster list
```

You can get additional details of the cluster by running
```
confluent kafka cluster describe $CC_KAFKA_CLUSTER
```

### 1.6 Create API keys 
We'll need API keys for the cluster itself and for Tableflow.

```
confluent api-key create --resource $CC_KAFKA_CLUSTER --description "Workshop API Key for Kafka Cluster"
```
The command outpust the key and the secret, keep them for later.
```
export KAFKA_API_KEY=
```
```
export KAFKA_API_SECRET=
```
Set to use these keys for the cluster.
```
confluent api-key use $KAFKA_API_KEY --resource $CC_KAFKA_CLUSTER
```

Now, let's do same steps for Tableflow

```
confluent api-key create --resource tableflow --description "Workshop API Key for Tableflow"
```
```
export TABLEFLOW_API_KEY=
```
```
export TABLEFLOW_API_SECRET=
```
You can test Tableflow access by listing topics (should be empty initially)
```
confluent tableflow topic list
```

## Setp 2. Bring the data in!
We'll stream cryptocurrency data from [coingecko](https://www.coingecko.com/) into an Apache Kafka topic.

### 2.1 Create Kafka topic

Create topic for cryptocurrency prices
```
confluent kafka topic create crypto-prices \
  --partitions 3 \
  --config retention.ms=604800000 \
  --config cleanup.policy=delete
```

You can list all topics
```
confluent kafka topic list
```
Get additional information and topic configuration
```
confluent kafka topic describe crypto-prices
confluent kafka topic configuration list crypto-prices
```

### 2.2 Deploy connector

Script [deploy-connector](scripts/kafka/deploy-connector.sh) deploys HttpSource connectors that brings the data from coingecko's API endpoint
```
( cd scripts/kafka && ./deploy-connector.sh )
```

## Step 3. Process streaming data with Apache Flink

Create a compute pool
```
confluent flink compute-pool create workshop-pool \
  --cloud aws \
  --region us-east-1 \
  --max-cfu 5 
```
Export the id
```
export FLINK_POOL_ID=
```
And set to use this compute pool
```
confluent flink compute-pool use $FLINK_POOL_ID
```

## 3.2
Enter the shell to run SQL queries:
```
confluent flink shell --compute-pool $FLINK_POOL_ID
```

Create exploded table with individual records for each cryptocurrency. This sets proper time attributes for windowing operations

```sql
CREATE TABLE `crypto-prices-exploded` (
    coin_id STRING,
    usd DOUBLE,
    usd_market_cap DOUBLE,
    usd_24h_vol DOUBLE,
    usd_24h_change DOUBLE,
    last_updated_at BIGINT,
    event_time AS TO_TIMESTAMP_LTZ(last_updated_at, 0),
    processed_at AS CURRENT_TIMESTAMP,
    WATERMARK FOR event_time AS event_time - INTERVAL '30' SECONDS
);

```

Populate the exploded table from the raw crypto-prices data
```sql
INSERT INTO `crypto-prices-exploded`
SELECT 
    coin_id,
    usd,
    usd_market_cap,
    usd_24h_vol,
    usd_24h_change,
    last_updated_at
FROM (
    SELECT 'bitcoin' as coin_id, bitcoin.usd, bitcoin.usd_market_cap, bitcoin.usd_24h_vol, bitcoin.usd_24h_change, bitcoin.last_updated_at FROM `crypto-prices` WHERE bitcoin IS NOT NULL
    UNION ALL
    SELECT 'ethereum' as coin_id, ethereum.usd, ethereum.usd_market_cap, ethereum.usd_24h_vol, ethereum.usd_24h_change, ethereum.last_updated_at FROM `crypto-prices` WHERE ethereum IS NOT NULL
    UNION ALL
    SELECT 'binancecoin' as coin_id, binancecoin.usd, binancecoin.usd_market_cap, binancecoin.usd_24h_vol, binancecoin.usd_24h_change, binancecoin.last_updated_at FROM `crypto-prices` WHERE binancecoin IS NOT NULL
    UNION ALL
    SELECT 'cardano' as coin_id, cardano.usd, cardano.usd_market_cap, cardano.usd_24h_vol, cardano.usd_24h_change, cardano.last_updated_at FROM `crypto-prices` WHERE cardano IS NOT NULL
    UNION ALL
    SELECT 'solana' as coin_id, solana.usd, solana.usd_market_cap, solana.usd_24h_vol, solana.usd_24h_change, solana.last_updated_at FROM `crypto-prices` WHERE solana IS NOT NULL
) exploded
WHERE usd IS NOT NULL AND usd > 0;
```

Check the latest 10 records
```sql
SELECT * FROM `crypto-prices-exploded` LIMIT 10;
```

You can also count records per cryptocurrency
```sql
SELECT 
    coin_id,
    COUNT(*) as record_count,
    AVG(usd) as avg_price,
    MIN(event_time) as earliest_update,
    MAX(event_time) as latest_update
FROM `crypto-prices-exploded`
GROUP BY coin_id;
```


## 3.3 Create Derived Stream for Price Predictions
```sql
CREATE TABLE `crypto-predictions` AS
SELECT
  event_time,
  coin_id,
  usd,
  forecast[1][2] AS predicted_usd,
  previous_price,
  (previous_price - usd) / usd AS pct_diff,
  anomaly_results[6] AS is_anomaly
FROM (
  SELECT
    coin_id,
    usd,
    event_time,
    LAG(usd, 1)
        OVER (PARTITION BY coin_id
            ORDER BY event_time) AS previous_price,
    ML_FORECAST(usd, event_time, JSON_OBJECT('horizon' VALUE 1))
      OVER (PARTITION BY coin_id
            ORDER BY event_time
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS forecast,
    ML_DETECT_ANOMALIES(usd, event_time, JSON_OBJECT('horizon' VALUE 1))
      OVER (PARTITION BY coin_id
            ORDER BY event_time
            RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS anomaly_results
  FROM `crypto-prices-exploded`
)
WHERE forecast[1][2] IS NOT NULL AND anomaly_results[6] IS NOT NULL;


```




## Setp 4. Configure access via Iceberg tables and connect DuckDB for analytics

### 4.1 Enable tableflow
```
# Enable Tableflow for the crypto-predictions topic created by Flink. The use case
# for exporting data for analytics is to analyze predictive accuracy of the models.
confluent tableflow topic enable crypto-predictions \
  --cluster $CC_KAFKA_CLUSTER \
  --storage-type MANAGED \
  --table-formats ICEBERG \
  --retention-ms 604800000
```

### 4.2

```
cat <<EOF
SET CC_KAFKA_CLUSTER = $CC_KAFKA_CLUSTER
SET TABLEFLOW_API_KEY = $TABLEFLOW_API_KEY
SET TABLEFLOW_API_SECRET = $TABLEFLOW_API_SECRET
EOF
```



todo - add image



```
SET CC_KAFKA_CLUSTER =
SET TABLEFLOW_API_KEY =
SET TABLEFLOW_API_SECRET =
```


duckdb --ui workshop_analytics.db
Give me an empty notebook

```sql
CREATE SECRET iceberg_secret (
    TYPE ICEBERG,
    CLIENT_ID 'your-tableflow-api-key',
    CLIENT_SECRET 'your-tableflow-api-secret',
    ENDPOINT 'https://tableflow.us-east-1.aws.confluent.cloud/iceberg/catalog/organizations/your-org-id/environments/your-env-id',
    OAUTH2_SCOPE 'catalog'
);
```

```sql
ATTACH 'warehouse' AS iceberg_catalog (
    TYPE iceberg,
    SECRET iceberg_secret,
    ENDPOINT 'https://tableflow.us-east-1.aws.confluent.cloud/iceberg/catalog/organizations/your-org-id/environments/your-env-id'
);
```


```duckdb --ui workshop_analytics.db```


```SHOW DATABASES;```

Analyze price forecast model efficacy for overall directional (increase / decrease) accuracy
```
SELECT
  price_direction_indicator,
  COUNT(*) AS count
FROM (
  SELECT
    usd - lag(usd) OVER w AS actual_change,
    usd - lag(predicted_usd) OVER w AS predicted_change,
    CASE
      WHEN SIGN(actual_change) == SIGN (predicted_change) THEN '⭐'
      ELSE '❌'
    END AS price_direction_indicator
  FROM iceberg_catalog."$CC_KAFKA_CLUSTER"."crypto-predictions"
  WINDOW w AS (
      PARTITION BY coin_id
      ORDER BY event_time ASC
      ROWS BETWEEN 1 PRECEDING AND CURRENT ROW
  )
)
GROUP BY price_direction_indicator;
```

Compare anomalous prices to non-anomalous prices to judge model efficacy
```
SELECT
  usd,
  previous_price,
  pct_diff,
  is_anomaly
FROM iceberg_catalog."$CC_KAFKA_CLUSTER"."crypto-predictions";
```


