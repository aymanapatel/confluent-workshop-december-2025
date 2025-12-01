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



```
CREATE TABLE `orders-flat` AS
SELECT
  orderid,
  itemid,
  orderunits,
  address.city   AS city,
  address.state  AS state,
  address.zipcode AS zipcode,
  event_time
FROM 
sample_data_orders
```

