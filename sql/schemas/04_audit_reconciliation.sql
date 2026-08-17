USE University_Asset_SSOT;
GO

-- =========================================================================
-- AUDIT RUN: SSOT FLEET INTEGRITY & RECONCILIATION REPORT
-- Run this script to verify pipeline execution health and data quality.
-- =========================================================================

PRINT '=========================================================================';
PRINT '                  1. FLEET MANAGEMENT STATE ANALYSIS                     ';
PRINT '=========================================================================';
-- Calculates the active reconciliation status of our campus fleet.
-- This serves as the direct source of truth for our Power BI donut visuals.
SELECT
    CASE
        WHEN in_sccm = 1 AND in_intune = 1 THEN 'Co-Managed (Both)'
        WHEN in_sccm = 1 AND in_intune = 0 THEN 'SCCM-Only (Legacy)'
        WHEN in_sccm = 0 AND in_intune = 1 THEN 'Intune-Only (Cloud)'
        ELSE 'Orphaned/Error State'
    END AS [management_state],
    COUNT(*) AS [device_count],
    CAST(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() AS DECIMAL(5,2)) AS [percentage_of_fleet]
FROM dbo.dim_unified_endpoints
GROUP BY in_sccm, in_intune;


PRINT '=========================================================================';
PRINT '                  2. DATA INTEGRITY & GAP IDENTIFICATION                 ';
PRINT '=========================================================================';
-- Flags critical pipeline gaps. In a healthy production SSOT,
-- missing serials and hostnames should always read 0.
SELECT
    COUNT(*) AS [total_reconciled_assets],

    -- Serial Number Gap Check
    SUM(CASE WHEN ssot_serial_number IS NULL OR TRIM(ssot_serial_number) = '' THEN 1 ELSE 0 END) AS [missing_serial_numbers],

    -- Hostname Gap Check
    SUM(CASE WHEN ssot_hostname IS NULL OR TRIM(ssot_hostname) = '' THEN 1 ELSE 0 END) AS [missing_hostnames],

    -- Primary User Association Gap Check
    SUM(CASE WHEN primary_user_email IS NULL THEN 1 ELSE 0 END) AS [unassigned_devices_count],

    -- Calculate User Association Completeness as a clear percentage
    CAST(
        (SUM(CASE WHEN primary_user_email IS NOT NULL AND primary_user_email <> 'unassigned@columbusstate.edu' THEN 1 ELSE 0 END) * 100.0)
        / COUNT(*) AS DECIMAL(5,2)
    ) AS [user_association_completeness_rate]
FROM dbo.dim_unified_endpoints;


PRINT '=========================================================================';
PRINT '                  3. DEVICE AGING & SILENCE AUDIT                        ';
PRINT '=========================================================================';
-- Flags devices that haven't been synchronized or updated within our
-- target SLAs. This targets systems that may be physically lost or decommissioned.
SELECT
    ssot_hostname,
    ssot_serial_number,
    primary_user_email,
    CASE
        WHEN in_sccm = 1 AND in_intune = 0 THEN 'SCCM'
        WHEN in_sccm = 0 AND in_intune = 1 THEN 'Intune'
        ELSE 'Co-Managed'
    END AS [primary_source],
    modified_date AS [last_reconciled_timestamp],
    DATEDIFF(day, modified_date, GETDATE()) AS [days_since_pipeline_sync]
FROM dbo.dim_unified_endpoints
-- Flag anything that hasn't synced through our staging tables in over 7 days
WHERE DATEDIFF(day, modified_date, GETDATE()) > 7;
