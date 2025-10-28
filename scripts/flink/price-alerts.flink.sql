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
