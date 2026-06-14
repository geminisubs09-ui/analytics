from fastapi import FastAPI, UploadFile, File, HTTPException, Form
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import pandas as pd
import requests
import io
import os

# Import modular routers
from backend.analytics.group_sales import router as group_sales_router
from backend.analytics.top_customers import router as top_customers_router
from backend.analytics.top_products import router as top_products_router
from backend.analytics.daily_trends import router as daily_trends_router
from backend.analytics.pricing_consistency import router as pricing_consistency_router
from backend.analytics.weekday_sales import router as weekday_sales_router
from backend.analytics.pareto import router as pareto_router
from backend.analytics.miti_trends import router as miti_trends_router
from backend.analytics.customer_retention import router as customer_retention_router
from backend.analytics.voucher_type_sales import router as voucher_type_sales_router
from backend.analytics.highest_margin_products import router as highest_margin_products_router
from backend.analytics.highest_margin_customers import router as highest_margin_customers_router
from backend.analytics.import_forecast import router as import_forecast_router
from backend.analytics.market_basket import router as market_basket_router
from backend.analytics.customer_clv import router as customer_clv_router
from backend.analytics.slow_moving_stock import router as slow_moving_stock_router
from backend.analytics.sales_forecast import router as sales_forecast_router

app = FastAPI(title="Sales Analytics Backend", version="1.0")

# Enable CORS for Flutter Web connections
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost",
        "http://localhost:8080",
        "http://localhost:3000",
        "https://geminisubs09-ui.github.io"
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(group_sales_router)
app.include_router(top_customers_router)
app.include_router(top_products_router)
app.include_router(daily_trends_router)
app.include_router(pricing_consistency_router)
app.include_router(weekday_sales_router)
app.include_router(pareto_router)
app.include_router(miti_trends_router)
app.include_router(customer_retention_router)
app.include_router(voucher_type_sales_router)
app.include_router(highest_margin_products_router)
app.include_router(highest_margin_customers_router)
app.include_router(import_forecast_router)
app.include_router(market_basket_router)
app.include_router(customer_clv_router)
app.include_router(slow_moving_stock_router)
app.include_router(sales_forecast_router)

# Helper function to load env variables from workspace .env
def get_supabase_credentials():
    # Check process environment variables first (for cloud deployments like Render)
    supabase_url = os.environ.get('SUPABASE_URL', '').strip()
    supabase_key = os.environ.get('SUPABASE_KEY', '').strip()
    
    if supabase_url and supabase_key:
        if supabase_url.endswith('/rest/v1/'):
            supabase_url = supabase_url[:-9]
        elif supabase_url.endswith('/rest/v1'):
            supabase_url = supabase_url[:-8]
        if supabase_url.endswith('/'):
            supabase_url = supabase_url[:-1]
        return supabase_url, supabase_key

    # Look for .env in the parent directory of backend (fallback for local development)
    backend_dir = os.path.dirname(os.path.abspath(__file__))
    env_path = os.path.join(os.path.dirname(backend_dir), ".env")
    
    env_vars = {}
    if not os.path.exists(env_path):
        raise HTTPException(status_code=500, detail=f".env config file not found at {env_path} and environment variables are not set")
        
    with open(env_path, 'r') as f:
        for line in f:
            if line.strip() and not line.startswith('#'):
                key, val = line.strip().split('=', 1)
                env_vars[key.strip()] = val.strip()
                
    supabase_url = env_vars.get('SUPABASE_URL', '').strip()
    supabase_key = env_vars.get('SUPABASE_KEY', '').strip()
    
    # Sanitize URL
    if supabase_url.endswith('/rest/v1/'):
        supabase_url = supabase_url[:-9]
    elif supabase_url.endswith('/rest/v1'):
        supabase_url = supabase_url[:-8]
    if supabase_url.endswith('/'):
        supabase_url = supabase_url[:-1]
        
    if not supabase_url or not supabase_key:
        raise HTTPException(status_code=500, detail="Supabase credentials missing in .env and environment variables are not set")
        
    return supabase_url, supabase_key

