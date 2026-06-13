import pandas as pd
import requests
from fastapi import APIRouter
from backend.analytics.utils import get_supabase_credentials, load_sales_items_df, apply_analytics_filters

router = APIRouter()

@router.get("/analytics/pricing-consistency")
def get_pricing_consistency(min_sales: int = 5, start_date: str = None, end_date: str = None, party: str = None, product_group: str = None):
    url, key = get_supabase_credentials()
    items_df = load_sales_items_df(url, key)
    if items_df.empty:
        return []
        
    headers = {"apikey": key, "Authorization": f"Bearer {key}"}
    prod_res = requests.get(f"{url}/rest/v1/products?select=product_name,group_name", headers=headers)
    products_df = pd.DataFrame(prod_res.json()) if prod_res.status_code == 200 else pd.DataFrame()
    
    _, items_df = apply_analytics_filters(
        items_df=items_df,
        products_df=products_df,
        start_date=start_date,
        end_date=end_date,
        party=party,
        product_group=product_group
    )
    
    # Exclude products in the 'Indian Item' group
    if not products_df.empty and not items_df.empty:
        merged = pd.merge(items_df, products_df, on='product_name', how='left')
        merged['group_name'] = merged['group_name'].fillna('')
        items_df = merged[merged['group_name'].str.lower().str.strip() != 'indian item']
        
    if items_df.empty:
        return []
        
    records = []
    for product_name, group in items_df.groupby('product_name'):
        sales_count = len(group)
        if sales_count < min_sales:
            continue
        min_rate = float(group['rate'].min())
        max_rate = float(group['rate'].max())
        avg_rate = float(group['rate'].mean())
        std_rate = float(group['rate'].std()) if sales_count > 1 else 0.0
        
        # Get invoices/parties for min rate
        min_rows = group[group['rate'] == min_rate]
        min_details = []
        for _, r in min_rows.drop_duplicates(subset=['vch_no']).head(3).iterrows():
            min_details.append(f"#{r['vch_no']}")
        min_rate_invoices = ", ".join(min_details)
        
        # Get invoices/parties for max rate
        max_rows = group[group['rate'] == max_rate]
        max_details = []
        for _, r in max_rows.drop_duplicates(subset=['vch_no']).head(3).iterrows():
            max_details.append(f"#{r['vch_no']}")
        max_rate_invoices = ", ".join(max_details)
        
        rate_spread_pct = ((max_rate - min_rate) / avg_rate) * 100 if avg_rate > 0 else 0.0
        
        records.append({
            'product_name': product_name,
            'min_rate': min_rate,
            'max_rate': max_rate,
            'avg_rate': avg_rate,
            'std_rate': std_rate if not pd.isna(std_rate) else 0.0,
            'sales_count': sales_count,
            'rate_spread_pct': rate_spread_pct,
            'min_rate_invoices': min_rate_invoices,
            'max_rate_invoices': max_rate_invoices
        })
        
    varying_prices = pd.DataFrame(records)
    if varying_prices.empty:
        return []
    varying_prices = varying_prices.sort_values(by='rate_spread_pct', ascending=False)
    return varying_prices.to_dict(orient='records')
