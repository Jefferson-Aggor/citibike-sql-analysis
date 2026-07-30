# Citi Bike Trip Data — SQL Analysis

An exploratory analysis of Citi Bike trip records in MySQL 8, written to practise aggregation,
window functions and CTEs against a dataset large and messy enough to punish careless queries.

The questions were written **before** exploring the data, then answered in SQL.

---

## Dataset

|                 |                                              |
| --------------- | -------------------------------------------- |
| Source          | Citi Bike System Data — monthly trip history |
| File            | `202606-citibike-tripdata_1.csv`             |
| Rows loaded     | 1,000,000                                    |
| Raw coverage    | 31 May – 14 June 2026                        |
| Analysis window | 1 – 13 June 2026                             |
| Columns         | 13                                           |
| Database        | MySQL 8.0                                    |

**This is a partial month.** Citi Bike splits its monthly exports by row count rather than by date,
and only the first file is loaded here — exactly one million rows, stopping mid-June. Absolute
counts throughout are a subset of June's real traffic. Every result below describes the first two
weeks of June, not the month.

One row per trip: ride ID, bike type, start and end timestamps, start and end station (name and
ID), start and end coordinates, and whether the rider was a member or a casual user.

---

## Setup

Schema written by hand rather than through an import wizard, so that every column type was a
deliberate choice:

```sql
CREATE TABLE city_bike_trip_data (
    ride_id            CHAR(16) CHARACTER SET ascii NOT NULL,
    rideable_type      VARCHAR(20) NOT NULL,
    started_at         DATETIME,
    ended_at           DATETIME,
    start_station_name VARCHAR(120),
    start_station_id   VARCHAR(20),
    end_station_name   VARCHAR(120),
    end_station_id     VARCHAR(20),
    start_lat          DOUBLE,
    start_lng          DOUBLE,
    end_lat            DOUBLE,
    end_lng            DOUBLE,
    member_casual      VARCHAR(20)
);
```

### Type decisions

- **`ride_id CHAR(16)`** — fixed-length hexadecimal, so `CHAR` rather than `VARCHAR`. It looks
  numeric in places but contains letters, so an integer type would be wrong.
- **Station IDs as `VARCHAR`, not numeric** — values include `6432.05` and alphanumeric codes such
  as `HB102` for the Hoboken and Jersey City stations. A numeric type silently mangles these.
- **Coordinates as `DOUBLE`, not `FLOAT`** — `FLOAT` carries roughly 7 significant digits and a
  latitude such as `40.7128` already uses six, leaving metre-scale error or worse.
- **`NOT NULL` used sparingly** — station names and end coordinates are genuinely absent for some
  trips, so constraining them would reject valid rows.

### Loading

Line terminators are `\n`, not `\r\n`, despite the file being downloaded on Windows — Citi Bike
generates these on Linux. Loading with `LINES TERMINATED BY '\r\n'` produced **zero rows and no
error message**: the whole file was read as a single line, which `IGNORE 1 ROWS` then skipped.
Recorded because a load that reports no error is not a load that worked.

---

## Filtering conventions

Applied identically in all eleven queries, so results are comparable across questions.

**Date window: 1 – 14 June 2026.**

- 31 May is dropped. It belongs to the preceding ISO week and would appear as a one-day week in the growth question.

Written as `started_at >= '2026-06-01'` rather than `DATE(started_at) >= '2026-06-01'`. Wrapping the
column in a function prevents MySQL using the index on it — same result, considerably slower across
a million rows.

**Blank station names** (`''` rather than `NULL`, an artifact of the load) are excluded wherever
stations are grouped or ranked: `580` rows `(486 blank start stations and 94 blank end stations )`.

---

## Data quality

| Issue                                                  | Scale | Handling                        |
| ------------------------------------------------------ | ----- | ------------------------------- |
| Blank station names stored as `''`                     | `580` | Excluded from Q3, Q7, Q8, Q11   |
| Very long trips — read as bikes not re-docked          | `406` | Excluded from duration averages |
| Sub-minute trips — read as undock, find fault, re-dock | `0`   | Excluded from duration averages |

"Not re-docked" is an **interpretation**, not a field in the data. There is no flag distinguishing a
bike left out overnight from a genuinely long ride.

