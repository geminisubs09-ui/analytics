import pandas as pd
from fastapi import APIRouter
from backend.analytics.utils import get_supabase_credentials, load_sales_items_df, apply_analytics_filters

router = APIRouter()

@router.get("/analytics/market-basket")
def get_market_basket(start_date: str = None, end_date: str = None, party: str = None, product_group: str = None, min_support: int = 2, top_n: int = 15):
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
        
    # We want pairs of products that are in the same voucher
    # First, group items by vch_no and get list of unique products
    basket_df = items_df.groupby('vch_no')['product_name'].unique().reset_index()
    
    pairs_counts = {}
    
    for products in basket_df['product_name']:
        n = len(products)
        if n < 2:
            continue
            
        # generate unique pairs
        products_list = sorted(list(products))
        for i in range(n):
            for j in range(i+1, n):
                p1, p2 = products_list[i], products_list[j]
                pair = (p1, p2)
                pairs_counts[pair] = pairs_counts.get(pair, 0) + 1
                
    # Format to dict
    records = []
    for (p1, p2), count in pairs_counts.items():
        if count >= min_support:
            records.append({
                "product_a": p1,
                "product_b": p2,
                "frequency": count
            })
            
    df_pairs = pd.DataFrame(records)
    if df_pairs.empty:
        return []
        
    df_pairs = df_pairs.sort_values(by="frequency", ascending=False).head(top_n)
    
    return df_pairs.to_dict(orient="records")
