import pandas as pd
import numpy as np
import os
import sys

import io

def parse_excel(file_path):
    xls = pd.ExcelFile(file_path)
    sheet_name = 'Sales Register' if 'Sales Register' in xls.sheet_names else \
                 ('Day Book' if 'Day Book' in xls.sheet_names else xls.sheet_names[0])
                 
    df = pd.read_excel(file_path, sheet_name=sheet_name, header=None)
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

def process_sales_excel(file_path, output_dir):
    print(f"Reading file: {file_path}")
    if not os.path.exists(file_path):
        print(f"Error: File '{file_path}' does not exist.")
        sys.exit(1)
        
    vouchers, items, product_costs = parse_excel(file_path)
    
    # Fill item-level costs using the parsed purchase costs in the sheet
    items_by_vch = {}
    for item in items:
        p_name = item['product_name']
        cost_rate = product_costs.get(p_name)
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
        
    # Recalculate voucher totals for Day Book
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

    vouchers_df = pd.DataFrame(vouchers).dropna(subset=['party', 'value'])
    items_df = pd.DataFrame(items)
    
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
