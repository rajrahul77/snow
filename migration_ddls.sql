-- ============================================================
-- Cost Analytics Dashboard - View DDLs for Migration
-- Source: ECOMMERCE_DEV.COST_ANALYTICS
-- Generated: 2026-08-25
-- Total Objects: 43 (42 Views + 1 Table)
-- ============================================================
-- IMPORTANT: Before running, create the target database/schema:
--   CREATE DATABASE IF NOT EXISTS <TARGET_DB>;
--   CREATE SCHEMA IF NOT EXISTS <TARGET_DB>.COST_ANALYTICS;
--   USE SCHEMA <TARGET_DB>.COST_ANALYTICS;
-- ============================================================

-- ============================================================
-- Table: ML_SPEND_FORECAST
-- ============================================================
create or replace TABLE ML_SPEND_FORECAST (
	FORECAST_DATE TIMESTAMP_NTZ(9),
	PREDICTED_CREDITS FLOAT,
	OPTIMISTIC_SPEND FLOAT,
	PESSIMISTIC_SPEND FLOAT
);

-- ============================================================
-- View: VW_ACTIVE_RESOURCES
-- ============================================================
create or replace view VW_ACTIVE_RESOURCES(
	RESOURCE_NAME,
	RESOURCE_TYPE,
	CREDITS_7D,
	QUERIES_7D,
	LAST_USED,
	LAST_QUERY_TIME,
	HOURS_SINCE_LAST_USE,
	STATUS_RECOMMENDATION
) as
WITH wh_usage AS (
    SELECT warehouse_name,
        MAX(end_time) AS last_used,
        ROUND(SUM(credits_used), 4) AS credits_7d
    FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
    WHERE start_time >= DATEADD(DAY, -7, CURRENT_DATE())
    GROUP BY warehouse_name
),
wh_queries AS (
    SELECT warehouse_name,
        COUNT(*) AS queries_7d,
        MAX(start_time) AS last_query_time
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
    WHERE start_time >= DATEADD(DAY, -7, CURRENT_DATE())
        AND warehouse_name IS NOT NULL
    GROUP BY warehouse_name
)
SELECT 
    u.warehouse_name AS resource_name,
    'WAREHOUSE' AS resource_type,
    u.credits_7d,
    COALESCE(q.queries_7d, 0) AS queries_7d,
    u.last_used,
    q.last_query_time,
    DATEDIFF('hour', COALESCE(q.last_query_time, u.last_used), CURRENT_TIMESTAMP()) AS hours_since_last_use,
    CASE 
        WHEN COALESCE(q.queries_7d, 0) = 0 THEN 'UNUSED - Candidate for suspension'
        WHEN DATEDIFF('hour', q.last_query_time, CURRENT_TIMESTAMP()) > 48 THEN 'IDLE 48h+ - Review needed'
        ELSE 'ACTIVE'
    END AS status_recommendation
FROM wh_usage u
LEFT JOIN wh_queries q ON u.warehouse_name = q.warehouse_name;

-- ============================================================
-- View: VW_BUDGET_BURNDOWN
-- ============================================================
create or replace view VW_BUDGET_BURNDOWN(
	USAGE_DATE,
	DAILY_CREDITS,
	MTD_CREDITS,
	DAY_NUMBER,
	DAYS_IN_MONTH,
	DAYS_REMAINING,
	AVG_DAILY_RATE,
	PROJECTED_EOM
) as
WITH daily_spend AS (
    SELECT 
        DATE_TRUNC('day', start_time)::DATE AS usage_date,
        SUM(credits_used) AS daily_credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
    WHERE start_time >= DATE_TRUNC('month', CURRENT_DATE())
    GROUP BY 1
),
running AS (
    SELECT 
        usage_date,
        ROUND(daily_credits, 2) AS daily_credits,
        ROUND(SUM(daily_credits) OVER (ORDER BY usage_date), 2) AS mtd_credits,
        ROW_NUMBER() OVER (ORDER BY usage_date) AS day_number
    FROM daily_spend
)
SELECT 
    usage_date,
    daily_credits,
    mtd_credits,
    day_number,
    DAY(LAST_DAY(CURRENT_DATE())) AS days_in_month,
    DAY(LAST_DAY(CURRENT_DATE())) - day_number AS days_remaining,
    ROUND(mtd_credits / NULLIF(day_number, 0), 4) AS avg_daily_rate,
    ROUND(mtd_credits / NULLIF(day_number, 0) * DAY(LAST_DAY(CURRENT_DATE())), 2) AS projected_eom
FROM running;

-- ============================================================
-- View: VW_BUDGET_BURN_RATE
-- ============================================================
create or replace view VW_BUDGET_BURN_RATE(
	USAGE_DATE,
	DAILY_CREDITS,
	MTD_CREDITS,
	DAYS_ELAPSED,
	DAYS_IN_MONTH,
	PROJECTED_EOM_CREDITS
) as
WITH daily_spend AS (
    SELECT DATE_TRUNC('day', start_time)::DATE AS usage_date,
        SUM(credits_used) AS daily_credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
    WHERE start_time >= DATE_TRUNC('month', CURRENT_DATE())
    GROUP BY 1
)
SELECT
    usage_date,
    ROUND(daily_credits, 2) AS daily_credits,
    ROUND(SUM(daily_credits) OVER (ORDER BY usage_date), 2) AS mtd_credits,
    DAYOFMONTH(CURRENT_DATE()) AS days_elapsed,
    DAY(LAST_DAY(CURRENT_DATE())) AS days_in_month,
    ROUND(SUM(daily_credits) OVER (ORDER BY usage_date) / DAYOFMONTH(usage_date) * DAY(LAST_DAY(CURRENT_DATE())), 2) AS projected_eom_credits
FROM daily_spend;

-- ============================================================
-- View: VW_CLUSTERING_COSTS
-- ============================================================
create or replace view VW_CLUSTERING_COSTS(
	DATABASE_NAME,
	SCHEMA_NAME,
	TABLE_NAME,
	USAGE_DATE,
	CLUSTERING_CREDITS,
	GB_RECLUSTERED
) as
SELECT
    database_name,
    schema_name,
    table_name,
    DATE_TRUNC('day', start_time)::DATE AS usage_date,
    ROUND(SUM(credits_used), 4) AS clustering_credits,
    SUM(num_bytes_reclustered) / (1024*1024*1024) AS gb_reclustered
FROM SNOWFLAKE.ACCOUNT_USAGE.AUTOMATIC_CLUSTERING_HISTORY
WHERE start_time >= DATEADD(DAY, -90, CURRENT_DATE())
GROUP BY database_name, schema_name, table_name, DATE_TRUNC('day', start_time);

-- ============================================================
-- View: VW_CONCURRENCY
-- ============================================================
create or replace view VW_CONCURRENCY(
	HOUR_SLOT,
	WAREHOUSE_NAME,
	QUERIES_IN_HOUR,
	UNIQUE_USERS,
	AVG_QUERY_SEC,
	QUEUED_COUNT
) as
SELECT
    DATE_TRUNC('hour', start_time) AS hour_slot,
    warehouse_name,
    COUNT(*) AS queries_in_hour,
    COUNT(DISTINCT user_name) AS unique_users,
    ROUND(AVG(total_elapsed_time) / 1000, 2) AS avg_query_sec,
    SUM(CASE WHEN queued_overload_time > 0 THEN 1 ELSE 0 END) AS queued_count
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(DAY, -14, CURRENT_DATE())
    AND warehouse_name IS NOT NULL
