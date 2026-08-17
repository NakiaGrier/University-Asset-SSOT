USE University_Asset_SSOT;
GO

CREATE OR ALTER PROCEDURE dbo.sp_reconcile_endpoints
AS
BEGIN
    -- SET NOCOUNT ON prevents extra network messages from slowing down execution
    SET NOCOUNT ON;

    -- Step 1: Deduplicate our staging feeds using CTEs (Common Table Expressions)
    -- This handles the edge case where the same device might appear multiple times in a raw export.
    WITH CleanedIntune AS (
    SELECT
        [Serial number],
        [Device name],
        [Compliance],
        [OS],
        [OS version],
        [Primary user email address],
        [Manufacturer],
        [Model],
        [Azure AD Device ID],
        -- DEFENSIVE SORTING ENGINE:
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(UPPER([Serial number]))
            ORDER BY
                -- Rule 1: Float populated check-in dates to the top (1), NULLs to the bottom (0)
                CASE WHEN [Last check-in] IS NOT NULL AND [Last check-in] <> '' THEN 1 ELSE 0 END DESC,

                -- Rule 2: Sort by actual check-in date descending
                [Last check-in] DESC,

                -- Rule 3: Tie-breaker: Use the record that was ingested into our DB most recently
                [Ingested_At] DESC
        ) as rn
    FROM dbo.stg_intune_endpoints
    WHERE [Serial number] IS NOT NULL AND TRIM([Serial number]) <> ''
),
    CleanedSCCM AS (
    SELECT
        [Serial Number],
        [Name],
        [Primary User(s)],
        [Operating System],
        [Operating System Build],
        [Resource ID],
        -- DEFENSIVE SORTING ENGINE:
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(UPPER([Serial Number]))
            ORDER BY
                -- Rule 1: Float populated online times to the top (1), NULLs to the bottom (0)
                CASE WHEN [Last Online Time] IS NOT NULL AND [Last Online Time] <> '' THEN 1 ELSE 0 END DESC,

                -- Rule 2: Sort by actual online time descending
                [Last Online Time] DESC,

                -- Rule 3: Tie-breaker: Use the staging ingestion timestamp
                [Ingested_At] DESC
        ) as rn
    FROM dbo.stg_sccm_endpoints
    WHERE [Serial Number] IS NOT NULL AND TRIM([Serial Number]) <> ''
),
    UnifiedStaging AS (
        -- Step 2: Combine staging tables using a FULL OUTER JOIN on clean serial numbers
        -- and apply our priority-based Coalesce Strategy.
        SELECT
            COALESCE(TRIM(UPPER(i.[Serial number])), TRIM(UPPER(s.[Serial Number]))) AS ssot_serial_number,
            COALESCE(i.[Device name], s.[Name]) AS ssot_hostname,
            i.[Azure AD Device ID] AS azure_ad_device_id,
            s.[Resource ID] AS sccm_resource_id,
            i.[Manufacturer] AS hardware_manufacturer,
            i.[Model] AS hardware_model,
            COALESCE(i.[OS], s.[Operating System]) AS os_family,
            COALESCE(i.[OS version], s.[Operating System Build]) AS os_build_version,
            COALESCE(i.[Primary user email address], s.[Primary User(s)]) AS primary_user_email,
            CASE WHEN s.[Serial Number] IS NOT NULL THEN 1 ELSE 0 END AS in_sccm,
            CASE WHEN i.[Serial number] IS NOT NULL THEN 1 ELSE 0 END AS in_intune,
            i.[Compliance] AS compliance_status
        FROM CleanedIntune i
        FULL OUTER JOIN CleanedSCCM s
            ON TRIM(UPPER(i.[Serial number])) = TRIM(UPPER(s.[Serial Number]))
        -- Only grab the most active record for each device (Row #1)
        WHERE (i.rn = 1 OR i.rn IS NULL)
          AND (s.rn = 1 OR s.rn IS NULL)
    )

    -- Step 3: Run an Upsert (MERGE) to insert new devices or update existing ones
    MERGE dbo.dim_unified_endpoints AS Target
    USING UnifiedStaging AS Source
    ON (Target.ssot_serial_number = Source.ssot_serial_number)

    -- If the device exists, update its attributes with the freshest values
    WHEN MATCHED THEN
        UPDATE SET
            Target.ssot_hostname = Source.ssot_hostname,
            Target.azure_ad_device_id = Source.azure_ad_device_id,
            Target.sccm_resource_id = Source.sccm_resource_id,
            Target.hardware_manufacturer = Source.hardware_manufacturer,
            Target.hardware_model = Source.hardware_model,
            Target.os_family = Source.os_family,
            Target.os_build_version = Source.os_build_version,
            Target.primary_user_email = Source.primary_user_email,
            Target.in_sccm = Source.in_sccm,
            Target.in_intune = Source.in_intune,
            Target.compliance_status = Source.compliance_status,
            Target.modified_date = GETDATE()

    -- If it's a brand new device, insert a clean new record
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (
            ssot_serial_number,
            ssot_hostname,
            azure_ad_device_id,
            sccm_resource_id,
            hardware_manufacturer,
            hardware_model,
            os_family,
            os_build_version,
            primary_user_email,
            in_sccm,
            in_intune,
            compliance_status
        )
        VALUES (
            Source.ssot_serial_number,
            Source.ssot_hostname,
            Source.azure_ad_device_id,
            Source.sccm_resource_id,
            Source.hardware_manufacturer,
            Source.hardware_model,
            Source.os_family,
            Source.os_build_version,
            Source.primary_user_email,
            Source.in_sccm,
            Source.in_intune,
            Source.compliance_status
        );

    print 'SSOT Reconciliation Process Completed Successfully!';
END;
GO

EXEC dbo.sp_reconcile_endpoints;
