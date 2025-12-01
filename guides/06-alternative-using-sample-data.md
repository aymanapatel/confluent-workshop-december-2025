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

