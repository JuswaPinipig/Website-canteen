# System Authentication Credentials & Account Registry
**Project:** Saint Joseph College — NovaLunch Enterprise Canteen System  
**Live Supabase URL:** `https://wtvkmywmlifcsddlgvnn.supabase.co`  
**Status:** All accounts verified active in Supabase Auth & PostgreSQL Profiles  

---

## 1. Student Portal Accounts

| Account Name | Email Address | Password | Student ID | RFID UID | Wallet Balance | Daily Cap |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Juan Dela Cruz** | `juan.student@sjc.edu.ph` | `Student123!` | `2023-01900` | `9A-4F-21-C8` | ₱350.00 | ₱200.00 |
| **Sophia Dela Cruz** | `sophia.student@sjc.edu.ph` | `Student123!` | `2023-01988` | `7B-3E-11-F4` | ₱420.00 | ₱250.00 |
| **Mark Anthony Santos** | `mark.student@sjc.edu.ph` | `Student123!` | `2023-02104` | `5C-2A-88-D1` | ₱85.00 | ₱150.00 |
| **Beatriz Ramos** | `beatriz.student@sjc.edu.ph` | `Student123!` | `2023-03011` | `3D-11-99-B0` | ₱120.00 | ₱200.00 |

---

## 2. Parent / Guardian Portal Accounts

| Account Name | Email Address | Password | Linked Student Accounts |
| :--- | :--- | :--- | :--- |
| **Maria Santos Dela Cruz** | `parent.maria@sjc.edu.ph` | `Parent123!` | Juan Dela Cruz & Sophia Dela Cruz |
| **Carlos Dela Cruz** | `parent.carlos@sjc.edu.ph` | `Parent123!` | Juan Dela Cruz |

---

## 3. Cashier POS Terminal Accounts

| Account Name | Email Address | Password | Terminal / Location |
| :--- | :--- | :--- | :--- |
| **Elena Rostata** | `cashier.pos@sjc.edu.ph` | `Cashier123!` | POS Terminal #01 (Main Canteen) |

---

## 4. System Administrator Accounts

| Account Name | Email Address | Password | Access Level |
| :--- | :--- | :--- | :--- |
| **System Administrator** | `admin.system@sjc.edu.ph` | `Admin123!` | Full System Administration (RBAC / Audits / Reports) |

---

## 5. Technical Connection Reference

```javascript
// Supabase Public Web Configuration
const SUPABASE_URL = "https://wtvkmywmlifcsddlgvnn.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_yywY2quhz5k1x6Pu_w6pgQ_e-mBU0q2";

// Programmatic Sign-In Example (JavaScript)
const { data, error } = await supabase.auth.signInWithPassword({
  email: 'juan.student@sjc.edu.ph',
  password: 'Student123!'
});
```