GROUP BY DATE_TRUNC('hour', start_time), warehouse_name;

-- ============================================================
-- View: VW_CONTAINER_COSTS
-- ============================================================
create or replace view VW_CONTAINER_COSTS(
	COMPUTE_POOL_NAME,
	APPLICATION_NAME,
	USAGE_DATE,
	TOTAL_CREDITS,
	USAGE_HOURS,
	AVG_CREDITS_PER_HOUR
) as
SELECT
    compute_pool_name,
    application_name,
    DATE_TRUNC('day', start_time)::DATE AS usage_date,
    ROUND(SUM(credits_used), 2) AS total_credits,
    COUNT(*) AS usage_hours,
    ROUND(AVG(credits_used), 4) AS avg_credits_per_hour
FROM SNOWFLAKE.ACCOUNT_USAGE.SNOWPARK_CONTAINER_SERVICES_HISTORY
WHERE start_time >= DATEADD(DAY, -90, CURRENT_DATE())
GROUP BY compute_pool_name, application_name, DATE_TRUNC('day', start_time);

-- ============================================================
-- View: VW_CORTEX_AI_USAGE
-- ============================================================
create or replace view VW_CORTEX_AI_USAGE(
	USAGE_DATE,
	SERVICE_TYPE,
	CREDITS_USED,
	CREDITS_BILLED,
	COMPUTE_CREDITS,
	CLOUD_SERVICES_CREDITS
) as
WITH ai_metering AS (
    SELECT
        SERVICE_TYPE,
        TRY_TO_DATE(REPLACE(USAGE_DATE, '"', '')) AS USAGE_DATE,
        CREDITS_USED_COMPUTE,
        CREDITS_USED_CLOUD_SERVICES,
        CREDITS_USED,
        CREDITS_BILLED
    FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
    WHERE SERVICE_TYPE IN (
        'AI_FUNCTIONS', 'AI_INFERENCE', 'AI_SERVICES',
        'CORTEX_AGENTS', 'CORTEX_CODE_SNOWSIGHT', 'CORTEX_SEARCH',
        'SNOWPARK_CONTAINER_SERVICES'
    )
)
SELECT
    USAGE_DATE,
    SERVICE_TYPE,
    ROUND(CREDITS_USED, 6)                  AS CREDITS_USED,
    ROUND(CREDITS_BILLED, 6)                AS CREDITS_BILLED,
    ROUND(CREDITS_USED_COMPUTE, 6)          AS COMPUTE_CREDITS,
    ROUND(CREDITS_USED_CLOUD_SERVICES, 6)   AS CLOUD_SERVICES_CREDITS
FROM ai_metering
WHERE USAGE_DATE IS NOT NULL
ORDER BY USAGE_DATE DESC, CREDITS_USED DESC;

-- ============================================================
-- View: VW_CORTEX_MODEL_USAGE
-- ============================================================
create or replace view VW_CORTEX_MODEL_USAGE(
	USAGE_DATE,
	FUNCTION_NAME,
	MODEL_NAME,
	INVOCATIONS,
	TOTAL_INPUT_TOKENS,
	TOTAL_OUTPUT_TOKENS,
	TOTAL_BULK_TOKENS,
	TOTAL_TOKENS,
	TOTAL_CREDITS,
	AVG_CREDITS_PER_CALL,
	AVG_TOKENS_PER_CALL
) as
WITH flattened AS (
    SELECT
        h.START_TIME::DATE                        AS USAGE_DATE,
        h.FUNCTION_NAME,
        COALESCE(h.MODEL_NAME, 'N/A')            AS MODEL_NAME,
        h.CREDITS,
        f.value:key:metric::STRING                AS METRIC_TYPE,
        TRY_TO_NUMBER(f.value:value::STRING)      AS TOKEN_VALUE
    FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AI_FUNCTIONS_USAGE_HISTORY h,
         LATERAL FLATTEN(INPUT => h.METRICS) f
    WHERE h.IS_COMPLETED = TRUE
),
per_call AS (
    SELECT
        USAGE_DATE,
        FUNCTION_NAME,
        MODEL_NAME,
        CREDITS,
        SUM(CASE WHEN METRIC_TYPE = 'input'  THEN TOKEN_VALUE ELSE 0 END) AS INPUT_TOKENS,
        SUM(CASE WHEN METRIC_TYPE = 'output' THEN TOKEN_VALUE ELSE 0 END) AS OUTPUT_TOKENS,
        SUM(CASE WHEN METRIC_TYPE = 'total'  THEN TOKEN_VALUE ELSE 0 END) AS BULK_TOKENS
    FROM flattened
    GROUP BY 1, 2, 3, 4
)
SELECT
    USAGE_DATE,
    FUNCTION_NAME,
    MODEL_NAME,
    COUNT(*)                                    AS INVOCATIONS,
    SUM(INPUT_TOKENS)                           AS TOTAL_INPUT_TOKENS,
    SUM(OUTPUT_TOKENS)                          AS TOTAL_OUTPUT_TOKENS,
    SUM(BULK_TOKENS)                            AS TOTAL_BULK_TOKENS,
    SUM(INPUT_TOKENS + OUTPUT_TOKENS + BULK_TOKENS) AS TOTAL_TOKENS,
    ROUND(SUM(CREDITS), 6)                      AS TOTAL_CREDITS,
    ROUND(SUM(CREDITS) / NULLIF(COUNT(*), 0), 8) AS AVG_CREDITS_PER_CALL,
    ROUND(SUM(INPUT_TOKENS + OUTPUT_TOKENS + BULK_TOKENS) / NULLIF(COUNT(*), 0), 0) AS AVG_TOKENS_PER_CALL
FROM per_call
GROUP BY 1, 2, 3
ORDER BY USAGE_DATE DESC, TOTAL_CREDITS DESC;

-- ============================================================
-- View: VW_COST_ANOMALIES
-- ============================================================
create or replace view VW_COST_ANOMALIES(
	WAREHOUSE_NAME,
	USAGE_DATE,
	DAILY_CREDITS,
	AVG_14D,
	STDDEV_14D,
	Z_SCORE,
	ANOMALY_FLAG
) as
WITH daily AS (
    SELECT DATE_TRUNC('day', start_time)::DATE AS usage_date,
        warehouse_name,
        SUM(credits_used) AS daily_credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
    WHERE start_time >= DATEADD(DAY, -60, CURRENT_DATE())
    GROUP BY 1, 2
),
stats AS (
    SELECT warehouse_name, usage_date, daily_credits,
        AVG(daily_credits) OVER (PARTITION BY warehouse_name ORDER BY usage_date ROWS BETWEEN 14 PRECEDING AND 1 PRECEDING) AS avg_14d,
        STDDEV(daily_credits) OVER (PARTITION BY warehouse_name ORDER BY usage_date ROWS BETWEEN 14 PRECEDING AND 1 PRECEDING) AS stddev_14d
    FROM daily
)
SELECT *,
    ROUND((daily_credits - avg_14d) / NULLIF(stddev_14d, 0), 2) AS z_score,
    CASE WHEN (daily_credits - avg_14d) / NULLIF(stddev_14d, 0) > 2 THEN 'SPIKE'
         WHEN (daily_credits - avg_14d) / NULLIF(stddev_14d, 0) < -2 THEN 'DROP'
         ELSE 'NORMAL'
    END AS anomaly_flag
