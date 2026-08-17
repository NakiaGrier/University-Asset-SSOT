University Asset Management SSOT - Operations Runbook
Unified Endpoint Reconciliation & Reporting Pipeline Version: 1.0.0 Last Updated: August 2026

Table of Contents
Executive Summary & Architecture Overview
Workspace Directory Structure
Data Dictionary & Source-to-Target Mapping (STM)
Staging & Ingestion Layer (Python Engine)
Reconciliation & Deduplication Engine (SQL Server)
Semantic Reporting Layer (Power BI View)
Power BI Dashboard Layout & DAX Measures
Maintenance, Troubleshooting, and Recovery Playbooks
1. Executive Summary & Architecture Overview
This runbook documents the operational architecture and nightly execution pipeline for the University Endpoint Asset Management Single Source of Truth (SSOT). The goal of this system is to combine disparate campus hardware directories—specifically legacy Microsoft System Center Configuration Manager (SCCM) and modern cloud-native Microsoft Intune—into a unified, deduplicated, and audited database schema [2, 14]. This unified data model directly feeds an interactive executive dashboard designed to track cloud migration progress, monitor security compliance, and resolve physical inventory gaps [2, 7].

End-to-End Pipeline Dataflow
+-----------------------+      +-----------------------+
|  Raw Intune CSV Feed  |      |   Raw SCCM CSV Feed   |
| (data/raw/Intune.csv) |      | (data/raw/SCCM.csv)   |
+-----------+-----------+      +-----------+-----------+
            |                              |
            |   [1. Ingest / load_staging.py]
            v                              v
+-----------------------+      +-----------------------+
| dbo.stg_intune_end... |      | dbo.stg_sccm_endpoints| (Staging Layer)
+-----------+-----------+      +-----------+-----------+
            |                              |
            +---------------+--------------+
                            |
                            |   [2. Reconcile / sp_reconcile_endpoints]
                            v
               +---------------------------+
               | dbo.dim_unified_endpoints | (SSOT Production Table)
               +-------------+-------------+
                             |
                             |   [3. Present / vw_powerbi_unified_endpoints]
                             v
               +---------------------------+
               | dbo.vw_powerbi_endpoints  | (Semantic Reporting View)
               +-------------+-------------+
                             |
                             |   [4. Import / Direct Refresh]
                             v
               +---------------------------+
               |     Power BI Dashboard    | (Executive & Operational KPIs)
               +---------------------------+
This pipeline follows the 5-Stage Data Integration Lifecycle [8, 15, 22]:

Profiling & Mapping: Extracting column headers and establishing Source-to-Target mappings [8, 15, 22].
System Architecture: Setting up local database tables and script hierarchies [15, 22].
Data Engine & SQL: Building staging schemas, Python load modules, and T-SQL upsert rules [8, 15, 22].
Testing & Audit: Executing data-quality checks, duplicate rankings, and baseline drift metrics [15, 22].
Reporting & Operations: Powering Power BI canvas components and maintaining system runbooks [15, 22].
2. Workspace Directory Structure
To maintain clean code governance and isolate production code from sensitive institutional data, the local project repository is structured as follows [7, 13]:

University-Asset-SSOT/
├── .vscode/                   # Local editor configurations (autopep8 style policies)
├── data/                      # Data storage (Blocked from Git tracking via .gitignore)
│   ├── raw/                   # Immutable landing zone for daily SCCM.csv and Intune.csv
│   ├── processed/             # Offline flat file outputs (unified_endpoints.csv)
│   └── metadata/              # Schema dictionaries (stm_starter_dictionary.csv)
├── src/                       # Python ETL source code
│   ├── ingestion/             # Load scripts (profile_headers.py, load_staging.py)
│   ├── cleaning/              # Text standardization and character sanitization rules
│   └── matching/              # Offline reconciliation scripts (merge_assets.py)
├── sql/                       # SQL Database Assets
│   ├── schemas/               # Table generation DDL scripts
│   └── views/                 # Stored procedures and reporting views
├── docs/                      # Operations runbooks and user documentation
├── .gitignore                 # Active security block file (protects raw files from public repos)
└── README.md                  # Main developer and repository introduction manual
3. Data Dictionary & Source-to-Target Mapping (STM)
The following Source-to-Target Mapping (STM) defines how unmapped columns from our source CSV exports [41] map to our unified dbo.dim_unified_endpoints destination table:

