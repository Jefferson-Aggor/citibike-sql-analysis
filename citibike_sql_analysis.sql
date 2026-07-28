SELECT *
FROM city_bike_trip_data 
LIMIT 5
;
-- 1. How many trips are in the table, and what date range do they cover? 
SELECT rideable_type, 
COUNT(*) AS trips, 
MIN(started_at) AS first_trip, 
MAX(ended_at) AS last_trip
FROM city_bike_trip_data
GROUP BY rideable_type WITH ROLLUP
;

-- 2. What share of all trips does each bike type account for, and how does that share differ between members and casual riders?
SELECT rideable_type, member_casual,
COUNT(*) AS trips,
ROUND((COUNT(*) / SUM(COUNT(*)) OVER())*100, 2) AS share_pct,
ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY member_casual), 2) AS pct_within_rider
FROM city_bike_trip_data
GROUP BY rideable_type, member_casual
;

-- 3. What are the ten busiest start stations, and the ten busiest end stations?
SELECT start_station_name,
COUNT(*) AS counts
FROM city_bike_trip_data
GROUP BY start_station_name
ORDER BY counts DESC
LIMIT 10
; 

SELECT end_station_name,
COUNT(*) AS counts
FROM city_bike_trip_data
GROUP BY end_station_name
ORDER BY counts DESC
LIMIT 10
; 

-- 4. What's the average trip duration by hour of day?
SELECT HOUR(started_at) AS hour_of_day, 
COUNT(*) AS trips, 
ROUND(AVG(TIMESTAMPDIFF(MINUTE, started_at, ended_at)), 1) AS avg_duration_min
FROM city_bike_trip_data
WHERE TIMESTAMPDIFF(MINUTE, started_at, ended_at) BETWEEN 1 AND 240 
GROUP BY hour_of_day
ORDER BY hour_of_day;

-- 5. How does trip volume differ on weekdays vs weekends, split by member type?
SELECT 
CASE WHEN DAYOFWEEK(started_at) IN (1, 7) THEN 'weekend' ELSE 'weekday' END AS day_type,
member_casual,
COUNT(*) AS trips,
COUNT(DISTINCT DATE(started_at)) as days,
ROUND(COUNT(*) / COUNT(DISTINCT DATE(started_at)),1) AS trips_per_day,
ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY member_casual), 1) AS pct_of_rider_trips
FROM city_bike_trip_data
GROUP BY day_type, member_casual
ORDER BY day_type, member_casual;

-- 6. For each bike type, what are the longest and shortest trips — including the stations, the timestamps, and the duration?