FROM stats
WHERE usage_date >= DATEADD(DAY, -30, CURRENT_DATE());

-- ============================================================
-- View: VW_COST_BY_SERVICE
-- ============================================================
create or replace view VW_COST_BY_SERVICE(
	SERVICE_TYPE,
	USAGE_DATE,
	TOTAL_CREDITS,
	PCT_OF_DAILY_TOTAL
) as
SELECT
    service_type,
    DATE_TRUNC('day', start_time)::DATE AS usage_date,
    ROUND(SUM(credits_used), 2) AS total_credits,
    ROUND(SUM(credits_used) / SUM(SUM(credits_used)) OVER (PARTITION BY DATE_TRUNC('day', start_time)) * 100, 1) AS pct_of_daily_total
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE start_time >= DATEADD(DAY, -90, CURRENT_DATE())
GROUP BY service_type, DATE_TRUNC('day', start_time);

-- ============================================================
-- View: VW_COST_FORECAST
-- ============================================================
create or replace view VW_COST_FORECAST(
	USAGE_DATE,
	ACTUAL_CREDITS,
	ROLLING_7D_AVG,
	ROLLING_30D_AVG,
	PROJECTED_MONTHLY_CREDITS,
	PROJECTED_MONTHLY_USD
) as
WITH daily_total AS (
    SELECT
        DATE_TRUNC('day', start_time)::DATE AS usage_date,
        SUM(credits_used) AS daily_credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
    WHERE start_time >= DATEADD(DAY, -60, CURRENT_DATE())
        AND start_time < CURRENT_DATE()
    GROUP BY DATE_TRUNC('day', start_time)
)
SELECT
    usage_date,
    ROUND(daily_credits, 2) AS actual_credits,
    ROUND(AVG(daily_credits) OVER (ORDER BY usage_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW), 2) AS rolling_7d_avg,
    ROUND(AVG(daily_credits) OVER (ORDER BY usage_date ROWS BETWEEN 29 PRECEDING AND CURRENT ROW), 2) AS rolling_30d_avg,
    ROUND(AVG(daily_credits) OVER (ORDER BY usage_date ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) * 30, 2) AS projected_monthly_credits,
    ROUND(AVG(daily_credits) OVER (ORDER BY usage_date ROWS BETWEEN 29 PRECEDING AND CURRENT ROW) * 30 * 3.00, 2) AS projected_monthly_usd
FROM daily_total;

-- ============================================================
-- View: VW_COST_SUMMARY_USD
-- ============================================================
create or replace view VW_COST_SUMMARY_USD(
	USAGE_DATE,
	SERVICE_TYPE,
	CREDITS,
	ESTIMATED_USD
) as
WITH params AS (SELECT 3.00 AS credit_price_usd)
SELECT
    DATE_TRUNC('day', m.start_time)::DATE AS usage_date,
    m.service_type,
    ROUND(SUM(m.credits_used), 2) AS credits,
    ROUND(SUM(m.credits_used) * p.credit_price_usd, 2) AS estimated_usd
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY m
CROSS JOIN params p
WHERE m.start_time >= DATEADD(DAY, -90, CURRENT_DATE())
GROUP BY DATE_TRUNC('day', m.start_time), m.service_type, p.credit_price_usd;

-- ============================================================
-- View: VW_COST_VELOCITY
-- ============================================================
create or replace view VW_COST_VELOCITY(
	USAGE_DATE,
	SERVICE_TYPE,
	DAILY_CREDITS,
	ROLLING_AVG_7D,
	VELOCITY,
	ACCELERATION,
	DRIFT_STATUS
) as
WITH daily_credits AS (
    SELECT 
        DATE_TRUNC('day', start_time)::DATE AS usage_date,
        service_type,
        SUM(credits_used) AS daily_credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
    WHERE start_time >= DATEADD(DAY, -60, CURRENT_DATE())
    GROUP BY 1, 2
),
with_velocity AS (
    SELECT *,
        AVG(daily_credits) OVER (PARTITION BY service_type ORDER BY usage_date ROWS BETWEEN 7 PRECEDING AND 1 PRECEDING) AS avg_7d_prior,
        AVG(daily_credits) OVER (PARTITION BY service_type ORDER BY usage_date ROWS BETWEEN 14 PRECEDING AND 8 PRECEDING) AS avg_prior_week,
        LAG(daily_credits, 1) OVER (PARTITION BY service_type ORDER BY usage_date) AS prev_day
    FROM daily_credits
)
SELECT 
    usage_date,
    service_type,
    ROUND(daily_credits, 4) AS daily_credits,
    ROUND(avg_7d_prior, 4) AS rolling_avg_7d,
    ROUND(daily_credits - COALESCE(avg_7d_prior, daily_credits), 4) AS velocity,
    ROUND((avg_7d_prior - COALESCE(avg_prior_week, avg_7d_prior)), 4) AS acceleration,
    CASE 
        WHEN daily_credits > avg_7d_prior * 2 AND avg_7d_prior > 0 THEN 'SPIKE'
        WHEN avg_7d_prior > avg_prior_week * 1.5 AND avg_prior_week > 0 THEN 'ACCELERATING'
        WHEN avg_7d_prior < avg_prior_week * 0.5 AND avg_prior_week > 0 THEN 'DECELERATING'
        ELSE 'STABLE'
    END AS drift_status
FROM with_velocity
WHERE usage_date >= DATEADD(DAY, -30, CURRENT_DATE());

-- ============================================================
-- View: VW_DATA_TRANSFER
-- ============================================================
create or replace view VW_DATA_TRANSFER(
	TRANSFER_DATE,
	SOURCE_CLOUD,
	SOURCE_REGION,
	TARGET_CLOUD,
	TARGET_REGION,
	TRANSFER_TYPE,
	TRANSFER_COUNT,
	GB_TRANSFERRED
) as
SELECT
    DATE_TRUNC('day', start_time)::DATE AS transfer_date,
    source_cloud,
    source_region,
    target_cloud,
    target_region,
    transfer_type,
    COUNT(*) AS transfer_count,
    ROUND(SUM(bytes_transferred) / POW(1024, 3), 2) AS gb_transferred
FROM SNOWFLAKE.ACCOUNT_USAGE.DATA_TRANSFER_HISTORY
WHERE start_time >= DATEADD(DAY, -90, CURRENT_DATE())
GROUP BY DATE_TRUNC('day', start_time), source_cloud, source_region, target_cloud, target_region, transfer_type;

