# Project Architectural Memory & Business Rules

This file documents the core architectural decisions, business constraints, and data-handling rules for the Sales Analytics & Flutter App project. **Any AI coding assistant must read this file before making any changes to the architecture.**

---

## 📱 App Architecture Directives
1. **Frontend**: Multiplatform Flutter application running on both **Android (Mobile)** and **Web**.
2. **Data Storage**: Local SQLite database (cached using Drift/Hive) synced with a cloud relational database (**Supabase PostgreSQL free tier**). **Do not rely on direct Excel parsing inside the frontend app.**
3. **ETL Pipeline**: An API backend (FastAPI or Node.js) handles raw Excel file uploads, parses them, and inserts them into the database.

---

## 🛡️ Data Integrity & Duplicate Prevention
1. **Primary Key Constraints**: A composite Primary Key or Unique Constraint must be enforced on `(vch_type, vch_no)` in the `vouchers` table.
2. **Conflict Policy**: When importing overlapping or duplicate Excel files, use `ON CONFLICT DO NOTHING` or `ON CONFLICT DO UPDATE` to skip or overwrite existing vouchers.
3. **Cascade Integrity**: Sales item lines are tied to vouchers via foreign key cascades. If a voucher is skipped as a duplicate, its items must not be re-imported.

---

## ⚠️ Unmapped / New Product Workflow (Direct User Requirement)
When importing sales data, new items may appear that do not exist in the product groups list (`products` table/file).
1. **Detection**: The import API must identify any product names in the imported sales register that are missing from the `products` mapping table.
2. **Notification Alert**: The backend must trigger and push a notification alert to the Flutter app: *"Check ungrouped items"*.
3. **In-App Resolution**: The Flutter App must provide an admin interface to:
   - Display a list of all current ungrouped products.
   - Allow the administrator to select and assign a product group (e.g., *Big Toys, Birthday Item, Fancy Toys, General, Indian Item*) directly from the app UI, which updates the database.
4. **File Update Fallback**: Alternatively, the administrator can update and upload a new version of the product group Excel file (`products.xlsx`) to resolve the mappings in bulk.

---

## 📆 Business Calendar Rules
1. **Nepal Weekend**: Saturdays are standard non-business days (NPR 0 sales). 
2. **Order Cycle**: Sundays are the busiest dispatch and order days (peak weekly sales). Tuesdays are the slowest order days. Use slow days for inventory planning.
3. **China Imports**: Goods are imported from China with a lead time of 2-3 months. Inventory planning is deferred for future implementation and must account for this 2-3 month lead time.

---

## 🛡️ Workspace Boundary & Security (CRITICAL)
1. **Strict Directory Isolation**: The AI coding assistant must ONLY read, write, or execute commands inside the `C:\Users\gupta\analytics` workspace directory.
2. **Production Safety**: Under no circumstances should the assistant read, write, list, or reference any sibling directories on the system (such as `bafa_v2`, `bafa_prime`, `bafa_catalogue`, `BILL ENTRY`, etc.), as those are production projects and must remain completely untouched and isolated.


