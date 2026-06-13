import pandas as pd
from fastapi import APIRouter
from backend.analytics.utils import get_supabase_credentials, load_vouchers_df, apply_analytics_filters

router = APIRouter()

@router.get("/analytics/highest-margin-customers")
def get_highest_margin_customers(limit: int = None, start_date: str = None, end_date: str = None):
    url, key = get_supabase_credentials()
    vouchers_df = load_vouchers_df(url, key)
    if vouchers_df.empty:
        return []
        
    vouchers_df, _ = apply_analytics_filters(
        vouchers_df=vouchers_df,
        start_date=start_date,
        end_date=end_date
    )
    
    if vouchers_df.empty:
        return []
        
    # Aggregate by customer (party)
    customer_summary = vouchers_df.groupby('party').agg(
        total_sales=('value', 'sum'),
        total_profit=('profit', 'sum')
    ).reset_index()
    
    customer_summary['profit_margin_pct'] = (customer_summary['total_profit'] / customer_summary['total_sales']) * 100
    customer_summary['profit_margin_pct'] = customer_summary['profit_margin_pct'].fillna(0.0)
    
    customer_summary = customer_summary.sort_values(by='profit_margin_pct', ascending=False)
    if limit is not None:
        customer_summary = customer_summary.head(limit)
    
    return customer_summary.to_dict(orient='records')
