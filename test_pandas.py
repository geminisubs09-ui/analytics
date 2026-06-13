import requests
import pandas as pd
import os

def parse_env(env_path):
    env_vars = {}
    if not os.path.exists(env_path):
        return env_vars
    with open(env_path, 'r') as f:
        for line in f:
            if line.strip() and not line.startswith('#'):
                key, val = line.strip().split('=', 1)
                env_vars[key.strip()] = val.strip()
    return env_vars

env_path = r"C:\Users\gupta\analytics\.env"
env = parse_env(env_path)
url = env.get('SUPABASE_URL').strip()
key = env.get('SUPABASE_KEY').strip()

if url.endswith('/rest/v1/'):
    url = url[:-9]
elif url.endswith('/rest/v1'):
    url = url[:-8]
if url.endswith('/'):
    url = url[:-1]

headers = {"apikey": key, "Authorization": f"Bearer {key}"}
print("Fetching sales items...")
res = requests.get(f"{url}/rest/v1/sales_items?select=*", headers=headers)
print("Response status:", res.status_code)
data = res.json()
print("Data length:", len(data))
if data:
    print("Sample item:", data[0])
df = pd.DataFrame(data)
print("DataFrame shape:", df.shape)
print("DataFrame columns:", list(df.columns))

print("Converting value to numeric...")
df['value'] = pd.to_numeric(df['value'], errors='coerce')
print("Converting quantity to numeric...")
df['quantity'] = pd.to_numeric(df['quantity'], errors='coerce')
print("Converting rate to numeric...")
df['rate'] = pd.to_numeric(df['rate'], errors='coerce')
print("Converting date to datetime...")
df['date'] = pd.to_datetime(df['date'], errors='coerce')
print("Successfully loaded sales items df!")
