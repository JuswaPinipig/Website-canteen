# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Saint Joseph College (SJC) community members across four core roles:
- **Students**: View menus, check e-wallet balance, track purchase history, and make instant RFID checkouts at the kiosk.
- **Parents**: Reload student e-wallets, set daily spending limits, track nutritional/meal purchase logs, and monitor activity.
- **Cashiers**: Operate the Point of Sale (POS) terminal, process RFID & manual tray payments, and issue receipts.
- **Administrators**: Manage user accounts (provisioning), configure meal menus/inventory, assign RFID cards, and inspect revenue analytics.

## Product Purpose

NovaLunch simplifies and accelerates institutional canteen operations through a seamless cashless payment system, automated AI tray recognition, and real-time cross-role Web portal management.

## Positioning

A hybrid Web + Hardware AI Canteen Ecosystem combining zero-friction computer vision tray scanning (YOLO), contact-free 125kHz RFID card authentication, and real-time cloud e-wallet settlement via Supabase.

## Operating Context

- **Physical Canteen Kiosk & POS**: High-volume, fast-throughput environments during lunch and break hours where fast student checkout and hardware stability (RFID reader + USB webcam) are critical.
- **Web Portal**: Responsive role-based dashboard accessible by students, parents, cashiers, and admins on desktop or mobile web browsers.

## Capabilities and Constraints

- **Web Portal Stack**: Vanilla HTML5, CSS3, JavaScript (ES6+), Supabase Client Library.
- **Hardware/Kiosk Stack**: Python 3, Tkinter GUI, OpenCV camera vision, Ultralytics YOLO model (`novalunch_yolo.pt`), USB HID RFID Keyboard Wedge listener.
- **Database & Sync**: Supabase PostgreSQL for real-time authentication, student e-wallet balances, menu inventory, and transaction audit logs.
- **Hardware Integration**: Normalizes 10-digit 125kHz EM4100 RFID badge numbers without manual keyboard focus.

## Brand Commitments

- **Institutional Identity**: Saint Joseph College (SJC) NovaLunch identity.
- **Design Aesthetic**: Modern, "quiet luxury" iOS-inspired aesthetic with dark glassmorphism, refined typography, pill buttons, smooth micro-interactions, and high visual legibility.

## Evidence on Hand

- `unified_web_portal.html`: Multi-role responsive HTML web application with embedded CSS and JavaScript.
- `student_kiosk_gui.py`: Interactive GUI for physical canteen kiosk with RFID payment simulation & settlement flow.
- `opencv_live_kiosk.py` & `live_yolo_camera_detector.py`: Live computer vision tray detection with YOLO model integration.

## Product Principles

1. **Zero-Friction Speed**: Minimize checkout latency at physical kiosks using automated RFID scans and computer vision detection.
2. **Quiet Luxury Aesthetics**: High visual polish, glassmorphism, clean typography, and tactile micro-animations across all portal roles.
3. **Data Integrity & Safety**: Strict parent-controlled spending caps, secure balance deductions, and audited transaction records.
4. **Hardware Resiliency**: Hardware-wedge RFID input handling with fallback mechanisms for unlinked cards or manual student lookup.

## Accessibility & Inclusion

- High contrast text readability against dark glass backgrounds.
- Large tap targets and voice audio feedback announcements for student-facing kiosk displays.
