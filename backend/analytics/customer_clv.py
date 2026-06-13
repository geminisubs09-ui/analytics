import pandas as pd
from fastapi import APIRouter
from backend.analytics.utils import get_supabase_credentials, load_vouchers_df, apply_analytics_filters

router = APIRouter()

@router.get("/analytics/customer-clv")
def get_customer_clv(start_date: str = None, end_date: str = None, party: str = None):
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
        
    # Exclude invalid parties
    vouchers_df = vouchers_df[vouchers_df['party'].notna() & (vouchers_df['party'] != '')]
    
    # Calculate CLV metrics per party
    summary = vouchers_df.groupby('party').agg(
        total_revenue=('revenue', 'sum'),
        total_orders=('vch_no', 'nunique'),
        first_purchase=('date', 'min'),
        last_purchase=('date', 'max')
    ).reset_index()
    
    # Filter out customers with zero revenue
    summary = summary[summary['total_revenue'] > 0]
    
    summary['average_order_value'] = summary['total_revenue'] / summary['total_orders']
    
    # Calculate days since first purchase to find lifespan
    # Convert dates to datetime
    summary['first_purchase_dt'] = pd.to_datetime(summary['first_purchase'])
    summary['last_purchase_dt'] = pd.to_datetime(summary['last_purchase'])
    
    # Lifespan in days (at least 1 to avoid division by zero)
    summary['lifespan_days'] = (summary['last_purchase_dt'] - summary['first_purchase_dt']).dt.days
    summary['lifespan_days'] = summary['lifespan_days'].apply(lambda x: x if x > 0 else 1)
    
    # Purchase Frequency (orders per year)
    summary['purchase_frequency_annual'] = (summary['total_orders'] / summary['lifespan_days']) * 365.0
    
    # Estimated Annual CLV (Historical) = AOV * PF_annual
    summary['estimated_annual_clv'] = summary['average_order_value'] * summary['purchase_frequency_annual']
    
    # Round values
    summary['total_revenue'] = summary['total_revenue'].round(2)
    summary['average_order_value'] = summary['average_order_value'].round(2)
    summary['purchase_frequency_annual'] = summary['purchase_frequency_annual'].round(1)
    summary['estimated_annual_clv'] = summary['estimated_annual_clv'].round(2)
    
    # Sort by total revenue (Historical CLV)
    summary = summary.sort_values(by='total_revenue', ascending=False)
    
    # Convert dates back to string
    summary['first_purchase'] = summary['first_purchase_dt'].dt.strftime('%Y-%m-%d')
    summary['last_purchase'] = summary['last_purchase_dt'].dt.strftime('%Y-%m-%d')
    
    # Drop temp columns
    summary = summary.drop(columns=['first_purchase_dt', 'last_purchase_dt'])
    
    return summary.to_dict(orient='records')
