import os
import time
import requests
import shutil
from datetime import datetime

# Directories configurations
WATCH_DIR = r"C:\Users\gupta\analytics\data\incoming"
ARCHIVE_DIR = r"C:\Users\gupta\analytics\data\archive"
API_URL = "http://127.0.0.1:8000"

def init_folders():
    os.makedirs(WATCH_DIR, exist_ok=True)
    os.makedirs(ARCHIVE_DIR, exist_ok=True)

def process_file(file_path):
    file_name = os.path.basename(file_path)
    print(f"\n[{datetime.now()}] Detected new file: {file_name}")
    
    # Wait briefly to ensure file writing has completely finished
    time.sleep(1.5)
    
    # Determine endpoint based on file name prefix
    endpoint = ""
    name_lower = file_name.lower()
    if "daybook" in name_lower or "sales" in name_lower:
        endpoint = "/upload/sales"
    elif "product" in name_lower:
        endpoint = "/upload/products"
    else:
        print(f"Skipping '{file_name}': File name does not contain 'sales', 'daybook' or 'products'.")
        return False

    url = f"{API_URL}{endpoint}"
    print(f"Uploading '{file_name}' to {url}...")
    
    try:
        with open(file_path, 'rb') as f:
            files = {
                'file': (
                    file_name, 
                    f, 
                    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
                )
            }
            res = requests.post(url, files=files)
            
        if res.status_code == 200:
            print(f"SUCCESS: {res.json()}")
            return True
        else:
            print(f"FAILED (Status {res.status_code}): {res.text}")
            return False
    except Exception as e:
        print(f"EXCEPTION uploading file: {e}")
        return False

def archive_file(file_path, success):
    file_name = os.path.basename(file_path)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    subfolder = "success" if success else "failed"
    dest_dir = os.path.join(ARCHIVE_DIR, subfolder)
    os.makedirs(dest_dir, exist_ok=True)
    
    name_parts = os.path.splitext(file_name)
    new_name = f"{name_parts[0]}_{timestamp}{name_parts[1]}"
    dest_path = os.path.join(dest_dir, new_name)
    
    try:
        shutil.move(file_path, dest_path)
        print(f"Moved processed file to: {dest_path}")
    except Exception as e:
        print(f"Error archiving file: {e}")

def main():
    init_folders()
    print("==================================================")
    print("   Sales Analytics File Auto-Uploader Watcher")
    print("==================================================")
    print(f"Watching folder: {WATCH_DIR}")
    print(f"Archive folder:  {ARCHIVE_DIR}")
    print("==================================================")
    print("Drop Excel (.xlsx) files here to import them. Press Ctrl+C to exit.\n")
    
    while True:
        try:
            for file_name in os.listdir(WATCH_DIR):
                file_path = os.path.join(WATCH_DIR, file_name)
                # Ensure it's a file and has .xlsx extension
                if os.path.isfile(file_path) and file_name.endswith('.xlsx'):
                    success = process_file(file_path)
                    archive_file(file_path, success)
            time.sleep(2)
        except KeyboardInterrupt:
            print("\nWatcher stopped.")
            break
        except Exception as e:
            print(f"Watcher scanner error: {e}")
            time.sleep(5)

if __name__ == '__main__':
    main()
