import os
import pandas as pd
import requests
from fastapi import HTTPException

# Helper function to load env variables from workspace .env
def get_supabase_credentials():
    # Look for .env in the parent directory of backend (which is two levels up from this file)
    analytics_dir = os.path.dirname(os.path.abspath(__file__)) # backend/analytics
    backend_dir = os.path.dirname(analytics_dir)                # backend
    project_root = os.path.dirname(backend_dir)                # root analytics dir
    env_path = os.path.join(project_root, ".env")
    
    env_vars = {}
    if not os.path.exists(env_path):
        raise HTTPException(status_code=500, detail=f".env config file not found at {env_path}")
        
    with open(env_path, 'r') as f:
        for line in f:
            if line.strip() and not line.startswith('#'):
                key, val = line.strip().split('=', 1)
                env_vars[key.strip()] = val.strip()
                
    supabase_url = env_vars.get('SUPABASE_URL', '').strip()
    supabase_key = env_vars.get('SUPABASE_KEY', '').strip()
    
    # Sanitize URL
    if supabase_url.endswith('/rest/v1/'):
        supabase_url = supabase_url[:-9]
    elif supabase_url.endswith('/rest/v1'):
        supabase_url = supabase_url[:-8]
    if supabase_url.endswith('/'):
        supabase_url = supabase_url[:-1]
        
    if not supabase_url or not supabase_key:
        raise HTTPException(status_code=500, detail="Supabase credentials missing in .env")
        
    return supabase_url, supabase_key

def load_vouchers_df(url, key):
    headers = {"apikey": key, "Authorization": f"Bearer {key}"}
    all_data = []
    limit = 1000
    offset = 0
    while True:
        res = requests.get(f"{url}/rest/v1/vouchers?select=*&limit={limit}&offset={offset}", headers=headers)
        if res.status_code != 200:
            raise HTTPException(status_code=500, detail=f"Failed to fetch vouchers: {res.text}")
        data = res.json()
        if not data:
            break
        all_data.extend(data)
        if len(data) < limit:
            break
        offset += limit
        
    df = pd.DataFrame(all_data)
    if not df.empty:
        df['value'] = pd.to_numeric(df['value'], errors='coerce')
        df['revenue'] = pd.to_numeric(df['revenue'], errors='coerce')
        df['cost'] = pd.to_numeric(df['cost'], errors='coerce')
        df['profit'] = pd.to_numeric(df['profit'], errors='coerce')
        df['profit_pct'] = pd.to_numeric(df['profit_pct'], errors='coerce')
    return df

def load_sales_items_df(url, key):
    headers = {"apikey": key, "Authorization": f"Bearer {key}"}
    all_data = []
    limit = 1000
    offset = 0
    while True:
        res = requests.get(f"{url}/rest/v1/sales_items?select=*&limit={limit}&offset={offset}", headers=headers)
        if res.status_code != 200:
            raise HTTPException(status_code=500, detail=f"Failed to fetch sales items: {res.text}")
        data = res.json()
        if not data:
            break
        all_data.extend(data)
        if len(data) < limit:
            break
        offset += limit
        
    df = pd.DataFrame(all_data)
    if not df.empty:
        df['value'] = pd.to_numeric(df['value'], errors='coerce')
        df['quantity'] = pd.to_numeric(df['quantity'], errors='coerce')
        df['rate'] = pd.to_numeric(df['rate'], errors='coerce')
    return df

def apply_analytics_filters(
    vouchers_df=None, 
    items_df=None, 
    products_df=None,
    start_date: str = None, 
    end_date: str = None, 
    party: str = None, 
    product_group: str = None,
    start_miti: str = None,
    end_miti: str = None
):
    # Helper to convert DD-MM-YYYY miti to YYYY-MM-DD key for comparison
    def get_miti_key(miti_str):
        if pd.isna(miti_str) or not miti_str:
            return ""
        parts = str(miti_str).strip().split('-')
        if len(parts) == 3:
            return f"{parts[2]}-{parts[1]}-{parts[0]}"
        return ""

    # 1. Filter Vouchers DataFrame
    if vouchers_df is not None and not vouchers_df.empty:
        filtered_vch = vouchers_df.copy()
        if start_date:
            filtered_vch = filtered_vch[filtered_vch['date'] >= start_date]
        if end_date:
            filtered_vch = filtered_vch[filtered_vch['date'] <= end_date]
        if party:
            filtered_vch = filtered_vch[filtered_vch['party'].str.lower() == party.lower().strip()]
        if start_miti:
            start_key = get_miti_key(start_miti)
            filtered_vch = filtered_vch[filtered_vch['miti'].apply(get_miti_key) >= start_key]
        if end_miti:
            end_key = get_miti_key(end_miti)
            filtered_vch = filtered_vch[filtered_vch['miti'].apply(get_miti_key) <= end_key]
        vouchers_df = filtered_vch

    # 2. Filter Sales Items DataFrame
    if items_df is not None and not items_df.empty:
        filtered_items = items_df.copy()
        if start_date:
            filtered_items = filtered_items[filtered_items['date'] >= start_date]
        if end_date:
            filtered_items = filtered_items[filtered_items['date'] <= end_date]
        if party:
            filtered_items = filtered_items[filtered_items['party'].str.lower() == party.lower().strip()]
            
        # Filter by B.S. date range
        if start_miti or end_miti:
            if 'miti' not in filtered_items.columns and vouchers_df is not None and not vouchers_df.empty:
                filtered_items = pd.merge(filtered_items, vouchers_df[['vch_type', 'vch_no', 'miti']], on=['vch_type', 'vch_no'], how='left')
            
            if 'miti' in filtered_items.columns:
                if start_miti:
                    start_key = get_miti_key(start_miti)
                    filtered_items = filtered_items[filtered_items['miti'].apply(get_miti_key) >= start_key]
                if end_miti:
                    end_key = get_miti_key(end_miti)
                    filtered_items = filtered_items[filtered_items['miti'].apply(get_miti_key) <= end_key]
                    
        # Filter by product group
        if product_group and products_df is not None and not products_df.empty:
            merged_items = pd.merge(filtered_items, products_df, on='product_name', how='left')
            merged_items['group_name'] = merged_items['group_name'].fillna('Unmapped')
            matching_items = merged_items[merged_items['group_name'].str.lower() == product_group.lower().strip()]
            filtered_items = filtered_items[filtered_items['product_name'].isin(matching_items['product_name'])]
            
        items_df = filtered_items

    return vouchers_df, items_df
