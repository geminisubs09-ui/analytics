import pandas as pd
import requests
from fastapi import APIRouter, HTTPException
from backend.analytics.utils import get_supabase_credentials, load_sales_items_df, load_vouchers_df, load_products_df, apply_analytics_filters

router = APIRouter()

@router.get("/analytics/group-sales")
def get_group_sales(start_date: str = None, end_date: str = None, party: str = None):
    url, key = get_supabase_credentials()
    items_df = load_sales_items_df(url, key)
    if items_df.empty:
        return []
        
    products_df = load_products_df(url, key)
    
    vouchers_df = load_vouchers_df(url, key)
    
    # Apply filters
    vouchers_df, items_df = apply_analytics_filters(
        vouchers_df=vouchers_df,
        items_df=items_df,
        products_df=products_df,
        start_date=start_date,
        end_date=end_date,
        party=party
    )
    
    if items_df.empty:
        return []
        
    # Merge mappings
    merged = pd.merge(items_df, products_df, on='product_name', how='left')
    merged['group_name'] = merged['group_name'].fillna('Unmapped')
    
    # Merge voucher details for profit pct
    merged = pd.merge(merged, vouchers_df[['vch_type', 'vch_no', 'profit_pct']], on=['vch_type', 'vch_no'], how='left')
    merged['profit_pct'] = merged['profit_pct'].fillna(0.0)
    
    # Calculate estimated item-level profit
    merged['estimated_profit'] = merged['value'] * (merged['profit_pct'] / 100.0)
    
    # Aggregate by group
    group_summary = merged.groupby('group_name').agg(
        order_lines_count=('product_name', 'count'),
        total_quantity=('quantity', 'sum'),
        total_sales_value=('value', 'sum'),
        estimated_profit=('estimated_profit', 'sum')
    ).reset_index()
    
    # Calculate profit margin pct
    group_summary['profit_margin_pct'] = (group_summary['estimated_profit'] / group_summary['total_sales_value']) * 100
    group_summary['profit_margin_pct'] = group_summary['profit_margin_pct'].fillna(0.0)
    
    # Rename columns for presentation
    group_summary = group_summary.rename(columns={'group_name': 'product_group'})
    
    return group_summary.to_dict(orient='records')