-- ============================================================
-- View: VW_DUPLICATE_QUERIES
-- ============================================================
create or replace view VW_DUPLICATE_QUERIES(
	QUERY_PARAMETERIZED_HASH,
	WAREHOUSE_NAME,
	EXECUTION_COUNT,
	UNIQUE_USERS,
	TOTAL_CREDITS_WASTED,
	AVG_CREDITS_PER_EXEC,
	FIRST_SEEN,
	LAST_SEEN
) as
SELECT
    query_parameterized_hash,
    warehouse_name,
    COUNT(*) AS execution_count,
    COUNT(DISTINCT user_name) AS unique_users,
    ROUND(SUM(credits_attributed_compute), 2) AS total_credits_wasted,
    ROUND(AVG(credits_attributed_compute), 4) AS avg_credits_per_exec,
    MIN(start_time) AS first_seen,
    MAX(start_time) AS last_seen
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
WHERE start_time >= DATEADD(DAY, -7, CURRENT_DATE())
    AND query_parameterized_hash IS NOT NULL
GROUP BY query_parameterized_hash, warehouse_name
HAVING execution_count > 50;

-- ============================================================
-- View: VW_EXPENSIVE_QUERY_PATTERNS
-- ============================================================
create or replace view VW_EXPENSIVE_QUERY_PATTERNS(
	QUERY_PARAMETERIZED_HASH,
	WAREHOUSE_NAME,
	SAMPLE_USER,
	EXECUTION_COUNT,
	TOTAL_CREDITS,
	AVG_CREDITS_PER_EXEC,
	EXAMPLE_QUERY_ID
) as
SELECT
    query_parameterized_hash,
    ANY_VALUE(warehouse_name) AS warehouse_name,
    ANY_VALUE(user_name) AS sample_user,
    COUNT(query_id) AS execution_count,
    ROUND(SUM(credits_attributed_compute), 2) AS total_credits,
    ROUND(AVG(credits_attributed_compute), 4) AS avg_credits_per_exec,
    ANY_VALUE(query_id) AS example_query_id
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
WHERE start_time >= DATEADD(DAY, -30, CURRENT_DATE())
    AND query_parameterized_hash IS NOT NULL
GROUP BY query_parameterized_hash
HAVING total_credits > 0;

-- ============================================================
-- View: VW_FAILED_QUERIES
-- ============================================================
create or replace view VW_FAILED_QUERIES(
	QUERY_DATE,
	USER_NAME,
	WAREHOUSE_NAME,
	ERROR_CODE,
	ERROR_MESSAGE,
	FAILURE_COUNT,
	WASTED_TIME_SEC
) as
SELECT
    DATE_TRUNC('day', start_time)::DATE AS query_date,
    user_name,
    warehouse_name,
    error_code,
    error_message,
    COUNT(*) AS failure_count,
    ROUND(SUM(total_elapsed_time) / 1000, 2) AS wasted_time_sec
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(DAY, -30, CURRENT_DATE())
    AND execution_status = 'FAIL'
GROUP BY DATE_TRUNC('day', start_time), user_name, warehouse_name, error_code, error_message;

-- ============================================================
-- View: VW_FORECAST_TRAINING
-- ============================================================
create or replace view VW_FORECAST_TRAINING(
	USAGE_DATE,
	CREDITS_USED
) as
SELECT
    TRY_TO_DATE(REPLACE(USAGE_DATE, '"', '')) AS USAGE_DATE,
    SUM(CREDITS_USED) AS CREDITS_USED
FROM ECOMMERCE_DEV.COST_ANALYTICS.VW_WAREHOUSE_DAILY
GROUP BY TRY_TO_DATE(REPLACE(USAGE_DATE, '"', ''))
HAVING TRY_TO_DATE(REPLACE(USAGE_DATE, '"', '')) IS NOT NULL
ORDER BY 1;

-- ============================================================
-- View: VW_FULL_TABLE_SCANS
-- ============================================================
create or replace view VW_FULL_TABLE_SCANS(
	QUERY_DATE,
	WAREHOUSE_NAME,
	USER_NAME,
	QUERY_ID,
	QUERY_TYPE,
	DURATION_SEC,
	SCANNED_GB,
	PARTITIONS_SCANNED,
	PARTITIONS_TOTAL,
	PARTITION_SCAN_PCT
) as
SELECT
    DATE_TRUNC('day', start_time)::DATE AS query_date,
    warehouse_name,
    user_name,
    query_id,
    query_type,
    ROUND(total_elapsed_time / 1000, 2) AS duration_sec,
    ROUND(bytes_scanned / POW(1024, 3), 2) AS scanned_gb,
    partitions_scanned,
    partitions_total,
    ROUND(partitions_scanned / NULLIF(partitions_total, 0) * 100, 1) AS partition_scan_pct
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(DAY, -14, CURRENT_DATE())
    AND partitions_total > 100
    AND partitions_scanned >= partitions_total * 0.9
    AND execution_status = 'SUCCESS';

-- ============================================================
-- View: VW_IDLE_USERS
-- ============================================================
create or replace view VW_IDLE_USERS(
	USER_NAME,
	CREATED_ON,
	LAST_SUCCESS_LOGIN,
	DAYS_SINCE_LOGIN,
	QUERIES_30D,
	STATUS
) as
SELECT
    u.name AS user_name,
    u.created_on,
    u.last_success_login,
    DATEDIFF('day', u.last_success_login, CURRENT_TIMESTAMP()) AS days_since_login,
    COALESCE(q.query_count, 0) AS queries_30d,
    CASE WHEN u.last_success_login IS NULL THEN 'NEVER_LOGGED_IN'
         WHEN DATEDIFF('day', u.last_success_login, CURRENT_TIMESTAMP()) > 90 THEN 'DORMANT_90D+'
         WHEN DATEDIFF('day', u.last_success_login, CURRENT_TIMESTAMP()) > 30 THEN 'INACTIVE_30D+'
         ELSE 'ACTIVE'
    END AS status
FROM SNOWFLAKE.ACCOUNT_USAGE.USERS u
LEFT JOIN (
    SELECT user_name, COUNT(*) AS query_count
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
    WHERE start_time >= DATEADD(DAY, -30, CURRENT_DATE())
    GROUP BY user_name
) q ON u.name = q.user_name
WHERE u.deleted_on IS NULL;

-- ============================================================
-- View: VW_LOGIN_HISTORY
-- ============================================================
create or replace view VW_LOGIN_HISTORY(
	USER_NAME,
	LOGIN_DATE,
	LOGIN_COUNT,
	SUCCESSFUL_LOGINS,
	FAILED_LOGINS,
	UNIQUE_IPS
) as
SELECT
    user_name,
    DATE_TRUNC('day', event_timestamp)::DATE AS login_date,
    COUNT(*) AS login_count,
    COUNT(CASE WHEN is_success = 'YES' THEN 1 END) AS successful_logins,
    COUNT(CASE WHEN is_success = 'NO' THEN 1 END) AS failed_logins,
    COUNT(DISTINCT client_ip) AS unique_ips
FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
WHERE event_timestamp >= DATEADD(DAY, -90, CURRENT_DATE())
GROUP BY user_name, DATE_TRUNC('day', event_timestamp);

-- ============================================================
-- View: VW_MATERIALIZED_VIEW_COSTS
-- ============================================================
create or replace view VW_MATERIALIZED_VIEW_COSTS(
	DATABASE_NAME,
	SCHEMA_NAME,
	TABLE_NAME,
	USAGE_DATE,
	MV_CREDITS
) as
SELECT
    database_name,
    schema_name,
    table_name,
    DATE_TRUNC('day', start_time)::DATE AS usage_date,
    ROUND(SUM(credits_used), 4) AS mv_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.MATERIALIZED_VIEW_REFRESH_HISTORY
WHERE start_time >= DATEADD(DAY, -90, CURRENT_DATE())
GROUP BY database_name, schema_name, table_name, DATE_TRUNC('day', start_time);

-- ============================================================
-- View: VW_MONTHLY_TRENDS
-- ============================================================
create or replace view VW_MONTHLY_TRENDS(
	MONTH_START,
	SERVICE_TYPE,
	CREDITS_USED
) as
SELECT
    DATE_TRUNC('month', start_time)::DATE AS month_start,
    service_type,
    ROUND(SUM(credits_used), 2) AS credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE start_time >= DATEADD(MONTH, -12, CURRENT_DATE())
GROUP BY DATE_TRUNC('month', start_time), service_type;

-- ============================================================
-- View: VW_PEAK_HOURS
-- ============================================================
create or replace view VW_PEAK_HOURS(
	WAREHOUSE_NAME,
	HOUR_OF_DAY,
	DAY_OF_WEEK,
	AVG_CREDITS,
	PEAK_CREDITS,
	SAMPLE_COUNT
) as
SELECT
    warehouse_name,
    EXTRACT(HOUR FROM start_time) AS hour_of_day,
    EXTRACT(DOW FROM start_time) AS day_of_week,
    ROUND(AVG(credits_used), 4) AS avg_credits,
    ROUND(MAX(credits_used), 4) AS peak_credits,
    COUNT(*) AS sample_count
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD(DAY, -30, CURRENT_DATE())
GROUP BY warehouse_name, EXTRACT(HOUR FROM start_time), EXTRACT(DOW FROM start_time);

-- ============================================================
-- View: VW_QUERY_PERFORMANCE
-- ============================================================
create or replace view VW_QUERY_PERFORMANCE(
	QUERY_DATE,
	WAREHOUSE_NAME,
	USER_NAME,
	TOTAL_QUERIES,
	AVG_DURATION_SEC,
	MAX_DURATION_SEC,
	TOTAL_GB_SCANNED,
	TOTAL_GB_SPILLED,
	FAILED_QUERIES
) as
SELECT
    DATE_TRUNC('day', start_time)::DATE AS query_date,
    warehouse_name,
    user_name,
    COUNT(*) AS total_queries,
    ROUND(AVG(total_elapsed_time) / 1000, 2) AS avg_duration_sec,
    ROUND(MAX(total_elapsed_time) / 1000, 2) AS max_duration_sec,
    SUM(bytes_scanned) / (1024*1024*1024) AS total_gb_scanned,
    SUM(bytes_spilled_to_local_storage + bytes_spilled_to_remote_storage) / (1024*1024*1024) AS total_gb_spilled,
    SUM(CASE WHEN execution_status = 'FAIL' THEN 1 ELSE 0 END) AS failed_queries
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(DAY, -90, CURRENT_DATE())
GROUP BY DATE_TRUNC('day', start_time), warehouse_name, user_name;

-- ============================================================
-- View: VW_QUEUE_TIMES
-- ============================================================
create or replace view VW_QUEUE_TIMES(
	QUERY_DATE,
	WAREHOUSE_NAME,
	TOTAL_QUERIES,
	QUEUED_QUERIES,
	QUEUE_PCT,
	AVG_QUEUE_SEC,
	MAX_QUEUE_SEC,
	AVG_PROVISIONING_SEC
) as
SELECT
    DATE_TRUNC('day', start_time)::DATE AS query_date,
    warehouse_name,
    COUNT(*) AS total_queries,
    COUNT(CASE WHEN queued_overload_time > 0 THEN 1 END) AS queued_queries,
    ROUND(COUNT(CASE WHEN queued_overload_time > 0 THEN 1 END) / NULLIF(COUNT(*), 0) * 100, 1) AS queue_pct,
    ROUND(AVG(queued_overload_time) / 1000, 2) AS avg_queue_sec,
    ROUND(MAX(queued_overload_time) / 1000, 2) AS max_queue_sec,
    ROUND(AVG(queued_provisioning_time) / 1000, 2) AS avg_provisioning_sec
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(DAY, -30, CURRENT_DATE())
    AND warehouse_name IS NOT NULL
GROUP BY DATE_TRUNC('day', start_time), warehouse_name;

-- ============================================================
-- View: VW_SEARCH_OPTIMIZATION_COSTS
-- ============================================================
create or replace view VW_SEARCH_OPTIMIZATION_COSTS(
	DATABASE_NAME,
	SCHEMA_NAME,
	TABLE_NAME,
	USAGE_DATE,
	SEARCH_OPT_CREDITS
) as
SELECT
    database_name,
    schema_name,
    table_name,
    DATE_TRUNC('day', start_time)::DATE AS usage_date,
    ROUND(SUM(credits_used), 4) AS search_opt_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.SEARCH_OPTIMIZATION_HISTORY
WHERE start_time >= DATEADD(DAY, -90, CURRENT_DATE())
GROUP BY database_name, schema_name, table_name, DATE_TRUNC('day', start_time);

-- ============================================================
-- View: VW_SERVERLESS_TASKS
-- ============================================================
create or replace view VW_SERVERLESS_TASKS(
	DATABASE_NAME,
	SCHEMA_NAME,
	TASK_NAME,
	USAGE_DATE,
	RUN_COUNT,
	TOTAL_CREDITS
) as
SELECT
    database_name,
    schema_name,
    task_name,
    DATE_TRUNC('day', start_time)::DATE AS usage_date,
    COUNT(*) AS run_count,
    ROUND(SUM(credits_used), 4) AS total_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.SERVERLESS_TASK_HISTORY
WHERE start_time >= DATEADD(DAY, -90, CURRENT_DATE())
GROUP BY database_name, schema_name, task_name, DATE_TRUNC('day', start_time);

-- ============================================================
-- View: VW_SNOWPIPE_COSTS
-- ============================================================
create or replace view VW_SNOWPIPE_COSTS(
	PIPE_NAME,
	USAGE_DATE,
	TOTAL_CREDITS,
	GB_INSERTED,
	FILES_INSERTED
) as
SELECT
    pipe_name,
    DATE_TRUNC('day', start_time)::DATE AS usage_date,
    ROUND(SUM(credits_used), 4) AS total_credits,
    SUM(bytes_inserted) / (1024*1024*1024) AS gb_inserted,
    SUM(files_inserted) AS files_inserted
