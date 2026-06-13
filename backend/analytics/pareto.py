import pandas as pd
from fastapi import APIRouter
from backend.analytics.utils import get_supabase_credentials, load_vouchers_df, load_sales_items_df, apply_analytics_filters

router = APIRouter()

@router.get("/analytics/pareto")
def get_pareto_analysis(start_date: str = None, end_date: str = None):
    url, key = get_supabase_credentials()
    vouchers_df = load_vouchers_df(url, key)
    items_df = load_sales_items_df(url, key)
    
    vouchers_df, items_df = apply_analytics_filters(
        vouchers_df=vouchers_df,
        items_df=items_df,
        start_date=start_date,
        end_date=end_date
    )
    
    if vouchers_df.empty or items_df.empty:
        return {
            "total_sales": 0.0,
            "total_unique_parties": 0,
            "parties_generating_80_percent_sales": 0,
            "percentage_of_parties_generating_80_percent": 0.0,
            "total_unique_products": 0,
            "products_generating_80_percent_sales": 0,
            "percentage_of_products_generating_80_percent": 0.0
        }
        
    # 1. Parties Pareto
    top_parties = vouchers_df.groupby('party')['value'].sum().sort_values(ascending=False).reset_index()
    total_sales = vouchers_df['value'].sum()
    top_parties['cumulative_sales'] = top_parties['value'].cumsum()
    top_parties['cumulative_pct'] = (top_parties['cumulative_sales'] / total_sales) * 100
    parties_80 = top_parties[top_parties['cumulative_pct'] <= 85]
    num_parties_80 = len(parties_80) + 1
    pct_parties_80 = (num_parties_80 / len(top_parties)) * 100
    
    # 2. Products Pareto
    top_products = items_df.groupby('product_name')['value'].sum().sort_values(ascending=False).reset_index()
    total_items_sales = items_df['value'].sum()
    top_products['cumulative_sales'] = top_products['value'].cumsum()
    top_products['cumulative_pct'] = (top_products['cumulative_sales'] / total_items_sales) * 100
    products_80 = top_products[top_products['cumulative_pct'] <= 85]
    num_products_80 = len(products_80) + 1
    pct_products_80 = (num_products_80 / len(top_products)) * 100
    
    return {
        "total_sales": total_sales,
        "total_unique_parties": len(top_parties),
        "parties_generating_80_percent_sales": num_parties_80,
        "percentage_of_parties_generating_80_percent": round(pct_parties_80, 2),
        
        "total_unique_products": len(top_products),
        "products_generating_80_percent_sales": num_products_80,
        "percentage_of_products_generating_80_percent": round(pct_products_80, 2)
    }