A missing end station name is a separate matter again: Citi Bike e-bikes may legitimately end a trip
outside a dock, so many of those rows are normal completed trips rather than abandoned bikes. The
two conditions overlap but are not the same set.

| ended           | length | trips  | percentage |
| --------------- | ------ | ------ | ---------- |
| has end station | long   | 392    | 0.04%      |
| has end station | normal | 999514 | 99.95%     |
| no end station  | long   | 14     | 0%         |
| no end station  | normal | 80     | 0.01%      |

### Dockless bikes parked legitimately — normal trips.

| no end station rows | but has coordinates | no coordinates |
| ------------------- | ------------------- | -------------- |
| 94                  | 94                  | 0              |

### Sub Minute Bikes that starts and ends at the same station

0

---

## Decisions

The choices with no correct answer, only a defensible one.

### Duration filter for averages: 1 – 300 minutes

- Under one minute is not a trip — a rider undocking a bike, finding a fault, and re-docking it.
- Beyond five hours, Citi Bike's pricing makes deliberate riding prohibitively expensive, so these
  are read as bikes never docked correctly.

Excludes `4%` of rows in the analysis window. Five hours is a
judgement call; 24 hours would be a defensible looser bound and 60 minutes a defensible tighter one.

### Duration filter for extremes: 1 – 1440 minutes

Q6 asks for the longest and shortest trips. A filter designed to protect an _average_ removes
exactly the rows an _extremes_ question is about — at a five-hour bound the answer would be pinned
at exactly 300 minutes, reporting the filter rather than the data. A 24-hour bound excludes obvious
data errors without capping the result.

Ties at the one-minute minimum are resolved arbitrarily by `ROW_NUMBER()`; `RANK()` would return all
of them.

### Minimum volume threshold for growth: 100 trips

Percentage growth on a small base is noise — a station going from 2 trips to 8 has grown 300% and
says nothing. Rows where the previous week saw fewer than 100 trips are excluded from Q11.

The threshold sits in the **outer query**, not as a `HAVING` in the aggregating CTE. Filtering
earlier would leave gaps in each station's weekly sequence, and `LAG()` would then compare
non-adjacent weeks as though they were consecutive.

### Round trips retained

A station's most common destination is frequently itself — a loop ride returning to the same dock.
Real behaviour, so it is kept in the Q8 results and flagged in a `note` column, since it is usually
not what "top destinations" is taken to mean.

### Weeks, and why growth is measured as a rate

ISO weeks via `YEARWEEK(started_at, 3)`: Monday start, with the year encoded so week numbers cannot
collide across years.

The analysis window holds two ISO weeks — **1–7 June (seven days) and 8–13 June (six days)**. Raw
counts would therefore show roughly a 14% decline for every station, caused entirely by the shorter
second week. Q11 normalises both weeks to trips per day before comparing, the same correction
applied in Q5.

This also means Q11 is a **single comparison per station**, not a trend.

### Incomplete rolling-average windows

The first six rows of Q10 average fewer than seven days, because
`ROWS BETWEEN 6 PRECEDING AND CURRENT ROW` uses whatever rows exist rather than returning `NULL`.
Those values climb steeply purely as the window fills, which looks like growth and is not. A
`days_in_window` column exposes this; with 13 days of data, only 7 rows carry a true 7-day average.

---

## Questions and findings

### Foundations

**1. How many trips, and what date range?**

`GROUP BY rideable_type WITH ROLLUP` gives per-type counts plus a grand-total row where
`rideable_type` is `NULL`. Both `MAX(started_at)` and `MAX(ended_at)` are reported — the first is
when trips stopped _beginning_, the second is inflated by any bike never re-docked.

Number of trips: `935409`
Date range: `From 2026-06-01 00:00:03 to 2026-06-14 20:44:16`

**2. Share of trips by bike type, and how it differs between members and casual riders**

Reported two ways: share of the grand total, and share _within_ each rider type via
`SUM(COUNT(*)) OVER (PARTITION BY member_casual)`. The second is the meaningful one — member and
casual volumes differ enough that share-of-total is dominated by the rider-type difference rather
than by any bike preference.