FROM SNOWFLAKE.ACCOUNT_USAGE.PIPE_USAGE_HISTORY
WHERE start_time >= DATEADD(DAY, -90, CURRENT_DATE())
GROUP BY pipe_name, DATE_TRUNC('day', start_time);

-- ============================================================
-- View: VW_SPCS_SERVICE_COSTS
-- ============================================================
create or replace view VW_SPCS_SERVICE_COSTS(
	COMPUTE_POOL_NAME,
	WORKLOAD_NAME,
	USAGE_DATE,
	DAILY_CREDITS,
	ACTIVE_HOURS,
	CREDITS_PER_HOUR,
	LIFETIME_CREDITS,
	LIFETIME_HOURS,
	ACTIVE_DAYS,
	AVG_DAILY_CREDITS,
	LAST_ACTIVE_DATE,
	PROJECTED_MONTHLY_CREDITS
) as
WITH pool_daily AS (
    SELECT
        COMPUTE_POOL_NAME,
        COALESCE(APPLICATION_NAME, 'STREAMLIT / NOTEBOOK')  AS WORKLOAD_NAME,
        START_TIME::DATE                                    AS USAGE_DATE,
        SUM(CREDITS_USED)                                   AS DAILY_CREDITS,
        COUNT(*)                                            AS ACTIVE_HOURS
    FROM SNOWFLAKE.ACCOUNT_USAGE.SNOWPARK_CONTAINER_SERVICES_HISTORY
    GROUP BY 1, 2, 3
),
totals AS (
    SELECT
        COMPUTE_POOL_NAME,
        WORKLOAD_NAME,
        SUM(DAILY_CREDITS)                                  AS LIFETIME_CREDITS,
        SUM(ACTIVE_HOURS)                                   AS LIFETIME_HOURS,
        COUNT(DISTINCT USAGE_DATE)                          AS ACTIVE_DAYS,
        MAX(USAGE_DATE)                                     AS LAST_ACTIVE_DATE
    FROM pool_daily
    GROUP BY 1, 2
)
SELECT
    p.COMPUTE_POOL_NAME,
    p.WORKLOAD_NAME,
    p.USAGE_DATE,
    ROUND(p.DAILY_CREDITS, 4)                               AS DAILY_CREDITS,
    p.ACTIVE_HOURS,
    ROUND(p.DAILY_CREDITS / NULLIF(p.ACTIVE_HOURS, 0), 4)   AS CREDITS_PER_HOUR,
    ROUND(t.LIFETIME_CREDITS, 4)                            AS LIFETIME_CREDITS,
    t.LIFETIME_HOURS,
    t.ACTIVE_DAYS,
    ROUND(t.LIFETIME_CREDITS / NULLIF(t.ACTIVE_DAYS, 0), 4) AS AVG_DAILY_CREDITS,
    t.LAST_ACTIVE_DATE,
    ROUND(t.LIFETIME_CREDITS / NULLIF(t.ACTIVE_DAYS, 0) * 30, 2) AS PROJECTED_MONTHLY_CREDITS
FROM pool_daily p
JOIN totals t
  ON p.COMPUTE_POOL_NAME = t.COMPUTE_POOL_NAME
 AND p.WORKLOAD_NAME = t.WORKLOAD_NAME
ORDER BY p.USAGE_DATE DESC, p.DAILY_CREDITS DESC;

-- ============================================================
-- View: VW_SPILLING_QUERIES
-- ============================================================
create or replace view VW_SPILLING_QUERIES(
	QUERY_DATE,
	WAREHOUSE_NAME,
	USER_NAME,
	QUERY_ID,
	QUERY_TYPE,
	DURATION_SEC,
	LOCAL_SPILL_GB,
	REMOTE_SPILL_GB,
	SCANNED_GB,
	PARTITIONS_SCANNED,
	PARTITIONS_TOTAL,
	PARTITION_SCAN_PCT
) as
SELECT
    DATE_TRUNC('day', start_time)::DATE AS query_date,
    warehouse_name,
    user_name,
    query_id,
    query_type,
    ROUND(total_elapsed_time / 1000, 2) AS duration_sec,
    ROUND(bytes_spilled_to_local_storage / POW(1024, 3), 2) AS local_spill_gb,
    ROUND(bytes_spilled_to_remote_storage / POW(1024, 3), 2) AS remote_spill_gb,
    ROUND(bytes_scanned / POW(1024, 3), 2) AS scanned_gb,
    partitions_scanned,
    partitions_total,
    ROUND(partitions_scanned / NULLIF(partitions_total, 0) * 100, 1) AS partition_scan_pct
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(DAY, -30, CURRENT_DATE())
    AND (bytes_spilled_to_local_storage > 0 OR bytes_spilled_to_remote_storage > 0)
    AND execution_status = 'SUCCESS';

-- ============================================================
-- View: VW_STORAGE_DAILY
-- ============================================================
create or replace view VW_STORAGE_DAILY(
	DATABASE_NAME,
	USAGE_DATE,
	DATABASE_GB,
	FAILSAFE_GB,
	HYBRID_TABLE_GB,
	TOTAL_GB
) as
SELECT
    database_name,
    usage_date,
    ROUND(average_database_bytes / POW(1024, 3), 2) AS database_gb,
    ROUND(average_failsafe_bytes / POW(1024, 3), 2) AS failsafe_gb,
    ROUND(COALESCE(average_hybrid_table_storage_bytes, 0) / POW(1024, 3), 2) AS hybrid_table_gb,
    ROUND((average_database_bytes + average_failsafe_bytes + COALESCE(average_hybrid_table_storage_bytes, 0)) / POW(1024, 3), 2) AS total_gb
FROM SNOWFLAKE.ACCOUNT_USAGE.DATABASE_STORAGE_USAGE_HISTORY
WHERE usage_date >= DATEADD(DAY, -90, CURRENT_DATE());

-- ============================================================
-- View: VW_TOP_EXPENSIVE_QUERIES
-- ============================================================
create or replace view VW_TOP_EXPENSIVE_QUERIES(
	QUERY_DATE,
	USER_NAME,
	WAREHOUSE_NAME,
	WAREHOUSE_SIZE,
	QUERY_TYPE,
	EXECUTION_STATUS,
	QUERY_SNIPPET,
	ELAPSED_SECONDS,
	GB_SCANNED,
	ESTIMATED_CREDITS,
	QUERY_ID
) as
SELECT
    START_TIME::DATE                                          AS QUERY_DATE,
    USER_NAME,
    WAREHOUSE_NAME,
    WAREHOUSE_SIZE,
    QUERY_TYPE,
    EXECUTION_STATUS,
    LEFT(QUERY_TEXT, 300)                                     AS QUERY_SNIPPET,
    ROUND(TOTAL_ELAPSED_TIME / 1000.0, 2)                     AS ELAPSED_SECONDS,
    ROUND(BYTES_SCANNED / POWER(1024, 3), 3)                  AS GB_SCANNED,
    ROUND(
        (TOTAL_ELAPSED_TIME / 1000.0 / 3600.0)
        * CASE UPPER(COALESCE(WAREHOUSE_SIZE, 'X-SMALL'))
            WHEN 'X-SMALL' THEN 1 WHEN 'SMALL' THEN 2 WHEN 'MEDIUM' THEN 4
            WHEN 'LARGE' THEN 8 WHEN 'X-LARGE' THEN 16 WHEN '2X-LARGE' THEN 32
            WHEN '3X-LARGE' THEN 64 WHEN '4X-LARGE' THEN 128 ELSE 1
          END, 6
    )                                                         AS ESTIMATED_CREDITS,
    QUERY_ID
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATE_TRUNC('month', CURRENT_DATE())
  AND WAREHOUSE_NAME IS NOT NULL
  AND TOTAL_ELAPSED_TIME > 0
