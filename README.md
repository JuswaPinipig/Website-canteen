# NovaLunch: An AI-Powered Canteen Management & Automated Checkout Ecosystem
> **Saint Joseph College of Novaliches, Inc.**

NovaLunch is an enterprise-grade AI canteen management system featuring automated visual tray classification, RFID student wallet authorization, real-time spending caps, parent oversight portals, multi-tier cashier POS terminals, and cloud database telemetry sync.

---

## 🏗️ Architecture & Directory Structure

The project strictly adheres to clean modular software architecture:

```
Website-canteen/
├── .env                              # Active environment variables
├── .env.example                      # Template environment variables configuration
├── .gitignore                        # Git ignore rules
├── DESIGN.md                         # System UI & UX design system specification
├── PRODUCT.md                        # Product requirements & specifications
├── README.md                         # Project documentation & run guides
├── requirements.txt                  # Python dependencies (PyQt5, Ultralytics YOLO, OpenCV, PyTorch)
├── skills-lock.json                  # Agent skill configuration lock
├── index.html                        # Root portal redirect landing page
├── OmniRoute/                        # AI Gateway Proxy Sub-system
└── src/
    ├── assets/                       # Static media, icons & trained model weights
    │   ├── images/
    │   │   ├── branding/             # Institutional logos & videos
    │   │   └── profiles/             # User avatar media
    │   └── models/
    │       └── novalunch_yolo.pt     # Trained YOLO object detection model weights
    ├── config/                       # Cloud & database rule configurations
    │   ├── database.rules.json       # Firebase Realtime DB rules
    │   ├── firebase-schema.json      # Firebase database schema definition
    │   ├── firebase-config.js        # Firebase JS SDK initialization
    │   └── storage.rules             # Firebase Storage security rules
    ├── hardware/                     # Edge hardware integrations & GUI kiosks
    │   └── student_kiosk_gui.py      # PyQt5 Edge Student Kiosk (RFID, Camera Watchdog)
    ├── ai_engine/                    # Model inference & dataset queues
    │   ├── inspect_yolo_model.py     # PyTorch/YOLO .pt weights metadata inspector
    │   ├── retrain_queue/            # Retrain dataset queue for edge model updates
    │   └── trays_queue/              # Edge tray capture buffer directory
    ├── database/                     # Local buffer DB & SQL migration scripts
    │   ├── novalunch_edge.db         # Local SQLite transaction buffer
    │   ├── accounts.json             # Seed account credentials
    │   ├── AUTHENTICATION_CREDENTIALS.md
    │   ├── final_governance_patch.sql
    │   ├── governance_patch.sql
    │   ├── inventory_batch_management.sql
    │   ├── operational_remediation_patch.sql
    │   ├── security_hardening.sql
    │   ├── seed_dummy_data.sql
    │   └── supabase_schema.sql
    ├── portals/                      # Web & Mobile User Interface Views
    │   ├── index.html                # Internal portal landing
    │   ├── unified_web_portal.html   # Multi-Portal SPA (Student, Parent, Cashier, Admin)
    │   ├── student/                  # Student pre-ordering web module
    │   ├── parent/                   # Parent oversight & top-up module
    │   ├── cashier/                  # Cashier POS terminal UI module
    │   └── admin/                    # Real-time analytics & stock alert module
    └── services/                     # Business logic, auth & shared handlers
        ├── supabaseClient.js         # Supabase client initialization
        ├── CalendarView.js           # Academic calendar controller
        ├── login.js                  # Auth login controller
        └── forgotpassword.js         # Password recovery controller
```

---

## 🚀 Quick Start Guide

### 1. Environment Setup
Create your local environment file:
```bash
cp .env.example .env
```

Install Python dependencies:
```bash
pip install -r requirements.txt
```

### 2. Launching the Web Portal
Open `src/portals/unified_web_portal.html` in any modern web browser or serve via local HTTP server:
```bash
npx serve src/portals
```
Or simply open `index.html` at the project root to auto-redirect.

### 3. Launching the Edge Kiosk (Hardware & AI Vision)
Execute the customer-facing display kiosk GUI:
```bash
python3 src/hardware/student_kiosk_gui.py
```

### 4. Inspecting Trained YOLO Weights
Run the model weights metadata inspector:
```bash
python3 src/ai_engine/inspect_yolo_model.py src/assets/models/novalunch_yolo.pt
```

---

## 🔒 Security & Data Compliance
- **No-Hardcoded-Data Architecture**: All institutional guardrails, discounts, limits, and product catalogs are dynamically loaded from Supabase PostgreSQL (`canteen_settings`).
- **Offline Edge Resiliency**: Transactions automatically persist to `src/database/novalunch_edge.db` (SQLite) if the network disconnects and sync asynchronously once online.
- **ROI Privacy Masking**: Overhead camera tray captures automatically crop tightly around the platform to prevent student face data collection.
