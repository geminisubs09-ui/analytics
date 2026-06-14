import pandas as pd
import requests
from fastapi import APIRouter
from backend.analytics.utils import get_supabase_credentials, load_sales_items_df, load_products_df, apply_analytics_filters

router = APIRouter()

def calculate_top_products(limit: int = None, start_date: str = None, end_date: str = None, party: str = None, product_group: str = None):
    url, key = get_supabase_credentials()
    items_df = load_sales_items_df(url, key)
    if items_df.empty:
        return []
        
    products_df = load_products_df(url, key)
    
    _, items_df = apply_analytics_filters(
        items_df=items_df,
        products_df=products_df,
        start_date=start_date,
        end_date=end_date,
        party=party,
        product_group=product_group
    )
    
    if items_df.empty:
        return []
        
    top_products = items_df.groupby('product_name').agg(
        total_sales_value=('value', 'sum'),
        total_quantity=('quantity', 'sum'),
        average_rate=('rate', 'mean'),
        transactions_count=('vch_no', 'count')
    ).reset_index()
    
    top_products = top_products.sort_values(by='total_sales_value', ascending=False)
    if limit is not None:
        top_products = top_products.head(limit)
    return top_products.to_dict(orient='records')

@router.get("/analytics/top-products")
def get_top_products(limit: int = None, start_date: str = None, end_date: str = None, party: str = None, product_group: str = None):
    return calculate_top_products(limit, start_date, end_date, party, product_group)

@router.get("/analytics/top-sales-products")
def get_top_sales_products(limit: int = None, start_date: str = None, end_date: str = None, party: str = None, product_group: str = None):
    return calculate_top_products(limit, start_date, end_date, party, product_group)
