import os
import sys
import sqlite3
import pandas as pd
import requests
import io
from datetime import datetime

def parse_env(env_path):
    env_vars = {}
    if not os.path.exists(env_path):
        print(f"Error: .env file not found at {env_path}")
        return env_vars
    with open(env_path, 'r') as f:
        for line in f:
            if line.strip() and not line.startswith('#'):
                key, val = line.strip().split('=', 1)
                env_vars[key.strip()] = val.strip()
    return env_vars

def init_sqlite_db(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Create Vouchers table
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS vouchers (
        date TEXT,
        miti TEXT,
        party TEXT,
        vch_type TEXT,
        vch_no TEXT,
        value REAL,
        revenue REAL,
        cost REAL,
        profit REAL,
        profit_pct REAL,
        PRIMARY KEY (vch_type, vch_no)
    )
    """)
    
    # Create Sales Items table
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS sales_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT,
        party TEXT,
        vch_type TEXT,
        vch_no TEXT,
        product_name TEXT,
        quantity REAL,
        rate REAL,
        value REAL,
        FOREIGN KEY (vch_type, vch_no) REFERENCES vouchers (vch_type, vch_no) ON DELETE CASCADE
    )
    """)

    # Create Products table
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS products (
        product_name TEXT PRIMARY KEY,
        group_name TEXT
    )
    """)
    
    conn.commit()
    return conn

def parse_sales_excel(file_path):
    xls = pd.ExcelFile(file_path)
    sheet_name = 'Sales Register' if 'Sales Register' in xls.sheet_names else xls.sheet_names[0]
    df = pd.read_excel(file_path, sheet_name=sheet_name, header=None)
    
    vouchers = []
    items = []
    current_voucher = None
    
    for i in range(5, len(df)):
        row = df.iloc[i].tolist()
        if len(row) < 14:
            continue
            
        date_val = row[0]
        miti_val = row[1]
        party_val = row[2]
        vch_type = row[7]
        vch_no = row[8]
        
        # Voucher Header Row
        if pd.notna(date_val) and date_val != 'Total:' and pd.notna(vch_no) and pd.notna(vch_type):
            date_str = str(date_val).split(' ')[0] if pd.notna(date_val) else None
            current_voucher = {
                'date': date_str,
                'miti': str(miti_val) if pd.notna(miti_val) else None,
                'party': str(party_val).strip() if pd.notna(party_val) else None,
                'vch_type': str(vch_type).strip() if pd.notna(vch_type) else None,
                'vch_no': str(vch_no).strip() if pd.notna(vch_no) else None,
                'value': float(row[9]) if pd.notna(row[9]) else 0.0,
                'revenue': float(row[10]) if pd.notna(row[10]) else 0.0,
                'cost': float(row[11]) if pd.notna(row[11]) else 0.0,
                'profit': float(row[12]) if pd.notna(row[12]) else 0.0,
                'profit_pct': float(row[13]) if pd.notna(row[13]) else 0.0
            }
            vouchers.append(current_voucher)
        elif current_voucher is not None:
            # Item Row
            item_name = row[1]
            qty = row[2]
            rate = row[3]
            val = row[4]
            
            if (pd.notna(item_name) and 
                item_name not in ['New Ref'] and 
                isinstance(qty, (int, float)) and pd.notna(qty) and 
                pd.notna(rate) and pd.notna(val)):
                
                items.append({
                    'date': current_voucher['date'],
                    'party': current_voucher['party'],
                    'vch_type': current_voucher['vch_type'],
                    'vch_no': current_voucher['vch_no'],
                    'product_name': str(item_name).strip(),
                    'quantity': float(qty),
                    'rate': float(rate),
                    'value': float(val)
                })
                
    return vouchers, items

def parse_products_excel(file_path):
    df = pd.read_excel(file_path, sheet_name='Stock Summary')
    first_group_name = df.columns[0]
    current_group = first_group_name
    
    products = []
    for i in range(len(df)):
        item_name = df.iloc[i, 0]
        group_indicator = df.iloc[i, 1]
        
        if pd.isna(item_name):
            continue
            
        if str(group_indicator).strip() == 'group':
            current_group = str(item_name).strip()
        else:
            products.append({
                'product_name': str(item_name).strip(),
                'group_name': current_group
            })
    return products

def import_sales_to_sqlite(conn, vouchers, items):
    cursor = conn.cursor()
    inserted_vouchers = 0
    skipped_vouchers = 0
    inserted_items = 0
    
    # Store items by voucher key
    items_by_vch = {}
    for item in items:
        key = (item['vch_type'], item['vch_no'])
        if key not in items_by_vch:
            items_by_vch[key] = []
        items_by_vch[key].append(item)
        
    for v in vouchers:
        cursor.execute(
            "SELECT count(*) FROM vouchers WHERE vch_type = ? AND vch_no = ?", 
            (v['vch_type'], v['vch_no'])
        )
        exists = cursor.fetchone()[0] > 0
        
        if exists:
            skipped_vouchers += 1
            continue
            
        cursor.execute("""
        INSERT INTO vouchers (date, miti, party, vch_type, vch_no, value, revenue, cost, profit, profit_pct)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (v['date'], v['miti'], v['party'], v['vch_type'], v['vch_no'], v['value'], v['revenue'], v['cost'], v['profit'], v['profit_pct']))
        inserted_vouchers += 1
        
        vch_key = (v['vch_type'], v['vch_no'])
        if vch_key in items_by_vch:
            for item in items_by_vch[vch_key]:
                cursor.execute("""
                INSERT INTO sales_items (date, party, vch_type, vch_no, product_name, quantity, rate, value)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, (item['date'], item['party'], item['vch_type'], item['vch_no'], item['product_name'], item['quantity'], item['rate'], item['value']))
                inserted_items += 1
                
    conn.commit()
    return inserted_vouchers, skipped_vouchers, inserted_items

def sync_sales_to_supabase(supabase_url, headers, existing_vouchers_set, vouchers, items):
    vouchers_to_insert = []
    items_to_insert = []
    skipped_count = 0
    
    # Store items by voucher key
    items_by_vch = {}
    for item in items:
        key = (item['vch_type'], item['vch_no'])
        if key not in items_by_vch:
            items_by_vch[key] = []
        items_by_vch[key].append(item)
        
    for v in vouchers:
        key = (v['vch_type'], v['vch_no'])
        if key in existing_vouchers_set:
            skipped_count += 1
            continue
        vouchers_to_insert.append(v)
        if key in items_by_vch:
            items_to_insert.extend(items_by_vch[key])
            
    if vouchers_to_insert:
        # Upload new vouchers
        vch_res = requests.post(f"{supabase_url}/rest/v1/vouchers", json=vouchers_to_insert, headers=headers)
        if vch_res.status_code not in [200, 201]:
            print(f"Error uploading vouchers to Supabase: {vch_res.text}")
            return 0, skipped_count, 0
            
        # Update existing vouchers set in-memory
        for v in vouchers_to_insert:
            existing_vouchers_set.add((v['vch_type'], v['vch_no']))
            
        # Upload corresponding items
        if items_to_insert:
            items_res = requests.post(f"{supabase_url}/rest/v1/sales_items", json=items_to_insert, headers=headers)
            if items_res.status_code not in [200, 201]:
                print(f"Error uploading sales items to Supabase: {items_res.text}")
                return len(vouchers_to_insert), skipped_count, 0
                
    return len(vouchers_to_insert), skipped_count, len(items_to_insert)

def import_products_to_sqlite(conn, products):
    cursor = conn.cursor()
    inserted = 0
    for p in products:
        cursor.execute("""
        INSERT OR REPLACE INTO products (product_name, group_name)
        VALUES (?, ?)
        """, (p['product_name'], p['group_name']))
        inserted += 1
    conn.commit()
    return inserted

def sync_products_to_supabase(supabase_url, headers, products):
    # Setup Prefer header for merge-duplicates
    prod_headers = headers.copy()
    prod_headers["Prefer"] = "resolution=merge-duplicates"
    
    # We can upload in batches if there are many products
    batch_size = 100
    synced = 0
    for i in range(0, len(products), batch_size):
        batch = products[i:i+batch_size]
        res = requests.post(f"{supabase_url}/rest/v1/products", json=batch, headers=prod_headers)
        if res.status_code not in [200, 201]:
            print(f"Error syncing products batch to Supabase: {res.text}")
            return synced
        synced += len(batch)
    return synced

def main():
    data_dir = r"C:\Users\gupta\analytics\data"
    db_path = os.path.join(data_dir, "sales_data.db")
    env_path = r"C:\Users\gupta\analytics\.env"
    
    print("==================================================")
    print("      Bulk Sales & Products Import & Sync         ")
    print("==================================================")
    
    # 1. Parse Env & Setup Supabase credentials
    env = parse_env(env_path)
    supabase_url = env.get('SUPABASE_URL')
    supabase_key = env.get('SUPABASE_KEY')
    
    if not supabase_url or 'replace_with_your_supabase_url' in supabase_url:
        print("Error: Supabase URL is not configured in .env.")
        sys.exit(1)
        
    supabase_url = supabase_url.strip().rstrip('/')
    if supabase_url.endswith('/rest/v1'):
        supabase_url = supabase_url[:-8]
    elif supabase_url.endswith('/rest/v1/'):
        supabase_url = supabase_url[:-9]
        
    headers = {
        "apikey": supabase_key,
        "Authorization": f"Bearer {supabase_key}",
        "Content-Type": "application/json"
    }
    
    # 2. Connect to local SQLite DB
    print(f"Initializing local SQLite database at: {db_path}")
    sqlite_conn = init_sqlite_db(db_path)
    
    # 3. Identify all Excel files
    all_files = [f for f in os.listdir(data_dir) if f.endswith('.xlsx')]
    print(f"Found {len(all_files)} Excel files in data directory.")
    
    products_file = "products.xlsx"
    sales_files = [f for f in all_files if f != products_file]
    
    # 4. Import & Sync Products first
    if products_file in all_files:
        products_path = os.path.join(data_dir, products_file)
        print(f"\n--- Processing Products File: {products_file} ---")
        try:
            products = parse_products_excel(products_path)
            print(f"Parsed {len(products)} products.")
            
            sqlite_prod_count = import_products_to_sqlite(sqlite_conn, products)
            print(f"SQLite: Imported/Updated {sqlite_prod_count} product group mappings.")
            
            supabase_prod_count = sync_products_to_supabase(supabase_url, headers, products)
            print(f"Supabase: Synced {supabase_prod_count} products.")
        except Exception as e:
            print(f"Error processing products file: {e}")
    else:
        print("\nWarning: products.xlsx not found in data directory. Skipping products import.")
        
    # 5. Fetch existing vouchers from Supabase to prevent duplicates in cloud
    print("\nFetching existing vouchers from Supabase...")
    try:
        existing_supabase_vouchers = set()
        limit = 1000
        offset = 0
        while True:
            vch_res = requests.get(f"{supabase_url}/rest/v1/vouchers?select=vch_type,vch_no&limit={limit}&offset={offset}", headers=headers)
            if vch_res.status_code != 200:
                raise Exception(f"Failed to fetch vouchers: {vch_res.text}")
            data = vch_res.json()
            if not data:
                break
            for v in data:
                existing_supabase_vouchers.add((v['vch_type'], v['vch_no']))
            if len(data) < limit:
                break
            offset += limit
        print(f"Found {len(existing_supabase_vouchers)} existing vouchers in Supabase.")
    except Exception as e:
        print(f"Failed to connect to Supabase: {e}")
        existing_supabase_vouchers = set()
        
    # 6. Process Sales Files
    total_sales_vouchers_parsed = 0
    total_sales_items_parsed = 0
    
    total_sqlite_vch_inserted = 0
    total_sqlite_vch_skipped = 0
    total_sqlite_items_inserted = 0
    
    total_supabase_vch_inserted = 0
    total_supabase_vch_skipped = 0
    total_supabase_items_inserted = 0
    
    for sf in sales_files:
        sf_path = os.path.join(data_dir, sf)
        print(f"\n--- Processing Sales File: {sf} ---")
        try:
            vouchers, items = parse_sales_excel(sf_path)
            total_sales_vouchers_parsed += len(vouchers)
            total_sales_items_parsed += len(items)
            print(f"Parsed: {len(vouchers)} vouchers, {len(items)} items.")
            
            # Local SQLite
            sqlite_vch_ins, sqlite_vch_skip, sqlite_items_ins = import_sales_to_sqlite(sqlite_conn, vouchers, items)
            total_sqlite_vch_inserted += sqlite_vch_ins
            total_sqlite_vch_skipped += sqlite_vch_skip
            total_sqlite_items_inserted += sqlite_items_ins
            print(f"SQLite: Imported {sqlite_vch_ins} vouchers, skipped {sqlite_vch_skip} duplicates. Items: {sqlite_items_ins} imported.")
            
            # Supabase
            sb_vch_ins, sb_vch_skip, sb_items_ins = sync_sales_to_supabase(
                supabase_url, headers, existing_supabase_vouchers, vouchers, items
            )
            total_supabase_vch_inserted += sb_vch_ins
            total_supabase_vch_skipped += sb_vch_skip
            total_supabase_items_inserted += sb_items_ins
            print(f"Supabase: Uploaded {sb_vch_ins} vouchers, skipped {sb_vch_skip} duplicates. Items: {sb_items_ins} uploaded.")
            
        except Exception as e:
            print(f"Error processing sales file '{sf}': {e}")
            
    # 7. Check for Ungrouped/Unmapped Products
    print("\n--- Checking for Ungrouped Products ---")
    try:
        # SQLite check
        cursor = sqlite_conn.cursor()
        cursor.execute("SELECT DISTINCT product_name FROM sales_items")
        all_sold_products = {row[0].strip() for row in cursor.fetchall() if row[0]}
        
        cursor.execute("SELECT product_name FROM products")
        all_mapped_products = {row[0].strip() for row in cursor.fetchall() if row[0]}
        
        ungrouped_products = sorted(list(all_sold_products - all_mapped_products))
        if ungrouped_products:
            print(f"WARNING: Found {len(ungrouped_products)} ungrouped products that have sales but no product group mapping:")
            for p in ungrouped_products[:15]:
                print(f"  - {p}")
            if len(ungrouped_products) > 15:
                print(f"  ... and {len(ungrouped_products) - 15} more.")
        else:
            print("Great! All sold products are correctly mapped to their product groups.")
    except Exception as e:
        print(f"Error checking ungrouped products: {e}")
        
    sqlite_conn.close()
    
    print("\n==================================================")
    print("                 Final Summary                    ")
    print("==================================================")
    print(f"Total Sales Files Processed: {len(sales_files)}")
    print(f"Total Vouchers Parsed:       {total_sales_vouchers_parsed}")
    print(f"Total Product Lines Parsed:  {total_sales_items_parsed}")
    print("-" * 50)
    print("SQLite Local Database:")
    print(f"  - New Vouchers Imported:    {total_sqlite_vch_inserted}")
    print(f"  - Duplicate Vouchers:       {total_sqlite_vch_skipped}")
    print(f"  - Product Lines Imported:   {total_sqlite_items_inserted}")
    print("Supabase Cloud Database:")
    print(f"  - New Vouchers Sync'd:      {total_supabase_vch_inserted}")
    print(f"  - Duplicate Vouchers:       {total_supabase_vch_skipped}")
    print(f"  - Product Lines Sync'd:     {total_supabase_items_inserted}")
    print("==================================================")

if __name__ == '__main__':
    main()
