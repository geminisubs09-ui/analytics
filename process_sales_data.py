import pandas as pd
import numpy as np
import os
import sys

def process_sales_excel(file_path, output_dir):
    print(f"Reading file: {file_path}")
    if not os.path.exists(file_path):
        print(f"Error: File '{file_path}' does not exist.")
        sys.exit(1)
        
    try:
        # Load the sheet. Tally registers usually export to sheet 0 or 'Sales Register'
        xls = pd.ExcelFile(file_path)
        sheet_name = 'Sales Register' if 'Sales Register' in xls.sheet_names else xls.sheet_names[0]
        df = pd.read_excel(file_path, sheet_name=sheet_name, header=None)
    except Exception as e:
        print(f"Error reading Excel file: {e}")
        sys.exit(1)
        
    vouchers = []
    items = []
    current_voucher = None
    
    print("Parsing rows... Please wait.")
    # Assuming standard Tally Sales Register format
    # Columns: 0: Date, 1: Miti/Product, 2: Party/Qty, 3: Rate, 4: Value, 7: Vch Type, 8: Vch No, 9: Value, 10: Gross, 11: Cost, 12: Gross Profit, 13: %-age
    for i in range(5, len(df)):
        row = df.iloc[i].tolist()
        
        # Safe extraction
        date_val = row[0] if len(row) > 0 else None
        miti_val = row[1] if len(row) > 1 else None
        party_val = row[2] if len(row) > 2 else None
        
        vch_type = row[7] if len(row) > 7 else None
        vch_no = row[8] if len(row) > 8 else None
        
        # Voucher Header row: A valid voucher must have a date (not 'Total:'), type, and number
        if pd.notna(date_val) and date_val != 'Total:' and pd.notna(vch_no) and pd.notna(vch_type):
            current_voucher = {
                'date': date_val,
                'miti': miti_val,
                'party': party_val,
                'vch_type': vch_type,
                'vch_no': vch_no,
                'value': row[9] if len(row) > 9 else None,
                'revenue': row[10] if len(row) > 10 else None,
                'cost': row[11] if len(row) > 11 else None,
                'profit': row[12] if len(row) > 12 else None,
                'profit_pct': row[13] if len(row) > 13 else None
            }
            vouchers.append(current_voucher)
        elif current_voucher is not None:
            # Item Row: Date is null, column 1 is non-null product name, cols 2,3,4 are numeric qty, rate, value
            item_name = row[1] if len(row) > 1 else None
            qty = row[2] if len(row) > 2 else None
            rate = row[3] if len(row) > 3 else None
            val = row[4] if len(row) > 4 else None
            
            # Skip reference lines (e.g. 'New Ref') and ensure columns have numbers for qty, rate, value
            if (pd.notna(item_name) and 
                item_name not in ['New Ref'] and 
                isinstance(qty, (int, float)) and pd.notna(qty) and 
                pd.notna(rate) and pd.notna(val)):
                
                items.append({
                    'date': current_voucher['date'],
                    'miti': current_voucher['miti'],
                    'party': current_voucher['party'],
                    'vch_type': current_voucher['vch_type'],
                    'vch_no': current_voucher['vch_no'],
                    'product_name': item_name,
                    'quantity': qty,
                    'rate': rate,
                    'value': val
                })

    vouchers_df = pd.DataFrame(vouchers).dropna(subset=['party', 'value'])
    items_df = pd.DataFrame(items)
    
    # Save outputs
    os.makedirs(output_dir, exist_ok=True)
    vouchers_out = os.path.join(output_dir, 'clean_vouchers.csv')
    items_out = os.path.join(output_dir, 'clean_sales_items.csv')
    
    vouchers_df.to_csv(vouchers_out, index=False)
    items_df.to_csv(items_out, index=False)
    
    print("\nProcessing Complete!")
    print(f"Total Vouchers (Orders) Parsed: {len(vouchers_df)}")
    print(f"Total Product Sales Lines Parsed: {len(items_df)}")
    print(f"Clean Vouchers saved to: {vouchers_out}")
    print(f"Clean Sales Items saved to: {items_out}")

if __name__ == '__main__':
    default_input = r"C:\Users\gupta\analytics\data\DayBook.xlsx"
    default_output_dir = r"C:\Users\gupta\analytics\data\output"
    
    input_file = sys.argv[1] if len(sys.argv) > 1 else default_input
    output_dir = sys.argv[2] if len(sys.argv) > 2 else default_output_dir
    
    process_sales_excel(input_file, output_dir)
