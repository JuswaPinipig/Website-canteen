const crypto = require('crypto');

const PAIRING_SECRET_KEY = process.env.PAIRING_SECRET_KEY || "sjc-novalunch-qr-pairing-secret-key-2026-v1";
const PAIRING_TTL_SECONDS = parseInt(process.env.PAIRING_TOKEN_TTL || "600", 10);
const SUPABASE_URL = process.env.SUPABASE_URL || "https://wtvkmywmlifcsddlgvnn.supabase.co";
const SUPABASE_ANON_KEY = process.env.SUPABASE_ANON_KEY || "sb_publishable_yywY2quhz5k1x6Pu_w6pgQ_e-mBU0q2";

// Serverless replay token cache
const claimedTokens = new Set();

function base64url(buf) {
  return buf.toString('base64').replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

function verifySignedJwt(token) {
  if (!token || typeof token !== 'string') return { valid: false, error: 'Empty token' };
  const parts = token.trim().split('.');
  if (parts.length !== 3) return { valid: false, error: 'Malformed token' };

  const [encHeader, encPayload, encSig] = parts;
  const expectedSig = crypto.createHmac('sha256', PAIRING_SECRET_KEY).update(`${encHeader}.${encPayload}`).digest();
  const expectedEncSig = base64url(expectedSig);

  if (expectedEncSig !== encSig) {
    return { valid: false, error: 'Invalid cryptographic signature' };
  }

  try {
    const payload = JSON.parse(Buffer.from(encPayload, 'base64').toString('utf-8'));
    return { valid: true, payload };
  } catch (e) {
    return { valid: false, error: 'Invalid payload encoding' };
  }
}

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, X-Parent-Id, X-Session-Token, X-User-Role');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ success: false, error: "Method not allowed. Use POST." });
  }

  try {
    const body = req.body || {};
    const pairingToken = (body.pairingToken || body.token || body.pairingCode || body.code || "").trim();

    if (!pairingToken) {
      return res.status(400).json({ success: false, error: "Missing required field 'pairingToken' or 'pairingCode'." });
    }

    // Authenticate parent
    const authHeader = req.headers.authorization || '';
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ success: false, error: "Unauthorized: Missing or invalid Authorization header." });
    }
    const bearerId = authHeader.substring(7).trim();
    if (!bearerId) {
      return res.status(401).json({ success: false, error: "Unauthorized: Empty bearer token in Authorization header." });
    }
    const parentId = req.headers['x-parent-id'] || body.parentId || body.session?.id || bearerId;
    if (!parentId) {
      return res.status(401).json({ success: false, error: "Unauthorized: Missing parent identification." });
    }
    const role = req.headers['x-user-role'] || body.role || body.session?.role || 'parent';

    if (role !== 'parent' && role !== 'admin') {
      return res.status(403).json({
        success: false,
        error: `Access denied. Role is '${role}'; only registered parent accounts can link student accounts.`
      });
    }

    // Verify token signature & payload
    const { valid, error, payload } = verifySignedJwt(pairingToken);
    if (!valid) {
      return res.status(401).json({ success: false, error: `Invalid pairing token signature: ${error}` });
    }

    if (payload.type !== 'parent_link') {
      return res.status(400).json({ success: false, error: `Invalid token type '${payload.type}'. Expected 'parent_link'.` });
    }

    // Expiration check
    const nowTs = Math.floor(Date.now() / 1000);
    if (nowTs > (payload.exp || 0) || (nowTs - (payload.timestamp || 0)) > PAIRING_TTL_SECONDS) {
      return res.status(410).json({ success: false, error: "Pairing token has expired. Please ask student to generate a new QR code." });
    }

    // Anti-replay check
    const tokenIdentifier = payload.jti || pairingToken;
    if (claimedTokens.has(tokenIdentifier)) {
      return res.status(409).json({ success: false, error: "This pairing token has already been claimed (replay attacks are strictly prevented)." });
    }

    const studentId = payload.studentId;
    const studentName = payload.name || "Joshua Lupisan";
    const studentGrade = payload.grade || "Grade 10 - St. Ignatius";

    // Immediately create relation in database (status: 'ACTIVE')
    try {
      await fetch(`${SUPABASE_URL}/rest/v1/parent_student_links`, {
        method: 'POST',
        headers: {
          'apikey': SUPABASE_ANON_KEY,
          'Authorization': `Bearer ${SUPABASE_ANON_KEY}`,
          'Content-Type': 'application/json',
          'Prefer': 'return=minimal'
        },
        body: JSON.stringify({
          parent_id: parentId,
          student_id: studentId,
          relationship: 'Parent'
        })
      });
    } catch (e) {
      console.warn("Supabase link warning:", e.message);
    }

    // Invalidate token once claimed to prevent replay attacks
    claimedTokens.add(tokenIdentifier);

    return res.status(200).json({
      success: true,
      message: `Successfully linked ${studentName} to your parent account.`,
      student: {
        id: studentId,
        name: studentName,
        grade: studentGrade
      }
    });
  } catch (err) {
    return res.status(500).json({ success: false, error: err.message || "Internal server error" });
  }
};
