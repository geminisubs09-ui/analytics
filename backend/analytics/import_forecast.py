import pandas as pd
import requests
from datetime import datetime, timedelta
from fastapi import APIRouter, HTTPException
from backend.analytics.utils import get_supabase_credentials, load_sales_items_df, load_products_df

router = APIRouter()

@router.get("/analytics/import-forecast")
def get_import_forecast(days: int = 90):
    print("get_import_forecast: Starting...")
    url, key = get_supabase_credentials()
    
    print("get_import_forecast: Loading items_df...")
    items_df = load_sales_items_df(url, key)
    
    if items_df.empty:
        print("get_import_forecast: items_df is empty!")
        return []
        
    print("get_import_forecast: Finding max date string...")
    # Clean the date strings to avoid issues
    items_df['clean_date'] = items_df['date'].apply(lambda d: str(d).split(' ')[0] if pd.notna(d) else '')
    
    max_date_str = items_df['clean_date'].max()
    print("get_import_forecast: Max transaction date string =", max_date_str)
    
    if not max_date_str or pd.isna(max_date_str):
        print("get_import_forecast: Max date is empty!")
        return []
        
    try:
        # standard python parsing is safe from C-extension segfaults
        max_date = datetime.strptime(max_date_str, '%Y-%m-%d')
        start_date = (max_date - timedelta(days=days)).strftime('%Y-%m-%d')
    except Exception as parse_err:
        print(f"get_import_forecast: Error parsing date {max_date_str}: {parse_err}")
        return []
        
    print("get_import_forecast: Start date filter =", start_date)
    
    recent_items = items_df[items_df['clean_date'] >= start_date].copy()
    print("get_import_forecast: Filtered recent_items, shape =", recent_items.shape)
    if recent_items.empty:
        print("get_import_forecast: recent_items is empty!")
        return []
        
    print("get_import_forecast: Grouping by product...")
    summary = recent_items.groupby('product_name').agg(
        total_quantity=('quantity', 'sum'),
        total_sales_value=('value', 'sum'),
        sales_count=('quantity', 'count')
    ).reset_index()
    print("get_import_forecast: Grouped summary, shape =", summary.shape)
    
    print("get_import_forecast: Fetching product groups...")
    products_df = load_products_df(url, key)
    if not products_df.empty:
        summary = pd.merge(summary, products_df, on='product_name', how='left')
        summary['group_name'] = summary['group_name'].fillna('Unmapped')
    else:
        summary['group_name'] = 'Unmapped'
    
    print("get_import_forecast: Calculating velocity metrics...")
    summary['monthly_run_rate'] = (summary['total_quantity'] / days) * 30.0
    summary['projected_3month_demand'] = summary['monthly_run_rate'] * 3.0
    summary['suggested_order_qty'] = summary['projected_3month_demand'] * 1.25
    
    print("get_import_forecast: Rounding columns...")
    summary['total_quantity'] = summary['total_quantity'].round(1)
    summary['total_sales_value'] = summary['total_sales_value'].round(2)
    summary['monthly_run_rate'] = summary['monthly_run_rate'].round(1)
    summary['projected_3month_demand'] = summary['projected_3month_demand'].round(1)
    summary['suggested_order_qty'] = summary['suggested_order_qty'].fillna(0.0).round(0).astype(int)
    
    print("get_import_forecast: Sorting results...")
    result = summary.sort_values(by='suggested_order_qty', ascending=False)
    print("get_import_forecast: Done! Returning", len(result), "records.")
    return result.to_dict(orient='records')
