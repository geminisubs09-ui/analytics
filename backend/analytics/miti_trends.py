import pandas as pd
import requests
from fastapi import APIRouter
from backend.analytics.utils import get_supabase_credentials, load_vouchers_df, load_sales_items_df, load_products_df, apply_analytics_filters

router = APIRouter()

@router.get("/analytics/miti-daily-trends")
def get_miti_daily_trends(
    start_date: str = None, 
    end_date: str = None, 
    party: str = None, 
    product_group: str = None,
    start_miti: str = None,
    end_miti: str = None
):
    url, key = get_supabase_credentials()
    vouchers_df = load_vouchers_df(url, key)
    if vouchers_df.empty:
        return []
        
    items_df = None
    products_df = None
    if product_group:
        items_df = load_sales_items_df(url, key)
        products_df = load_products_df(url, key)
            
    vouchers_df, items_df = apply_analytics_filters(
        vouchers_df=vouchers_df,
        items_df=items_df,
        products_df=products_df,
        start_date=start_date,
        end_date=end_date,
        party=party,
        product_group=product_group,
        start_miti=start_miti,
        end_miti=end_miti
    )
    
    if product_group:
        if items_df.empty:
            return []
        if 'miti' not in items_df.columns:
            items_df = pd.merge(items_df, vouchers_df[['vch_type', 'vch_no', 'miti', 'profit_pct']], on=['vch_type', 'vch_no'], how='inner')
        else:
            items_df = pd.merge(items_df, vouchers_df[['vch_type', 'vch_no', 'profit_pct']], on=['vch_type', 'vch_no'], how='inner')
            
        items_df = items_df[items_df['miti'].notna() & (items_df['miti'] != '')]
        if items_df.empty:
            return []
            
        def get_miti_sort_key(miti_str):
            parts = str(miti_str).strip().split('-')
            if len(parts) == 3:
                return f"{parts[2]}-{parts[1]}-{parts[0]}"
            return ""
            
        items_df['sort_key'] = items_df['miti'].apply(get_miti_sort_key)
        items_df['estimated_profit'] = items_df['value'] * (items_df['profit_pct'].fillna(0.0) / 100.0)
        items_df['vch_key'] = items_df['vch_type'].astype(str) + "_" + items_df['vch_no'].astype(str)
        
        daily_sales = items_df.groupby(['miti', 'sort_key']).agg(
            daily_sales=('value', 'sum'),
            daily_profit=('estimated_profit', 'sum'),
            vouchers_count=('vch_key', 'nunique')
        ).reset_index().sort_values(by='sort_key')
    else:
        vouchers_df = vouchers_df[vouchers_df['miti'].notna() & (vouchers_df['miti'] != '')]
        if vouchers_df.empty:
            return []
            
        def get_miti_sort_key(miti_str):
            parts = str(miti_str).strip().split('-')
            if len(parts) == 3:
                return f"{parts[2]}-{parts[1]}-{parts[0]}"
            return ""
            
        vouchers_df['sort_key'] = vouchers_df['miti'].apply(get_miti_sort_key)
        
        daily_sales = vouchers_df.groupby(['miti', 'sort_key']).agg(
            daily_sales=('value', 'sum'),
            daily_profit=('profit', 'sum'),
            vouchers_count=('vch_no', 'count')
        ).reset_index().sort_values(by='sort_key')
        
    daily_sales = daily_sales.drop(columns=['sort_key'])
    return daily_sales.to_dict(orient='records')

@router.get("/analytics/miti-monthly-trends")
def get_miti_monthly_trends(
    start_date: str = None, 
    end_date: str = None, 
    party: str = None, 
    product_group: str = None,
    start_miti: str = None,
    end_miti: str = None
):
    url, key = get_supabase_credentials()
    vouchers_df = load_vouchers_df(url, key)
    if vouchers_df.empty:
        return []
        
    items_df = None
    products_df = None
    if product_group:
        items_df = load_sales_items_df(url, key)
        products_df = load_products_df(url, key)
            
    vouchers_df, items_df = apply_analytics_filters(
        vouchers_df=vouchers_df,
        items_df=items_df,
        products_df=products_df,
        start_date=start_date,
        end_date=end_date,
        party=party,
        product_group=product_group,
        start_miti=start_miti,
        end_miti=end_miti
    )
    
    NEPALI_MONTHS = {
        "01": "Baishakh",
        "02": "Jestha",
        "03": "Ashadh",
        "04": "Shrawan",
        "05": "Bhadra",
        "06": "Ashwin",
        "07": "Kartik",
        "08": "Mangsir",
        "09": "Poush",
        "10": "Magh",
        "11": "Falgun",
        "12": "Chaitra"
    }
    
    def parse_miti_parts(miti_str):
        parts = str(miti_str).strip().split('-')
        if len(parts) == 3:
            y = parts[2]
            m = parts[1]
            m_name = NEPALI_MONTHS.get(m, f"Month {m}")
            return pd.Series([y, m, m_name, f"{y}-{m}"])
        return pd.Series(["", "", "", ""])
        
    if product_group:
        if items_df.empty:
            return []
        if 'miti' not in items_df.columns:
            items_df = pd.merge(items_df, vouchers_df[['vch_type', 'vch_no', 'miti', 'profit_pct']], on=['vch_type', 'vch_no'], how='inner')
        else:
            items_df = pd.merge(items_df, vouchers_df[['vch_type', 'vch_no', 'profit_pct']], on=['vch_type', 'vch_no'], how='inner')
            
        items_df = items_df[items_df['miti'].notna() & (items_df['miti'] != '')]
        if items_df.empty:
            return []
            
        items_df[['year', 'month_code', 'month_name', 'period_sort_key']] = items_df['miti'].apply(parse_miti_parts)
        items_df = items_df[items_df['year'] != ""]
        items_df['estimated_profit'] = items_df['value'] * (items_df['profit_pct'].fillna(0.0) / 100.0)
        items_df['vch_key'] = items_df['vch_type'].astype(str) + "_" + items_df['vch_no'].astype(str)
        
        monthly_sales = items_df.groupby(['year', 'month_code', 'month_name', 'period_sort_key']).agg(
            monthly_sales=('value', 'sum'),
            monthly_profit=('estimated_profit', 'sum'),
            vouchers_count=('vch_key', 'nunique')
        ).reset_index().sort_values(by='period_sort_key')
    else:
        vouchers_df = vouchers_df[vouchers_df['miti'].notna() & (vouchers_df['miti'] != '')]
        if vouchers_df.empty:
            return []
            
        vouchers_df[['year', 'month_code', 'month_name', 'period_sort_key']] = vouchers_df['miti'].apply(parse_miti_parts)
        vouchers_df = vouchers_df[vouchers_df['year'] != ""]
        if vouchers_df.empty:
            return []
            
        monthly_sales = vouchers_df.groupby(['year', 'month_code', 'month_name', 'period_sort_key']).agg(
            monthly_sales=('value', 'sum'),
            monthly_profit=('profit', 'sum'),
            vouchers_count=('vch_no', 'count')
        ).reset_index().sort_values(by='period_sort_key')
        
    monthly_sales['period'] = monthly_sales['month_name'] + " " + monthly_sales['year']
    monthly_sales = monthly_sales.drop(columns=['period_sort_key'])
    return monthly_sales.to_dict(orient='records')
