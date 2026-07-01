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
from backend.analytics.pareto import router as pareto_router
from backend.analytics.miti_trends import router as miti_trends_router
from backend.analytics.customer_retention import router as customer_retention_router
from backend.analytics.voucher_type_sales import router as voucher_type_sales_router
from backend.analytics.highest_margin_products import router as highest_margin_products_router
from backend.analytics.highest_margin_customers import router as highest_margin_customers_router
from backend.analytics.import_forecast import router as import_forecast_router
from backend.analytics.customer_clv import router as customer_clv_router
from backend.analytics.slow_moving_stock import router as slow_moving_stock_router
from backend.analytics.sales_forecast import router as sales_forecast_router
from backend.analytics.utils import load_vouchers_df, load_sales_items_df

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
app.include_router(pareto_router)
app.include_router(miti_trends_router)
app.include_router(customer_retention_router)
app.include_router(voucher_type_sales_router)
app.include_router(highest_margin_products_router)
app.include_router(highest_margin_customers_router)
app.include_router(import_forecast_router)
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
    xls = pd.ExcelFile(io.BytesIO(contents))
    sheet_name = 'Sales Register' if 'Sales Register' in xls.sheet_names else \
                 ('Day Book' if 'Day Book' in xls.sheet_names else xls.sheet_names[0])
                 
    df = pd.read_excel(xls, sheet_name=sheet_name, header=None)
    num_cols = df.shape[1]
    
    vouchers = []
    items = []
    product_costs = {}
    
    if num_cols >= 14:
        # Sales Register format
        current_voucher = None
        for i in range(5, len(df)):
            row = df.iloc[i].tolist()
            if len(row) < 14:
                continue
            date_val = row[0]
            miti_val = row[1]
            party_val = row[2]
            vch_type = row[7]
            vch_no = row[8]
            
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
                        'value': float(val),
                        'cost': None,
                        'cost_rate': None
                    })
        return vouchers, items, product_costs

    else:
        # Day Book format (11 columns)
        current_vch_type = None
        for i in range(5, len(df)):
            row = df.iloc[i].tolist()
            if len(row) < 9:
                continue
            date_val = row[0]
            vch_type = row[7]
            vch_no = row[8]
            
            is_vch = pd.notna(date_val) and date_val != 'Total:' and pd.notna(vch_no) and pd.notna(vch_type)
            if is_vch:
                current_vch_type = str(vch_type).strip()
            elif current_vch_type == 'Purchase':
                item_name = row[1]
                qty = row[2]
                rate = row[3]
                if (pd.notna(item_name) and item_name not in ['New Ref'] and 
                    isinstance(qty, (int, float)) and pd.notna(qty) and 
                    isinstance(rate, (int, float)) and pd.notna(rate)):
                    product_costs[str(item_name).strip()] = float(rate)
                    
        sales_types = {'Sales', 'Head Office Sales', 'Bafal Sales', 'Pasal', 'Payment', 'Receipt'}
        current_voucher = None
        pending_narration = None
        for i in range(5, len(df)):
            row = df.iloc[i].tolist()
            if len(row) < 9:
                continue
            date_val = row[0]
            miti_val = row[1]
            party_val = row[2]
            vch_type = row[7]
            vch_no = row[8]
            
            is_vch = pd.notna(date_val) and date_val != 'Total:' and pd.notna(vch_no) and pd.notna(vch_type)
            if is_vch:
                vch_type_str = str(vch_type).strip()
                if vch_type_str in sales_types:
                    date_str = str(date_val).split(' ')[0] if pd.notna(date_val) else None
                    val_9 = float(row[9]) if pd.notna(row[9]) else 0.0
                    val_10 = float(row[10]) if pd.notna(row[10]) else 0.0
                    voucher_value = val_9 if val_9 > 0 else val_10
                    
                    current_voucher = {
                        'date': date_str,
                        'miti': str(miti_val) if pd.notna(miti_val) else None,
                        'party': str(party_val).strip() if pd.notna(party_val) else None,
                        'vch_type': vch_type_str,
                        'vch_no': str(vch_no).strip(),
                        'value': voucher_value,
                        'revenue': 0.0,
                        'cost': 0.0,
                        'profit': 0.0,
                        'profit_pct': 0.0
                    }
                    vouchers.append(current_voucher)
                    pending_narration = None
                else:
                    current_voucher = None
            elif current_voucher is not None:
                if current_voucher['vch_type'] in {'Payment', 'Receipt'}:
                    if pd.notna(row[1]) and pd.isna(row[2]) and pd.isna(row[3]) and pd.isna(row[4]):
                        pending_narration = str(row[1]).strip()
                    elif pd.isna(row[1]) and pd.notna(row[2]) and (pd.notna(row[3]) or pd.notna(row[4])):
                        leg_party = str(row[2]).strip()
                        leg_amount = float(row[3]) if pd.notna(row[3]) else (float(row[4]) if pd.notna(row[4]) else 0.0)
                        narration = pending_narration if pending_narration else leg_party
                        items.append({
                            'date': current_voucher['date'],
                            'party': leg_party,
                            'vch_type': current_voucher['vch_type'],
                            'vch_no': current_voucher['vch_no'],
                            'product_name': narration,
                            'quantity': 1.0,
                            'rate': leg_amount,
                            'value': leg_amount,
                            'cost': None,
                            'cost_rate': None
                        })
                        pending_narration = None
                else:
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
                            'value': float(val),
                            'cost': None,
                            'cost_rate': None
                        })
        return vouchers, items, product_costs

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
        vouchers, items, product_costs = parse_sales_excel(contents)
    except Exception as parse_err:
        raise HTTPException(status_code=400, detail=f"Failed to parse Excel file: {parse_err}")
        
    # 1. Update Supabase with new cost rates from Purchase vouchers
    if product_costs:
        sb_prods = [{"product_name": name, "group_name": "General", "cost_rate": rate} for name, rate in product_costs.items()]
        prod_headers = headers.copy()
        prod_headers["Prefer"] = "resolution=merge-duplicates"
        prod_res = requests.post(f"{url}/rest/v1/products", json=sb_prods, headers=prod_headers)
        if prod_res.status_code not in [200, 201]:
            raise HTTPException(status_code=500, detail=f"Failed to sync products: {prod_res.text}")
            
    # 2. Fetch all product cost rates from Supabase
    db_costs = {}
    limit = 1000
    offset = 0
    while True:
        prod_res = requests.get(f"{url}/rest/v1/products?select=product_name,cost_rate&limit={limit}&offset={offset}", headers=headers)
        if prod_res.status_code != 200:
            raise HTTPException(status_code=500, detail=f"Failed to fetch product costs: {prod_res.text}")
        data = prod_res.json()
        if not data:
            break
        for p in data:
            name = p.get('product_name')
            rate = p.get('cost_rate')
            if name and rate is not None:
                db_costs[name.strip()] = float(rate)
        if len(data) < limit:
            break
        offset += limit
        
    # Combine costs (new sheet takes precedence)
    db_costs.update(product_costs)
    
    # 3. Calculate cost/margin for sales items
    items_by_vch = {}
    for item in items:
        p_name = item['product_name']
        cost_rate = db_costs.get(p_name)
        if cost_rate is not None:
            item['cost'] = item['quantity'] * cost_rate
            item['cost_rate'] = cost_rate
        else:
            item['cost'] = None
            item['cost_rate'] = None
            
        key_tuple = (item['vch_type'], item['vch_no'])
        if key_tuple not in items_by_vch:
            items_by_vch[key_tuple] = []
        items_by_vch[key_tuple].append(item)
        
    # 4. Recalculate voucher totals
    for v in vouchers:
        key_tuple = (v['vch_type'], v['vch_no'])
        v_items = items_by_vch.get(key_tuple, [])
        
        if v['vch_type'] in {'Payment', 'Receipt'}:
            v['revenue'] = 0.0
            v['cost'] = None
            v['profit'] = None
            v['profit_pct'] = None
        else:
            if v.get('revenue', 0.0) == 0.0:
                v['revenue'] = sum(item['value'] for item in v_items)
                if v['value'] == 0.0:
                    v['value'] = v['revenue']
                    
                has_all_costs = all(item['cost'] is not None for item in v_items)
                if has_all_costs and v_items:
                    v['cost'] = sum(item['cost'] for item in v_items)
                    v['profit'] = v['revenue'] - v['cost']
                    v['profit_pct'] = (v['profit'] / v['revenue']) * 100.0 if v['revenue'] > 0 else 0.0
                else:
                    v['cost'] = None
                    v['profit'] = None
                    v['profit_pct'] = None
                
    # 5. Check for existing vouchers in Supabase
    existing_vouchers = set()
    limit = 1000
    offset = 0
    while True:
        vch_res = requests.get(f"{url}/rest/v1/vouchers?select=vch_type,vch_no&limit={limit}&offset={offset}", headers=headers)
        if vch_res.status_code != 200:
            raise HTTPException(status_code=500, detail=f"Failed to fetch existing vouchers: {vch_res.text}")
        data = vch_res.json()
        if not data:
            break
        for v in data:
            existing_vouchers.add((v['vch_type'], v['vch_no']))
        if len(data) < limit:
            break
        offset += limit
    
    vouchers_to_insert = []
    items_to_insert = []
    skipped_count = 0
    
    seen_in_batch = set()
    for v in vouchers:
        key_tuple = (v['vch_type'], v['vch_no'])
        if key_tuple in existing_vouchers or key_tuple in seen_in_batch:
            skipped_count += 1
            continue
        vouchers_to_insert.append(v)
        seen_in_batch.add(key_tuple)
        if key_tuple in items_by_vch:
            items_to_insert.extend(items_by_vch[key_tuple])
            
    if vouchers_to_insert:
        vch_insert_res = requests.post(f"{url}/rest/v1/vouchers", json=vouchers_to_insert, headers=headers)
        if vch_insert_res.status_code not in [200, 201]:
            raise HTTPException(status_code=500, detail=f"Failed to insert vouchers: {vch_insert_res.text}")
            
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
        items_res = requests.get(f"{url}/rest/v1/sales_items?select=product_name&vch_type=in.(Sales,Head%20Office%20Sales,Bafal%20Sales,Pasal)&limit={limit}&offset={offset}", headers=headers)
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

