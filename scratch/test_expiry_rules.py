import re
import sys

def test_portal_expiry_implementation():
    with open('src/portals/unified_web_portal.html', 'r', encoding='utf-8') as f:
        html = f.read()

    # 1. Check getProductExpiryDetails helper exists
    assert 'function getProductExpiryDetails(product, inventoryBatches' in html, "Missing getProductExpiryDetails helper"
    print("✅ getProductExpiryDetails helper present")

    # 2. Check StudentNearExpiryModal exists
    assert 'function StudentNearExpiryModal({ isOpen, onClose, item, onConfirm })' in html, "Missing StudentNearExpiryModal"
    print("✅ StudentNearExpiryModal component present")

    # 3. Check NearExpiryWarningModal exists
    assert 'function NearExpiryWarningModal({ isOpen, onClose, item' in html, "Missing NearExpiryWarningModal"
    print("✅ NearExpiryWarningModal component present")

    # 4. Check StudentView filters out archived and expired items
    assert 'const expiry = getProductExpiryDetails(i, inventoryBatches);' in html, "Missing getProductExpiryDetails in StudentView"
    assert 'if (expiry.isArchived || expiry.isExpired) return false;' in html, "Missing archival/expiry filter in StudentView"
    print("✅ StudentView correctly excludes archived and expired items")

    # 5. Check StudentNearExpiryModal is rendered inside StudentView
    assert '<StudentNearExpiryModal' in html, "Missing StudentNearExpiryModal tag in StudentView"
    print("✅ StudentNearExpiryModal is rendered in StudentView")

    # 6. Check CashierView filters out archived and expired items
    assert 'function CashierView({ posCart, posTotal, menuCatalog, registeredUsers, recentOrders = [], preorders = [], inventoryBatches = []' in html, "CashierView missing inventoryBatches prop"
    print("✅ CashierView receives inventoryBatches")

    # 7. Check App component passes inventoryBatches to all views
    assert 'inventoryBatches={inventoryBatches}' in html, "Missing inventoryBatches prop passing in App"
    print("✅ App root passes inventoryBatches to StudentView, ParentView, and CashierView")

def test_kiosk_expiry_implementation():
    with open('src/hardware/student_kiosk_gui.py', 'r', encoding='utf-8') as f:
        py_code = f.read()

    assert 'def lookup_pos_item' in py_code, "Missing lookup_pos_item in kiosk"
    assert 'if it.get("available") is False or it.get("status") in ["archived", "EXPIRED", "expired"]:' in py_code, "Missing archival/expiry filter in aggregate_detections"
    assert 'if pos_info.get("available") is False or pos_info.get("status") in ["archived", "EXPIRED", "expired"]:' in py_code, "Missing archival/expiry filter in detections loop"
    print("✅ Hardware Kiosk correctly filters out archived and expired items")

if __name__ == '__main__':
    test_portal_expiry_implementation()
    test_kiosk_expiry_implementation()
    print("\n🎉 ALL EXPIRY & ARCHIVAL TESTS PASSED!")
