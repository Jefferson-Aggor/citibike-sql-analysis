DROP DATABASE IF EXISTS `City_bike_trip_data`;
CREATE DATABASE `City_bike_trip_data`;
USE `City_bike_trip_data`;

SET GLOBAL local_infile = 1;

CREATE TABLE city_bike_trip_data(
ride_id CHAR(16) CHARACTER SET ascii NOT NULL,
rideable_type VARCHAR(20) NOT NULL,
started_at DATETIME,
ended_at DATETIME,
start_station_name VARCHAR(120),
start_station_id VARCHAR(20),
end_station_name VARCHAR(120),
end_station_id VARCHAR(20),
start_lat DOUBLE,
start_lng DOUBLE ,
end_lat DOUBLE,
end_lng DOUBLE,
member_casual VARCHAR(20)
);

LOAD DATA LOCAL INFILE 'C:/Users/Jefferson/Downloads/202606-citibike-tripdata/202606-citibike-tripdata_1.csv'
INTO TABLE city_bike_trip_data
FIELDS TERMINATED BY ',' ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;