@app.get("/products/uncosted")
def get_uncosted_products():
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
        items_res = requests.get(f"{url}/rest/v1/sales_items?select=product_name&vch_type=in.(Sales,Head%20Office%20Sales,Bafal%20Sales,Pasal)&limit={limit}&offset={offset}", headers=headers)
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
        
    # Get products with defined cost_rate (paginated)
    costed_products = set()
    offset = 0
    while True:
        prod_res = requests.get(f"{url}/rest/v1/products?select=product_name,cost_rate&limit={limit}&offset={offset}", headers=headers)
        if prod_res.status_code != 200:
            raise HTTPException(status_code=500, detail=f"Failed to fetch mapped products: {prod_res.text}")
        data = prod_res.json()
        if not data:
            break
        for prod in data:
            name = prod.get('product_name')
            rate = prod.get('cost_rate')
            if name and rate is not None:
                costed_products.add(name.strip())
        if len(data) < limit:
            break
        offset += limit
        
    # Uncosted are sold but not in costed_products
    uncosted = list(sold_products - costed_products)
    return {"uncosted_products": sorted(uncosted), "count": len(uncosted)}

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

@app.get("/analytics/ledger")
def get_ledger(party: str, start_date: str = None, end_date: str = None, start_miti: str = None, end_miti: str = None):
    url, key = get_supabase_credentials()
    vouchers_df = load_vouchers_df(url, key)
    items_df = load_sales_items_df(url, key)
    
    if vouchers_df.empty and items_df.empty:
        return []
        
    def get_miti_key(miti_str):
        if pd.isna(miti_str) or not miti_str:
            return ""
        parts = str(miti_str).strip().split('-')
        if len(parts) == 3:
            return f"{parts[2]}-{parts[1]}-{parts[0]}"
        return ""
        
    start_miti_key = get_miti_key(start_miti) if start_miti else ""
    end_miti_key = get_miti_key(end_miti) if end_miti else ""
    
    ledger_entries = []
    
    # 1. Process Sales-related vouchers for this party
    sales_types = {'Sales', 'Head Office Sales', 'Bafal Sales', 'Pasal'}
    if not vouchers_df.empty:
        party_sales_vchs = vouchers_df[
            (vouchers_df['party'].str.lower() == party.lower().strip()) &
            (vouchers_df['vch_type'].isin(sales_types))
        ]
        
        for _, vch in party_sales_vchs.iterrows():
            vch_date = str(vch['date']) if pd.notna(vch['date']) else ""
            if start_date and vch_date < start_date:
                continue
            if end_date and vch_date > end_date:
                continue
            vch_miti = str(vch['miti']) if pd.notna(vch['miti']) else ""
            if start_miti_key and get_miti_key(vch_miti) < start_miti_key:
                continue
            if end_miti_key and get_miti_key(vch_miti) > end_miti_key:
                continue
                
            v_items_desc = ""
            if not items_df.empty:
                vch_items = items_df[
                    (items_df['vch_type'] == vch['vch_type']) &
                    (items_df['vch_no'] == vch['vch_no'])
                ]
                if not vch_items.empty:
                    v_items_desc = ", ".join(f"{row['product_name']} ({int(row['quantity']) if row['quantity'].is_integer() else row['quantity']})" for _, row in vch_items.iterrows())
                    
            ledger_entries.append({
                'date': vch_date,
                'miti': vch_miti,
                'vch_type': str(vch['vch_type']),
                'vch_no': str(vch['vch_no']),
                'debit': float(vch['value']),
                'credit': 0.0,
                'narration': v_items_desc
            })
            
    # 2. Process Payment and Receipt legs for this party
    if not items_df.empty:
        payment_receipt_items = items_df[
            (items_df['party'].str.lower() == party.lower().strip()) &
            (items_df['vch_type'].isin({'Payment', 'Receipt'}))
        ]
        
        if not payment_receipt_items.empty:
            if 'miti' not in payment_receipt_items.columns and not vouchers_df.empty:
                payment_receipt_items = pd.merge(payment_receipt_items, vouchers_df[['vch_type', 'vch_no', 'miti']], on=['vch_type', 'vch_no'], how='left')
                
            for _, item in payment_receipt_items.iterrows():
                item_date = str(item['date']) if pd.notna(item['date']) else ""
                if start_date and item_date < start_date:
                    continue
                if end_date and item_date > end_date:
                    continue
                item_miti = str(item['miti']) if 'miti' in item and pd.notna(item['miti']) else ""
                if start_miti_key and get_miti_key(item_miti) < start_miti_key:
                    continue
                if end_miti_key and get_miti_key(item_miti) > end_miti_key:
                    continue
                    
                v_type = str(item['vch_type'])
                val = float(item['value'])
                
                debit = val if v_type == 'Payment' else 0.0
                credit = val if v_type == 'Receipt' else 0.0
                
                ledger_entries.append({
                    'date': item_date,
                    'miti': item_miti,
                    'vch_type': v_type,
                    'vch_no': str(item['vch_no']),
                    'debit': debit,
                    'credit': credit,
                    'narration': str(item['product_name'])
                })
                
    ledger_entries = sorted(ledger_entries, key=lambda x: (x['date'], x['vch_no']))
    
    running_balance = 0.0
    for entry in ledger_entries:
        running_balance += entry['debit'] - entry['credit']
        entry['running_balance'] = running_balance
        
    return ledger_entries

@app.get("/raw/{table}")
def get_raw_table(table: str, filter: str = None):
    if table not in ["vouchers", "sales_items", "products"]:
        raise HTTPException(status_code=400, detail="Invalid table name")
    
    url, key = get_supabase_credentials()
    headers = {
        "apikey": key,
        "Authorization": f"Bearer {key}"
    }
    
    results = []
    limit = 1000
    offset = 0
    while True:
        req_url = f"{url}/rest/v1/{table}?select=*&limit={limit}&offset={offset}"
        if filter:
            req_url += f"&{filter}"
            
        res = requests.get(req_url, headers=headers)
        if res.status_code != 200:
            raise HTTPException(status_code=500, detail=f"Failed to fetch {table} from Supabase: {res.text}")
            
        data = res.json()
        if not data:
            break
        results.extend(data)
        if len(data) < limit:
            break
        offset += limit
        
    return results

