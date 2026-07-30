 
-- 1. How many trips are in the table, and what date range do they cover?
SELECT rideable_type,
       COUNT(*)        AS trips,
       MIN(started_at) AS first_start,
       MAX(started_at) AS last_start,
       MAX(ended_at)   AS last_end
FROM city_bike_trip_data
WHERE started_at >= '2026-06-01'
  AND started_at <  '2026-06-14'
GROUP BY rideable_type WITH ROLLUP;
 
 
-- 2. What share of all trips does each bike type account for, and how does
SELECT rideable_type,
       member_casual,
       COUNT(*) AS trips,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS share_pct,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY member_casual), 2) AS pct_within_rider
FROM city_bike_trip_data
WHERE started_at >= '2026-06-01'
  AND started_at <  '2026-06-14'
GROUP BY rideable_type, member_casual
ORDER BY member_casual, rideable_type;
 
 
-- 3. What are the ten busiest start stations, and the ten busiest end stations?
SELECT start_station_name AS station,
       COUNT(*)           AS trips
FROM city_bike_trip_data
WHERE started_at >= '2026-06-01'
  AND started_at <  '2026-06-14'
  AND start_station_name <> ''
GROUP BY station
ORDER BY trips DESC
LIMIT 10;
 
SELECT end_station_name AS station,
       COUNT(*)         AS trips
FROM city_bike_trip_data
WHERE started_at >= '2026-06-01'
  AND started_at <  '2026-06-14'
  AND end_station_name <> ''
GROUP BY station
ORDER BY trips DESC
LIMIT 10;
 
 
-- 4. What's the average trip duration by hour of day?
SELECT HOUR(started_at) AS hour_of_day,
       COUNT(*)         AS trips,
       ROUND(AVG(TIMESTAMPDIFF(MINUTE, started_at, ended_at)), 1) AS avg_duration_min
FROM city_bike_trip_data
WHERE started_at >= '2026-06-01'
  AND started_at <  '2026-06-14'
  AND TIMESTAMPDIFF(MINUTE, started_at, ended_at) BETWEEN 1 AND 5*60
GROUP BY hour_of_day
ORDER BY hour_of_day;
 
 
-- 5. How does trip volume differ on weekdays vs weekends, split by member type?
SELECT CASE WHEN DAYOFWEEK(started_at) IN (1, 7) THEN 'weekend' ELSE 'weekday' END AS day_type,
       member_casual,
       COUNT(*)                         AS trips,
       COUNT(DISTINCT DATE(started_at)) AS days,
       ROUND(COUNT(*) / COUNT(DISTINCT DATE(started_at)), 1) AS trips_per_day,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY member_casual), 1) AS pct_of_rider_trips
FROM city_bike_trip_data
WHERE started_at >= '2026-06-01'
  AND started_at <  '2026-06-14'
GROUP BY day_type, member_casual
ORDER BY day_type, member_casual;
 
-- 6. For each bike type, what are the longest and shortest trips — including
WITH ride_details AS (
    SELECT rideable_type,
           start_station_name,
           end_station_name,
           started_at,
           ended_at,
           TIMESTAMPDIFF(MINUTE, started_at, ended_at) AS time_diff
    FROM city_bike_trip_data
    WHERE started_at >= '2026-06-01'
      AND started_at <  '2026-06-14'
      AND TIMESTAMPDIFF(MINUTE, started_at, ended_at) BETWEEN 1 AND 24*60
),
numbered AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY rideable_type ORDER BY time_diff DESC) AS rn_high,
           ROW_NUMBER() OVER (PARTITION BY rideable_type ORDER BY time_diff ASC)  AS rn_low
    FROM ride_details
)
SELECT CASE WHEN rn_high = 1 THEN 'longest' ELSE 'shortest' END AS extreme,
       rideable_type,
       start_station_name,
       end_station_name,
       started_at,
       ended_at,
       time_diff
FROM numbered
WHERE rn_high = 1 OR rn_low = 1
ORDER BY rideable_type, extreme;
 
 
-- 7. For each of the top 20 stations, what is its single busiest hour of the day?
WITH hourly_counts AS (
    SELECT start_station_name AS station,
           HOUR(started_at)   AS hour_of_day,
           COUNT(*)           AS trips
    FROM city_bike_trip_data
    WHERE started_at >= '2026-06-01'
      AND started_at <  '2026-06-14'
      AND start_station_name <> ''
    GROUP BY station, hour_of_day
),
with_totals AS (
    SELECT *,
           SUM(trips) OVER (PARTITION BY station)  AS total_trips,
           ROW_NUMBER() OVER (PARTITION BY station ORDER BY trips DESC) AS rn
    FROM hourly_counts
)
SELECT station,
       hour_of_day AS busiest_hour,
       trips       AS trips_in_hour,
       total_trips
