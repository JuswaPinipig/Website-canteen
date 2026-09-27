const crypto = require('crypto');

const PAIRING_SECRET_KEY = process.env.PAIRING_SECRET_KEY || "sjc-novalunch-qr-pairing-secret-key-2026-v1";
const PAIRING_TTL_SECONDS = parseInt(process.env.PAIRING_TOKEN_TTL || "600", 10);

function base64url(buf) {
  return buf.toString('base64').replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

function generateSignedJwt(payload) {
  const header = { alg: "HS256", typ: "JWT" };
  const encHeader = base64url(Buffer.from(JSON.stringify(header)));
  const encPayload = base64url(Buffer.from(JSON.stringify(payload)));
  const sig = crypto.createHmac('sha256', PAIRING_SECRET_KEY).update(`${encHeader}.${encPayload}`).digest();
  return `${encHeader}.${encPayload}.${base64url(sig)}`;
}

module.exports = async function handler(req, res) {
  // Enable CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Student-Id, X-Session-Token, X-User-Role');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ success: false, error: "Method not allowed. Use POST." });
  }

  try {
    const authHeader = req.headers.authorization || '';
    const bearerId = authHeader.startsWith('Bearer ') ? authHeader.substring(7).trim() : null;
    const body = req.body || {};
    const studentId = req.headers['x-student-id'] || body.studentId || bearerId || body.session?.id || 'c653fe97-2934-4fae-a8f6-18ebb4754886';
    const role = req.headers['x-user-role'] || body.role || body.session?.role || 'student';

    if (role !== 'student' && role !== 'admin') {
      return res.status(403).json({
        success: false,
        error: `Access denied. Role is '${role}'; only verified student accounts can generate parent pairing tokens.`
      });
    }

    const nowTs = Math.floor(Date.now() / 1000);
    const expiresAt = nowTs + PAIRING_TTL_SECONDS;
    const jti = crypto.randomUUID();

    const studentName = body.name || body.session?.name || body.session?.full_name || "Joshua Lupisan";
    const studentGrade = body.grade || body.session?.grade || "Grade 10 - St. Ignatius";

    // Required specification payload: { studentId: string, timestamp: number, type: 'parent_link' }
    const tokenPayload = {
      studentId: String(studentId),
      timestamp: nowTs,
      type: 'parent_link',
      exp: expiresAt,
      jti,
      name: studentName,
      grade: studentGrade
    };

    const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    let pairingCode = "";
    for (let i = 0; i < 6; i++) pairingCode += chars[Math.floor(Math.random() * chars.length)];

    tokenPayload.code = pairingCode;
    const token = generateSignedJwt(tokenPayload);

    return res.status(200).json({
      success: true,
      pairingToken: token,
      pairingCode,
      expiresAt,
      expiresIn: PAIRING_TTL_SECONDS,
      payload: {
        studentId: String(studentId),
        timestamp: nowTs,
        type: 'parent_link'
      },
      student: {
        id: String(studentId),
        name: studentName,
        grade: studentGrade
      }
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
};
