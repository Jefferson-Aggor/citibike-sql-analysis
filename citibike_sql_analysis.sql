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

SELECT *
FROM city_bike_trip_data 
LIMIT 5
;

-- 6. For each bike type, what are the longest and shortest trips — including the stations,
-- the timestamps, and the duration?
WITH ride_details AS (
SELECT rideable_type, 
	start_station_name,
	end_station_name, 
	started_at,
	ended_at,
    TIMESTAMPDIFF(minute, started_at, ended_at) AS time_diff
FROM city_bike_trip_data
WHERE TIMESTAMPDIFF(minute, started_at, ended_at) BETWEEN 1 AND 5*60
), 

numbered AS (
SELECT *,
	ROW_NUMBER() OVER(PARTITION BY rideable_type ORDER BY TIMESTAMPDIFF(minute, started_at, ended_at) DESC) AS rn_high,
    ROW_NUMBER() OVER(PARTITION BY rideable_type ORDER BY TIMESTAMPDIFF(minute, started_at, ended_at) ASC) AS rn_low
    
    FROM ride_details
)

SELECT 
CASE 
	WHEN rn_high = 1 THEN 'longest' 
    ELSE 'shortest'
END AS duration,
	rideable_type, 
	start_station_name,
	end_station_name, 
	started_at,
	ended_at,
    TIMESTAMPDIFF(minute, started_at, ended_at) AS time_diff
FROM numbered
WHERE rn_high = 1 OR rn_low = 1
ORDER BY duration
;

-- 7. For each of the top 20 stations, what is its single busiest hour of the day?
WITH hourly_counts AS (
    SELECT start_station_name AS station,
           HOUR(started_at)   AS hour_of_day,
           COUNT(*)           AS trips
    FROM city_bike_trip_data
    WHERE start_station_name != ''
    GROUP BY station, hour_of_day
),
with_totals AS (
    SELECT *,
           SUM(trips) OVER (PARTITION BY station) AS total_trips,
           ROW_NUMBER() OVER (PARTITION BY station ORDER BY trips DESC) AS rn
    FROM hourly_counts
)
SELECT station,
       hour_of_day AS busiest_hour,
       trips       AS trips_in_hour,
       total_trips,
       rn
FROM with_totals
WHERE rn = 1
ORDER BY total_trips DESC
LIMIT 20; 

-- 8. For each start station, what are its top 3 destination stations?
WITH station_details AS (
SELECT 
	start_station_name AS station,
    end_station_name AS destination,
	COUNT(*) AS trips
    FROM city_bike_trip_data
    WHERE start_station_name != '' AND end_station_name != ''
    GROUP BY start_station_name, end_station_name
),
	details AS (
    SELECT *,
    SUM(trips) OVER(PARTITION BY station) as total_trips,
    RANK() OVER(PARTITION BY station ORDER BY trips DESC) as rn
    FROM station_details
    )
    
    SELECT station, destination, trips, total_trips
    FROM details
    WHERE rn <=3
    ORDER BY total_trips DESC, station, rn;


-- 9. What's the cumulative number of trips across the month, day by day?
-- 10. What's the 7-day rolling average of daily trips?
-- 11. Week over week, which stations grew fastest?
-- 12. Which stations have the biggest imbalance between departures and arrivals?
-- 13. What are the ten most common station-to-station routes, and what fraction of trips are round trips?
-- What's the median trip duration, and the 90th percentile? How do those compare to the mean, and what does the difference tell you?
-- Do casual riders take longer trips at weekends than on weekdays — and does that gap hold for members too?