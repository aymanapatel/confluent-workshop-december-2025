# Hands-On with Confluent Cloud: Apache Kafka®, Apache Flink®, and Tableflow

This is simplified flow. For more information check detailed guides.

## Step 1 - Set up playground

### 1.1 Onen the repository in GutHub Codespace

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

Describe cluster to verify settings

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


## 3. 

```
confluent flink compute-pool create workshop-pool \
  --cloud aws \
  --region us-east-1 \
  --max-cfu 5 \
  --environment $CC_ENV_ID
```

```export FLINK_POOL_ID=```
```confluent flink compute-pool use $FLINK_POOL_ID```

## 3.2

```
confluent flink shell --compute-pool $FLINK_POOL_ID
```

Create exploded table with individual records for each cryptocurrency
Note: This creates a table with proper time attributes for windowing operations

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

```sql
SELECT * FROM `crypto-prices-exploded` LIMIT 10;
```

Count records per cryptocurrency
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

Other optional things you can try:

```
-- Filter for significant price changes using exploded data
SELECT 
  coin_id,
  usd as price,
  usd_24h_change as change_pct,
  usd_market_cap as market_cap,
  event_time
FROM `crypto-prices-exploded`
WHERE ABS(usd_24h_change) > 3.0;

-- Compare current prices across cryptocurrencies
SELECT 
  coin_id,
  usd as current_price,
  usd_24h_change as daily_change,
  CASE 
    WHEN usd_24h_change > 0 THEN '📈 UP'
    WHEN usd_24h_change < 0 THEN '📉 DOWN'
    ELSE '➡️ FLAT'
  END as trend_indicator
FROM `crypto-prices-exploded`
WHERE event_time >= CURRENT_TIMESTAMP - INTERVAL '5' MINUTES;

-- Calculate 5-minute moving averages using exploded data
SELECT 
  coin_id as cryptocurrency,
  window_start,
  window_end,
  AVG(usd) as avg_price,
  MIN(usd) as min_price,
  MAX(usd) as max_price,
  AVG(usd_market_cap) as avg_market_cap,
  AVG(usd_24h_vol) as avg_volume,
  COUNT(*) as price_updates
FROM TABLE(
  TUMBLE(TABLE `crypto-prices-exploded`, DESCRIPTOR(event_time), INTERVAL '5' MINUTES)
)
GROUP BY coin_id, window_start, window_end;

-- Price volatility calculation using sliding windows with TVF syntax
SELECT 
  coin_id as cryptocurrency,
  w.window_start,
  w.window_end,
  AVG(usd) as avg_price,
  STDDEV(usd) as price_volatility,
  (MAX(usd) - MIN(usd)) / AVG(usd) * 100 as price_range_pct,
  AVG(ABS(usd_24h_change)) as avg_daily_volatility
FROM TABLE(
  HOP(TABLE `crypto-prices-exploded`, DESCRIPTOR(event_time), INTERVAL '1' MINUTES, INTERVAL '5' MINUTES)
) AS w
GROUP BY coin_id, w.window_start, w.window_end;
```

## 3.3 Price alerts

```sql
-- Create price alerts using exploded cryptocurrency data

-- insert into `price-alerts`
CREATE TABLE `price-alerts` AS (
SELECT 
  coin_id AS cryptocurrency,
  usd AS current_price,
  usd_24h_change AS price_change,
  CASE 
    WHEN usd_24h_change > 5 THEN 'STRONG_BULLISH'
    WHEN usd_24h_change > 5 THEN 'BULLISH'
    WHEN usd_24h_change < -5 THEN 'STRONG_BEARISH'
    WHEN usd_24h_change < -3 THEN 'BEARISH'
    ELSE 'NEUTRAL'
  END AS alert_type,
  event_time AS alert_time
FROM `crypto-prices-exploded`
WHERE ABS(usd_24h_change) > 3.0
);

```

## 3.4 Create Derived Stream for Price Predictions
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

```
confluent tableflow topic enable price-alerts \
  --cluster $CC_KAFKA_CLUSTER \
  --storage-type MANAGED \
  --table-formats ICEBERG \
  --retention-ms 604800000
```

```
confluent tableflow topic enable crypto-trends \
  --cluster $CC_KAFKA_CLUSTER \
  --storage-type MANAGED \
  --table-formats ICEBERG \
  --retention-ms 604800000

```

## 4 Configure access via Iceberg tables and connect DuckDB for analytics

### 4.1 Enable tableflow
```
confluent tableflow topic enable crypto-prices \
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




