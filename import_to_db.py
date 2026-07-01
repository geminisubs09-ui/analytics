import pandas as pd
import sqlite3
import os
import sys
import io

def init_database(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Create Vouchers table with a primary key on (vch_type, vch_no)
    # This prevents duplicate vouchers from ever being inserted
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
    
    # Create Sales Items table linked to vouchers
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

    # Create Products mapping table
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS products (
        product_name TEXT PRIMARY KEY,
        group_name TEXT
    )
    """)
    
    # SQLite migrations - add cost columns if they don't exist
    try:
        cursor.execute("ALTER TABLE products ADD COLUMN cost_rate REAL")
    except sqlite3.OperationalError:
        pass
        
    try:
        cursor.execute("ALTER TABLE sales_items ADD COLUMN cost REAL")
    except sqlite3.OperationalError:
        pass
        
    try:
        cursor.execute("ALTER TABLE sales_items ADD COLUMN cost_rate REAL")
    except sqlite3.OperationalError:
        pass
    
    conn.commit()
    return conn

def parse_excel(file_path_or_contents):
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

def import_to_db(excel_path, db_path):
    print(f"Reading: {excel_path}")
    vouchers, items, product_costs = parse_excel(excel_path)
    
    conn = init_database(db_path)
    cursor = conn.cursor()
    
    # 1. Update products table with purchase costs
    for p_name, p_cost in product_costs.items():
        cursor.execute("""
        INSERT INTO products (product_name, group_name, cost_rate)
        VALUES (?, 'General', ?)
        ON CONFLICT (product_name) DO UPDATE SET cost_rate = excluded.cost_rate
        """, (p_name, p_cost))
    conn.commit()
    
    # 2. Load all product costs from database
    cursor.execute("SELECT product_name, cost_rate FROM products")
    db_costs = {row[0]: row[1] for row in cursor.fetchall() if row[1] is not None}
    
    # 3. Calculate cost/margin for sales items
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
        
    # 4. Recalculate voucher totals
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
                
    inserted_vouchers = 0
    skipped_vouchers = 0
    inserted_items = 0
    
    for v in vouchers:
        # Check if the voucher already exists in DB
        cursor.execute(
            "SELECT count(*) FROM vouchers WHERE vch_type = ? AND vch_no = ?", 
            (v['vch_type'], v['vch_no'])
        )
        exists = cursor.fetchone()[0] > 0
        
        if exists:
            skipped_vouchers += 1
            continue
            
        # If it doesn't exist, insert the voucher
        cursor.execute("""
        INSERT INTO vouchers (date, miti, party, vch_type, vch_no, value, revenue, cost, profit, profit_pct)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (v['date'], v['miti'], v['party'], v['vch_type'], v['vch_no'], v['value'], v['revenue'], v['cost'], v['profit'], v['profit_pct']))
        
        inserted_vouchers += 1
        
        # Insert corresponding items for this voucher
        vch_key = (v['vch_type'], v['vch_no'])
        if vch_key in items_by_vch:
            for item in items_by_vch[vch_key]:
                cursor.execute("""
                INSERT INTO sales_items (date, party, vch_type, vch_no, product_name, quantity, rate, value, cost, cost_rate)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, (item['date'], item['party'], item['vch_type'], item['vch_no'], item['product_name'], item['quantity'], item['rate'], item['value'], item['cost'], item['cost_rate']))
                inserted_items += 1
                
    conn.commit()
    conn.close()
    
    print("\n--- Import Summary ---")
    print(f"Total Vouchers Processed: {len(vouchers)}")
    print(f"Successfully Imported Vouchers: {inserted_vouchers}")
    print(f"Skipped Duplicate Vouchers: {skipped_vouchers}")
    print(f"Successfully Imported Product Lines: {inserted_items}")

def import_products_to_db(products_excel_path, db_path):
    if not os.path.exists(products_excel_path):
        print(f"Products file not found at: {products_excel_path}")
        return
        
    print(f"Reading products file: {products_excel_path}")
    try:
        df = pd.read_excel(products_excel_path, sheet_name='Stock Summary')
    except Exception as e:
        print(f"Error reading products Excel: {e}")
        return
        
    first_group_name = df.columns[0]
    current_group = first_group_name
    
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    inserted = 0
    for i in range(len(df)):
        item_name = df.iloc[i, 0]
        group_indicator = df.iloc[i, 1]
        
        if pd.isna(item_name):
            continue
            
        if str(group_indicator).strip() == 'group':
            current_group = str(item_name).strip()
        else:
            product_name = str(item_name).strip()
            cursor.execute("""
            INSERT OR REPLACE INTO products (product_name, group_name)
            VALUES (?, ?)
            """, (product_name, current_group))
            inserted += 1
            
    conn.commit()
    conn.close()
    print(f"Successfully imported {inserted} product-to-group mappings.")

if __name__ == '__main__':
    excel_file = r"C:\Users\gupta\analytics\data\DayBook.xlsx"
    products_file = r"C:\Users\gupta\analytics\data\products.xlsx"
    database_file = r"C:\Users\gupta\analytics\data\sales_data.db"
    
    import_to_db(excel_file, database_file)
    import_products_to_db(products_file, database_file)