# Model for assigning groups
class AssignGroupRequest(BaseModel):
    product_name: str
    group_name: str

# --- PARSING HELPERS ---

def parse_sales_excel(contents):
    df = pd.read_excel(io.BytesIO(contents), sheet_name=0, header=None)
    
    vouchers = []
    items = []
    current_voucher = None
    
    for i in range(5, len(df)):
        row = df.iloc[i].tolist()
        date_val = row[0]
        miti_val = row[1]
        party_val = row[2]
        vch_type = row[7]
        vch_no = row[8]
        
        # Voucher Header
        if pd.notna(date_val) and date_val != 'Total:' and pd.notna(vch_no) and pd.notna(vch_type):
            date_str = str(date_val).split(' ')[0] if pd.notna(date_val) else None
            current_voucher = {
                'date': date_str,
                'miti': str(miti_val) if pd.notna(miti_val) else None,
                'party': str(party_val).strip() if pd.notna(party_val) else None,
                'vch_type': str(vch_type).strip() if pd.notna(vch_type) else None,
                'vch_no': str(vch_no).strip() if pd.notna(vch_no) else None,
                'value': float(row[9]) if pd.notna(row[9]) else 0.0,
                'revenue': float(row[10]) if pd.notna(row[10]) else 0.0,
                'cost': float(row[11]) if pd.notna(row[11]) else 0.0,
                'profit': float(row[12]) if pd.notna(row[12]) else 0.0,
                'profit_pct': float(row[13]) if pd.notna(row[13]) else 0.0
            }
            vouchers.append(current_voucher)
        elif current_voucher is not None:
            # Item Row
            item_name = row[1]
            qty = row[2]
            rate = row[3]
            val = row[4]
            
            if (pd.notna(item_name) and 
                item_name not in ['New Ref'] and 
                isinstance(qty, (int, float)) and pd.notna(qty) and 
                pd.notna(rate) and pd.notna(val)):
                
                items.append({
                    'date': current_voucher['date'],
                    'party': current_voucher['party'],
                    'vch_type': current_voucher['vch_type'],
                    'vch_no': current_voucher['vch_no'],
                    'product_name': str(item_name).strip(),
                    'quantity': float(qty),
                    'rate': float(rate),
                    'value': float(val)
                })
                
    return vouchers, items

def parse_products_excel(contents):
    df = pd.read_excel(io.BytesIO(contents), sheet_name=0)
    first_group_name = df.columns[0]
    current_group = first_group_name
    
    products = []
    for i in range(len(df)):
        item_name = df.iloc[i, 0]
        group_indicator = df.iloc[i, 1]
        
        if pd.isna(item_name):
            continue
            
        if str(group_indicator).strip() == 'group':
            current_group = str(item_name).strip()
        else:
            products.append({
                'product_name': str(item_name).strip(),
                'group_name': current_group
            })
    return products

# --- API ENDPOINTS ---

@app.get("/")
def read_root():
    return {"message": "Sales Analytics Backend API is running successfully."}

