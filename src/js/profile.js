// studentprofile.js

// ── Tab switching ─────────────────────────────────────────────────────────────
function switchTab(event, tabId) {
    document.querySelectorAll('.tab-btn').forEach(t => t.classList.remove('active'));
    document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
    event.currentTarget.classList.add('active');
    document.getElementById(tabId).classList.add('active');
    window.scrollTo({
        top: document.querySelector('.profile-tabs').offsetTop - 100,
        behavior: 'smooth'
    });
}

// ── Helper: display value or dash ─────────────────────────────────────────────
function val(v) {
    return (v && String(v).trim()) ? String(v).trim() : '—';
}

// ── Build guardian cards dynamically ─────────────────────────────────────────
function renderGuardians(guardians) {
    const container = document.getElementById('guardiansContainer');
    if (!container) return;

    if (!guardians || guardians.length === 0) {
        container.innerHTML = `
            <div class="no-guardian-msg">
                <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5">
                    <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/>
                    <circle cx="9" cy="7" r="4"/>
                    <path d="M23 21v-2a4 4 0 0 0-3-3.87"/>
                    <path d="M16 3.13a4 4 0 0 1 0 7.75"/>
                </svg>
                <p>No guardian information on file.</p>
                <span>Please contact the registrar if this is incorrect.</span>
            </div>`;
        return;
    }

    container.innerHTML = guardians.map((g, index) => {
        const isPrimary   = g.is_primary;
        const isDeceased  = g.is_deceased;
        const priorityNum = g.priority;

        const badge = isPrimary
            ? `<span class="guardian-badge primary-badge">Primary</span>`
            : `<span class="guardian-badge secondary-badge">#${priorityNum} Contact</span>`;

        const deceasedBadge = isDeceased
            ? `<span class="guardian-badge deceased-badge">Deceased</span>`
            : '';

        const pickupBadge = g.pickup_auth
            ? `<span class="guardian-badge pickup-badge">Pickup Authorized</span>`
            : '';

        const fullAddress = [g.address, g.city, g.province, g.zip]
            .filter(p => p && p.trim() && p !== '—')
            .join(', ') || '—';

        return `
        <div class="guardian-card ${isPrimary ? 'guardian-card--primary' : ''} ${isDeceased ? 'guardian-card--deceased' : ''}">
            <div class="guardian-card-header">
                <div class="guardian-avatar">${getInitials(g.name)}</div>
                <div class="guardian-title-group">
                    <div class="guardian-name">${val(g.name)}</div>
                    <div class="guardian-relation">${val(g.relationship)}</div>
                </div>
                <div class="guardian-badges">
                    ${badge}${deceasedBadge}${pickupBadge}
                </div>
            </div>
            <div class="guardian-body">
                <div class="guardian-row">
                    <div class="guardian-field">
                        <span class="gf-label">Occupation</span>
                        <span class="gf-value">${val(g.occupation)}</span>
                    </div>
                    <div class="guardian-field">
                        <span class="gf-label">Contact</span>
                        <span class="gf-value">${val(g.contact)}</span>
                    </div>
                </div>
                <div class="guardian-field guardian-field--full">
                    <span class="gf-label">Address</span>
                    <span class="gf-value">${fullAddress}</span>
                </div>
            </div>
        </div>`;
    }).join('');
}

function getInitials(name) {
    if (!name || name === '—') return '?';
    const parts = name.trim().split(/\s+/);
    if (parts.length === 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

// ── Main loader ───────────────────────────────────────────────────────────────
function loadStudentProfile() {
    fetch('studentsprofileviewing.php')
        .then(r => r.json())
        .then(data => {
            if (data.error) {
                document.getElementById('studentFullName').textContent = 'Profile Unavailable';
                document.getElementById('studentGradeLevel').textContent = data.error;
                return;
            }

            // Hero
            const fullName = [data.fname, data.mname, data.lname].filter(Boolean).join(' ');
            document.getElementById('studentFullName').textContent   = fullName;
            document.getElementById('studentGradeLevel').textContent = data.grade_level || '';

            const syBadge = document.getElementById('syBadge');
            if (syBadge) syBadge.textContent = data.school_year ? 'S.Y. ' + data.school_year : 'S.Y. —';

            const photoEl = document.getElementById('studentPhoto');
            const PLACEHOLDER = '../student profile/Student media/profilepicture.jpg';
            if (data.photo && data.photo.trim()) {
                photoEl.src = data.photo;
                // Fall back to placeholder if the photo URL fails to load
                photoEl.onerror = function () {
                    this.onerror = null;
                    this.src = PLACEHOLDER;
                };
            } else {
                // No photo on record — use placeholder
                photoEl.src = PLACEHOLDER;
            }

            const enrollEl = document.getElementById('heroEnrollType');
            if (enrollEl) enrollEl.textContent = data.enrollment_type || '—';

            // Basic info
            document.getElementById('firstName').textContent   = val(data.fname);
            document.getElementById('middleName').textContent  = val(data.mname);
            document.getElementById('lastName').textContent    = val(data.lname);
            document.getElementById('sex').textContent         = val(data.sex);
            document.getElementById('dob').textContent         = val(data.dob);
            document.getElementById('age').textContent         = val(data.age);
            document.getElementById('pob').textContent         = val(data.pob);
            document.getElementById('nationality').textContent = val(data.nationality);
            document.getElementById('religion').textContent    = val(data.religion);

            // Contact & residency (no mobile)
            document.getElementById('address').textContent  = val(data.address);
            document.getElementById('city').textContent     = val(data.city);
            document.getElementById('province').textContent = val(data.province);
            document.getElementById('zip').textContent      = val(data.zip);
            document.getElementById('email').textContent    = val(data.email);

            // Mirror hero stats
            const heroNat = document.getElementById('heroNationality');
            const heroRel = document.getElementById('heroReligion');
            if (heroNat) heroNat.textContent = val(data.nationality);
            if (heroRel) heroRel.textContent = val(data.religion);

            // Guardians — dynamic render
            renderGuardians(data.guardians || []);

            // Guardian count badge
            const countEl = document.getElementById('guardianCount');
            if (countEl && data.guardians) {
                countEl.textContent = data.guardians.length;
                countEl.style.display = data.guardians.length > 0 ? 'inline-flex' : 'none';
            }
        })
        .catch(err => console.error('Fetch error:', err));
}

document.addEventListener('DOMContentLoaded', loadStudentProfile);