# src/matching/merge_assets.py
import os
import sys
import pandas as pd

# Standardize Windows Terminal output
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8')

# Define file paths within our workspace structure
SCCM_PATH = "data/raw/SCCM.csv"
INTUNE_PATH = "data/raw/Intune.csv"
OUTPUT_PATH = "data/processed/unified_endpoints.csv"


def run_asset_reconciliation():
    print("[START] Beginning multi-source endpoint matching engine...")

    # 1. Verify files exist before loading
    if not os.path.exists(SCCM_PATH) or not os.path.exists(INTUNE_PATH):
        print("❌ Error: Missing raw source files in 'data/raw/'.")
        print("Please ensure your exports are named exactly 'SCCM.csv' and 'Intune.csv'.")
        return

    # 2. Ingest raw datasets with fallback encodings
    try:
        sccm_df = pd.read_csv(SCCM_PATH)
    except UnicodeDecodeError:
        sccm_df = pd.read_csv(SCCM_PATH, encoding='cp1252')

    try:
        intune_df = pd.read_csv(INTUNE_PATH)
    except UnicodeDecodeError:
        intune_df = pd.read_csv(INTUNE_PATH, encoding='cp1252')

    print(
        f" -> Successfully loaded SCCM ({len(sccm_df)} records) and Intune ({len(intune_df)} records).")

    # 3. Clean and standardize Serial Numbers (strip spaces and force uppercase)
    sccm_df['clean_serial'] = sccm_df['Serial Number'].astype(
        str).str.strip().str.upper()
    intune_df['clean_serial'] = intune_df['Serial number'].astype(
        str).str.strip().str.upper()

    # 4. Perform an Outer Join to capture all records from both systems
    merged = pd.merge(
        sccm_df,
        intune_df,
        on='clean_serial',
        how='outer',
        suffixes=('_sccm', '_intune'),
        indicator=True
    )

    # 5. Build our SSOT fields using a Coalesce strategy (preferring Intune for cloud-native fields)
    unified_records = []
    for _, row in merged.iterrows():
        # Coalesce Hostname
        hostname = row['Device name'] if pd.notna(
            row['Device name']) else row['Name']

        # Coalesce OS Name
        os_name = row['OS'] if pd.notna(row['OS']) else row['Operating System']

        # Coalesce User
        user = row['Primary user email address'] if pd.notna(
            row['Primary user email address']) else row['Primary User(s)']

        unified_records.append({
            "ssot_serial_number": row['clean_serial'],
            "ssot_hostname": hostname,
            "ssot_os_name": os_name,
            "ssot_primary_user": user,
            "in_sccm": 1 if row['_merge'] in ['left_only', 'both'] else 0,
            "in_intune": 1 if row['_merge'] in ['right_only', 'both'] else 0,
            "match_status": "Co-Managed" if row['_merge'] == 'both' else ("SCCM-Only" if row['_merge'] == 'left_only' else "Intune-Only")
        })

    # Save processed SSOT table
    unified_df = pd.DataFrame(unified_records)
    os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
    unified_df.to_csv(OUTPUT_PATH, index=False)

    # 6. Output profiling statistics
    print("\n--- 📈 Reconciliation Statistics ---")
    print(unified_df['match_status'].value_counts())
    print(f"\n[SUCCESS] Unified SSOT table saved to: {OUTPUT_PATH}")


if __name__ == "__main__":
    run_asset_reconciliation()
