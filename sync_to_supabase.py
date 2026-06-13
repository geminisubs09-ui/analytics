import pandas as pd
import requests
import os
import sys

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

def parse_sales_excel(file_path):
    xls = pd.ExcelFile(file_path)
    sheet_name = 'Sales Register' if 'Sales Register' in xls.sheet_names else xls.sheet_names[0]
    df = pd.read_excel(file_path, sheet_name=sheet_name, header=None)
    
    vouchers = []
    items = []
    current_voucher = None
    
    for i in range(5, len(df)):
        row = df.iloc[i].tolist()
        date_val = row[0]
        miti_val = row[1]
        party_val = row[2]
        vch_type = row[7]
        vch_no = row[8]
        
        # Voucher Header
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

def sync_data(excel_path, products_path, env_path):
    env = parse_env(env_path)
    supabase_url = env.get('SUPABASE_URL')
    supabase_key = env.get('SUPABASE_KEY')
    
    if not supabase_url or 'replace_with_your_supabase_url' in supabase_url:
        print("Error: Please update the SUPABASE_URL in your .env file first.")
        return
        
    # Clean up the Supabase URL
    supabase_url = supabase_url.strip()
    if supabase_url.endswith('/rest/v1/'):
        supabase_url = supabase_url[:-9]
    elif supabase_url.endswith('/rest/v1'):
        supabase_url = supabase_url[:-8]
    if supabase_url.endswith('/'):
        supabase_url = supabase_url[:-1]
        
    print(f"Connecting to Supabase at: {supabase_url}")
    
    # Setup headers for Supabase REST requests
    headers = {
        "apikey": supabase_key,
        "Authorization": f"Bearer {supabase_key}",
        "Content-Type": "application/json"
    }
    
    # 1. Parse Files
    print("Parsing Excel files...")
    vouchers, items = parse_sales_excel(excel_path)
    products = parse_products_excel(products_path)
    
    # 2. Sync Products (using upsert via resolution=merge-duplicates)
    print("Syncing product categories...")
    prod_headers = headers.copy()
    prod_headers["Prefer"] = "resolution=merge-duplicates"
    
    prod_res = requests.post(f"{supabase_url}/rest/v1/products", json=products, headers=prod_headers)
    if prod_res.status_code not in [200, 201]:
        print(f"Error syncing products: {prod_res.text}")
        return
    print(f"Synced {len(products)} product categories.")
    
    # 3. Check for existing vouchers in Supabase
    print("Checking for duplicate vouchers already in Supabase...")
    vch_res = requests.get(f"{supabase_url}/rest/v1/vouchers?select=vch_type,vch_no", headers=headers)
    if vch_res.status_code != 200:
        print(f"Error fetching existing vouchers: {vch_res.text}")
        return
        
    existing_vouchers = {(v['vch_type'], v['vch_no']) for v in vch_res.json()}
    print(f"Found {len(existing_vouchers)} existing vouchers in the cloud database.")
    
    # Filter out duplicates
    vouchers_to_insert = []
    items_to_insert = []
    skipped_count = 0
    
    # Map items by their voucher key
    items_by_vch = {}
    for item in items:
        key = (item['vch_type'], item['vch_no'])
        if key not in items_by_vch:
            items_by_vch[key] = []
        items_by_vch[key].append(item)
        
    for v in vouchers:
        key = (v['vch_type'], v['vch_no'])
        if key in existing_vouchers:
            skipped_count += 1
            continue
        vouchers_to_insert.append(v)
        if key in items_by_vch:
            items_to_insert.extend(items_by_vch[key])
            
    # 4. Insert new vouchers
    if vouchers_to_insert:
        print(f"Uploading {len(vouchers_to_insert)} new vouchers...")
        vch_insert_res = requests.post(f"{supabase_url}/rest/v1/vouchers", json=vouchers_to_insert, headers=headers)
        if vch_insert_res.status_code not in [200, 201]:
            print(f"Error inserting vouchers: {vch_insert_res.text}")
            return
            
        # 5. Insert corresponding items
        if items_to_insert:
            print(f"Uploading {len(items_to_insert)} product sales lines...")
            items_insert_res = requests.post(f"{supabase_url}/rest/v1/sales_items", json=items_to_insert, headers=headers)
            if items_insert_res.status_code not in [200, 201]:
                print(f"Error inserting sales items: {items_insert_res.text}")
                return
    
    print("\n--- Supabase Cloud Sync Summary ---")
    print(f"Total Vouchers in Excel: {len(vouchers)}")
    print(f"Skipped Duplicate Vouchers: {skipped_count}")
    print(f"Successfully Uploaded New Vouchers: {len(vouchers_to_insert)}")
    print(f"Successfully Uploaded Product Sales Lines: {len(items_to_insert)}")

if __name__ == '__main__':
    excel_file = r"C:\Users\gupta\analytics\data\DayBook.xlsx"
    products_file = r"C:\Users\gupta\analytics\data\products.xlsx"
    env_file = r"C:\Users\gupta\analytics\.env"
    
    sync_data(excel_file, products_file, env_file)
