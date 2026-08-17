# src/ingestion/profile_headers.py
import os
import sys
import pandas as pd

# Prevent terminal encoding issues on Windows
if sys.platform == "win32":
    sys.stdout.reconfigure(encoding='utf-8')

RAW_DIR = "data/raw"
METADATA_DIR = "data/metadata"


def profile_raw_exports():
    print("[START] Scanning raw data folder for SCCM and Intune exports...")

    # Check if the raw directory exists
    if not os.path.exists(RAW_DIR):
        print(
            f"❌ Error: The directory '{RAW_DIR}' does not exist. Please run setup_folders.py first.")
        return

    # List all files in the raw folder
    files = [f for f in os.listdir(RAW_DIR) if f.endswith(
        '.csv') or f.endswith('.xlsx')]

    if not files:
        print(
            f"⚠️ No files found in '{RAW_DIR}'. Please drop your SCCM and Intune CSV/Excel exports there!")
        return

    print(f"👉 Detected {len(files)} file(s) in raw storage.")

    # We will compile a summary of all schemas found
    schema_summary = []

    for file in files:
        file_path = os.path.join(RAW_DIR, file)
        print(f"\nProcessing: {file}")

        try:
            # Handle encoding defensively; university exports often use UTF-16 or Windows-1252
            if file.endswith('.csv'):
                # Try UTF-8 first, fallback to ANSI if it fails
                try:
                    df = pd.read_csv(file_path, nrows=5)
                except UnicodeDecodeError:
                    df = pd.read_csv(file_path, nrows=5, encoding='cp1252')
            else:
                df = pd.read_excel(file_path, nrows=5)

            columns = list(df.columns)
            print(f" -> Found {len(columns)} columns.")

            # Save metadata for this file
            for col in columns:
                schema_summary.append({
                    "Source_File": file,
                    "Source_Column": col,
                    "Target_SSOT_Field": "UNMAPPED",  # To be filled during schema mapping
                    "Data_Type": str(df[col].dtype),
                    "Sample_Value": str(df[col].iloc) if len(df) > 0 else "NULL"
                })

        except Exception as e:
            print(f" ❌ Failed to read {file}. Error: {str(e)}")

    # Write the compiled schema spreadsheet to metadata for mapping
    if schema_summary:
        summary_df = pd.DataFrame(schema_summary)
        os.makedirs(METADATA_DIR, exist_ok=True)
        output_path = os.path.join(METADATA_DIR, "stm_starter_dictionary.csv")
        summary_df.to_csv(output_path, index=False)
        print(f"\n[SUCCESS] Generated schema map starter at: {output_path}")
        print("👉 Open this file in Excel or VS Code to map your source columns to target fields!")


if __name__ == "__main__":
    profile_raw_exports()
