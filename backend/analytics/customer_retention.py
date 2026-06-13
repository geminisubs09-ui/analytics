import pandas as pd
from datetime import datetime
from fastapi import APIRouter
from backend.analytics.utils import get_supabase_credentials, load_vouchers_df, apply_analytics_filters

router = APIRouter()

@router.get("/analytics/customer-retention")
def get_customer_retention(start_date: str = None, end_date: str = None):
    url, key = get_supabase_credentials()
    vouchers_df = load_vouchers_df(url, key)
    if vouchers_df.empty:
        return []
        
    vouchers_df, _ = apply_analytics_filters(
        vouchers_df=vouchers_df,
        start_date=start_date,
        end_date=end_date
    )
    
    # Drop rows where party is missing
    vouchers_df = vouchers_df[vouchers_df['party'].notna() & (vouchers_df['party'].str.strip() != '')]
    if vouchers_df.empty:
        return []
        
    # We clean the dates to YYYY-MM-DD
    vouchers_df['clean_date'] = vouchers_df['date'].apply(lambda d: str(d).split(' ')[0] if pd.notna(d) else '')
    vouchers_df = vouchers_df[vouchers_df['clean_date'] != '']
    if vouchers_df.empty:
        return []
        
    max_date_str = vouchers_df['clean_date'].max()
    max_dataset_date = datetime.strptime(max_date_str, '%Y-%m-%d')
    
    # Calculate statistics per customer
    customer_groups = vouchers_df.groupby('party')
    
    retention_list = []
    for party_name, group in customer_groups:
        dates_sorted = sorted(group['clean_date'].tolist())
        first_order = dates_sorted[0]
        last_order = dates_sorted[-1]
        
        last_order_dt = datetime.strptime(last_order, '%Y-%m-%d')
        inactive_days = (max_dataset_date - last_order_dt).days
        
        avg_interval = None
        if len(dates_sorted) >= 2:
            parsed_dates = [datetime.strptime(d, '%Y-%m-%d') for d in dates_sorted]
            diffs = [(parsed_dates[i] - parsed_dates[i-1]).days for i in range(1, len(parsed_dates))]
            avg_interval = sum(diffs) / len(diffs)
            
        if inactive_days <= 3:
            status = "Active"
        elif inactive_days <= 7:
            status = "Slowing Down"
        else:
            status = "Churn Risk"
            
        total_orders = len(group)
        total_rev = float(group['value'].sum())
        avg_val = float(group['value'].mean())
        
        retention_list.append({
            "party": party_name,
            "first_order_date": first_order,
            "last_order_date": last_order,
            "total_orders": total_orders,
            "total_revenue": round(total_rev, 2),
            "avg_order_value": round(avg_val, 2),
            "avg_order_interval_days": round(avg_interval, 2) if avg_interval is not None else None,
            "inactive_days": inactive_days,
            "status": status
        })
        
    retention_list = sorted(retention_list, key=lambda x: x['total_revenue'], reverse=True)
    return retention_list
