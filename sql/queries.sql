-- sql/queries.sql, written and run by Notebook A
CREATE OR REPLACE TABLE tr AS SELECT * FROM 'data/processed/traffic.parquet';
-- Q1: hourly profile by day type
SELECT hour, day_type, AVG(vehicles) AS mean_vehicles, AVG(speed) AS mean_speed_kmh, COUNT(vehicles) AS cell_hours
FROM tr WHERE city_outage = 0 AND partial_outage = 0 AND value_fault = 0 GROUP BY 1, 2 ORDER BY 2, 1;
-- Q2: mean vehicles by day type and period (years, the 2024 data split at the level break), relative to ordinary weekdays of the same period
WITH m AS (SELECT CASE WHEN ts >= TIMESTAMP '2024-01-24' THEN '2024 after break' WHEN YEAR(ts) = 2024 THEN '2024 before break' ELSE CAST(YEAR(ts) AS VARCHAR) END AS year,
                  day_type, AVG(vehicles) AS mean_vehicles, COUNT(vehicles) AS cell_hours
           FROM tr WHERE city_outage = 0 AND partial_outage = 0 AND value_fault = 0 GROUP BY 1, 2)
SELECT m.*, ROUND(100 * (m.mean_vehicles / w.mean_vehicles - 1), 1) AS pct_vs_weekday
FROM m JOIN (SELECT year, mean_vehicles FROM m WHERE day_type = 'weekday') w USING (year) ORDER BY year, pct_vs_weekday;
-- Q3: completeness and outages by month
SELECT strftime(ts, '%Y-%m') AS month, ROUND(100.0 * AVG(recorded), 2) AS recorded_pct,
       SUM(city_outage) / COUNT(DISTINCT cell) AS city_outage_hours, SUM(partial_outage) / COUNT(DISTINCT cell) AS partial_outage_hours,
       SUM(value_fault) / COUNT(DISTINCT cell) AS faulty_hours
FROM tr GROUP BY 1 ORDER BY 1;
-- Q4: cells thinning out over time, by quarter
WITH c AS (SELECT cell, CONCAT(YEAR(ts), '-Q', QUARTER(ts)) AS quarter, AVG(recorded) AS coverage FROM tr GROUP BY 1, 2)
SELECT quarter, COUNT(*) AS cells, SUM(CASE WHEN coverage >= 0.5 THEN 1 ELSE 0 END) AS cells_with_half_coverage,
       ROUND(AVG(coverage), 3) AS mean_coverage, ROUND(MIN(coverage), 3) AS worst_cell FROM c GROUP BY 1 ORDER BY 1;
-- Q5: holiday echo, described: the same hour one week earlier divided by today, by type of the current day
WITH d AS (SELECT cell, ts, day_type, vehicles, LAG(vehicles, 168) OVER (PARTITION BY cell ORDER BY ts) AS last_week
           FROM tr)
SELECT day_type, COUNT(*) AS cell_hours, ROUND(SUM(last_week) / SUM(vehicles), 3) AS last_week_over_today
FROM d WHERE vehicles IS NOT NULL AND last_week IS NOT NULL GROUP BY 1 ORDER BY 3;
-- Q6: model table on the full hourly grid, target = vehicles in the next hour, every lag is an exact hour lag
CREATE OR REPLACE TABLE feat AS
WITH b AS (
  SELECT cell, ts, lat, lon, vehicles AS volume, speed, city_outage AS outage_now, partial_outage AS partial_now, value_fault AS fault_now,
         LEAD(vehicles, 1) OVER w AS y, LEAD(ts, 1) OVER w AS ts_y,
         LEAD(city_outage, 1) OVER w AS outage_y, LEAD(partial_outage, 1) OVER w AS partial_y, LEAD(value_fault, 1) OVER w AS fault_y,
         LAG(vehicles, 1) OVER w AS lag1, LAG(vehicles, 2) OVER w AS lag2,
         LAG(vehicles, 23) OVER w AS lag23,                      -- same hour yesterday (24 h before the target)
         LAG(vehicles, 167) OVER w AS lag167,                    -- same hour last week (168 h before the target)
         LAG(vehicles, 335) OVER w AS lag335,                    -- two weeks before the target
         LAG(vehicles, 503) OVER w AS lag503,                    -- three weeks before the target
         ts - LAG(ts, 1) OVER w AS gap
  FROM tr WINDOW w AS (PARTITION BY cell ORDER BY ts))
SELECT b.*, HOUR(b.ts_y) AS hour_y, SIN(2 * PI() * HOUR(b.ts_y) / 24) AS hour_sin, COS(2 * PI() * HOUR(b.ts_y) / 24) AS hour_cos,
       ISODOW(b.ts_y) - 1 AS dow_y, CASE WHEN ISODOW(b.ts_y) >= 6 THEN 1 ELSE 0 END AS is_weekend_y,
       CONCAT(YEAR(b.ts), '-Q', QUARTER(b.ts)) AS quarter,
       c.is_holiday AS is_holiday_y, CASE WHEN HOUR(b.ts_y) >= 13 THEN c.is_arife ELSE 0 END AS is_arife_y,   -- FIX: arife is a holiday from 13:00 only
       c.is_admin_leave AS is_admin_leave_y, c.is_ramadan AS is_ramadan_y,
       c.is_school_break AS is_school_break_y, c.is_special_event AS is_special_event_y, c.holiday_like AS holiday_like_y,
       c.holiday_last_week AS holiday_last_week_y, c.holiday_2w AS holiday_2w_y, c.holiday_3w AS holiday_3w_y,
       c.days_since_holiday AS days_since_holiday_y, c.day_type AS day_type_y
FROM b LEFT JOIN 'data/processed/calendar_daily.parquet' c ON CAST(b.ts_y AS DATE) = CAST(c.date AS DATE)
WHERE b.ts_y IS NOT NULL;
-- Q7: quality of the model table
SELECT COUNT(*) AS rows, COUNT(DISTINCT cell) AS cells, MIN(ts) AS first_ts, MAX(ts) AS last_ts,
       MAX(EXTRACT(EPOCH FROM gap)) / 3600 AS max_gap_hours, COUNT(*) - COUNT(DISTINCT cell || CAST(ts AS VARCHAR)) AS dup_keys,
       ROUND(100.0 * AVG(CASE WHEN y IS NULL THEN 1 ELSE 0 END), 2) AS target_missing_pct FROM feat;