FROM with_totals
WHERE rn = 1
ORDER BY total_trips DESC
LIMIT 20;
 
 
-- 8. For each start station, what are its top 3 destination stations?
WITH station_details AS (
    SELECT start_station_name AS station,
           end_station_name   AS destination,
           COUNT(*)           AS trips
    FROM city_bike_trip_data
    WHERE started_at >= '2026-06-01'
      AND started_at <  '2026-06-14'
      AND start_station_name <> ''
      AND end_station_name   <> ''
    GROUP BY station, destination
),
details AS (
    SELECT *,
           SUM(trips) OVER (PARTITION BY station)                     AS total_trips,
           RANK()     OVER (PARTITION BY station ORDER BY trips DESC) AS rn
    FROM station_details
)
SELECT station,
       rn,
       destination,
       trips,
       total_trips,
       CASE WHEN station = destination THEN 'round trip' ELSE '' END AS note
FROM details
WHERE rn <= 3
ORDER BY total_trips DESC, station, rn;
 
-- 9. What's the cumulative number of trips, day by day?
WITH daily AS (
    SELECT DATE(started_at) AS day,
           COUNT(*)         AS trips
    FROM city_bike_trip_data
    WHERE started_at >= '2026-06-01'
      AND started_at <  '2026-06-14'
    GROUP BY day
),
cumulative_table AS (
    SELECT *,
           SUM(trips) OVER (ORDER BY day) AS cumulative
    FROM daily
)
SELECT day, trips, cumulative
FROM cumulative_table
ORDER BY day;
 
 
-- 10. What's the 7-day rolling average of daily trips?
WITH daily AS (
    SELECT DATE(started_at) AS day,
           COUNT(*)         AS trips
    FROM city_bike_trip_data
    WHERE started_at >= '2026-06-01'
      AND started_at <  '2026-06-14'
    GROUP BY day
),
calc AS (
    SELECT *,
           ROUND(AVG(trips) OVER (
               ORDER BY day
               ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
           ), 1) AS rolling_7day,
           COUNT(*) OVER (
               ORDER BY day
               ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
           ) AS days_in_window
    FROM daily
)
SELECT day, trips, rolling_7day, days_in_window
FROM calc
ORDER BY day;
 
 
-- 11. Week over week, which stations grew fastest?
WITH weekly_details AS (
    SELECT start_station_name              AS station,
           YEARWEEK(started_at, 3)         AS week,
           MIN(DATE(started_at))           AS week_start,
           COUNT(DISTINCT DATE(started_at)) AS days_in_week,
           COUNT(*)                        AS trips
    FROM city_bike_trip_data
    WHERE started_at >= '2026-06-01'
      AND started_at <  '2026-06-14'
      AND start_station_name <> ''
    GROUP BY station, week
),
rates AS (
    SELECT *,
           trips / days_in_week AS trips_per_day
    FROM weekly_details
),
calc AS (
    SELECT *,
           LAG(trips)         OVER (PARTITION BY station ORDER BY week) AS prev_trips,
           LAG(trips_per_day) OVER (PARTITION BY station ORDER BY week) AS prev_rate
    FROM rates
)
SELECT week_start,
       station,
       prev_trips,
       trips,
       ROUND(prev_rate, 1)     AS prev_trips_per_day,
       ROUND(trips_per_day, 1) AS trips_per_day,
       ROUND(100 * (trips_per_day - prev_rate) / prev_rate, 1) AS pct_growth
FROM calc
WHERE prev_trips >= 100 
ORDER BY pct_growth DESC
LIMIT 20;

-- 12. Which stations have the biggest imbalance between departures and arrivals?
-- 13. What are the ten most common station-to-station routes, and what fraction of trips are round trips?
-- What's the median trip duration, and the 90th percentile? How do those compare to the mean, and what does the difference tell you?
-- Do casual riders take longer trips at weekends than on weekdays — and does that gap hold for members too?