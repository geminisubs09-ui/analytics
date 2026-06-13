import pandas as pd
import requests
from fastapi import APIRouter
from backend.analytics.utils import get_supabase_credentials, load_vouchers_df, load_sales_items_df, apply_analytics_filters

router = APIRouter()

@router.get("/analytics/daily-trends")
def get_daily_trends(start_date: str = None, end_date: str = None, party: str = None, product_group: str = None):
    url, key = get_supabase_credentials()
    vouchers_df = load_vouchers_df(url, key)
    if vouchers_df.empty:
        return []
        
    items_df = None
    products_df = None
    if product_group:
        items_df = load_sales_items_df(url, key)
        headers = {"apikey": key, "Authorization": f"Bearer {key}"}
        prod_res = requests.get(f"{url}/rest/v1/products?select=product_name,group_name", headers=headers)
        if prod_res.status_code == 200:
            products_df = pd.DataFrame(prod_res.json())
            
    vouchers_df, items_df = apply_analytics_filters(
        vouchers_df=vouchers_df,
        items_df=items_df,
        products_df=products_df,
        start_date=start_date,
        end_date=end_date,
        party=party,
        product_group=product_group
    )
    
    if product_group:
        if items_df.empty:
            return []
        merged = pd.merge(items_df, vouchers_df[['vch_type', 'vch_no', 'profit_pct']], on=['vch_type', 'vch_no'], how='inner')
        merged['estimated_profit'] = merged['value'] * (merged['profit_pct'].fillna(0.0) / 100.0)
        merged['date_str'] = merged['date'].apply(lambda d: str(d).split(' ')[0] if pd.notna(d) else '')
        merged['vch_key'] = merged['vch_type'].astype(str) + "_" + merged['vch_no'].astype(str)
        daily_sales = merged.groupby('date_str').agg(
            daily_sales=('value', 'sum'),
            daily_profit=('estimated_profit', 'sum'),
            vouchers_count=('vch_key', 'nunique')
        ).reset_index().sort_values(by='date_str')
    else:
        if vouchers_df.empty:
            return []
        vouchers_df['date_str'] = vouchers_df['date'].apply(lambda d: str(d).split(' ')[0] if pd.notna(d) else '')
        daily_sales = vouchers_df.groupby('date_str').agg(
            daily_sales=('value', 'sum'),
            daily_profit=('profit', 'sum'),
            vouchers_count=('vch_no', 'count')
        ).reset_index().sort_values(by='date_str')
        
    return daily_sales.to_dict(orient='records')
