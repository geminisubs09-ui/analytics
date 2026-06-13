import sqlite3

conn = sqlite3.connect('data/sales_data.db')
c = conn.cursor()

print("--- Date ranges in vouchers ---")
c.execute("SELECT MIN(date), MAX(date) FROM vouchers")
print("Gregorian Date range:", c.fetchone())

c.execute("SELECT MIN(miti), MAX(miti) FROM vouchers")
print("Miti range:", c.fetchone())

print("\n--- Unique Gregorian Year-Months in vouchers ---")
c.execute("SELECT DISTINCT strftime('%Y-%m', date) as ym FROM vouchers ORDER BY ym")
for r in c.fetchall():
    print(r[0])

print("\n--- Unique Miti Year-Months in vouchers ---")
# Miti format is DD-MM-YYYY, so the year is the last 4 characters
c.execute("SELECT DISTINCT substr(miti, 7, 4) || '-' || substr(miti, 4, 2) as ym FROM vouchers ORDER BY ym")
for r in c.fetchall():
    print(r[0])

conn.close()
