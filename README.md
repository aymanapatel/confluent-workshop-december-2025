# Cryptocurrency Analytics Pipeline - Workshop Notes

## Resources

### Links
- **GitHub Repository**: [cc-workshop-cryptocurrency-analytics-pipeline](https://github.com/anelook/cc-workshop-cryptocurrency-analytics-pipeline?tab=readme-ov-file)
- **Excalidraw Diagram**: https://excalidraw.com/#room=32234063a6650f477253,yQz48QZKfkO1A_L_nFJyXQ
- [Setup guide](./SETUP.md)

---

## Architecture Overview

### Data Pipeline Flow
```
📊 CoinGecko API 
    ↓ (HttpSource Connector)
🔥 Kafka Topic: crypto-prices (raw nested data)
    ↓ (Flink SQL transformation)
📋 Flink Tables:
    ├─ crypto-prices-exploded (normalized, with watermarks)
    ├─ crypto-predictions (ML forecasts + anomaly detection)
    ├─ crypto-trends (10-minute tumbling windows)
    └─ price-alerts (filtered events)
    ↓ (Tableflow materialization)
🗄️ Iceberg Tables (Parquet files in S3)
    ↓ (DuckDB queries)
📈 Analytics & Insights
```

### Key Components
1. **Data Ingestion**: HttpSource connector pulls cryptocurrency data from CoinGecko API
2. **Stream Processing**: Flink SQL transforms, enriches, and analyzes real-time data
3. **Data Materialization**: Tableflow converts streaming data to Iceberg tables
4. **Analytics**: DuckDB queries Iceberg tables for historical analysis

### Tracked Cryptocurrencies
- Bitcoin
- Ethereum
- Binancecoin (BNB)
- Cardano (ADA)
- Solana (SOL)

---

## Tools Deep Dive

### Apache Kafka
- **Purpose**: Distributed event streaming platform
- **Use Case**: Ingests cryptocurrency price updates in real-time
- **Topic Configuration**:
  - Partitions: 3 (for parallel processing)
  - Retention: 7 days (604800000 ms)
  - Cleanup policy: Delete

**Key Topics:**
- `crypto-prices`: Raw nested JSON from CoinGecko
- `crypto-prices-exploded`: Normalized data (one row per coin)
- `crypto-predictions`: ML predictions and anomaly flags
- `crypto-trends`: Windowed aggregations
- `price-alerts`: Alert signals based on thresholds

### Apache Flink
- **Purpose**: Stream processing engine for real-time transformations
- **Compute Resources**: Confluent Flink Units (CFUs)
- **SQL Interface**: Allows SQL queries on streaming data

#### Key Flink Concepts

**1. Event Time Processing**
- Uses `last_updated_at` from API as event time
- Converts to timestamp: `TO_TIMESTAMP_LTZ(last_updated_at, 0)`
- Separate from processing time (`CURRENT_TIMESTAMP`)

**2. Watermarks**
- Handles late-arriving events
- Configuration: `event_time - INTERVAL '30' SECONDS`
- Allows events up to 30 seconds late before closing windows

**3. Window Functions**

**Tumbling Windows** (non-overlapping):
- Duration: 10 minutes
- Use: Trend analysis with discrete time buckets
```sql
TUMBLE(TABLE `crypto-prices-exploded`, DESCRIPTOR(event_time), INTERVAL '10' MINUTES)
```

**Hopping Windows** (sliding/overlapping):
- Slide: 1 minute
- Size: 5 minutes
- Use: Moving averages with overlap
```sql
HOP(TABLE `crypto-prices-exploded`, DESCRIPTOR(event_time), INTERVAL '1' MINUTES, INTERVAL '5' MINUTES)
```

**4. Window Aggregation Functions**
- `AVG(usd)`: Average price in window
- `STDDEV(usd)`: Price volatility/standard deviation
- `FIRST_VALUE(usd)`: First price in window
- `LAST_VALUE(usd)`: Last price in window
- `MIN/MAX(usd)`: Price range boundaries

**5. Analytical Functions**
- `LAG(usd, 1) OVER (PARTITION BY coin_id ORDER BY event_time)`: Previous price per coin
- Window specification for partitioned analytics

### Confluent ML Functions (ARIMA-based)

#### ML_FORECAST
Predicts future values using time-series forecasting:
```sql
ML_FORECAST(usd, event_time, JSON_OBJECT('horizon' VALUE 1))
    OVER (PARTITION BY coin_id
          ORDER BY event_time
          RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
```
- **Returns**: Array `[timestamp, predicted_value]`
- **Horizon**: Number of steps ahead to predict (1 = next value)
- **Access**: `forecast[1][2]` gets the predicted USD value

#### ML_DETECT_ANOMALIES
Identifies abnormal price movements:
```sql
ML_DETECT_ANOMALIES(usd, event_time, JSON_OBJECT('horizon' VALUE 1))
    OVER (PARTITION BY coin_id
          ORDER BY event_time
          RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
```
- **Returns**: Array with anomaly indicators
- **Access**: `anomaly_results[6]` extracts boolean anomaly flag

### Tableflow
- **Purpose**: Materializes Kafka topics as Iceberg tables
- **Storage**: Managed storage in AWS S3
- **Format**: Apache Iceberg (columnar, versioned)
- **Retention**: 7 days for analytics tables

**Configuration per Table:**
```bash
confluent tableflow topic enable <topic-name> \
  --cluster $CC_KAFKA_CLUSTER \
  --storage-type MANAGED \
  --table-formats ICEBERG \
  --retention-ms 604800000
```

### Apache Iceberg
- **Purpose**: Open table format for analytics
- **Benefits**:
  - Schema evolution (add/modify columns)
  - Time travel (query historical snapshots)
  - ACID transactions
  - Efficient column pruning and predicate pushdown
  
**Integration Points:**
- Storage: AWS S3 (Parquet files)
- Catalog: Confluent Tableflow catalog
- Query engines: DuckDB, Snowflake, Spark, Trino

### DuckDB
- **Purpose**: Lightweight analytical database for querying Iceberg tables
- **Features**:
  - In-process SQL OLAP database
  - Native Iceberg support via `iceberg` extension
  - OAuth2 authentication to Tableflow catalog
  - Web UI for interactive queries

**Connection Setup:**
```sql
CREATE SECRET iceberg_secret (
    TYPE ICEBERG,
    CLIENT_ID '<tableflow-api-key>',
    CLIENT_SECRET '<tableflow-api-secret>',
    ENDPOINT '<tableflow-endpoint-url>',
    OAUTH2_SCOPE 'catalog'
);

ATTACH 'warehouse' AS iceberg_catalog (
    TYPE iceberg,
    SECRET iceberg_secret,
    ENDPOINT '<tableflow-endpoint-url>'
);
```

---

## SQL Query Patterns

### 1. Data Transformation (Flink)

#### Exploding Nested JSON
Converts nested cryptocurrency data to normalized rows:
```sql
CREATE TABLE `crypto-prices-exploded` (...);

INSERT INTO `crypto-prices-exploded`
SELECT coin_id, usd, usd_market_cap, usd_24h_vol, usd_24h_change, last_updated_at
FROM (
    SELECT 'bitcoin' as coin_id, bitcoin.usd, ... FROM `crypto-prices` WHERE bitcoin IS NOT NULL
    UNION ALL
    SELECT 'ethereum' as coin_id, ethereum.usd, ... FROM `crypto-prices` WHERE ethereum IS NOT NULL
    -- ... more coins
) WHERE usd IS NOT NULL AND usd > 0;
```

#### Creating Derived Tables with Window Aggregations
```sql
CREATE TABLE `crypto-trends` AS
SELECT 
  coin_id as cryptocurrency,
  window_start,
  window_end,
  AVG(usd) as avg_price,
  STDDEV(usd) as price_volatility,
  (LAST_VALUE(usd) - FIRST_VALUE(usd)) / FIRST_VALUE(usd) * 100 as price_change_pct,
  CASE 
    WHEN price_change_pct > 2 THEN 'UPWARD'
    WHEN price_change_pct < -2 THEN 'DOWNWARD'
    ELSE 'SIDEWAYS'
  END as trend_direction
FROM TABLE(
  TUMBLE(TABLE `crypto-prices-exploded`, DESCRIPTOR(event_time), INTERVAL '10' MINUTES)
)
GROUP BY coin_id, window_start, window_end;
```

#### Alert Logic with Filtering
```sql
CREATE TABLE `price-alerts` AS
SELECT 
  coin_id AS cryptocurrency,
  usd AS current_price,
  usd_24h_change AS price_change,
  CASE 
    WHEN usd_24h_change > 5 THEN 'STRONG_BULLISH'
    WHEN usd_24h_change > 3 THEN 'BULLISH'
    WHEN usd_24h_change < -5 THEN 'STRONG_BEARISH'
    WHEN usd_24h_change < -3 THEN 'BEARISH'
    ELSE 'NEUTRAL'
  END AS alert_type,
  event_time AS alert_time
FROM `crypto-prices-exploded`
WHERE ABS(usd_24h_change) > 3.0;
```

### 2. Analytics Queries (DuckDB)

#### Query Materialized Tables
```sql
-- Latest price alerts
SELECT * FROM iceberg_catalog."$CC_KAFKA_CLUSTER"."price-alerts"
ORDER BY alert_time DESC
LIMIT 10;
```

#### Alert Pattern Analysis
```sql
SELECT
    cryptocurrency,
    alert_type,
    COUNT(*) as alert_count,
    AVG(price_change) as avg_change,
    MIN(alert_time) as first_alert,
    MAX(alert_time) as latest_alert
FROM iceberg_catalog."$CC_KAFKA_CLUSTER"."price-alerts"
WHERE alert_time >= NOW() - INTERVAL 2 HOURS
GROUP BY cryptocurrency, alert_type
ORDER BY alert_count DESC;
```

#### Forecast Accuracy Analysis
Evaluates directional accuracy (did prediction match actual direction?):
```sql
SELECT
  price_direction_indicator,
  COUNT(*) AS count
FROM (
  SELECT
    usd - lag(usd) OVER w AS actual_change,
    predicted_usd - lag(predicted_usd) OVER w AS predicted_change,
    CASE
      WHEN SIGN(actual_change) = SIGN(predicted_change) THEN '⭐'
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

---

## Statistics & ML Models

### ARIMA (AutoRegressive Integrated Moving Average)
Statistical model for time-series forecasting used by Confluent ML functions:

#### Components
- **AutoRegressive (AR)**: 
  - Uses past values (lags) to predict future
  - Example: Today's price influenced by yesterday's price
  - Mathematical form: $y_t = c + φ₁y_{t-1} + φ₂y_{t-2} + ... + ε_t$

- **Integrated (I)**: 
  - Removes trends to achieve stationarity
  - Differencing: $y'_t = y_t - y_{t-1}$
  - Makes variance constant over time

- **Moving Average (MA)**: 
  - Uses past forecast errors to improve predictions
  - Smooths out noise in the data
  - Mathematical form: `y_t = μ + ε_t + θ₁ε_{t-1} + θ₂ε_{t-2} + ...`

#### Application in Workshop
- **Prediction Horizon**: 1 step ahead (next data point)
- **Partitioning**: Separate model per cryptocurrency
- **Window**: Unbounded preceding (all historical data)
- **Output**: Predicted USD price and anomaly flag

### Anomaly Detection
Uses statistical methods to identify outliers:
- **Method**: Time-series based anomaly detection
- **Baseline**: Historical patterns per cryptocurrency
- **Threshold**: Statistical deviation from expected values
- **Use Case**: Flag unusual price movements (crashes, spikes)

### Statistical Aggregations

#### Volatility Measurement
```sql
STDDEV(usd) as price_volatility
```
- Standard deviation of prices in window
- Higher value = more volatile/risky

#### Price Range Percentage
```sql
(MAX(usd) - MIN(usd)) / AVG(usd) * 100 as price_range_pct
```
- Shows percentage swing within window
- Normalized by average price

#### Confidence Scoring
```sql
LEAST(ABS(price_change_pct) / 10.0, 1.0) as confidence_score
```
- Scales trend strength to [0, 1]
- Larger price changes = higher confidence
- Caps at 1.0 (100%)

---

## Key Takeaways

### Architecture Benefits
1. **Real-time Processing**: Flink processes events as they arrive
2. **Scalability**: Kafka partitioning + Flink parallelism
3. **Flexibility**: SQL interface for stream processing
4. **Analytics-Ready**: Iceberg tables for historical analysis
5. **Cost-Effective**: 7-day retention prevents unbounded storage

### Data Flow Highlights
- **Source**: CoinGecko API (external REST endpoint)
- **Ingestion**: HttpSource connector → Kafka topic
- **Processing**: Flink SQL (explode, enrich, aggregate, predict)
- **Storage**: Tableflow → Iceberg → S3 (Parquet)
- **Query**: DuckDB → OLAP analytics on historical data

### Best Practices Demonstrated
- Event time processing with watermarks
- Partitioned window operations
- Derived tables for specific use cases
- Separation of streaming (Flink) and batch (DuckDB) analytics
- Managed storage with retention policies


