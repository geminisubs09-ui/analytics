import sys
import os

# Ensure project root is in the path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from backend.analytics.group_sales import get_group_sales
from backend.analytics.top_customers import get_top_customers, get_top_sellers
from backend.analytics.top_products import get_top_products, get_top_sales_products
from backend.analytics.daily_trends import get_daily_trends
from backend.analytics.pricing_consistency import get_pricing_consistency
from backend.analytics.weekday_sales import get_weekday_sales
from backend.analytics.pareto import get_pareto_analysis
from backend.analytics.miti_trends import get_miti_daily_trends, get_miti_monthly_trends
from backend.analytics.customer_retention import get_customer_retention
from backend.analytics.voucher_type_sales import get_sales_by_voucher_type
from backend.analytics.highest_margin_products import get_highest_margin_products
from backend.analytics.highest_margin_customers import get_highest_margin_customers
from backend.main import get_ungrouped_products

funcs = [
    ("get_group_sales", get_group_sales),
    ("get_top_customers", get_top_customers),
    ("get_top_sellers", get_top_sellers),
    ("get_top_products", get_top_products),
    ("get_top_sales_products", get_top_sales_products),
    ("get_daily_trends", get_daily_trends),
    ("get_pricing_consistency", get_pricing_consistency),
    ("get_weekday_sales", get_weekday_sales),
    ("get_pareto_analysis", get_pareto_analysis),
    ("get_miti_daily_trends", get_miti_daily_trends),
    ("get_miti_monthly_trends", get_miti_monthly_trends),
    ("get_customer_retention", get_customer_retention),
    ("get_sales_by_voucher_type", get_sales_by_voucher_type),
    ("get_highest_margin_products", get_highest_margin_products),
    ("get_highest_margin_customers", get_highest_margin_customers),
    ("get_ungrouped_products", get_ungrouped_products)
]

for name, func in funcs:
    print(f"--- Calling {name} ---")
    try:
        res = func()
        print(f"SUCCESS: Type of response: {type(res)}")
        if isinstance(res, list):
            print(f"Returned list with {len(res)} items.")
            if res:
                print(f"Sample: {res[0]}")
        else:
            print(f"Returned: {res}")
    except Exception as e:
        print(f"ERROR in {name}:")
        import traceback
        traceback.print_exc()
    print("-" * 50)