Source File	Source Field	Target SSOT Column	SSOT Data Type	Resolution Strategy / Priority
Intune.csv	Serial number	ssot_serial_number	VARCHAR(255)	Primary Key Join Indicator. Standardized to uppercase, spaces stripped [41].
SCCM.csv	Serial Number	ssot_serial_number	VARCHAR(255)	Primary Key Join Indicator. Standardized to uppercase, spaces stripped [41].
Intune.csv	Device name	ssot_hostname	VARCHAR(255)	COALESCE (Priority 1): Selected first if non-null [41].
SCCM.csv	Name	ssot_hostname	VARCHAR(255)	COALESCE (Priority 2): Fallback if Intune is null [41].
Intune.csv	Azure AD Device ID	azure_ad_device_id	VARCHAR(255)	Retained directly from Intune source [41].
SCCM.csv	Resource ID	sccm_resource_id	INT	Retained directly from SCCM source [41].
Intune.csv	Manufacturer	hardware_manufacturer	VARCHAR(100)	Retained directly from Intune source [41].
Intune.csv	Model	hardware_model	VARCHAR(255)	Retained directly from Intune source [41].
Intune.csv	OS	os_family	VARCHAR(100)	COALESCE (Priority 1): Selected first if non-null [41].
SCCM.csv	Operating System	os_family	VARCHAR(100)	COALESCE (Priority 2): Fallback if Intune is null [41].
Intune.csv	OS version	os_build_version	VARCHAR(100)	COALESCE (Priority 1): Selected first if non-null [41].
SCCM.csv	Operating System Build	os_build_version	VARCHAR(100)	COALESCE (Priority 2): Fallback if Intune is null [41].
Intune.csv	Primary user email address	primary_user_email	VARCHAR(255)	COALESCE (Priority 1): Selected first if non-null [41].
SCCM.csv	Primary User(s)	primary_user_email	VARCHAR(255)	COALESCE (Priority 2): Fallback if Intune is null [41].
Intune.csv	Compliance	compliance_status	VARCHAR(100)	Retained directly from Intune source [41].
4. Staging & Ingestion Layer (Python Engine)
We leverage an ELT (Extract, Load, Transform) pattern. The raw file inputs are left unmodified to ensure complete operational auditability. The Python module src/ingestion/load_staging.py runs nightly to pull CSV exports and append them directly to the database staging layer.

# src/ingestion/load_staging.py
import os
import sys
import urllib
import pandas as pd
from sqlalchemy import create_engine

if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8')

SERVER_NAME = r'localhost\SQLEXPRESS'
DATABASE_NAME = 'University_Asset_SSOT'
SCCM_FILE = 'data/raw/SCCM.csv'
INTUNE_FILE = 'data/raw/Intune.csv'

def get_sql_engine(server, database):
    params = urllib.parse.quote_plus(
        f"DRIVER={{ODBC Driver 17 for SQL Server}};"
        f"SERVER={server};"
        f"DATABASE={database};"
        f"Trusted_Connection=yes;"
    )
    return create_engine(f"mssql+pyodbc:///?odbc_connect={params}")

def load_csv_to_staging():
    print("[START] Connecting to SQL Server staging tables...")
    engine = get_sql_engine(SERVER_NAME, DATABASE_NAME)

    # Ingest SCCM
    if os.path.exists(SCCM_FILE):
        try:
            sccm_df = pd.read_csv(SCCM_FILE)
        except UnicodeDecodeError:
            sccm_df = pd.read_csv(SCCM_FILE, encoding='cp1252')

        with engine.begin() as conn:
            conn.exec_driver_sql("TRUNCATE TABLE dbo.stg_sccm_endpoints;")
        sccm_df.to_sql('stg_sccm_endpoints', con=engine, if_exists='append', index=False)
        print(f" -> Successfully loaded {len(sccm_df)} rows into dbo.stg_sccm_endpoints.")

    # Ingest Intune
    if os.path.exists(INTUNE_FILE):
        try:
            intune_df = pd.read_csv(INTUNE_FILE)
        except UnicodeDecodeError:
            intune_df = pd.read_csv(INTUNE_FILE, encoding='cp1252')

        with engine.begin() as conn:
            conn.exec_driver_sql("TRUNCATE TABLE dbo.stg_intune_endpoints;")
        intune_df.to_sql('stg_intune_endpoints', con=engine, if_exists='append', index=False)
        print(f" -> Successfully loaded {len(intune_df)} rows into dbo.stg_intune_endpoints.")

if __name__ == "__main__":
    load_csv_to_staging()
5. Reconciliation & Deduplication Engine (SQL Server)
After staging tables are populated, our core transformation is executed via SQL Server using sp_reconcile_endpoints. This stored procedure handles crucial data-cleaning, deduplication, and integration requirements:

Deduplication: We partition the staging datasets by serial number and rank them via a Window Function (ROW_NUMBER()). If duplicate serial entries exist, the newest check-in is selected.
Defensive Missing Dates: If Last check-in or Last Online Time is null, the sorting engine uses CASE checks to float active records with valid timestamps to the top, utilizing Ingested_At as a deterministic tie-breaker.
Upsert Operations: We execute a T-SQL MERGE statement. If a record with a matching serial number exists in production, its details are updated. If it is a new device, a new surrogate key and record are created.
-- Executing the reconciliation routine
USE University_Asset_SSOT;
GO

EXEC dbo.sp_reconcile_endpoints;
GO
6. Reporting Layer & Semantic View
Power BI does not query the physical storage table directly. Instead, we use dbo.vw_powerbi_unified_endpoints as a semantic gateway. This pushes complex, resource-heavy calculations (like string concatenation and nested conditional checks) leftward to the SQL Server database engine.

USE University_Asset_SSOT;
GO

