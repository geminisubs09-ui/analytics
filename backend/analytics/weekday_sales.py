import pandas as pd
import requests
from datetime import datetime
from fastapi import APIRouter
from backend.analytics.utils import get_supabase_credentials, load_vouchers_df, load_sales_items_df, apply_analytics_filters

router = APIRouter()

@router.get("/analytics/weekday-sales")
def get_weekday_sales(start_date: str = None, end_date: str = None, party: str = None, product_group: str = None):
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
    
    def get_weekday_name(d):
        if pd.isna(d) or not d:
            return None
        try:
            return datetime.strptime(str(d).split(' ')[0], '%Y-%m-%d').strftime('%A')
        except Exception:
            return None

    if product_group:
        if items_df.empty:
            return []
        items_df['day_of_week'] = items_df['date'].apply(get_weekday_name)
        items_df['vch_key'] = items_df['vch_type'].astype(str) + "_" + items_df['vch_no'].astype(str)
        dow_sales = items_df.groupby('day_of_week').agg(
            total_sales=('value', 'sum'),
            vouchers_count=('vch_key', 'nunique')
        ).reset_index()
    else:
        if vouchers_df.empty:
            return []
        vouchers_df['day_of_week'] = vouchers_df['date'].apply(get_weekday_name)
        dow_sales = vouchers_df.groupby('day_of_week').agg(
            total_sales=('value', 'sum'),
            vouchers_count=('vch_no', 'count')
        ).reset_index()
        
    # Order weekdays logically starting with Monday
    order = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
    dow_sales['day_index'] = dow_sales['day_of_week'].apply(lambda x: order.index(x) if x in order else 9)
    dow_sales = dow_sales.sort_values(by='day_index').drop(columns=['day_index'])
    
    return dow_sales.to_dict(orient='records')
