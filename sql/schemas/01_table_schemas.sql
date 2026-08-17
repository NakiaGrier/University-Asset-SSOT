IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'University_Asset_SSOT')
BEGIN
    CREATE DATABASE University_Asset_SSOT;
END
GO

USE University_Asset_SSOT;
GO

-- =========================================================================
-- 1. STAGING LAYER (Safe Landing Zone for Raw CSV Ingestion)
-- =========================================================================

-- Staging table for Intune Exports
IF OBJECT_ID('dbo.stg_intune_endpoints', 'U') IS NOT NULL
    DROP TABLE dbo.stg_intune_endpoints;
GO

CREATE TABLE dbo.stg_intune_endpoints (
    [Device ID] VARCHAR(255) NULL,
    [Device name] VARCHAR(255) NULL,
    [Compliance] VARCHAR(100) NULL,
    [OS] VARCHAR(100) NULL,
    [OS version] VARCHAR(100) NULL,
    [Primary user email address] VARCHAR(255) NULL,
    [Last check-in] VARCHAR(100) NULL,
    [Model] VARCHAR(255) NULL,
    [Manufacturer] VARCHAR(255) NULL,
    [Serial number] VARCHAR(255) NULL, -- Raw Serial Key
    [Azure AD Device ID] VARCHAR(255) NULL,
    [Ingested_At] DATETIME DEFAULT GETDATE()
);
GO

-- Staging table for SCCM Exports
IF OBJECT_ID('dbo.stg_sccm_endpoints', 'U') IS NOT NULL
    DROP TABLE dbo.stg_sccm_endpoints;
GO

CREATE TABLE dbo.stg_sccm_endpoints (
    [Name] VARCHAR(255) NULL,
    [Primary User(s)] VARCHAR(255) NULL,
    [Currently Logged on User] VARCHAR(255) NULL,
    [Client Activity] VARCHAR(100) NULL,
    [Last Online Time] VARCHAR(100) NULL,
    [Operating System] VARCHAR(255) NULL,
    [Operating System Build] VARCHAR(100) NULL,
    [Resource ID] INT NULL,
    [Serial Number] VARCHAR(255) NULL, -- Raw Serial Key
    [Ingested_At] DATETIME DEFAULT GETDATE()
);
GO


-- =========================================================================
-- 2. PRODUCTION SSOT LAYER (Clean, Unified Star-Schema Dimension)
-- =========================================================================

IF OBJECT_ID('dbo.dim_unified_endpoints', 'U') IS NOT NULL
    DROP TABLE dbo.dim_unified_endpoints;
GO

CREATE TABLE dbo.dim_unified_endpoints (
    -- Surrogate Key (Primary Key for Power BI relationships)
    [ssot_device_key] INT IDENTITY(1,1) PRIMARY KEY,

    -- Natural Keys & Standardized Identifiers
    [ssot_serial_number] VARCHAR(255) NOT NULL UNIQUE,
    [ssot_hostname] VARCHAR(255) NOT NULL,
    [azure_ad_device_id] VARCHAR(255) NULL,
    [sccm_resource_id] INT NULL,

    -- Hardware Attributes
    [hardware_manufacturer] VARCHAR(100) NULL,
    [hardware_model] VARCHAR(255) NULL,

    -- Operating System Status
    [os_family] VARCHAR(100) NULL,
    [os_build_version] VARCHAR(100) NULL,

    -- Directory & Identity Attributes
    [primary_user_email] VARCHAR(255) NULL,

    -- Integration Audit Indicators
    [in_sccm] BIT NOT NULL DEFAULT 0,
    [in_intune] BIT NOT NULL DEFAULT 0,
    [compliance_status] VARCHAR(100) NULL,
    [last_seen_date] DATETIME NULL,
    [modified_date] DATETIME DEFAULT GETDATE()
);
GO
