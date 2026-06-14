import pandas as pd
import requests
from fastapi import APIRouter
from backend.analytics.utils import get_supabase_credentials, load_vouchers_df, load_sales_items_df, load_products_df, apply_analytics_filters

router = APIRouter()

@router.get("/analytics/highest-margin-products")
def get_highest_margin_products(limit: int = 10, start_date: str = None, end_date: str = None, product_group: str = None):
    url, key = get_supabase_credentials()
    items_df = load_sales_items_df(url, key)
    if items_df.empty:
        return []
        
    products_df = load_products_df(url, key)
    
    vouchers_df = load_vouchers_df(url, key)
    
    _, items_df = apply_analytics_filters(
        vouchers_df=vouchers_df,
        items_df=items_df,
        products_df=products_df,
        start_date=start_date,
        end_date=end_date,
        product_group=product_group
    )
    
    if items_df.empty or vouchers_df.empty:
        return []
        
    # Merge items and vouchers to get profit_pct
    merged = pd.merge(items_df, vouchers_df[['vch_type', 'vch_no', 'profit_pct']], on=['vch_type', 'vch_no'], how='inner')
    merged['profit_pct'] = pd.to_numeric(merged['profit_pct'], errors='coerce').fillna(0.0)
    
    # Calculate estimated profit for each item line
    merged['estimated_profit'] = merged['value'] * (merged['profit_pct'] / 100.0)
    
    # Aggregate by product
    product_summary = merged.groupby('product_name').agg(
        total_sales_value=('value', 'sum'),
        total_quantity=('quantity', 'sum'),
        total_profit=('estimated_profit', 'sum')
    ).reset_index()
    
    product_summary['average_margin_pct'] = (product_summary['total_profit'] / product_summary['total_sales_value']) * 100
    product_summary['average_margin_pct'] = product_summary['average_margin_pct'].fillna(0.0)
    
    product_summary = product_summary.sort_values(by='average_margin_pct', ascending=False).head(limit)
    
    return product_summary.to_dict(orient='records')
