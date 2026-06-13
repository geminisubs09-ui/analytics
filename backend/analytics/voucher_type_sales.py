import pandas as pd
from fastapi import APIRouter
from backend.analytics.utils import get_supabase_credentials, load_vouchers_df, apply_analytics_filters

router = APIRouter()

@router.get("/analytics/sales-by-voucher-type")
def get_sales_by_voucher_type(start_date: str = None, end_date: str = None, party: str = None):
    url, key = get_supabase_credentials()
    vouchers_df = load_vouchers_df(url, key)
    if vouchers_df.empty:
        return []
        
    vouchers_df, _ = apply_analytics_filters(
        vouchers_df=vouchers_df,
        start_date=start_date,
        end_date=end_date,
        party=party
    )
    
    if vouchers_df.empty:
        return []
        
    # Group by vch_type
    summary = vouchers_df.groupby('vch_type').agg(
        total_sales=('value', 'sum'),
        total_profit=('profit', 'sum'),
        vouchers_count=('vch_no', 'count')
    ).reset_index()
    
    summary['profit_margin_pct'] = (summary['total_profit'] / summary['total_sales']) * 100
    summary['profit_margin_pct'] = summary['profit_margin_pct'].fillna(0.0)
    summary = summary.sort_values(by='total_sales', ascending=False)
    
    return summary.to_dict(orient='records')