| rideable type | member_casual | trips  | share percentage | percentage within rider |
| ------------- | ------------- | ------ | ---------------- | ----------------------- |
| classic_bike  | casual        | 43116  | 4.61%            | 23.71%                  |
| electric_bike | casual        | 138699 | 14.83%           | 76.29%                  |
| classic_bike  | member        | 214921 | 22.98%           | 28.52%                  |
| electric_bike | member        | 538673 | 57.59%           | 71.48%                  |

**3. Ten busiest start stations, and ten busiest end stations**

| station                       | trips |
| ----------------------------- | ----- |
| Pier 61 at Chelsea Piers      | 3079  |
| W 21 St & 6 Ave               | 2953  |
| 9 Ave & W 33 St               | 2813  |
| Cooper Square & Astor Pl      | 2681  |
| 12 Ave & W 40 St              | 2560  |
| 11 Ave & W 41 St              | 2542  |
| 10 Ave & W 14 St              | 2529  |
| Washington St & Gansevoort St | 2427  |
| Cleveland Pl & Spring St      | 2384  |
| Broadway & W 25 St            | 2366  |

**4. Average trip duration by hour of day**

Trip count is reported alongside each average, because an average over a few thousand trips at 3am
is far weaker evidence than one over hundreds of thousands at 5pm, and the two are
indistinguishable without it.

| hour_of_day | trips | avg_duration_min |
| ----------- | ----- | ---------------- |
| 0           | 17708 | 13.3             |
| 1           | 8911  | 13.0             |
| 2           | 5107  | 13.0             |
| 3           | 3193  | 13.5             |
| 4           | 2930  | 12.5             |
| 5           | 6290  | 9.8              |
| 6           | 17631 | 9.6              |
| 7           | 36511 | 10.4             |
| 8           | 58527 | 11.1             |
| 9           | 46421 | 11.2             |
| 10          | 38357 | 12.1             |
| 11          | 40942 | 12.8             |
| 12          | 45539 | 12.7             |
| 13          | 48616 | 13.0             |
| 14          | 52306 | 12.9             |
| 15          | 57132 | 13.2             |
| 16          | 66244 | 13.2             |
| 17          | 87885 | 13.1             |
| 18          | 83729 | 12.9             |
| 19          | 66538 | 12.9             |
| 20          | 51549 | 12.9             |
| 21          | 34709 | 12.9             |
| 22          | 28432 | 13.0             |
| 23          | 29849 | 13.8             |

**5. Weekday vs weekend volume, split by member type**

Raw totals are not comparable — the window holds more weekdays than weekend days — so volume is
normalised to trips per day.

| day_type | member_casual | trips  | days | trips_per_day | pct_of_rider_trips |
| -------- | ------------- | ------ | ---- | ------------- | ------------------ |
| weekday  | casual        | 125571 | 10   | 12557.1       | 69.1               |
| weekday  | member        | 601974 | 10   | 60197.4       | 79.9               |
| weekend  | casual        | 56244  | 3    | 18748.0       | 30.9               |
| weekend  | member        | 151620 | 3    | 50540.0       | 20.1               |

### Window functions

**6. Longest and shortest trip per bike type, with stations and timestamps**

Two `ROW_NUMBER()` windows over the same partition with opposite orderings, computed in one pass,
then filtered to `rn_high = 1 OR rn_low = 1`.

| extreme  | rideable_type | start_station_name           | end_station_name     | started_at          | ended_at            | time_diff |
| -------- | ------------- | ---------------------------- | -------------------- | ------------------- | ------------------- | --------- |
| longest  | classic_bike  | 6 Ave & Broome St            | E 27 St & Park Ave S | 2026-06-12 15:21:06 | 2026-06-13 15:15:46 | 1434      |
| shortest | classic_bike  | Degraw St & Smith St         | Butler St & Court St | 2026-06-10 23:59:52 | 2026-06-11 00:01:33 | 1         |
| longest  | electric_bike | Bradley Ave & Greenpoint Ave |                      | 2026-06-02 17:03:09 | 2026-06-03 07:03:06 | 839       |
| shortest | electric_bike | Broadway & 12 St             | 21 St & 31 Dr        | 2026-06-04 16:50:33 | 2026-06-04 16:51:53 | 1         |

**7. Busiest hour for each of the top 20 stations**

