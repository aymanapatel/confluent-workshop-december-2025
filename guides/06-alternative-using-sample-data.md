# Variation of the workshop in case coingecko has issues

Confluent Cloud offers a possibility to set up the Datagen Kafka Connector to produce sample events
<img width="2357" height="1079" alt="sample-data" src="https://github.com/user-attachments/assets/880a3d3c-601f-4081-8ced-9cb2a9d5236c" />

Proceed with sample_data_orders. The topic will be populated with events such as

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

```sql
SELECT * FROM  `sample_data_orders` LIMIT 10;
```

```sql
DESCRIBE `sample_data_orders`
```


## Enriched / flattened view with event time
```sql

CREATE TABLE `orders_enriched_table` (
  ordertime BIGINT NOT NULL,
  orderid INT NOT NULL,
  itemid STRING NOT NULL,
  orderunits DOUBLE NOT NULL,
  city STRING,
  state STRING,
  zipcode BIGINT,
  event_time AS TO_TIMESTAMP_LTZ(ordertime, 3),
  WATERMARK FOR event_time AS event_time - INTERVAL '30' SECONDS
);

```
```sql
INSERT INTO `orders_enriched_table`
SELECT
  ordertime,
  orderid,
  itemid,
  orderunits,
  address.city    AS city,
  address.state   AS state,
  address.zipcode AS zipcode
FROM `sample_data_orders`;
```

```sql
SELECT * FROM `orders_enriched_table` LIMIT 10;
```

```sql
CREATE TABLE `order_alerts` AS
SELECT
  orderid,
  itemid,
  orderunits,
  address.state   AS state,
  address.city    AS city,
  address.zipcode AS zipcode,
  TO_TIMESTAMP_LTZ(ordertime, 3) AS alert_time,
  CASE
    WHEN orderunits >= 20 THEN 'HUGE_ORDER'
    WHEN orderunits >= 10 THEN 'LARGE_ORDER'
    WHEN orderunits >= 5  THEN 'MEDIUM_ORDER'
    ELSE 'NORMAL'
  END AS alert_type
FROM `sample_data_orders`
```





```
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

```
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

```
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

```
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

```
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

duckdb

```
confluent tableflow topic enable order-alerts \
  --cluster $CC_KAFKA_CLUSTER \
  --storage-type MANAGED \
  --table-formats ICEBERG \
  --retention-ms 604800000
```  
```sql
SELECT *
FROM iceberg_catalog."$CC_KAFKA_CLUSTER"."order-alerts"
ORDER BY alert_time DESC
LIMIT 10;
```

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


