import pandas as pd
from fastapi import APIRouter
from backend.analytics.utils import get_supabase_credentials, load_sales_items_df, load_products_df, apply_analytics_filters
from datetime import datetime, timedelta

router = APIRouter()

@router.get("/analytics/slow-moving-stock")
def get_slow_moving_stock(start_date: str = None, end_date: str = None, party: str = None, product_group: str = None, threshold_days: int = 60):
    url, key = get_supabase_credentials()
    items_df = load_sales_items_df(url, key)
    
    if items_df.empty:
        return []
        
    _, items_df = apply_analytics_filters(
        items_df=items_df,
        start_date=start_date,
        end_date=end_date,
        party=party,
        product_group=product_group
    )
    
    if items_df.empty:
        return []
        
    # Clean the date strings to avoid issues
    items_df['clean_date'] = items_df['date'].apply(lambda d: str(d).split(' ')[0] if pd.notna(d) else '')
    
    # We want to identify the maximum global date to serve as "today"
    max_date_str = items_df['clean_date'].max()
    if not max_date_str or pd.isna(max_date_str):
        return []
        
    try:
        max_date = datetime.strptime(max_date_str, '%Y-%m-%d')
    except Exception:
        return []
        
    # Group by product
    summary = items_df.groupby('product_name').agg(
        last_sale_date=('clean_date', 'max'),
        total_quantity=('quantity', 'sum'),
        total_revenue=('value', 'sum')
    ).reset_index()
    
    # Calculate days since last sale
    def calculate_days_since(d_str):
        try:
            d = datetime.strptime(d_str, '%Y-%m-%d')
            return (max_date - d).days
        except Exception:
            return 0
            
    summary['days_since_last_sale'] = summary['last_sale_date'].apply(calculate_days_since)
    
    # Filter for slow moving (days >= threshold_days)
    slow_moving = summary[summary['days_since_last_sale'] >= threshold_days].copy()
    
    if slow_moving.empty:
        return []
        
    # Optional: fetch product groups to enrich data
    products_df = load_products_df(url, key)
    if not products_df.empty:
        slow_moving = pd.merge(slow_moving, products_df, on='product_name', how='left')
        slow_moving['group_name'] = slow_moving['group_name'].fillna('Unmapped')
    else:
        slow_moving['group_name'] = 'Unmapped'
        
    # Sort by days since last sale (descending)
    slow_moving = slow_moving.sort_values(by='days_since_last_sale', ascending=False)
    
    slow_moving['total_quantity'] = slow_moving['total_quantity'].round(1)
    slow_moving['total_revenue'] = slow_moving['total_revenue'].round(2)
    
    return slow_moving.to_dict(orient='records')