"Top" is defined as **total departures**, because that is what the data supports. Departures plus
arrivals, or peak-hour volume, would each give a different list. Trips per dock is arguably the
truest measure of pressure on a station and cannot be computed — the dataset has no dock counts.

`LIMIT 20` is valid here only because `rn = 1` has already reduced the result to one row per
station; applied earlier it would have returned 20 station-hours.

| station                        | busiest_hour | trips_in_hour | total_trips |
| ------------------------------ | ------------ | ------------- | ----------- |
| Pier 61 at Chelsea Piers       | 18           | 388           | 3079        |
| W 21 St & 6 Ave                | 17           | 318           | 2953        |
| 9 Ave & W 33 St                | 17           | 465           | 2813        |
| Cooper Square & Astor Pl       | 18           | 262           | 2681        |
| 12 Ave & W 40 St               | 17           | 266           | 2560        |
| 11 Ave & W 41 St               | 18           | 273           | 2542        |
| 10 Ave & W 14 St               | 17           | 277           | 2529        |
| Washington St & Gansevoort St  | 17           | 246           | 2427        |
| Cleveland Pl & Spring St       | 18           | 255           | 2384        |
| Broadway & W 25 St             | 17           | 374           | 2366        |
| E 17 St & Broadway             | 17           | 239           | 2365        |
| Park Ave & E 42 St             | 17           | 358           | 2364        |
| N 7 St & Driggs Ave            | 18           | 246           | 2358        |
| Greenwich Ave & 8 Ave          | 18           | 226           | 2327        |
| University Pl & E 14 St        | 17           | 219           | 2318        |
| Broadway & E 14 St             | 18           | 243           | 2276        |
| Broadway & W 58 St             | 17           | 197           | 2273        |
| W 30 St & 10 Ave               | 17           | 236           | 2269        |
| W 31 St & 7 Ave                | 17           | 191           | 2263        |
| Metropolitan Ave & Bedford Ave | 19           | 214           | 2242        |

**8. Top 3 destinations for each start station**

Ranked with `RANK()` rather than `ROW_NUMBER()`, because routes tie at low counts often enough that
arbitrary tie-breaking would misrepresent the result — so some stations return more than three rows
where there is a tie at third place.

| station                       | rn  | destination                   | trips | total_trips | note       |
| ----------------------------- | --- | ----------------------------- | ----- | ----------- | ---------- |
| Pier 61 at Chelsea Piers      | 1   | Pier 40 - Hudson River Park   | 121   | 3079        |            |
| Pier 61 at Chelsea Piers      | 2   | 8 Ave & W 16 St               | 97    | 3079        |            |
| Pier 61 at Chelsea Piers      | 3   | North Moore St & Greenwich St | 84    | 3079        |            |
| W 21 St & 6 Ave               | 1   | W 22 St & 10 Ave              | 178   | 2953        |            |
| W 21 St & 6 Ave               | 2   | 10 Ave & W 28 St              | 113   | 2953        |            |
| W 21 St & 6 Ave               | 3   | W 20 St & 8 Ave               | 97    | 2953        |            |
| 9 Ave & W 33 St               | 1   | Hudson St & W 13 St           | 109   | 2813        |            |
| 9 Ave & W 33 St               | 2   | 11 Ave & W 41 St              | 105   | 2813        |            |
| 9 Ave & W 33 St               | 3   | W 24 St & 7 Ave               | 101   | 2813        |            |
| Cooper Square & Astor Pl      | 1   | 1 Ave & E 6 St                | 144   | 2681        |            |
| Cooper Square & Astor Pl      | 2   | E 17 St & Broadway            | 82    | 2681        |            |
| Cooper Square & Astor Pl      | 3   | E 6 St & Ave B                | 80    | 2681        |            |
| 12 Ave & W 40 St              | 1   | Pier 40 - Hudson River Park   | 148   | 2560        |            |
| 12 Ave & W 40 St              | 2   | 10 Ave & W 14 St              | 139   | 2560        |            |
| 12 Ave & W 40 St              | 3   | West St & Liberty St          | 70    | 2560        |            |
| 11 Ave & W 41 St              | 1   | W 42 St & 8 Ave               | 179   | 2542        |            |
| 11 Ave & W 41 St              | 2   | W 34 St & 11 Ave              | 152   | 2542        |            |
| 11 Ave & W 41 St              | 3   | 11 Ave & W 41 St              | 111   | 2542        | round trip |
| 10 Ave & W 14 St              | 1   | 10 Ave & W 14 St              | 124   | 2529        | round trip |
| 10 Ave & W 14 St              | 2   | Pier 40 - Hudson River Park   | 79    | 2529        |            |
| 10 Ave & W 14 St              | 3   | 11 Ave & W 41 St              | 67    | 2529        |            |
| Washington St & Gansevoort St | 1   | Greenwich Ave & 8 Ave         | 100   | 2426        |            |
| Washington St & Gansevoort St | 2   | Morton St & Greenwich St      | 91    | 2426        |            |
| Washington St & Gansevoort St | 3   | Washington St & Gansevoort St | 75    | 2426        | round trip |