CREATE OR ALTER VIEW dbo.vw_powerbi_unified_endpoints
AS
SELECT
    [ssot_device_key],
    [ssot_serial_number],
    [ssot_hostname],
    [azure_ad_device_id],
    [sccm_resource_id],
    [hardware_manufacturer],
    [hardware_model],
    [os_family],
    [os_build_version],
    COALESCE([primary_user_email], 'unassigned@columbusstate.edu') AS [primary_user_email],
    [in_sccm],
    [in_intune],
    CASE
        WHEN [in_sccm] = 1 AND [in_intune] = 1 THEN 'Co-Managed (Both)'
        WHEN [in_sccm] = 1 AND [in_intune] = 0 THEN 'SCCM-Only (Legacy)'
        WHEN [in_sccm] = 0 AND [in_intune] = 1 THEN 'Intune-Only (Cloud)'
        ELSE 'Orphaned/Stale'
    END AS [management_state],
    CASE
        WHEN [primary_user_email] IS NULL OR TRIM([primary_user_email]) = '' THEN 'Unassigned Device'
        ELSE 'Assigned to User'
    END AS [identity_assignment_status],
    COALESCE([compliance_status], 'Unknown/Not Enrolled') AS [clean_compliance_status],
    [modified_date] AS [last_sync_timestamp]
FROM dbo.dim_unified_endpoints;
GO
7. Power BI Dashboard Layout & DAX Measures
Power BI Connection Rules
Connection Mode: Import Mode is utilized to leverage local memory caching, yielding up to a 10x compression ratio on inventory strings and instant on-screen slice actions.
Credentials: Windows Integrated Authentication (Trusted_Connection=yes) is used to completely eliminate the risk of hardcoding database passwords in our reporting layer.
Core DAX Calculations
These formulas must be entered into the Power BI dataset to compute our executive KPIs:

Total Endpoints = COUNTROWS('vw_powerbi_unified_endpoints')

Modern Management Rate =
DIVIDE(
    CALCULATE(
        COUNTROWS('vw_powerbi_unified_endpoints'),
        'vw_powerbi_unified_endpoints'[management_state] IN {"Intune-Only (Cloud)", "Co-Managed (Both)"}
    ),
    [Total Endpoints],
    0
)

OS Compliance Rate =
DIVIDE(
    CALCULATE(
        COUNTROWS('vw_powerbi_unified_endpoints'),
        'vw_powerbi_unified_endpoints'[clean_compliance_status] = "Compliant"
    ),
    [Total Endpoints],
    0
)

Unassigned Devices Count =
CALCULATE(
    COUNTROWS('vw_powerbi_unified_endpoints'),
    'vw_powerbi_unified_endpoints'[identity_assignment_status] = "Unassigned Device"
)

Last Sync Display =
VAR LatestSync = MAX('vw_powerbi_unified_endpoints'[last_sync_timestamp])
RETURN
    IF(
        ISBLANK(LatestSync),
        "Last Sync: Unknown",
        "Last Sync: " & FORMAT(LatestSync, "yyyy-mm-dd hh:nn AM/PM")
    )
8. Maintenance, Troubleshooting, and Recovery Playbooks
Playbook A: Troubleshooting Pipeline Ingestion Failure
Symptom: Python load script crashes with UnicodeEncodeError or ModuleNotFoundError: No module named 'pandas'.
Resolution Steps:
Open a terminal in the project directory and verify the package dependencies are fully met:
pip install pandas openpyxl sqlalchemy pyodbc
If raw CSV files contain modern UTF-8 accents or emojis, ensure your scripts invoke sys.stdout.reconfigure(encoding='utf-8') to prevent Windows terminal character mapping crashes.
Verify raw files exist in data/raw/ and are named exactly SCCM.csv and Intune.csv.
Playbook B: Managing Local SQL Server Instance Connection Gaps
Symptom: Python throws connection timeout errors or OperationalError: (pyodbc.Error) ('08001'...).
Resolution Steps:
Press Win + R, type services.msc, and press Enter. Verify that the SQL Server (SQLEXPRESS) service is running.
Confirm your server named instance in load_staging.py aligns with your active SQL Server instance:
Standard SQL Express: localhost\SQLEXPRESS
Developer Edition / Default: localhost
Ensure the ODBC Driver is installed. If your workstation lacks ODBC Driver 17 for SQL Server, download it from Microsoft or update your python engine setup to reference Driver 18.
Playbook C: Resolving Blank or Missing Check-In Times
Symptom: Duplicate entries are appearing in production or the Power BI dashboard displays unexpected device quantities due to sorting failures on missing check-in dates.
Resolution Steps:
Open SSMS and run the validation scripts in Section 5 of this manual.
Ensure the order of fallback criteria inside the ROW_NUMBER() OVER (...) window function remains active:
ORDER BY
    CASE WHEN [Last check-in] IS NOT NULL AND [Last check-in] <> '' THEN 1 ELSE 0 END DESC,
    [Last check-in] DESC,
    [Ingested_At] DESC
This strictly forces empty records to sort last, resolving duplicates using the ingestion order tie-breaker without failing.
