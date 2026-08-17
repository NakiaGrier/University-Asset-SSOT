# src/ingestion/load_staging.py
import os
import sys
import urllib
import pandas as pd
from sqlalchemy import create_engine

# Prevent terminal encoding issues on Windows
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8')

# --- CONFIGURATION CONFIG ---
# Replace 'localhost\\SQLEXPRESS' with your SSMS server name if different!
SERVER_NAME = r'(localdb)\MSSQLLocalDB'
DATABASE_NAME = 'University_Asset_SSOT'
SCCM_FILE = 'data/raw/SCCM.csv'
INTUNE_FILE = 'data/raw/Intune.csv'


def get_sql_engine(server, database):
    """Generates a secure SQL Alchemy connection engine for SQL Server."""
    params = urllib.parse.quote_plus(
        f"DRIVER={{ODBC Driver 17 for SQL Server}};"
        f"SERVER={server};"
        f"DATABASE={database};"
        f"Trusted_Connection=yes;"  # Uses your active Windows Credentials
    )
    return create_engine(f"mssql+pyodbc:///?odbc_connect={params}")


def load_csv_to_staging():
    print("[START] Connecting to SQL Server and preparing staging load...")
    engine = get_sql_engine(SERVER_NAME, DATABASE_NAME)

    # 1. Load and Profile SCCM Data
    if os.path.exists(SCCM_FILE):
        print("\nIngesting SCCM raw data...")
        try:
            sccm_df = pd.read_csv(SCCM_FILE)
        except UnicodeDecodeError:
            sccm_df = pd.read_csv(SCCM_FILE, encoding='cp1252')

        # Truncate existing staging table and load clean records
        # 'replace' automatically drops/recreates or truncates if schema matches
        # We append so we don't destroy custom DDL, but we clean it manually first
        with engine.begin() as conn:
            conn.exec_driver_sql("TRUNCATE TABLE dbo.stg_sccm_endpoints;")

        # Write to SQL
        sccm_df.to_sql('stg_sccm_endpoints', con=engine,
                       if_exists='append', index=False)
        print(
            f" -> Successfully loaded {len(sccm_df)} rows into dbo.stg_sccm_endpoints.")
    else:
        print(f"⚠️ SCCM file not found at {SCCM_FILE}. Skipping.")

    # 2. Load and Profile Intune Data
    if os.path.exists(INTUNE_FILE):
        print("\nIngesting Intune raw data...")
        try:
            intune_df = pd.read_csv(INTUNE_FILE)
        except UnicodeDecodeError:
            intune_df = pd.read_csv(INTUNE_FILE, encoding='cp1252')

        with engine.begin() as conn:
            conn.exec_driver_sql("TRUNCATE TABLE dbo.stg_intune_endpoints;")

        # Write to SQL
        intune_df.to_sql('stg_intune_endpoints', con=engine,
                         if_exists='append', index=False)
        print(
            f" -> Successfully loaded {len(intune_df)} rows into dbo.stg_intune_endpoints.")
    else:
        print(f"⚠️ Intune file not found at {INTUNE_FILE}. Skipping.")

    print("\n[SUCCESS] Staging load execution complete!")


if __name__ == "__main__":
    load_csv_to_staging()
