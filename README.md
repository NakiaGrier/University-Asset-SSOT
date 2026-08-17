🚀 University Endpoint Asset Management Single Source of Truth (SSOT)
An enterprise-grade, automated ELT (Extract, Load, Transform) data integration pipeline and interactive compliance dashboard. This project integrates disparate endpoint management tools (Microsoft SCCM and Microsoft Intune) into a centralized Microsoft SQL Server database, resolving identity conflicts, establishing hardware-matching logic, and delivering real-time executive-level analytics in Power BI.

📊 High-Level Pipeline Architecture
  [ Raw Data Exports ]             [ Local SQL Database ]               [ Analytics Layer ]
  +------------------+             +--------------------+               +-----------------+
  |  Intune (CSV)    | --[Python]-->| stg_intune_status  |               |                 |
  +------------------+   (pyodbc)  +--------------------+               |                 |
                                             |                          |   Power BI      |
                                     (Stored Procedure) --[SQL View]--> |   Dashboard     |
                                             |                          |  (Import Mode)  |
  +------------------+   (pyodbc)  +--------------------+               |                 |
  |  SCCM (CSV)      | --[Python]-->| stg_sccm_status    |               |                 |
  +------------------+             +--------------------+               +-----------------+
                                             |
                                             v
                                   +--------------------+
                                   | dim_unified_assets |  <-- Coalesced, Deduplicated
                                   +--------------------+
🛠️ Technology Stack
Database Engine: Microsoft SQL Server (SSMS) & T-SQL
Data Pipeline Engine: Python 3 (Pandas, SQLAlchemy, pyodbc)
Business Intelligence: Power BI Desktop (DAX, Import Mode modeling)
Version Control & Documentation: Git, GitHub, Markdown (Operations Runbook)
🔑 Core Features & Business Logic
1. Robust Multi-Source Ingestion (Python)
A defensive Python ingestion script handles legacy Windows-1252 (ANSI) and UTF-8 encoding variations from source file exports on Windows. The script truncates staging tables on each run and executes high-speed bulk inserts into the staging layer (stg_).

2. Defensive Deduplication & Priority Coalescing (T-SQL)
Deduplication: A SQL window function (ROW_NUMBER() OVER (PARTITION BY Serial Number ORDER BY CheckIn DESC)) identifies duplicate records within a single source and ranks active machines first. It implements a fallback tie-breaker sorting routine to gracefully handle records with NULL or missing check-in timestamps.
Entity Resolution: Uses a FULL OUTER JOIN on cleaned, uppercase, space-stripped serial numbers to bridge systems.
The Coalesce Strategy: Merges duplicate attributes across systems into a single target field. It prioritizes modern cloud-managed Intune values for attributes like hostnames and user emails, falling back to legacy SCCM properties if Intune data is absent.
3. Star-Schema Analytical Modeling (SQL Views & DAX)
The database exposes a clean reporting view (vw_powerbi_unified_endpoints) acting as a semantic translation layer for Power BI. This view shifts heavy row-level logic (like CASE statements for management state and unassigned flags) to the SQL database engine, protecting Power BI dashboard memory limits.

📁 Repository Directory Structure
University-Asset-SSOT/
├── .vscode/               # VS Code workspace settings (autopep8, formatting)
├── data/
│   ├── raw/               # Unmodified SCCM and Intune CSV exports (Git ignored)
│   ├── processed/         # Python matched & coalesced CSV backups
│   └── metadata/          # Data dictionaries and Source-to-Target Maps (STM)
├── src/
│   ├── ingestion/         # Python CSV loader scripts
│   └── matching/          # Local matching and data profiling routines
├── sql/
│   ├── schemas/           # Database DDL staging and dimension table schemas
│   └── views/             # Production database views for BI reporting
├── docs/
│   └── operations-runbook.md  # Step-by-step IT deployment and playbook manual
├── .gitignore             # Prevents confidential device lists from leaking to GitHub
└── README.md              # Project executive summary and guide
🚀 Getting Started
Configure local workspace: Open VS Code inside the project directory. Install the autopep8 extension for style formatting.
Run SQL schemas: Execute the DDL script in SQL Server Management Studio (SSMS) to create staging, dimension, and reporting view objects.
Deploy code dependencies:
pip install pandas sqlalchemy pyodbc openpyxl
Populate Staging: Drop your raw files into data/raw/ (naming them SCCM.csv and Intune.csv), configure your local server parameter in src/ingestion/load_staging.py, and run the script.
Reconcile Inventory: Run EXEC dbo.sp_reconcile_endpoints; in SSMS to execute the ELT engine.
Load Reporting View: Open Power BI Desktop, connect to your local localhost\SQLEXPRESS SQL Server, and import dbo.vw_powerbi_unified_endpoints.