ORDER BY ESTIMATED_CREDITS DESC
LIMIT 500;

-- ============================================================
-- View: VW_TOP_RESOURCES
-- ============================================================
create or replace view VW_TOP_RESOURCES(
	RESOURCE_TYPE,
	RESOURCE_NAME,
	TOTAL_CREDITS
) as
WITH warehouse_costs AS (
    SELECT 'WAREHOUSE' AS resource_type, warehouse_name AS resource_name, ROUND(SUM(credits_used), 2) AS total_credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
    WHERE start_time >= DATEADD('month', -1, CURRENT_DATE())
    GROUP BY warehouse_name
),
compute_pool_costs AS (
    SELECT 'COMPUTE_POOL' AS resource_type, compute_pool_name AS resource_name, ROUND(SUM(credits_used), 2) AS total_credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.SNOWPARK_CONTAINER_SERVICES_HISTORY
    WHERE start_time >= DATEADD('month', -1, CURRENT_DATE())
    GROUP BY compute_pool_name
)
SELECT * FROM warehouse_costs
UNION ALL
SELECT * FROM compute_pool_costs;

-- ============================================================
-- View: VW_USER_COSTS
-- ============================================================
create or replace view VW_USER_COSTS(
	USER_NAME,
	USAGE_DATE,
	QUERY_COUNT,
	COMPUTE_CREDITS,
	QAS_CREDITS,
	TOTAL_CREDITS
) as
SELECT
    user_name,
    DATE_TRUNC('day', start_time)::DATE AS usage_date,
    COUNT(DISTINCT query_id) AS query_count,
    ROUND(SUM(credits_attributed_compute), 4) AS compute_credits,
    ROUND(SUM(COALESCE(credits_used_query_acceleration, 0)), 4) AS qas_credits,
    ROUND(SUM(credits_attributed_compute + COALESCE(credits_used_query_acceleration, 0)), 4) AS total_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
WHERE start_time >= DATEADD(DAY, -90, CURRENT_DATE())
GROUP BY user_name, DATE_TRUNC('day', start_time);

-- ============================================================
-- View: VW_USER_WASTE_SCORE
-- ============================================================
create or replace view VW_USER_WASTE_SCORE(
	USER_NAME,
	TOTAL_QUERIES,
	FULL_SCAN_PCT,
	SPILL_PCT,
	FAILURE_PCT,
	CREDITS_USED,
	EFFICIENCY_SCORE
) as
WITH user_metrics AS (
    SELECT 
        user_name,
        COUNT(*) AS total_queries,
        ROUND(SUM(CASE WHEN partitions_scanned >= partitions_total * 0.9 AND partitions_total > 10 THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(*), 0) * 100, 1) AS full_scan_pct,
        ROUND(SUM(CASE WHEN bytes_spilled_to_remote_storage > 0 THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(*), 0) * 100, 1) AS spill_pct,
        ROUND(SUM(CASE WHEN execution_status != 'SUCCESS' THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(*), 0) * 100, 1) AS failure_pct,
        ROUND(SUM(credits_used_cloud_services), 4) AS credits_used
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
    WHERE start_time >= DATEADD(DAY, -14, CURRENT_DATE())
        AND user_name IS NOT NULL
        AND warehouse_name IS NOT NULL
    GROUP BY user_name
    HAVING COUNT(*) >= 10
)
SELECT *,
    ROUND(GREATEST(0, 100 - (
        full_scan_pct * 0.35 +
        spill_pct * 0.3 +
        failure_pct * 0.35
    )), 0) AS efficiency_score
FROM user_metrics;

-- ============================================================
-- View: VW_WAREHOUSE_DAILY
-- ============================================================
create or replace view VW_WAREHOUSE_DAILY(
	WAREHOUSE_NAME,
	USAGE_DATE,
	CREDITS_USED,
	CREDITS_COMPUTE,
	CREDITS_CLOUD_SERVICES
) as
SELECT
    warehouse_name,
    DATE_TRUNC('day', start_time)::DATE AS usage_date,
    ROUND(SUM(credits_used), 2) AS credits_used,
    ROUND(SUM(credits_used_compute), 2) AS credits_compute,
    ROUND(SUM(credits_used_cloud_services), 2) AS credits_cloud_services
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD(DAY, -90, CURRENT_DATE())
GROUP BY warehouse_name, DATE_TRUNC('day', start_time);

-- ============================================================
-- View: VW_WAREHOUSE_MOM
-- ============================================================
create or replace view VW_WAREHOUSE_MOM(
	WAREHOUSE_NAME,
	MONTH,
	CREDITS,
	PREV_MONTH_CREDITS,
	CHANGE
) as
WITH monthly AS (
    SELECT warehouse_name, DATE_TRUNC('month', start_time) AS month, SUM(credits_used) AS credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
    WHERE start_time >= DATEADD('month', -3, CURRENT_DATE())
    GROUP BY warehouse_name, DATE_TRUNC('month', start_time)
)
SELECT
    warehouse_name,
    month,
    ROUND(credits, 2) AS credits,
    ROUND(LAG(credits) OVER (PARTITION BY warehouse_name ORDER BY month), 2) AS prev_month_credits,
    ROUND(credits - COALESCE(LAG(credits) OVER (PARTITION BY warehouse_name ORDER BY month), 0), 2) AS change
FROM monthly;

-- ============================================================
-- View: VW_WAREHOUSE_SIZING
-- ============================================================
create or replace view VW_WAREHOUSE_SIZING(
	WAREHOUSE_NAME,
	TOTAL_QUERIES,
	AVG_DURATION_SEC,
	P95_DURATION_SEC,
	REMOTE_SPILL_TB,
	PCT_QUEUED,
	RECOMMENDATION
) as
SELECT
    warehouse_name,
    COUNT(DISTINCT query_id) AS total_queries,
    ROUND(AVG(total_elapsed_time)/1000, 2) AS avg_duration_sec,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY total_elapsed_time)/1000, 2) AS p95_duration_sec,
    ROUND(SUM(bytes_spilled_to_remote_storage)/POW(1024,4), 4) AS remote_spill_tb,
    ROUND(AVG(CASE WHEN queued_overload_time > 0 THEN 1.0 ELSE 0 END)*100, 1) AS pct_queued,
    CASE WHEN AVG(CASE WHEN queued_overload_time > 0 THEN 1.0 ELSE 0 END) > 0.1 THEN 'UPSIZE: High queueing'
         WHEN SUM(bytes_spilled_to_remote_storage) > 0 THEN 'UPSIZE: Remote spilling detected'
         WHEN AVG(total_elapsed_time) < 500 AND COUNT(*) < 100 THEN 'DOWNSIZE: Light usage'
         ELSE 'OK'
    END AS recommendation
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(DAY, -14, CURRENT_DATE())
    AND warehouse_name IS NOT NULL
