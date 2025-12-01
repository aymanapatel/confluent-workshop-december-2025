# Variation of the workshop in case coingecko API has issues

Confluent Cloud offers a possibility to set up the Datagen Kafka Connector to produce sample events
<img width="2357" height="1079" alt="sample-data" src="https://github.com/user-attachments/assets/880a3d3c-601f-4081-8ced-9cb2a9d5236c" />

Select to generate sample order data. The topic will be populated with events such as

```json
{
  "ordertime": 1517131318905,
  "orderid": 3,
  "itemid": "Item_9",
  "orderunits": 4.867134079954157,
  "address": {
    "city": "City_97",
    "state": "State_38",
    "zipcode": 57590
  }
}
```

In Flink console you can check latest 10 items

```sql
SELECT * FROM  `sample_data_orders` LIMIT 10;
```

Get the schema of the `sample_data_orders` table 
```sql
DESCRIBE `sample_data_orders`
```


## Enriched / flattened view with event time

Create a derived table that has a couple of additional properties.

```sql
CREATE TABLE `orders-enriched` (
  key        BYTES,
  ordertime  BIGINT,
  orderid    INT,
  itemid     STRING,
  orderunits DOUBLE,
  city       STRING,
  state      STRING,
  zipcode    BIGINT,
  event_time AS TO_TIMESTAMP_LTZ(ordertime, 3),
  processed_at AS CURRENT_TIMESTAMP,
  WATERMARK FOR event_time AS event_time - INTERVAL '30' SECONDS
);
```


Insert data into the new table
```sql
INSERT INTO `orders-enriched`
SELECT
  key,
  ordertime,
  orderid,
  itemid,
  orderunits,
  address.city,
  address.state,
  address.zipcode
FROM `sample_data_orders`;
```

## Moving averages / windowed stats over orders

5-minute tumbling windows, grouped by itemid:

```sql
SELECT
  itemid              AS product_id,
  window_start,
  window_end,
  AVG(orderunits)     AS avg_units,
  MIN(orderunits)     AS min_units,
  MAX(orderunits)     AS max_units,
  SUM(orderunits)     AS total_units,
  COUNT(*)            AS orders_count
FROM TABLE(
  TUMBLE(
    TABLE `orders-enriched`,
    DESCRIPTOR(event_time),
    INTERVAL '5' MINUTES
  )
)
GROUP BY
  itemid,
  window_start,
  window_end;
```

## Order trends

10-minute tumbling windows on event_time.
Per item (itemid), per window:
- avg_units – average orderunits in the window
- units_volatility – STDDEV(orderunits) in the window
- units_change_pct – percentage change from first to last orderunits in that window

Trend label:
> 2% → UPWARD
< -2% → DOWNWARD
otherwise → SIDEWAYS

confidence_score: scaled 0–1 based on ABS(units_change_pct) 
```sql
CREATE TABLE `order-trends` AS
SELECT 
  itemid AS product_id,
  window_start,
  window_end,
  avg_units,
  units_volatility,
  CASE 
    WHEN units_change_pct > 2 THEN 'UPWARD'
    WHEN units_change_pct < -2 THEN 'DOWNWARD'
    ELSE 'SIDEWAYS'
  END AS trend_direction,
  LEAST(ABS(units_change_pct) / 10.0, 1.0) AS confidence_score
FROM (
  SELECT 
    itemid,
    window_start,
    window_end,
    AVG(orderunits) AS avg_units,
    STDDEV(orderunits) AS units_volatility,
    (LAST_VALUE(orderunits) - FIRST_VALUE(orderunits)) / FIRST_VALUE(orderunits) * 100 AS units_change_pct
  FROM TABLE(
    TUMBLE(
      TABLE `orders-enriched`,        
      DESCRIPTOR(event_time),
      INTERVAL '10' MINUTES
    )
  )
  GROUP BY itemid, window_start, window_end
);
```

## Alerts

Alerts on the number of ordered units:
```sql
CREATE TABLE `order-alerts` AS
SELECT 
  itemid AS product_id,
  orderunits AS current_units,
  units_change_pct AS units_change,
  CASE
    WHEN units_change_pct > 10 THEN 'STRONG_UP'
    WHEN units_change_pct > 3 THEN 'UP'
    WHEN units_change_pct < -10 THEN 'STRONG_DOWN'
    WHEN units_change_pct < -3 THEN 'DOWN'
    ELSE 'NEUTRAL'
  END AS alert_type,
  event_time AS alert_time
FROM (
  SELECT
    itemid,
    orderunits,
    event_time,
    /* % change vs previous order of the same item */
    ((orderunits - LAG(orderunits) OVER (
        PARTITION BY itemid ORDER BY event_time
    )) / LAG(orderunits) OVER (
        PARTITION BY itemid ORDER BY event_time
    )) * 100 AS units_change_pct
  FROM `orders-enriched`
)
WHERE ABS(units_change_pct) > 3;
```

## Materialize data via Tableflow
```
confluent tableflow topic enable order-alerts \
  --cluster $CC_KAFKA_CLUSTER \
  --storage-type MANAGED \
  --table-formats ICEBERG \
  --retention-ms 604800000
```

Start DuckDB UI
```
duckdb --ui workshop_analytics.db
```

Get latest 10 items from the table
```sql
SELECT *
FROM iceberg_catalog."$CC_KAFKA_CLUSTER"."order-alerts"
ORDER BY alert_time DESC
LIMIT 10;
```

Analyze order alert patterns:
- how many alerts fired,
- the average % units change,
- when the first and latest alert happened in the last 2 hours.

```sql
SELECT
    product_id,
    alert_type,
    COUNT(*) AS alert_count,
    AVG(units_change) AS avg_change,
    MIN(alert_time) AS first_alert,
    MAX(alert_time) AS latest_alert
FROM iceberg_catalog."$CC_KAFKA_CLUSTER"."order-alerts"
WHERE alert_time >= NOW() - INTERVAL 2 HOURS
GROUP BY product_id, alert_type
ORDER BY alert_count DESC;
```


