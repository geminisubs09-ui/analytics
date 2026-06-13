-- Create Vouchers Table
CREATE TABLE IF NOT EXISTS vouchers (
    date DATE,
    miti TEXT,
    party TEXT,
    vch_type TEXT,
    vch_no TEXT,
    value NUMERIC(15, 2),
    revenue NUMERIC(15, 2),
    cost NUMERIC(15, 2),
    profit NUMERIC(15, 2),
    profit_pct NUMERIC(10, 2),
    PRIMARY KEY (vch_type, vch_no)
);

-- Create Products Group Mapping Table
CREATE TABLE IF NOT EXISTS products (
    product_name TEXT PRIMARY KEY,
    group_name TEXT NOT NULL
);

-- Create Sales Items Table
CREATE TABLE IF NOT EXISTS sales_items (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    date DATE,
    party TEXT,
    vch_type TEXT NOT NULL,
    vch_no TEXT NOT NULL,
    product_name TEXT NOT NULL,
    quantity NUMERIC(12, 3),
    rate NUMERIC(12, 2),
    value NUMERIC(15, 2),
    FOREIGN KEY (vch_type, vch_no) REFERENCES vouchers (vch_type, vch_no) ON DELETE CASCADE
);

-- Indexing for Performance
CREATE INDEX IF NOT EXISTS idx_sales_items_voucher ON sales_items (vch_type, vch_no);
CREATE INDEX IF NOT EXISTS idx_sales_items_product ON sales_items (product_name);
