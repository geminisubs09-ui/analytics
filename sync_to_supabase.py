import pandas as pd
import requests
import os
import sys
import io

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

def parse_sales_excel(file_path_or_contents):
    if isinstance(file_path_or_contents, bytes):
        xls = pd.ExcelFile(io.BytesIO(file_path_or_contents))
    else:
        xls = pd.ExcelFile(file_path_or_contents)
        
    sheet_name = 'Sales Register' if 'Sales Register' in xls.sheet_names else \
                 ('Day Book' if 'Day Book' in xls.sheet_names else xls.sheet_names[0])
                 
    df = pd.read_excel(xls, sheet_name=sheet_name, header=None)
    num_cols = df.shape[1]
    
    vouchers = []
    items = []
    product_costs = {}
    
    if num_cols >= 14:
        # Sales Register format
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
                        'value': float(val),
                        'cost': None,
                        'cost_rate': None
                    })
        return vouchers, items, product_costs

    else:
        # Day Book format (11 columns)
        current_vch_type = None
        for i in range(5, len(df)):
            row = df.iloc[i].tolist()
            if len(row) < 9:
                continue
            date_val = row[0]
            vch_type = row[7]
            vch_no = row[8]
            
            is_vch = pd.notna(date_val) and date_val != 'Total:' and pd.notna(vch_no) and pd.notna(vch_type)
            if is_vch:
                current_vch_type = str(vch_type).strip()
            elif current_vch_type == 'Purchase':
                item_name = row[1]
                qty = row[2]
                rate = row[3]
                if (pd.notna(item_name) and item_name not in ['New Ref'] and 
                    isinstance(qty, (int, float)) and pd.notna(qty) and 
                    isinstance(rate, (int, float)) and pd.notna(rate)):
                    product_costs[str(item_name).strip()] = float(rate)
                    
        sales_types = {'Sales', 'Head Office Sales', 'Bafal Sales', 'Pasal', 'Payment', 'Receipt'}
        current_voucher = None
        pending_narration = None
        for i in range(5, len(df)):
            row = df.iloc[i].tolist()
            if len(row) < 9:
                continue
            date_val = row[0]
            miti_val = row[1]
            party_val = row[2]
            vch_type = row[7]
            vch_no = row[8]
            
            is_vch = pd.notna(date_val) and date_val != 'Total:' and pd.notna(vch_no) and pd.notna(vch_type)
            if is_vch:
                vch_type_str = str(vch_type).strip()
                if vch_type_str in sales_types:
                    date_str = str(date_val).split(' ')[0] if pd.notna(date_val) else None
                    val_9 = float(row[9]) if pd.notna(row[9]) else 0.0
                    val_10 = float(row[10]) if pd.notna(row[10]) else 0.0
                    voucher_value = val_9 if val_9 > 0 else val_10
                    
                    current_voucher = {
                        'date': date_str,
                        'miti': str(miti_val) if pd.notna(miti_val) else None,
                        'party': str(party_val).strip() if pd.notna(party_val) else None,
                        'vch_type': vch_type_str,
                        'vch_no': str(vch_no).strip(),
                        'value': voucher_value,
                        'revenue': 0.0,
                        'cost': 0.0,
                        'profit': 0.0,
                        'profit_pct': 0.0
                    }
                    vouchers.append(current_voucher)
                    pending_narration = None
                else:
                    current_voucher = None
            elif current_voucher is not None:
                if current_voucher['vch_type'] in {'Payment', 'Receipt'}:
                    if pd.notna(row[1]) and pd.isna(row[2]) and pd.isna(row[3]) and pd.isna(row[4]):
                        pending_narration = str(row[1]).strip()
                    elif pd.isna(row[1]) and pd.notna(row[2]) and (pd.notna(row[3]) or pd.notna(row[4])):
                        leg_party = str(row[2]).strip()
                        leg_amount = float(row[3]) if pd.notna(row[3]) else (float(row[4]) if pd.notna(row[4]) else 0.0)
                        narration = pending_narration if pending_narration else leg_party
                        items.append({
                            'date': current_voucher['date'],
                            'party': leg_party,
                            'vch_type': current_voucher['vch_type'],
                            'vch_no': current_voucher['vch_no'],
                            'product_name': narration,
                            'quantity': 1.0,
                            'rate': leg_amount,
                            'value': leg_amount,
                            'cost': None,
                            'cost_rate': None
                        })
                        pending_narration = None
                else:
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
                            'value': float(val),
                            'cost': None,
                            'cost_rate': None
                        })
        return vouchers, items, product_costs

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
        
    supabase_url = supabase_url.strip()
    if supabase_url.endswith('/rest/v1/'):
        supabase_url = supabase_url[:-9]
    elif supabase_url.endswith('/rest/v1'):
        supabase_url = supabase_url[:-8]
    if supabase_url.endswith('/'):
        supabase_url = supabase_url[:-1]
        
    print(f"Connecting to Supabase at: {supabase_url}")
    
    headers = {
        "apikey": supabase_key,
        "Authorization": f"Bearer {supabase_key}",
        "Content-Type": "application/json"
    }
    
    # 1. Parse Files
    print("Parsing Excel files...")
    vouchers, items, product_costs = parse_sales_excel(excel_path)
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
    
    # 3. Update Supabase with new cost rates from Purchase vouchers
    if product_costs:
        print(f"Uploading {len(product_costs)} updated purchase cost rates to Supabase...")
        sb_prods = [{"product_name": name, "group_name": "General", "cost_rate": rate} for name, rate in product_costs.items()]
        requests.post(f"{supabase_url}/rest/v1/products", json=sb_prods, headers=prod_headers)
        
    # 4. Fetch all product cost rates from Supabase
    db_costs = {}
    print("Fetching product cost rates from Supabase...")
    limit = 1000
    offset = 0
    while True:
        prod_res = requests.get(f"{supabase_url}/rest/v1/products?select=product_name,cost_rate&limit={limit}&offset={offset}", headers=headers)
        if prod_res.status_code != 200:
            print(f"Error fetching product costs: {prod_res.text}")
            break
        data = prod_res.json()
        if not data:
            break
        for p in data:
            name = p.get('product_name')
            rate = p.get('cost_rate')
            if name and rate is not None:
                db_costs[name.strip()] = float(rate)
        if len(data) < limit:
            break
        offset += limit
        
    # Combine costs (new sheet takes precedence)
    db_costs.update(product_costs)
    
    # 5. Calculate cost/margin for sales items
    items_by_vch = {}
    for item in items:
        p_name = item['product_name']
        cost_rate = db_costs.get(p_name)
        if cost_rate is not None:
            item['cost'] = item['quantity'] * cost_rate
            item['cost_rate'] = cost_rate
        else:
            item['cost'] = None
            item['cost_rate'] = None
            
        key = (item['vch_type'], item['vch_no'])
        if key not in items_by_vch:
            items_by_vch[key] = []
        items_by_vch[key].append(item)
        
    # 6. Recalculate voucher totals
    for v in vouchers:
        key = (v['vch_type'], v['vch_no'])
        v_items = items_by_vch.get(key, [])
        
        if v['vch_type'] in {'Payment', 'Receipt'}:
            v['revenue'] = 0.0
            v['cost'] = None
            v['profit'] = None
            v['profit_pct'] = None
        else:
            if v.get('revenue', 0.0) == 0.0:
                v['revenue'] = sum(item['value'] for item in v_items)
                if v['value'] == 0.0:
                    v['value'] = v['revenue']
                    
                has_all_costs = all(item['cost'] is not None for item in v_items)
                if has_all_costs and v_items:
                    v['cost'] = sum(item['cost'] for item in v_items)
                    v['profit'] = v['revenue'] - v['cost']
                    v['profit_pct'] = (v['profit'] / v['revenue']) * 100.0 if v['revenue'] > 0 else 0.0
                else:
                    v['cost'] = None
                    v['profit'] = None
                    v['profit_pct'] = None
                
    # 7. Check for existing vouchers in Supabase
    print("Checking for duplicate vouchers already in Supabase...")
    existing_vouchers = set()
    limit = 1000
    offset = 0
    while True:
        vch_res = requests.get(f"{supabase_url}/rest/v1/vouchers?select=vch_type,vch_no&limit={limit}&offset={offset}", headers=headers)
        if vch_res.status_code != 200:
            print(f"Error fetching existing vouchers: {vch_res.text}")
            return
        data = vch_res.json()
        if not data:
            break
        for v in data:
            existing_vouchers.add((v['vch_type'], v['vch_no']))
        if len(data) < limit:
            break
        offset += limit
    print(f"Found {len(existing_vouchers)} existing vouchers in the cloud database.")
    
    # Filter out duplicates
    vouchers_to_insert = []
    items_to_insert = []
    skipped_count = 0
    
    seen_in_batch = set()
    for v in vouchers:
        key = (v['vch_type'], v['vch_no'])
        if key in existing_vouchers or key in seen_in_batch:
            skipped_count += 1
            continue
        vouchers_to_insert.append(v)
        seen_in_batch.add(key)
        if key in items_by_vch:
            items_to_insert.extend(items_by_vch[key])
            
    # 8. Upload new vouchers and sales items to Supabase
    if vouchers_to_insert:
        print(f"Uploading {len(vouchers_to_insert)} new vouchers...")
        vch_insert_res = requests.post(f"{supabase_url}/rest/v1/vouchers", json=vouchers_to_insert, headers=headers)
        if vch_insert_res.status_code not in [200, 201]:
            print(f"Error inserting vouchers: {vch_insert_res.text}")
            return
            
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
