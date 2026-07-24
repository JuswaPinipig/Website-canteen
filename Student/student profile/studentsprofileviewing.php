<?php
session_start();
header('Content-Type: application/json');

require __DIR__ . '/studentprofiledb.php'; // $conn → school_system (mysqli)

if ($conn->connect_error) {
    echo json_encode(["error" => "DB connection failed: " . $conn->connect_error]);
    exit;
}

// ── Auth ──────────────────────────────────────────────────────────────────────
if (!isset($_SESSION['user_id'])) {
    if (!isset($_GET['id'])) {
        echo json_encode(["error" => "No session found. Please log in."]);
        exit;
    }
    $user_id = intval($_GET['id']);
} else {
    $user_id = intval($_SESSION['user_id']);
}

// ── Step 1: Fetch student row ─────────────────────────────────────────────────
$uStmt = $conn->prepare(
    "SELECT s.id AS student_id,
            s.first_name, s.middle_name, s.last_name,
            s.sex, s.date_of_birth, s.place_of_birth,
            s.nationality, s.religion,
            s.address, s.city, s.province, s.zip_code,
            s.personal_email,
            s.enrollment_type,
            gl.display_name AS grade_level
     FROM   students  s
     JOIN   grade_levels gl ON gl.id = s.grade_level_id
     WHERE  s.user_id = ?
     LIMIT  1"
);

if (!$uStmt) {
    echo json_encode(["error" => "SQL prepare error: " . $conn->error]);
    exit;
}

$uStmt->bind_param("i", $user_id);
$uStmt->execute();
$result = $uStmt->get_result();

if ($result->num_rows === 0) {
    echo json_encode(["error" => "No student profile found for this account. Please contact the registrar."]);
    exit;
}

$student    = $result->fetch_assoc();
$student_id = $student['student_id'];
$uStmt->close();

// ── Step 1b: Active school year ───────────────────────────────────────────────
$syStmt = $conn->prepare("SELECT label FROM school_years WHERE is_active = 1 LIMIT 1");
$activeSchoolYear = '';
if ($syStmt) {
    $syStmt->execute();
    $syResult = $syStmt->get_result();
    if ($syResult->num_rows > 0) {
        $activeSchoolYear = $syResult->fetch_assoc()['label'] ?? '';
    }
    $syStmt->close();
}

// ── Step 2: Age from DOB ──────────────────────────────────────────────────────
$student['age'] = '';
if (!empty($student['date_of_birth'])) {
    $dob = new DateTime($student['date_of_birth']);
    $student['age'] = $dob->diff(new DateTime('today'))->y;
    $student['date_of_birth'] = $dob->format('F j, Y');
}

// ── Step 3: Fetch ALL active guardians (ordered by emergency priority) ────────
$guardians = [];
$pStmt = $conn->prepare(
    "SELECT g.id,
            g.full_name,
            sg.relationship_label,
            sg.is_primary,
            sg.emergency_priority,
            sg.pickup_authorized,
            g.occupation,
            g.home_address,
            g.city,
            g.province,
            g.zip_code,
            g.comm_method,
            g.mobile_number,
            g.email_address,
            g.is_deceased
     FROM   student_guardians sg
     JOIN   guardians          g  ON g.id = sg.guardian_id
     WHERE  sg.student_id = ?
       AND  sg.is_active   = 1
     ORDER  BY sg.emergency_priority ASC, sg.is_primary DESC"
);

if ($pStmt) {
    $pStmt->bind_param("i", $student_id);
    $pStmt->execute();
    $pResult = $pStmt->get_result();

    while ($row = $pResult->fetch_assoc()) {
        // Build contact string
        $method  = $row['comm_method'] ?? '';
        $contact = '';
        if ($method === 'Phone' || $method === 'Both') {
            $contact = $row['mobile_number'] ?? '';
        } elseif ($method === 'Email') {
            $contact = $row['email_address'] ?? '';
        } else {
            $contact = $row['mobile_number'] ?? $row['email_address'] ?? '';
        }

        $guardians[] = [
            'name'           => $row['full_name']           ?? '',
            'relationship'   => $row['relationship_label']  ?? '',
            'occupation'     => $row['occupation']          ?? '',
            'address'        => $row['home_address']        ?? '',
            'city'           => $row['city']                ?? '',
            'province'       => $row['province']            ?? '',
            'zip'            => $row['zip_code']            ?? '',
            'contact'        => $contact,
            'is_primary'     => (bool)($row['is_primary']   ?? false),
            'pickup_auth'    => (bool)($row['pickup_authorized'] ?? false),
            'is_deceased'    => (bool)($row['is_deceased']  ?? false),
            'priority'       => (int)($row['emergency_priority'] ?? 99),
        ];
    }
    $pStmt->close();
}

// ── Step 4: Build response ────────────────────────────────────────────────────
// ── Photo: use stored path if available, else placeholder ─────────────────────
$photoPath = $student['photo_path'] ?? '';
if (empty(trim($photoPath))) {
    $photoPath = '../student profile/Student media/profilepicture.jpg';
}

$response = [
    'fname'           => $student['first_name']  ?? '',
    'mname'           => $student['middle_name'] ?? '',
    'lname'           => $student['last_name']   ?? '',
    'photo'           => $photoPath,
    'grade_level'     => $student['grade_level'] ?? '',
    'enrollment_type' => ucfirst($student['enrollment_type'] ?? ''),
    'school_year'     => $activeSchoolYear,

    'sex'         => ucfirst($student['sex']          ?? ''),
    'dob'         => $student['date_of_birth']         ?? '',
    'age'         => $student['age']                   ?? '',
    'pob'         => $student['place_of_birth']        ?? '',
    'nationality' => $student['nationality']           ?? '',
    'religion'    => $student['religion']              ?? '',

    'address'     => $student['address']               ?? '',
    'city'        => $student['city']                  ?? '',
    'province'    => $student['province']              ?? '',
    'zip'         => $student['zip_code']              ?? '',
    'email'       => $student['personal_email']        ?? '',

    // Array of all active guardians
    'guardians'   => $guardians,
];

echo json_encode($response);
$conn->close();
?>