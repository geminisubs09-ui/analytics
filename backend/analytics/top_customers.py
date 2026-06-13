import pandas as pd
import requests
from fastapi import APIRouter
from backend.analytics.utils import get_supabase_credentials, load_vouchers_df, load_sales_items_df, apply_analytics_filters

router = APIRouter()

def calculate_top_customers(limit: int, start_date: str, end_date: str, product_group: str):
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
        product_group=product_group
    )
    
    if product_group:
        if items_df.empty:
            return []
        merged = pd.merge(items_df, vouchers_df[['vch_type', 'vch_no', 'profit_pct']], on=['vch_type', 'vch_no'], how='inner')
        merged['estimated_profit'] = merged['value'] * (merged['profit_pct'].fillna(0.0) / 100.0)
        
        top_parties = merged.groupby('party').agg(
            total_sales=('value', 'sum'),
            total_profit=('estimated_profit', 'sum'),
            vouchers_count=('vch_no', 'nunique')
        ).reset_index()
    else:
        if vouchers_df.empty:
            return []
        top_parties = vouchers_df.groupby('party').agg(
            total_sales=('value', 'sum'),
            total_profit=('profit', 'sum'),
            vouchers_count=('vch_no', 'count')
        ).reset_index()
        
    top_parties['avg_order_value'] = top_parties['total_sales'] / top_parties['vouchers_count']
    top_parties['profit_margin_pct'] = (top_parties['total_profit'] / top_parties['total_sales']) * 100
    top_parties['profit_margin_pct'] = top_parties['profit_margin_pct'].fillna(0.0)
    top_parties = top_parties.sort_values(by='total_sales', ascending=False).head(limit)
    
    return top_parties.to_dict(orient='records')

@router.get("/analytics/top-customers")
def get_top_customers(limit: int = 10, start_date: str = None, end_date: str = None, product_group: str = None):
    return calculate_top_customers(limit, start_date, end_date, product_group)

@router.get("/analytics/top-sellers")
def get_top_sellers(limit: int = 10, start_date: str = None, end_date: str = None, product_group: str = None):
    # 'top-sellers' groups by party/client, which is identical to top-customers
    return calculate_top_customers(limit, start_date, end_date, product_group)
