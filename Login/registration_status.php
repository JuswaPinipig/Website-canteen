<?php
/**
 * registration_status.php
 * Saint Joseph College of Novaliches Inc.
 *
 * Public endpoint — no auth required.
 * Called by the login page to show the registration banner.
 *
 * Reads from system_deadlines WHERE type = 'enrollment', tied to
 * the currently active school year. Uses start_datetime / end_datetime
 * for precision (falls back to start_date / end_date if the datetime
 * columns are NULL).
 *
 * Returns JSON:
 * {
 *   "is_open":    bool,
 *   "start_date": "Month D, YYYY" | null,
 *   "end_date":   "Month D, YYYY" | null
 * }
 */

header('Content-Type: application/json');
header('Cache-Control: no-store, no-cache, must-revalidate');

require_once __DIR__ . '/logindb.php'; // gives us $conn

try {
    $stmt = $conn->prepare("
        SELECT
            COALESCE(sd.start_datetime, sd.start_date) AS open_at,
            COALESCE(sd.end_datetime,   sd.end_date)   AS close_at
        FROM   system_deadlines sd
        JOIN   school_years sy ON sy.id = sd.school_year_id
        WHERE  sd.type  = 'enrollment'
          AND  sy.is_active = 1
          AND  COALESCE(sd.start_datetime, sd.start_date) <= NOW()
          AND  COALESCE(sd.end_datetime,   sd.end_date)   >= NOW()
        ORDER  BY sd.start_datetime DESC
        LIMIT  1
    ");
    $stmt->execute();
    $row = $stmt->fetch();

    if ($row) {
        $fmt = static fn(string $d): string =>
            (new DateTimeImmutable($d))->format('F j, Y');

        echo json_encode([
            'is_open'    => true,
            'start_date' => $fmt($row['open_at']),
            'end_date'   => $fmt($row['close_at']),
        ]);
    } else {
        echo json_encode([
            'is_open'    => false,
            'start_date' => null,
            'end_date'   => null,
        ]);
    }

} catch (PDOException $e) {
    error_log('[registration_status.php] ' . $e->getMessage());
    echo json_encode([
        'is_open'    => false,
        'start_date' => null,
        'end_date'   => null,
    ]);
}