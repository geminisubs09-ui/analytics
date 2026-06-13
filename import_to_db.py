import pandas as pd
import sqlite3
import os
import sys

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
    
    conn.commit()
    return conn

def parse_excel(file_path):
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
        # A valid voucher must have a non-null date (which is not 'Total:'), and valid voucher type & number
        if pd.notna(date_val) and date_val != 'Total:' and pd.notna(vch_no) and pd.notna(vch_type):
            # Convert date to string for SQLite
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
            # Item row
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

def import_to_db(excel_path, db_path):
    print(f"Reading: {excel_path}")
    vouchers, items = parse_excel(excel_path)
    
    conn = init_database(db_path)
    cursor = conn.cursor()
    
    inserted_vouchers = 0
    skipped_vouchers = 0
    inserted_items = 0
    
    # Store items by voucher key (vch_type, vch_no)
    items_by_vch = {}
    for item in items:
        key = (item['vch_type'], item['vch_no'])
        if key not in items_by_vch:
            items_by_vch[key] = []
        items_by_vch[key].append(item)
    
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
                INSERT INTO sales_items (date, party, vch_type, vch_no, product_name, quantity, rate, value)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """, (item['date'], item['party'], item['vch_type'], item['vch_no'], item['product_name'], item['quantity'], item['rate'], item['value']))
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