### Ordered windows

**9. Cumulative trips, day by day**

`SUM(trips) OVER (ORDER BY day)` with no explicit frame, so MySQL applies its default,
`ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW`. Verified by checking the final cumulative value
against `COUNT(*)` over the same window.

| day        | trips | cumulative |
| ---------- | ----- | ---------- |
| 2026-06-01 | 62401 | 62401      |
| 2026-06-02 | 71103 | 133504     |
| 2026-06-03 | 77814 | 211318     |
| 2026-06-04 | 74493 | 285811     |
| 2026-06-05 | 76958 | 362769     |
| 2026-06-06 | 65538 | 428307     |
| 2026-06-07 | 64899 | 493206     |
| 2026-06-08 | 74206 | 567412     |
| 2026-06-09 | 74256 | 641668     |
| 2026-06-10 | 75755 | 717423     |
| 2026-06-11 | 74096 | 791519     |
| 2026-06-12 | 66463 | 857982     |
| 2026-06-13 | 77427 | 935409     |

**10. 7-day rolling average of daily trips**

Seven days because any 7-day span contains exactly one of each weekday, so the weekly cycle cancels
out entirely. A 5-day window would wobble depending on how many weekend days it happened to catch.

| day        | trips | rolling_7day | days_in_window |
| ---------- | ----- | ------------ | -------------- |
| 2026-06-01 | 62401 | 62401.0      | 1              |
| 2026-06-02 | 71103 | 66752.0      | 2              |
| 2026-06-03 | 77814 | 70439.3      | 3              |
| 2026-06-04 | 74493 | 71452.8      | 4              |
| 2026-06-05 | 76958 | 72553.8      | 5              |
| 2026-06-06 | 65538 | 71384.5      | 6              |
| 2026-06-07 | 64899 | 70458.0      | 7              |
| 2026-06-08 | 74206 | 72144.4      | 7              |
| 2026-06-09 | 74256 | 72594.9      | 7              |
| 2026-06-10 | 75755 | 72300.7      | 7              |
| 2026-06-11 | 74096 | 72244.0      | 7              |
| 2026-06-12 | 66463 | 70744.7      | 7              |
| 2026-06-13 | 77427 | 72443.1      | 7              |

**11. Week over week, which stations grew fastest**

`LAG(trips_per_day) OVER (PARTITION BY station ORDER BY week)` carries the previous week's rate onto
each row, so growth becomes arithmetic across columns of a single row. The partition keeps each
station's history separate; ordering by week rather than by volume is what makes "previous" mean
earlier in time.

