import requests
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
supabase_url = env.get('SUPABASE_URL')
supabase_key = env.get('SUPABASE_KEY')

if not supabase_url or 'replace_with' in supabase_url:
    print("Please configure your .env file with your correct Supabase URL first.")
    exit(1)

# Clean up the Supabase URL
supabase_url = supabase_url.strip()
if supabase_url.endswith('/rest/v1/'):
    supabase_url = supabase_url[:-9]
elif supabase_url.endswith('/rest/v1'):
    supabase_url = supabase_url[:-8]
if supabase_url.endswith('/'):
    supabase_url = supabase_url[:-1]

headers = {
    "apikey": supabase_key,
    "Authorization": f"Bearer {supabase_key}"
}

print("Fetching OpenAPI schema from Supabase to list visible tables...")
res = requests.get(f"{supabase_url}/rest/v1/", headers=headers)

if res.status_code == 200:
    schema = res.json()
    paths = list(schema.get('paths', {}).keys())
    print("\n--- Available Database Endpoints (Tables) ---")
    if paths:
        for path in paths:
            if path != '/':
                print(f"Table found: {path.replace('/','')}")
    else:
        print("No tables found! Your database is completely empty.")
else:
    print(f"Error connecting to Supabase: {res.status_code} - {res.text}")