GROUP BY warehouse_name;

-- ============================================================
-- View: VW_WAREHOUSE_SIZING_BASELINE
-- ============================================================
create or replace view VW_WAREHOUSE_SIZING_BASELINE(
	WAREHOUSE_NAME,
	WAREHOUSE_SIZE,
	TOTAL_QUERIES,
	AVG_DURATION_SEC,
	P50_DURATION_SEC,
	P95_DURATION_SEC,
	LOCAL_SPILL_GB,
	REMOTE_SPILL_GB,
	PCT_QUEUED,
	CLOUD_CREDITS,
	ACTIVE_DAYS,
	CREDITS_PER_DAY
) as
SELECT
    warehouse_name,
    warehouse_size,
    COUNT(*) AS total_queries,
    ROUND(AVG(total_elapsed_time)/1000, 2) AS avg_duration_sec,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_elapsed_time)/1000, 2) AS p50_duration_sec,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY total_elapsed_time)/1000, 2) AS p95_duration_sec,
    ROUND(SUM(bytes_spilled_to_local_storage)/POW(1024,3), 2) AS local_spill_gb,
    ROUND(SUM(bytes_spilled_to_remote_storage)/POW(1024,3), 2) AS remote_spill_gb,
    ROUND(AVG(CASE WHEN queued_overload_time > 0 THEN 1.0 ELSE 0 END)*100, 1) AS pct_queued,
    ROUND(SUM(credits_used_cloud_services), 2) AS cloud_credits,
    COUNT(DISTINCT DATE_TRUNC('day', start_time)::DATE) AS active_days,
    ROUND(SUM(credits_used_cloud_services) / NULLIF(COUNT(DISTINCT DATE_TRUNC('day', start_time)::DATE), 0), 4) AS credits_per_day
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(DAY, -30, CURRENT_DATE())
    AND warehouse_name IS NOT NULL
GROUP BY warehouse_name, warehouse_size;

-- ============================================================
-- View: VW_WAREHOUSE_UTILIZATION
-- ============================================================
create or replace view VW_WAREHOUSE_UTILIZATION(
	WAREHOUSE_NAME,
	USAGE_DATE,
	ACTIVE_HOURS,
	IDLE_HOURS,
	UTILIZATION_PCT,
	DAILY_CREDITS,
	AVG_CREDITS_PER_ACTIVE_HOUR
) as
WITH hourly AS (
    SELECT
        warehouse_name,
        DATE_TRUNC('hour', start_time) AS hour_slot,
        SUM(credits_used) AS credits,
        SUM(credits_used_compute) AS compute_credits,
        SUM(credits_used_cloud_services) AS cloud_credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
    WHERE start_time >= DATEADD(DAY, -30, CURRENT_DATE())
    GROUP BY warehouse_name, DATE_TRUNC('hour', start_time)
)
SELECT
    warehouse_name,
    DATE_TRUNC('day', hour_slot)::DATE AS usage_date,
    COUNT(*) AS active_hours,
    24 - COUNT(*) AS idle_hours,
    ROUND(COUNT(*) / 24.0 * 100, 1) AS utilization_pct,
    ROUND(SUM(credits), 2) AS daily_credits,
    ROUND(AVG(credits), 4) AS avg_credits_per_active_hour
FROM hourly
GROUP BY warehouse_name, DATE_TRUNC('day', hour_slot);

-- ============================================================
-- View: VW_WASTE_SCORE
-- ============================================================
create or replace view VW_WASTE_SCORE(
	WAREHOUSE_NAME,
	TOTAL_QUERIES,
	CREDITS_14D,
	UTILIZATION_PCT,
	CACHE_MISS_PCT,
	FULL_SCAN_PCT,
	SPILL_PCT,
	QUEUE_PCT,
	EFFICIENCY_SCORE
) as
WITH warehouse_metrics AS (
    SELECT 
        q.warehouse_name,
        COUNT(*) AS total_queries,
        ROUND(AVG(CASE WHEN q.bytes_scanned = 0 AND q.partitions_total > 0 THEN 0 ELSE 1 END) * 100, 1) AS cache_miss_pct,
        ROUND(SUM(CASE WHEN q.partitions_scanned >= q.partitions_total * 0.9 AND q.partitions_total > 10 THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(*), 0) * 100, 1) AS full_scan_pct,
        ROUND(SUM(CASE WHEN q.bytes_spilled_to_local_storage > 0 OR q.bytes_spilled_to_remote_storage > 0 THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(*), 0) * 100, 1) AS spill_pct,
        ROUND(SUM(CASE WHEN q.queued_overload_time > 0 THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(*), 0) * 100, 1) AS queue_pct
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY q
    WHERE q.start_time >= DATEADD(DAY, -14, CURRENT_DATE())
        AND q.warehouse_name IS NOT NULL
        AND q.execution_status = 'SUCCESS'
    GROUP BY q.warehouse_name
),
utilization AS (
    SELECT warehouse_name,
        ROUND(SUM(credits_used), 2) AS credits_14d,
        COUNT(DISTINCT DATE_TRUNC('hour', start_time)) AS active_hours,
        ROUND(COUNT(DISTINCT DATE_TRUNC('hour', start_time))::FLOAT / (14*24) * 100, 1) AS active_hour_pct
    FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
    WHERE start_time >= DATEADD(DAY, -14, CURRENT_DATE())
    GROUP BY warehouse_name
)
SELECT 
    w.warehouse_name,
    w.total_queries,
    u.credits_14d,
    u.active_hour_pct AS utilization_pct,
    w.cache_miss_pct,
    w.full_scan_pct,
    w.spill_pct,
    w.queue_pct,
    ROUND(GREATEST(0, 100 - (
        w.full_scan_pct * 0.3 +
        w.spill_pct * 0.25 +
        w.queue_pct * 0.2 +
        (100 - u.active_hour_pct) * 0.15 +
        w.cache_miss_pct * 0.1
    )), 0) AS efficiency_score
FROM warehouse_metrics w
JOIN utilization u ON w.warehouse_name = u.warehouse_name;

-- ============================================================
-- View: VW_WEEKLY_TRENDS
-- ============================================================
create or replace view VW_WEEKLY_TRENDS(
	WEEK_START,
	SERVICE_TYPE,
	CREDITS_USED
) as
SELECT
    DATE_TRUNC('week', start_time)::DATE AS week_start,
    service_type,
    ROUND(SUM(credits_used), 2) AS credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
WHERE start_time >= DATEADD(DAY, -180, CURRENT_DATE())
GROUP BY DATE_TRUNC('week', start_time), service_type;

-- ============================================================
-- END OF MIGRATION SCRIPT
-- ============================================================