| week_start | station                     | prev_trips | trips | prev_trips_per_day | trips_per_day | pct_growth |
| ---------- | --------------------------- | ---------- | ----- | ------------------ | ------------- | ---------- |
| 2026-06-08 | E 72 St & Park Ave          | 307        | 430   | 43.9               | 71.7          | 63.4       |
| 2026-06-08 | E 51 St & 2 Ave             | 189        | 370   | 37.8               | 61.7          | 63.1       |
| 2026-06-08 | Broadway & W 36 St          | 326        | 440   | 46.6               | 73.3          | 57.5       |
| 2026-06-08 | W 47 St & 6 Ave             | 371        | 495   | 53.0               | 82.5          | 55.7       |
| 2026-06-08 | Degraw St & Hoyt St         | 190        | 248   | 27.1               | 41.3          | 52.3       |
| 2026-06-08 | E 46 St & Madison Ave       | 417        | 447   | 59.6               | 89.4          | 50.1       |
| 2026-06-08 | Central Park W & W 97 St    | 359        | 460   | 51.3               | 76.7          | 49.5       |
| 2026-06-08 | 5 St & 6 Ave                | 181        | 232   | 25.9               | 38.7          | 49.5       |
| 2026-06-08 | E 115 St & Madison Ave      | 115        | 147   | 16.4               | 24.5          | 49.1       |
| 2026-06-08 | Irving Ave & Halsey St      | 111        | 140   | 15.9               | 23.3          | 47.1       |
| 2026-06-08 | 36 St & 3 Ave               | 104        | 131   | 14.9               | 21.8          | 47.0       |
| 2026-06-08 | Maple St & Flatbush Ave     | 112        | 139   | 16.0               | 23.2          | 44.8       |
| 2026-06-08 | 36 St & 4 Ave               | 136        | 168   | 19.4               | 28.0          | 44.1       |
| 2026-06-08 | 8 Ave & W 27 St             | 485        | 593   | 69.3               | 98.8          | 42.6       |
| 2026-06-08 | Madison Ave & E 120 St      | 117        | 140   | 16.7               | 23.3          | 39.6       |
| 2026-06-08 | Herkimer St & New York Ave  | 116        | 138   | 16.6               | 23.0          | 38.8       |
| 2026-06-08 | W 51 St & Rockefeller Plaza | 191        | 221   | 31.8               | 44.2          | 38.8       |
| 2026-06-08 | E 45 St & 3 Ave             | 227        | 269   | 32.4               | 44.8          | 38.3       |
| 2026-06-08 | E 43 St & Madison Ave       | 746        | 737   | 106.6              | 147.4         | 38.3       |
| 2026-06-08 | E 33 St & 5 Ave             | 550        | 651   | 78.6               | 108.5         | 38.1       |

### Not yet answered

12. Stations with the biggest imbalance between departures and arrivals
13. Ten most common station-to-station routes, and the share that are round trips
14. Median and 90th-percentile trip duration, against the mean
15. Do casual riders take longer trips at weekends than on weekdays, and does the gap hold for
    members too?

### Questions the data could not answer

Two questions written before exploring the data proved unanswerable, recorded here because finding
out is part of the exercise:

- **Rank stations by volume within each district** — there is no district or borough column. Only
  coordinates and station names are available, and assigning a borough to a coordinate needs a
  geographic boundary file that is not part of this dataset.
- **Month-over-month station growth** — a single partial month is loaded, so there is no prior
  period. Substituted with the week-over-week question above.

---

## Repository

```
setup.sql        Database, table definition and LOAD DATA statement
analysis.sql     Diagnostics D1-D7, then Q1-Q11
questions.md     The fifteen questions, as written before exploring the data
README.md
```

`setup.sql` drops and recreates the database — read it before running it.

CSV files are excluded via `.gitignore`; the source file exceeds GitHub's 100 MB limit. Download it
from Citi Bike System Data and load it with `setup.sql`.

---

## Reflection

The difficult part of this project was not syntax. Every substantive error was the query answering a
different question than intended:

- grouping by trip _duration_ when the question asked for hour of _day_
- comparing raw weekday and weekend totals across unequal numbers of days
- capping the maximum with a filter designed to protect the mean
- partitioning by destination when the question was about origins
- ranking ascending when the question asked which was busiest
- writing `WHERE a AND b <> ''`, which parses as `WHERE a AND (b <> '')` and, because MySQL coerces
  a non-numeric string to 0, silently keeps only stations whose names begin with a digit

None of these produce an error message. All produce plausible-looking output. The habit that catches
them is checking the _shape_ of the result before reading the numbers: Q4 must return exactly 24
rows, Q7 exactly 20, and anything else means a different question was answered.

A later pass found a second class of problem — filters applied in some queries but not others, so
results were not comparable across questions. Fixing that meant settling one convention and applying
it everywhere, which is why the filtering conventions are stated above rather than left implicit in
each query.

## Next

- Load the remaining split files, giving a full month, complete ISO weeks, and a real month-over-
  month comparison
- Normalise stations into a separate table and join, rather than repeating names across a million
  rows
- Q12-Q15
