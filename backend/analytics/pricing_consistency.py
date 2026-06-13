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
    
    if items_df.empty:
        return []
        
    product_rates = items_df.groupby('product_name').agg(
        min_rate=('rate', 'min'),
        max_rate=('rate', 'max'),
        avg_rate=('rate', 'mean'),
        std_rate=('rate', 'std'),
        sales_count=('rate', 'count')
    ).reset_index()
    
    product_rates['rate_spread_pct'] = ((product_rates['max_rate'] - product_rates['min_rate']) / product_rates['avg_rate']) * 100
    product_rates['rate_spread_pct'] = product_rates['rate_spread_pct'].fillna(0.0)
    product_rates['std_rate'] = product_rates['std_rate'].fillna(0.0)
    
    varying_prices = product_rates[product_rates['sales_count'] >= min_sales].sort_values(by='rate_spread_pct', ascending=False)
    return varying_prices.to_dict(orient='records')
