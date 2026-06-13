import requests
import json

BASE_URL = "http://127.0.0.1:8000"

endpoints = [
    ("/", "GET"),
    ("/analytics/group-sales", "GET"),
    ("/analytics/top-customers", "GET"),
    ("/analytics/top-sellers", "GET"),
    ("/analytics/top-products", "GET"),
    ("/analytics/top-sales-products", "GET"),
    ("/analytics/daily-trends", "GET"),
    ("/analytics/pricing-consistency", "GET"),
    ("/analytics/weekday-sales", "GET"),
    ("/analytics/pareto", "GET"),
    ("/analytics/miti-daily-trends", "GET"),
    ("/analytics/miti-monthly-trends", "GET"),
    ("/analytics/customer-retention", "GET"),
    ("/analytics/sales-by-voucher-type", "GET"),
    ("/analytics/highest-margin-products", "GET"),
    ("/analytics/highest-margin-customers", "GET"),
    ("/products/ungrouped", "GET")
]



def test_all():
    print("--- Database Date Range Diagnostics ---")
    try:
        import sqlite3
        conn = sqlite3.connect(r"C:\Users\gupta\analytics\data\sales_data.db")
        c = conn.cursor()
        c.execute("SELECT MIN(date), MAX(date) FROM vouchers")
        print("SQLite Gregorian date range:", c.fetchone())
        
        c.execute("SELECT MIN(miti), MAX(miti) FROM vouchers")
        print("SQLite Miti range:", c.fetchone())
        
        c.execute("SELECT DISTINCT strftime('%Y-%m', date) FROM vouchers ORDER BY 1")
        print("SQLite Year-Months:", [r[0] for r in c.fetchall()])
        
        conn.close()
    except Exception as e:
        print("Error reading SQLite dates:", e)

    print("\nTesting FastAPI endpoints...")
    for endpoint, method in endpoints:
        url = f"{BASE_URL}{endpoint}"
        print(f"Calling {method} {url}...")
        try:
            if method == "GET":
                res = requests.get(url)
            else:
                res = requests.post(url)
            print(f"Status: {res.status_code}")
            if res.status_code == 200:
                data = res.json()
                if isinstance(data, list):
                    print(f"Returned list with {len(data)} items. First item: {data[0] if data else 'None'}")
                elif isinstance(data, dict):
                    print(f"Returned dict keys: {list(data.keys())}")
                else:
                    print(f"Returned: {data}")
            else:
                print(f"Error: {res.text}")
        except Exception as e:
            print(f"Exception calling {url}: {e}")
        print("-" * 40)

if __name__ == '__main__':
    test_all()
