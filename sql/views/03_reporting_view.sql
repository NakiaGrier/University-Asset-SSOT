USE University_Asset_SSOT;
GO

-- Create the reporting view optimized for direct Power BI Import Mode
CREATE OR ALTER VIEW dbo.vw_powerbi_unified_endpoints
AS
SELECT
    -- 1. Keys & Identifiers (For relationships and details)
    [ssot_device_key],
    [ssot_serial_number],
    [ssot_hostname],
    [azure_ad_device_id],
    [sccm_resource_id],

    -- 2. Device Attributes
    [hardware_manufacturer],
    [hardware_model],
    [os_family],
    [os_build_version],

    -- 3. Identity Alignment
    COALESCE([primary_user_email], 'unassigned@columbusstate.edu') AS [primary_user_email],

    -- 4. Ingestion Traceability Flags
    [in_sccm],
    [in_intune],

    -- 5. PRE-CALCULATED BUSINESS LOGIC (Pushing complexity left)

    -- Unified Management Category
    CASE
        WHEN [in_sccm] = 1 AND [in_intune] = 1 THEN 'Co-Managed (Both)'
        WHEN [in_sccm] = 1 AND [in_intune] = 0 THEN 'SCCM-Only (Legacy)'
        WHEN [in_sccm] = 0 AND [in_intune] = 1 THEN 'Intune-Only (Cloud)'
        ELSE 'Orphaned/Stale'
    END AS [management_state],

    -- Identity Completeness Flag
    CASE
        WHEN [primary_user_email] IS NULL OR TRIM([primary_user_email]) = '' THEN 'Unassigned Device'
        ELSE 'Assigned to User'
    END AS [identity_assignment_status],

    -- Standardized Compliance Status
    COALESCE([compliance_status], 'Unknown/Not Enrolled') AS [clean_compliance_status],

    -- System Age Audit Flag (Simulated example)
    [modified_date] AS [last_sync_timestamp]
FROM dbo.dim_unified_endpoints;
GO
