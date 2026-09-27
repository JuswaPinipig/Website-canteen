"""
Test suite for NovaLunch Instant QR Student-Parent Pairing Engine
Verifies:
1. Short-lived token generation (POST /api/students/pairing-token)
2. Token signature verification
3. Direct claim and instant parent-student link activation (POST /api/parents/link-by-qr)
4. Anti-replay prevention (claiming an already used token fails with 409)
5. Expiry handling (expired tokens rejected with 410)
6. Malformed/invalid token rejection (clean 400/401 error)
7. 6-character fallback code pairing flow
"""

import sys
import os
import time

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from src.services.qr_pairing_service import (
    handle_create_pairing_token,
    handle_link_by_qr,
    generate_signed_jwt,
    verify_jwt_signature,
    PAIRING_SECRET_KEY,
    PAIRING_TTL_SECONDS
)

def run_tests():
    print("=== Testing NovaLunch Student-Parent Pairing Engine ===")

    student_id = "c653fe97-2934-4fae-a8f6-18ebb4754886" # Joshua Lupisan
    parent_id = "02e0f6ca-ae0c-432e-8745-02b53adcd2f4"  # Maria Santos

    # 1. Test token creation by student
    status, res = handle_create_pairing_token(
        headers={'authorization': f'Bearer {student_id}', 'x-user-role': 'student', 'x-student-id': student_id},
        body_data={'studentId': student_id}
    )
    assert status == 200, f"Expected 200 from create token, got {status}: {res}"
    assert res.get('success') is True, "Expected success: True"
    pairing_token = res.get('pairingToken')
    pairing_code = res.get('pairingCode')
    assert pairing_token, "Missing pairingToken in response"
    assert pairing_code, "Missing pairingCode in response"
    print(f"✅ Token created successfully: code={pairing_code}, length={len(pairing_token)}")

    # 2. Test signature validation
    is_valid, err, payload = verify_jwt_signature(pairing_token, PAIRING_SECRET_KEY)
    assert is_valid is True, f"Signature verification failed: {err}"
    assert payload.get('studentId') == student_id, "Payload studentId mismatch"
    assert payload.get('type') == 'parent_link', "Payload type mismatch"
    print("✅ Cryptographic HMAC-SHA256 signature verified")

    # 3. Test non-parent role rejection on link-by-qr
    status_fail_role, res_fail_role = handle_link_by_qr(
        headers={'authorization': f'Bearer {student_id}', 'x-user-role': 'student'},
        body_data={'pairingToken': pairing_token, 'parentId': student_id, 'role': 'student'}
    )
    assert status_fail_role in [401, 403], f"Expected 401/403 for non-parent, got {status_fail_role}"
    print("✅ Non-parent unauthorized role rejection verified")

    # 4. Test claiming token by parent
    status_claim, res_claim = handle_link_by_qr(
        headers={'authorization': f'Bearer {parent_id}', 'x-user-role': 'parent', 'x-parent-id': parent_id},
        body_data={'pairingToken': pairing_token, 'parentId': parent_id}
    )
    assert status_claim == 200, f"Expected 200 on claim, got {status_claim}: {res_claim}"
    assert res_claim.get('success') is True, "Expected success: True on claim"
    assert res_claim.get('student', {}).get('id') == student_id, "Linked student mismatch"
    print(f"✅ Parent successfully linked student: {res_claim.get('message')}")

    # 5. Test REPLAY ATTACK: Attempt to claim the SAME token again
    status_replay, res_replay = handle_link_by_qr(
        headers={'authorization': f'Bearer {parent_id}', 'x-user-role': 'parent', 'x-parent-id': parent_id},
        body_data={'pairingToken': pairing_token, 'parentId': parent_id}
    )
    assert status_replay == 409, f"Expected 409 Conflict for replayed token, got {status_replay}: {res_replay}"
    assert res_replay.get('success') is False, "Replay should return success: False"
    print(f"✅ Anti-replay verified: 409 Conflict returned on reused token ({res_replay.get('error')})")

    # 6. Test EXPIRED TOKEN: create an expired token manually and attempt claim
    past_ts = int(time.time()) - 1000
    expired_payload = {
        "studentId": student_id,
        "timestamp": past_ts,
        "type": "parent_link",
        "exp": past_ts + 600, # expired 400s ago
        "jti": "test-expired-jti-" + str(past_ts)
    }
    expired_token = generate_signed_jwt(expired_payload, PAIRING_SECRET_KEY)
    status_exp, res_exp = handle_link_by_qr(
        headers={'authorization': f'Bearer {parent_id}', 'x-user-role': 'parent', 'x-parent-id': parent_id},
        body_data={'pairingToken': expired_token, 'parentId': parent_id}
    )
    assert status_exp == 410, f"Expected 410 Gone for expired token, got {status_exp}: {res_exp}"
    print(f"✅ Expiry check verified: 410 returned for expired token ({res_exp.get('error')})")

    # 7. Test MALFORMED / INVALID SIGNATURE token
    status_bad, res_bad = handle_link_by_qr(
        headers={'authorization': f'Bearer {parent_id}', 'x-user-role': 'parent', 'x-parent-id': parent_id},
        body_data={'pairingToken': "fake.invalid.signature", 'parentId': parent_id}
    )
    assert status_bad in [400, 401], f"Expected 400/401 for bad signature, got {status_bad}"
    print(f"✅ Tampered token rejected: {status_bad} ({res_bad.get('error')})")

    # 8. Test 6-character fallback code pairing
    status2, res2 = handle_create_pairing_token(
        headers={'authorization': f'Bearer {student_id}', 'x-user-role': 'student', 'x-student-id': student_id},
        body_data={'studentId': student_id}
    )
    assert status2 == 200
    code2 = res2.get('pairingCode')
    assert code2, "Missing second pairing code"

    status_code_claim, res_code_claim = handle_link_by_qr(
        headers={'authorization': f'Bearer {parent_id}', 'x-user-role': 'parent', 'x-parent-id': parent_id},
        body_data={'pairingCode': code2, 'parentId': parent_id}
    )
    assert status_code_claim == 200, f"Expected 200 on code claim, got {status_code_claim}: {res_code_claim}"
    print(f"✅ 6-character fallback code claim verified: {code2}")

    print("\n🎉 ALL PAIRING API & SECURITY EDGE CASES PASSED!")

if __name__ == '__main__':
    run_tests()