@app.post("/upload/sales")
async def upload_sales(file: UploadFile = File(...)):
    url, key = get_supabase_credentials()
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json"
    }
    
    try:
        contents = await file.read()
        vouchers, items = parse_sales_excel(contents)
    except Exception as parse_err:
        raise HTTPException(status_code=400, detail=f"Failed to parse Excel file: {parse_err}")
        
    # Check for existing vouchers in Supabase
    vch_res = requests.get(f"{url}/rest/v1/vouchers?select=vch_type,vch_no", headers=headers)
    if vch_res.status_code != 200:
        raise HTTPException(status_code=500, detail=f"Failed to fetch existing vouchers: {vch_res.text}")
        
    existing_vouchers = {(v['vch_type'], v['vch_no']) for v in vch_res.json()}
    
    vouchers_to_insert = []
    items_to_insert = []
    skipped_count = 0
    
    items_by_vch = {}
    for item in items:
        key_tuple = (item['vch_type'], item['vch_no'])
        if key_tuple not in items_by_vch:
            items_by_vch[key_tuple] = []
        items_by_vch[key_tuple].append(item)
        
    for v in vouchers:
        key_tuple = (v['vch_type'], v['vch_no'])
        if key_tuple in existing_vouchers:
            skipped_count += 1
            continue
        vouchers_to_insert.append(v)
        if key_tuple in items_by_vch:
            items_to_insert.extend(items_by_vch[key_tuple])
            
    if vouchers_to_insert:
        # Insert vouchers
        vch_insert_res = requests.post(f"{url}/rest/v1/vouchers", json=vouchers_to_insert, headers=headers)
        if vch_insert_res.status_code not in [200, 201]:
            raise HTTPException(status_code=500, detail=f"Failed to insert vouchers: {vch_insert_res.text}")
            
        # Insert items
        if items_to_insert:
            items_insert_res = requests.post(f"{url}/rest/v1/sales_items", json=items_to_insert, headers=headers)
            if items_insert_res.status_code not in [200, 201]:
                raise HTTPException(status_code=500, detail=f"Failed to insert sales items: {items_insert_res.text}")
                
    return {
        "message": "Sales sheet parsed and synced successfully.",
        "total_parsed_vouchers": len(vouchers),
        "skipped_duplicate_vouchers": skipped_count,
        "new_vouchers_imported": len(vouchers_to_insert),
        "new_items_imported": len(items_to_insert)
    }

@app.post("/upload/products")
async def upload_products(file: UploadFile = File(...)):
    url, key = get_supabase_credentials()
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates"
    }
    
    try:
        contents = await file.read()
        products = parse_products_excel(contents)
    except Exception as parse_err:
        raise HTTPException(status_code=400, detail=f"Failed to parse products Excel file: {parse_err}")
        
    prod_res = requests.post(f"{url}/rest/v1/products", json=products, headers=headers)
    if prod_res.status_code not in [200, 201]:
        raise HTTPException(status_code=500, detail=f"Failed to sync products: {prod_res.text}")
        
    return {
        "message": "Products mapping uploaded successfully.",
        "total_products_synced": len(products)
    }

@app.get("/products/ungrouped")
def get_ungrouped_products():
    url, key = get_supabase_credentials()
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}"
    }
    
    # Get distinct sold products (paginated)
    sold_products = set()
    limit = 1000
    offset = 0
    while True:
        items_res = requests.get(f"{url}/rest/v1/sales_items?select=product_name&limit={limit}&offset={offset}", headers=headers)
        if items_res.status_code != 200:
            raise HTTPException(status_code=500, detail=f"Failed to fetch sales items: {items_res.text}")
        data = items_res.json()
        if not data:
            break
        for item in data:
            name = item.get('product_name')
            if name:
                sold_products.add(name.strip())
        if len(data) < limit:
            break
        offset += limit
    
    # Get mapped products (paginated)
    mapped_products = set()
    offset = 0
    while True:
        prod_res = requests.get(f"{url}/rest/v1/products?select=product_name&limit={limit}&offset={offset}", headers=headers)
        if prod_res.status_code != 200:
            raise HTTPException(status_code=500, detail=f"Failed to fetch mapped products: {prod_res.text}")
        data = prod_res.json()
        if not data:
            break
        for prod in data:
            name = prod.get('product_name')
            if name:
                mapped_products.add(name.strip())
        if len(data) < limit:
            break
        offset += limit
    
    # Unmapped/ungrouped are the difference
    ungrouped = list(sold_products - mapped_products)
    
    return {"ungrouped_products": sorted(ungrouped), "count": len(ungrouped)}

@app.post("/products/assign-group")
def assign_group(req: AssignGroupRequest):
    url, key = get_supabase_credentials()
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates"
    }
    
    payload = {
        "product_name": req.product_name.strip(),
        "group_name": req.group_name.strip()
    }
    
    res = requests.post(f"{url}/rest/v1/products", json=[payload], headers=headers)
    if res.status_code not in [200, 201]:
        raise HTTPException(status_code=500, detail=f"Failed to assign group: {res.text}")
        
    return {
        "message": f"Successfully mapped '{req.product_name}' to group '{req.group_name}'."
    }
