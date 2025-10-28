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
