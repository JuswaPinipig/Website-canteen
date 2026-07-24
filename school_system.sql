-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: 127.0.0.1
-- Generation Time: Jul 24, 2026 at 05:16 PM
-- Server version: 10.4.32-MariaDB
-- PHP Version: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `school_system`
--

DELIMITER $$
--
-- Procedures
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_enroll_student` (IN `p_enrollment_id` INT, IN `p_new_status` ENUM('pending','enrolled','unregistered','archived'), IN `p_registrar_id` INT, IN `p_reason` VARCHAR(500), IN `p_ip` VARCHAR(45), OUT `p_success` TINYINT, OUT `p_message` VARCHAR(255))   BEGIN
    DECLARE v_old_status     ENUM('pending','enrolled','unregistered','archived');
    DECLARE v_student_id     INT;
    DECLARE v_school_year_id INT;
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SET p_success = 0;
        SET p_message = 'Database error during status update.';
    END;

    -- Fetch current row
    SELECT status, student_id, school_year_id
    INTO   v_old_status, v_student_id, v_school_year_id
    FROM   enrollments
    WHERE  id = p_enrollment_id
    LIMIT  1;

    IF v_student_id IS NULL THEN
        SET p_success = 0;
        SET p_message = 'Enrollment record not found.';
    ELSEIF v_old_status = p_new_status THEN
        SET p_success = 0;
        SET p_message = CONCAT('Student is already ', p_new_status, '.');
    ELSEIF v_old_status = 'archived' THEN
        SET p_success = 0;
        SET p_message = 'Cannot update an archived enrollment.';
    ELSEIF p_new_status = 'unregistered' AND (p_reason IS NULL OR p_reason = '') THEN
        SET p_success = 0;
        SET p_message = 'A reason is required when unregistering.';
    ELSE
        START TRANSACTION;

        UPDATE enrollments
        SET
            status              = p_new_status,
            unregistered_reason = IF(p_new_status = 'unregistered', p_reason, NULL),
            processed_by        = p_registrar_id,
            processed_at        = NOW(),
            updated_at          = NOW()
        WHERE id = p_enrollment_id;

        -- Sync students.registration_status
        UPDATE students
        SET
            registration_status = CASE p_new_status
                WHEN 'enrolled'     THEN 'enrolled'
                WHEN 'pending'      THEN 'docs_submitted'
                WHEN 'unregistered' THEN 'pending'
                WHEN 'archived'     THEN 'archived'
            END,
            updated_at = NOW()
        WHERE id = v_student_id;

        -- Sync users.account_status if enrolled
        IF p_new_status = 'enrolled' THEN
            UPDATE users u
            JOIN   students s ON s.user_id = u.id
            SET    u.account_status = 'enrolled',
                   u.updated_at    = NOW()
            WHERE  s.id = v_student_id;
        END IF;

        -- Immutable audit log
        INSERT INTO enrollment_logs
            (enrollment_id, student_id, changed_by, old_status, new_status, notes, ip_address)
        VALUES
            (p_enrollment_id, v_student_id, p_registrar_id,
             v_old_status, p_new_status,
             IF(p_new_status = 'unregistered', p_reason, NULL),
             p_ip);

        COMMIT;
        SET p_success = 1;
        SET p_message = CONCAT('Student status updated to ', p_new_status, '.');
    END IF;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `admins`
--

CREATE TABLE `admins` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL COMMENT 'FK → users.id',
  `first_name` varchar(100) DEFAULT NULL,
  `middle_name` varchar(100) DEFAULT NULL,
  `last_name` varchar(100) DEFAULT NULL,
  `full_name` varchar(200) DEFAULT NULL COMMENT 'Kept for legacy reads; prefer first+last',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `school_email` varchar(255) DEFAULT NULL COMMENT 'FK → users.school_email (denormalized for convenience)',
  `personal_email` varchar(255) DEFAULT NULL COMMENT 'Personal email address',
  `role` varchar(50) DEFAULT NULL COMMENT 'e.g. registrar, admin',
  `is_archived` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `admins`
--

INSERT INTO `admins` (`id`, `user_id`, `first_name`, `middle_name`, `last_name`, `full_name`, `created_at`, `school_email`, `personal_email`, `role`, `is_archived`) VALUES
(1, 1, 'Joshua', 'Lupisan', 'Aguilar', 'Joshua Aguilar', '2026-05-16 18:14:54', 'admin@sjcadmin.edu.ph', 'phillippejoshua275@gmail.com', 'admin', 0),
(5, 8, 'Kurt', NULL, 'Michael', 'Kurt Michael', '2026-05-18 19:10:53', 'kurtmichael@sjcadmin.edu.ph', 'phillippejoshua2.74@gmail.com', 'admin', 0);

-- --------------------------------------------------------

--
-- Table structure for table `audit_logs`
--

CREATE TABLE `audit_logs` (
  `id` int(11) NOT NULL,
  `admin_id` int(11) NOT NULL,
  `action` enum('create','update','archive','activate','deactivate','restore','delete','finalize') NOT NULL,
  `table_name` varchar(100) NOT NULL,
  `record_id` int(11) NOT NULL,
  `old_values` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL COMMENT 'Row state before change' CHECK (json_valid(`old_values`)),
  `new_values` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL COMMENT 'Row state after change' CHECK (json_valid(`new_values`)),
  `ip_address` varchar(45) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `user_agent` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `audit_logs`
--

INSERT INTO `audit_logs` (`id`, `admin_id`, `action`, `table_name`, `record_id`, `old_values`, `new_values`, `ip_address`, `created_at`, `user_agent`) VALUES
(1, 1, 'create', 'school_years', 1, NULL, '{\"label\":\"2026-2027\",\"start\":\"2026-05-17\",\"end\":\"2027-05-17\",\"active\":0,\"confirmed\":1}', '::1', '2026-05-16 18:05:13', NULL),
(2, 1, 'create', 'school_years', 1, NULL, '{\"label\":\"2026-2027\",\"start\":\"2026-05-17\",\"end\":\"2027-05-17\",\"active\":0,\"confirmed\":1}', '::1', '2026-05-16 18:34:16', NULL),
(3, 1, 'create', 'school_years', 2, NULL, '{\"label\":\"2027-2028\",\"start\":\"2027-05-12\",\"end\":\"2028-05-05\",\"active\":0,\"confirmed\":1}', '::1', '2026-05-16 18:43:17', NULL),
(4, 1, 'activate', 'school_years', 1, NULL, '{\"label\":\"2026-2027\",\"status\":\"active\"}', '::1', '2026-05-16 19:18:34', NULL),
(5, 1, 'activate', 'school_years', 2, NULL, '{\"label\":\"2027-2028\",\"status\":\"active\"}', '::1', '2026-05-16 19:18:38', NULL),
(6, 1, 'activate', 'school_years', 1, NULL, '{\"label\":\"2026-2027\",\"status\":\"active\"}', '::1', '2026-05-16 19:18:41', NULL),
(7, 1, 'create', 'sections', 1, NULL, '{\"grade_level_id\":7,\"name\":\"OBEDIENCE\",\"capacity\":40,\"school_year_id\":1}', '::1', '2026-05-16 19:23:50', NULL),
(8, 1, 'create', 'sections', 2, NULL, '{\"grade_level_id\":7,\"name\":\"LOYALTY\",\"capacity\":40,\"school_year_id\":1}', '::1', '2026-05-16 19:23:56', NULL),
(9, 1, 'create', 'sections', 3, NULL, '{\"grade_level_id\":7,\"name\":\"DIGNITY\",\"capacity\":40,\"school_year_id\":1}', '::1', '2026-05-16 19:24:03', NULL),
(10, 1, 'create', 'sections', 4, NULL, '{\"grade_level_id\":7,\"name\":\"PEACE\",\"capacity\":40,\"school_year_id\":1}', '::1', '2026-05-16 19:24:09', NULL),
(11, 1, 'create', 'sections', 5, NULL, '{\"grade_level_id\":7,\"name\":\"CERTITUDE\",\"capacity\":40,\"school_year_id\":1}', '::1', '2026-05-16 19:24:17', NULL),
(12, 1, 'archive', 'sections', 5, NULL, NULL, '::1', '2026-05-16 19:24:28', NULL),
(13, 1, 'activate', 'sections', 5, NULL, NULL, '::1', '2026-05-16 19:24:32', NULL),
(14, 1, 'update', 'sections', 5, '{\"id\":5,\"grade_level_id\":7,\"name\":\"CERTITUDE\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:24:17\",\"updated_at\":\"2026-05-17 03:24:32\",\"room\":null}', '{\"name\":\"CERTITUDE\",\"capacity\":25,\"adviser_id\":null}', '::1', '2026-05-16 19:24:37', NULL),
(15, 1, 'update', 'sections', 3, '{\"id\":3,\"grade_level_id\":7,\"name\":\"DIGNITY\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:24:03\",\"updated_at\":\"2026-05-17 03:24:03\",\"room\":null}', '{\"name\":\"DIGNITY\",\"capacity\":25,\"adviser_id\":null}', '::1', '2026-05-16 19:24:40', NULL),
(16, 1, 'update', 'sections', 2, '{\"id\":2,\"grade_level_id\":7,\"name\":\"LOYALTY\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:23:56\",\"updated_at\":\"2026-05-17 03:23:56\",\"room\":null}', '{\"name\":\"LOYALTY\",\"capacity\":25,\"adviser_id\":null}', '::1', '2026-05-16 19:24:42', NULL),
(17, 1, 'update', 'sections', 1, '{\"id\":1,\"grade_level_id\":7,\"name\":\"OBEDIENCE\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:23:50\",\"updated_at\":\"2026-05-17 03:23:50\",\"room\":null}', '{\"name\":\"OBEDIENCE\",\"capacity\":25,\"adviser_id\":null}', '::1', '2026-05-16 19:24:49', NULL),
(18, 1, 'update', 'sections', 4, '{\"id\":4,\"grade_level_id\":7,\"name\":\"PEACE\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:24:09\",\"updated_at\":\"2026-05-17 03:24:09\",\"room\":null}', '{\"name\":\"PEACE\",\"capacity\":25,\"adviser_id\":null}', '::1', '2026-05-16 19:24:53', NULL),
(19, 1, 'create', 'sections', 6, NULL, '{\"grade_level_id\":8,\"name\":\"PRUDENCE\",\"capacity\":25,\"school_year_id\":1}', '::1', '2026-05-16 19:25:04', NULL),
(20, 1, 'create', 'sections', 7, NULL, '{\"grade_level_id\":8,\"name\":\"PATIENCE\",\"capacity\":25,\"school_year_id\":1}', '::1', '2026-05-16 19:25:26', NULL),
(21, 1, 'create', 'sections', 8, NULL, '{\"grade_level_id\":8,\"name\":\"COMPETENCE\",\"capacity\":25,\"school_year_id\":1}', '::1', '2026-05-16 19:25:38', NULL),
(22, 1, 'create', 'sections', 9, NULL, '{\"grade_level_id\":8,\"name\":\"DISCERNMENT\",\"capacity\":25,\"school_year_id\":1}', '::1', '2026-05-16 19:25:52', NULL),
(23, 1, 'create', 'sections', 10, NULL, '{\"grade_level_id\":9,\"name\":\"WISDOM\",\"capacity\":25,\"school_year_id\":1}', '::1', '2026-05-16 19:26:05', NULL),
(24, 1, 'create', 'sections', 11, NULL, '{\"grade_level_id\":9,\"name\":\"RIGHTEOUS\",\"capacity\":25,\"school_year_id\":1}', '::1', '2026-05-16 19:26:19', NULL),
(25, 1, 'create', 'sections', 12, NULL, '{\"grade_level_id\":9,\"name\":\"TRANQUILITY\",\"capacity\":25,\"school_year_id\":1}', '::1', '2026-05-16 19:26:34', NULL),
(26, 1, 'create', 'sections', 13, NULL, '{\"grade_level_id\":9,\"name\":\"COURAGE\",\"capacity\":25,\"school_year_id\":1}', '::1', '2026-05-16 19:26:41', NULL),
(27, 1, 'create', 'sections', 14, NULL, '{\"grade_level_id\":10,\"name\":\"HUMILITY\",\"capacity\":25,\"school_year_id\":1}', '::1', '2026-05-16 19:26:52', NULL),
(28, 1, 'create', 'sections', 15, NULL, '{\"grade_level_id\":10,\"name\":\"HONESTY\",\"capacity\":25,\"school_year_id\":1}', '::1', '2026-05-16 19:27:05', NULL),
(29, 1, 'create', 'sections', 16, NULL, '{\"grade_level_id\":10,\"name\":\"INTEGRITY\",\"capacity\":25,\"school_year_id\":1}', '::1', '2026-05-16 19:27:30', NULL),
(30, 1, 'create', 'sections', 17, NULL, '{\"grade_level_id\":10,\"name\":\"PERSEVERANCE\",\"capacity\":25,\"school_year_id\":1}', '::1', '2026-05-16 19:27:43', NULL),
(31, 1, 'create', 'subjects', 1, NULL, '{\"name\":\"ENGLISH\",\"code\":\"ENGLISH-07\",\"gradeId\":7}', '::1', '2026-05-16 19:30:08', NULL),
(32, 1, 'create', 'subjects', 2, NULL, '{\"name\":\"Math\",\"code\":\"MATH-07\",\"gradeId\":7}', '::1', '2026-05-16 19:30:30', NULL),
(33, 1, 'create', 'subjects', 3, NULL, '{\"name\":\"SCIENCE\",\"code\":\"SCI-07\",\"gradeId\":7}', '::1', '2026-05-16 19:30:52', NULL),
(34, 1, 'update', 'subjects', 1, '{\"id\":1,\"name\":\"ENGLISH\",\"code\":\"ENGLISH-07\",\"grade_level_id\":7,\"units\":\"1.00\",\"hours_per_week\":1,\"is_active\":1,\"is_archived\":0,\"created_at\":\"2026-05-17 03:30:08\",\"updated_at\":\"2026-05-17 03:30:08\"}', '{\"name\":\"ENGLISH\",\"code\":\"ENG-07\",\"gradeId\":7,\"hours\":1}', '::1', '2026-05-16 19:31:00', NULL),
(35, 1, 'deactivate', 'subjects', 1, NULL, NULL, '::1', '2026-05-16 19:31:07', NULL),
(36, 1, 'activate', 'subjects', 1, NULL, NULL, '::1', '2026-05-16 19:31:08', NULL),
(37, 1, 'create', 'subjects', 4, NULL, '{\"name\":\"FILIPINO\",\"code\":\"FIL-07\",\"gradeId\":7}', '::1', '2026-05-16 19:31:29', NULL),
(38, 1, 'update', 'subjects', 2, '{\"id\":2,\"name\":\"Math\",\"code\":\"MATH-07\",\"grade_level_id\":7,\"units\":\"1.00\",\"hours_per_week\":1,\"is_active\":1,\"is_archived\":0,\"created_at\":\"2026-05-17 03:30:30\",\"updated_at\":\"2026-05-17 03:30:30\"}', '{\"name\":\"MATH\",\"code\":\"MATH-07\",\"gradeId\":7,\"hours\":1}', '::1', '2026-05-16 19:31:37', NULL),
(39, 1, 'create', 'subjects', 5, NULL, '{\"name\":\"VALUES EDUCATION\",\"code\":\"ESP-07\",\"gradeId\":7}', '::1', '2026-05-16 19:32:08', NULL),
(40, 1, 'create', 'subjects', 6, NULL, '{\"name\":\"ARALING PANLIPUNAN\",\"code\":\"AP-07\",\"gradeId\":7}', '::1', '2026-05-16 19:32:23', NULL),
(41, 1, 'create', 'subjects', 7, NULL, '{\"name\":\"MAPEH\",\"code\":\"MAPEH-07\",\"gradeId\":7}', '::1', '2026-05-16 19:32:39', NULL),
(42, 1, 'create', 'subjects', 8, NULL, '{\"name\":\"TLE\",\"code\":\"TLE-07\",\"gradeId\":7}', '::1', '2026-05-16 19:32:52', NULL),
(43, 1, 'update', 'subjects', 4, '{\"id\":4,\"name\":\"FILIPINO\",\"code\":\"FIL-07\",\"grade_level_id\":7,\"units\":\"1.00\",\"hours_per_week\":1,\"is_active\":1,\"is_archived\":0,\"created_at\":\"2026-05-17 03:31:29\",\"updated_at\":\"2026-05-17 03:31:29\"}', '{\"name\":\"FILIPINO\",\"code\":\"FILIPINO-07\",\"gradeId\":7,\"hours\":1}', '::1', '2026-05-16 19:34:36', NULL),
(44, 1, 'update', 'subjects', 1, '{\"id\":1,\"name\":\"ENGLISH\",\"code\":\"ENG-07\",\"grade_level_id\":7,\"units\":\"1.00\",\"hours_per_week\":1,\"is_active\":1,\"is_archived\":0,\"created_at\":\"2026-05-17 03:30:08\",\"updated_at\":\"2026-05-17 03:31:08\"}', '{\"name\":\"ENGLISH\",\"code\":\"ENGLISH-07\",\"gradeId\":7,\"hours\":1}', '::1', '2026-05-16 19:34:43', NULL),
(45, 1, 'update', 'subjects', 3, '{\"id\":3,\"name\":\"SCIENCE\",\"code\":\"SCI-07\",\"grade_level_id\":7,\"units\":\"1.00\",\"hours_per_week\":1,\"is_active\":1,\"is_archived\":0,\"created_at\":\"2026-05-17 03:30:52\",\"updated_at\":\"2026-05-17 03:30:52\"}', '{\"name\":\"SCIENCE\",\"code\":\"SCIENCE-07\",\"gradeId\":7,\"hours\":1}', '::1', '2026-05-16 19:34:53', NULL),
(46, 1, 'update', 'subjects', 6, '{\"id\":6,\"name\":\"ARALING PANLIPUNAN\",\"code\":\"AP-07\",\"grade_level_id\":7,\"units\":\"1.00\",\"hours_per_week\":1,\"is_active\":1,\"is_archived\":0,\"created_at\":\"2026-05-17 03:32:23\",\"updated_at\":\"2026-05-17 03:32:23\"}', '{\"name\":\"ARALING PANLIPUNAN\",\"code\":\"AP-07\",\"gradeId\":7,\"hours\":1}', '::1', '2026-05-16 19:35:29', NULL),
(47, 1, 'create', 'subjects', 9, NULL, '{\"name\":\"ENGLISH\",\"code\":\"ENG-8\",\"gradeId\":8}', '::1', '2026-05-16 19:46:46', NULL),
(48, 1, 'update', 'subjects', 9, '{\"id\":9,\"name\":\"ENGLISH\",\"code\":\"ENG-8\",\"grade_level_id\":8,\"units\":\"1.00\",\"hours_per_week\":1,\"is_active\":1,\"is_archived\":0,\"created_at\":\"2026-05-17 03:46:46\",\"updated_at\":\"2026-05-17 03:46:46\"}', '{\"name\":\"ENGLISH\",\"code\":\"ENGLISH-8\",\"gradeId\":8,\"hours\":1}', '::1', '2026-05-16 19:46:57', NULL),
(49, 1, 'create', 'subjects', 10, NULL, '{\"name\":\"MATH\",\"code\":\"MATH-8\",\"gradeId\":8}', '::1', '2026-05-16 19:47:11', NULL),
(50, 1, 'create', 'subjects', 11, NULL, '{\"name\":\"SCIENCE\",\"code\":\"SCIENCE-8\",\"gradeId\":8}', '::1', '2026-05-16 19:47:24', NULL),
(51, 1, 'create', 'subjects', 12, NULL, '{\"name\":\"FILIPINO\",\"code\":\"FILIPINO-8\",\"gradeId\":8}', '::1', '2026-05-16 19:47:34', NULL),
(52, 1, 'create', 'subjects', 13, NULL, '{\"name\":\"VALUES EDUCATION\",\"code\":\"ESP-8\",\"gradeId\":8}', '::1', '2026-05-16 19:47:47', NULL),
(53, 1, 'create', 'subjects', 14, NULL, '{\"name\":\"ARALING PANLIPUNAN\",\"code\":\"AP-8\",\"gradeId\":8}', '::1', '2026-05-16 19:47:57', NULL),
(54, 1, 'create', 'subjects', 15, NULL, '{\"name\":\"MAPEH\",\"code\":\"MAPEH-8\",\"gradeId\":8}', '::1', '2026-05-16 19:48:09', NULL),
(55, 1, 'create', 'subjects', 16, NULL, '{\"name\":\"TLE\",\"code\":\"TLE-8\",\"gradeId\":8}', '::1', '2026-05-16 19:48:26', NULL),
(56, 1, 'create', 'subjects', 17, NULL, '{\"name\":\"ENGLISH\",\"code\":\"ENG-9\",\"gradeId\":9}', '::1', '2026-05-16 19:55:28', NULL),
(57, 1, 'update', 'subjects', 14, '{\"id\":14,\"name\":\"ARALING PANLIPUNAN\",\"code\":\"AP-8\",\"grade_level_id\":8,\"units\":\"1.00\",\"hours_per_week\":1,\"is_active\":1,\"is_archived\":0,\"created_at\":\"2026-05-17 03:47:57\",\"updated_at\":\"2026-05-17 03:47:57\"}', '{\"name\":\"ARALING PANLIPUNAN\",\"code\":\"AP-08\",\"gradeId\":8,\"hours\":1}', '::1', '2026-05-16 19:55:37', NULL),
(58, 1, 'update', 'subjects', 9, '{\"id\":9,\"name\":\"ENGLISH\",\"code\":\"ENGLISH-8\",\"grade_level_id\":8,\"units\":\"1.00\",\"hours_per_week\":1,\"is_active\":1,\"is_archived\":0,\"created_at\":\"2026-05-17 03:46:46\",\"updated_at\":\"2026-05-17 03:46:57\"}', '{\"name\":\"ENGLISH\",\"code\":\"ENGLISH-08\",\"gradeId\":8,\"hours\":1}', '::1', '2026-05-16 19:55:42', NULL),
(59, 1, 'update', 'subjects', 12, '{\"id\":12,\"name\":\"FILIPINO\",\"code\":\"FILIPINO-8\",\"grade_level_id\":8,\"units\":\"1.00\",\"hours_per_week\":1,\"is_active\":1,\"is_archived\":0,\"created_at\":\"2026-05-17 03:47:34\",\"updated_at\":\"2026-05-17 03:47:34\"}', '{\"name\":\"FILIPINO\",\"code\":\"FILIPINO-08\",\"gradeId\":8,\"hours\":1}', '::1', '2026-05-16 19:55:46', NULL),
(60, 1, 'update', 'subjects', 15, '{\"id\":15,\"name\":\"MAPEH\",\"code\":\"MAPEH-8\",\"grade_level_id\":8,\"units\":\"1.00\",\"hours_per_week\":1,\"is_active\":1,\"is_archived\":0,\"created_at\":\"2026-05-17 03:48:09\",\"updated_at\":\"2026-05-17 03:48:09\"}', '{\"name\":\"MAPEH\",\"code\":\"MAPEH-08\",\"gradeId\":8,\"hours\":1}', '::1', '2026-05-16 19:55:49', NULL),
(61, 1, 'update', 'subjects', 10, '{\"id\":10,\"name\":\"MATH\",\"code\":\"MATH-8\",\"grade_level_id\":8,\"units\":\"1.00\",\"hours_per_week\":1,\"is_active\":1,\"is_archived\":0,\"created_at\":\"2026-05-17 03:47:11\",\"updated_at\":\"2026-05-17 03:47:11\"}', '{\"name\":\"MATH\",\"code\":\"MATH-08\",\"gradeId\":8,\"hours\":1}', '::1', '2026-05-16 19:55:52', NULL),
(62, 1, 'update', 'subjects', 11, '{\"id\":11,\"name\":\"SCIENCE\",\"code\":\"SCIENCE-8\",\"grade_level_id\":8,\"units\":\"1.00\",\"hours_per_week\":1,\"is_active\":1,\"is_archived\":0,\"created_at\":\"2026-05-17 03:47:24\",\"updated_at\":\"2026-05-17 03:47:24\"}', '{\"name\":\"SCIENCE\",\"code\":\"SCIENCE-08\",\"gradeId\":8,\"hours\":1}', '::1', '2026-05-16 19:55:55', NULL),
(63, 1, 'update', 'subjects', 16, '{\"id\":16,\"name\":\"TLE\",\"code\":\"TLE-8\",\"grade_level_id\":8,\"units\":\"1.00\",\"hours_per_week\":1,\"is_active\":1,\"is_archived\":0,\"created_at\":\"2026-05-17 03:48:26\",\"updated_at\":\"2026-05-17 03:48:26\"}', '{\"name\":\"TLE\",\"code\":\"TLE-08\",\"gradeId\":8,\"hours\":1}', '::1', '2026-05-16 19:56:02', NULL),
(64, 1, 'update', 'subjects', 13, '{\"id\":13,\"name\":\"VALUES EDUCATION\",\"code\":\"ESP-8\",\"grade_level_id\":8,\"units\":\"1.00\",\"hours_per_week\":1,\"is_active\":1,\"is_archived\":0,\"created_at\":\"2026-05-17 03:47:47\",\"updated_at\":\"2026-05-17 03:47:47\"}', '{\"name\":\"VALUES EDUCATION\",\"code\":\"ESP-08\",\"gradeId\":8,\"hours\":1}', '::1', '2026-05-16 19:56:05', NULL),
(65, 1, 'update', 'subjects', 17, '{\"id\":17,\"name\":\"ENGLISH\",\"code\":\"ENG-9\",\"grade_level_id\":9,\"units\":\"1.00\",\"hours_per_week\":1,\"is_active\":1,\"is_archived\":0,\"created_at\":\"2026-05-17 03:55:28\",\"updated_at\":\"2026-05-17 03:55:28\"}', '{\"name\":\"ENGLISH\",\"code\":\"ENG-09\",\"gradeId\":9,\"hours\":1}', '::1', '2026-05-16 19:56:10', NULL),
(66, 1, 'create', 'subjects', 18, NULL, '{\"name\":\"MATH\",\"code\":\"MATH-09\",\"gradeId\":9}', '::1', '2026-05-16 19:56:22', NULL),
(67, 1, 'create', 'subjects', 19, NULL, '{\"name\":\"SCIENCE\",\"code\":\"SCIENCE-09\",\"gradeId\":9}', '::1', '2026-05-16 19:56:33', NULL),
(68, 1, 'create', 'subjects', 20, NULL, '{\"name\":\"FILIPINO\",\"code\":\"FILIPINO-09\",\"gradeId\":9}', '::1', '2026-05-16 19:56:45', NULL),
(69, 1, 'create', 'subjects', 21, NULL, '{\"name\":\"VALUES EDUCATION\",\"code\":\"ESP-09\",\"gradeId\":9}', '::1', '2026-05-16 19:56:55', NULL),
(70, 1, 'create', 'subjects', 22, NULL, '{\"name\":\"ARALING PANLIPUNAN\",\"code\":\"AP-09\",\"gradeId\":9}', '::1', '2026-05-16 19:57:10', NULL),
(71, 1, 'create', 'subjects', 23, NULL, '{\"name\":\"MAPEH\",\"code\":\"MAPEH-09\",\"gradeId\":9}', '::1', '2026-05-16 19:57:21', NULL),
(72, 1, 'create', 'subjects', 24, NULL, '{\"name\":\"TLE\",\"code\":\"TLE-09\",\"gradeId\":9}', '::1', '2026-05-16 19:57:29', NULL),
(73, 1, 'create', 'subjects', 25, NULL, '{\"name\":\"ENGLISH\",\"code\":\"ENGLISH-10\",\"gradeId\":10}', '::1', '2026-05-16 19:57:43', NULL),
(74, 1, 'create', 'subjects', 26, NULL, '{\"name\":\"MATH\",\"code\":\"MATH-10\",\"gradeId\":10}', '::1', '2026-05-16 19:57:53', NULL),
(75, 1, 'create', 'subjects', 27, NULL, '{\"name\":\"SCIENCE\",\"code\":\"SCIENCE-10\",\"gradeId\":10}', '::1', '2026-05-16 19:58:01', NULL),
(76, 1, 'create', 'subjects', 28, NULL, '{\"name\":\"FILIPINO\",\"code\":\"FILIPINO-10\",\"gradeId\":10}', '::1', '2026-05-16 19:59:28', NULL),
(77, 1, 'update', 'subjects', 17, '{\"id\":17,\"name\":\"ENGLISH\",\"code\":\"ENG-09\",\"grade_level_id\":9,\"units\":\"1.00\",\"hours_per_week\":1,\"is_active\":1,\"is_archived\":0,\"created_at\":\"2026-05-17 03:55:28\",\"updated_at\":\"2026-05-17 03:56:10\"}', '{\"name\":\"ENGLISH\",\"code\":\"ENGLISH-09\",\"gradeId\":9,\"hours\":1}', '::1', '2026-05-16 19:59:52', NULL),
(78, 1, 'create', 'subjects', 32, NULL, '{\"name\":\"VALUES EDUCATION\",\"code\":\"ESP-10\",\"gradeId\":10}', '::1', '2026-05-16 20:01:17', NULL),
(79, 1, 'create', 'subjects', 33, NULL, '{\"name\":\"ARALING PANLIPUNAN\",\"code\":\"AP-10\",\"gradeId\":10}', '::1', '2026-05-16 20:01:32', NULL),
(80, 1, 'create', 'subjects', 34, NULL, '{\"name\":\"MAPEH\",\"code\":\"MAPEH-10\",\"gradeId\":10}', '::1', '2026-05-16 20:01:42', NULL),
(81, 1, 'create', 'subjects', 35, NULL, '{\"name\":\"TLE\",\"code\":\"TLE-10\",\"gradeId\":10}', '::1', '2026-05-16 20:01:49', NULL),
(82, 1, 'create', 'curriculum', 1, NULL, '{\"school_year_id\":1,\"grade_level_id\":7,\"subject_id\":6}', '::1', '2026-05-16 20:02:01', NULL),
(83, 1, 'create', 'curriculum', 2, NULL, '{\"school_year_id\":1,\"grade_level_id\":7,\"subject_id\":1}', '::1', '2026-05-16 20:02:01', NULL),
(84, 1, 'create', 'curriculum', 3, NULL, '{\"school_year_id\":1,\"grade_level_id\":7,\"subject_id\":4}', '::1', '2026-05-16 20:02:02', NULL),
(85, 1, 'create', 'curriculum', 4, NULL, '{\"school_year_id\":1,\"grade_level_id\":7,\"subject_id\":7}', '::1', '2026-05-16 20:02:03', NULL),
(86, 1, 'create', 'curriculum', 5, NULL, '{\"school_year_id\":1,\"grade_level_id\":7,\"subject_id\":2}', '::1', '2026-05-16 20:02:03', NULL),
(87, 1, 'create', 'curriculum', 6, NULL, '{\"school_year_id\":1,\"grade_level_id\":7,\"subject_id\":3}', '::1', '2026-05-16 20:02:04', NULL),
(88, 1, 'create', 'curriculum', 7, NULL, '{\"school_year_id\":1,\"grade_level_id\":7,\"subject_id\":8}', '::1', '2026-05-16 20:02:04', NULL),
(89, 1, 'create', 'curriculum', 8, NULL, '{\"school_year_id\":1,\"grade_level_id\":7,\"subject_id\":5}', '::1', '2026-05-16 20:02:07', NULL),
(90, 1, 'create', 'curriculum', 9, NULL, '{\"school_year_id\":1,\"grade_level_id\":8,\"subject_id\":14}', '::1', '2026-05-16 20:02:08', NULL),
(91, 1, 'create', 'curriculum', 10, NULL, '{\"school_year_id\":1,\"grade_level_id\":8,\"subject_id\":9}', '::1', '2026-05-16 20:02:08', NULL),
(92, 1, 'create', 'curriculum', 11, NULL, '{\"school_year_id\":1,\"grade_level_id\":8,\"subject_id\":12}', '::1', '2026-05-16 20:02:08', NULL),
(93, 1, 'create', 'curriculum', 12, NULL, '{\"school_year_id\":1,\"grade_level_id\":8,\"subject_id\":15}', '::1', '2026-05-16 20:02:09', NULL),
(94, 1, 'create', 'curriculum', 13, NULL, '{\"school_year_id\":1,\"grade_level_id\":8,\"subject_id\":10}', '::1', '2026-05-16 20:02:10', NULL),
(95, 1, 'create', 'curriculum', 14, NULL, '{\"school_year_id\":1,\"grade_level_id\":8,\"subject_id\":11}', '::1', '2026-05-16 20:02:11', NULL),
(96, 1, 'create', 'curriculum', 15, NULL, '{\"school_year_id\":1,\"grade_level_id\":8,\"subject_id\":16}', '::1', '2026-05-16 20:02:11', NULL),
(97, 1, 'create', 'curriculum', 16, NULL, '{\"school_year_id\":1,\"grade_level_id\":8,\"subject_id\":13}', '::1', '2026-05-16 20:02:13', NULL),
(98, 1, 'create', 'curriculum', 17, NULL, '{\"school_year_id\":1,\"grade_level_id\":9,\"subject_id\":22}', '::1', '2026-05-16 20:02:15', NULL),
(99, 1, 'create', 'curriculum', 18, NULL, '{\"school_year_id\":1,\"grade_level_id\":9,\"subject_id\":17}', '::1', '2026-05-16 20:02:15', NULL),
(100, 1, 'create', 'curriculum', 19, NULL, '{\"school_year_id\":1,\"grade_level_id\":9,\"subject_id\":20}', '::1', '2026-05-16 20:02:16', NULL),
(101, 1, 'create', 'curriculum', 20, NULL, '{\"school_year_id\":1,\"grade_level_id\":9,\"subject_id\":23}', '::1', '2026-05-16 20:02:16', NULL),
(102, 1, 'create', 'curriculum', 21, NULL, '{\"school_year_id\":1,\"grade_level_id\":9,\"subject_id\":18}', '::1', '2026-05-16 20:02:17', NULL),
(103, 1, 'create', 'curriculum', 22, NULL, '{\"school_year_id\":1,\"grade_level_id\":9,\"subject_id\":19}', '::1', '2026-05-16 20:02:18', NULL),
(104, 1, 'create', 'curriculum', 23, NULL, '{\"school_year_id\":1,\"grade_level_id\":9,\"subject_id\":24}', '::1', '2026-05-16 20:02:19', NULL),
(105, 1, 'create', 'curriculum', 24, NULL, '{\"school_year_id\":1,\"grade_level_id\":9,\"subject_id\":21}', '::1', '2026-05-16 20:02:20', NULL),
(106, 1, 'create', 'curriculum', 25, NULL, '{\"school_year_id\":1,\"grade_level_id\":10,\"subject_id\":33}', '::1', '2026-05-16 20:02:23', NULL),
(107, 1, 'create', 'curriculum', 26, NULL, '{\"school_year_id\":1,\"grade_level_id\":10,\"subject_id\":25}', '::1', '2026-05-16 20:02:24', NULL),
(108, 1, 'create', 'curriculum', 27, NULL, '{\"school_year_id\":1,\"grade_level_id\":10,\"subject_id\":28}', '::1', '2026-05-16 20:02:25', NULL),
(109, 1, 'create', 'curriculum', 28, NULL, '{\"school_year_id\":1,\"grade_level_id\":10,\"subject_id\":34}', '::1', '2026-05-16 20:02:25', NULL),
(110, 1, 'create', 'curriculum', 29, NULL, '{\"school_year_id\":1,\"grade_level_id\":10,\"subject_id\":32}', '::1', '2026-05-16 20:02:29', NULL),
(111, 1, 'create', 'curriculum', 30, NULL, '{\"school_year_id\":1,\"grade_level_id\":10,\"subject_id\":35}', '::1', '2026-05-16 20:02:29', NULL),
(112, 1, 'create', 'curriculum', 31, NULL, '{\"school_year_id\":1,\"grade_level_id\":10,\"subject_id\":27}', '::1', '2026-05-16 20:02:30', NULL),
(113, 1, 'create', 'curriculum', 32, NULL, '{\"school_year_id\":1,\"grade_level_id\":10,\"subject_id\":26}', '::1', '2026-05-16 20:02:32', NULL),
(114, 1, 'archive', 'curriculum', 25, NULL, NULL, '::1', '2026-05-16 20:02:35', NULL),
(115, 1, 'create', 'curriculum', 33, NULL, '{\"school_year_id\":1,\"grade_level_id\":10,\"subject_id\":33}', '::1', '2026-05-16 20:02:35', NULL),
(116, 1, 'archive', 'curriculum', 33, NULL, NULL, '::1', '2026-05-16 20:02:35', NULL),
(117, 1, 'create', 'curriculum', 34, NULL, '{\"school_year_id\":1,\"grade_level_id\":10,\"subject_id\":33}', '::1', '2026-05-16 20:02:35', NULL),
(118, 1, 'archive', 'curriculum', 34, NULL, NULL, '::1', '2026-05-16 20:02:35', NULL),
(119, 1, 'create', 'curriculum', 35, NULL, '{\"school_year_id\":1,\"grade_level_id\":10,\"subject_id\":33}', '::1', '2026-05-16 20:02:36', NULL),
(120, 1, 'archive', 'curriculum', 35, NULL, NULL, '::1', '2026-05-16 20:02:36', NULL),
(121, 1, 'create', 'curriculum', 36, NULL, '{\"school_year_id\":1,\"grade_level_id\":10,\"subject_id\":33}', '::1', '2026-05-16 20:02:40', NULL),
(122, 1, 'create', 'cashiers', 1, NULL, '{\"full_name\":\"Carlos Menendez\",\"username\":\"CarlosMendez\",\"role\":\"cashier\",\"school_email\":\"carlosmenendez@sjccashier.edu.ph\"}', '::1', '2026-05-17 17:53:00', NULL),
(123, 1, 'update', 'students', 1, '{\"personal_email\":\"phillippejoshua274@gmail.com\"}', '{\"personal_email\":\"phillippejoshua274@gmail.com\"}', '::1', '2026-05-18 19:09:01', NULL),
(124, 1, 'update', 'students', 1, '{\"lrn\":null}', '{\"lrn\":\"000000000001\"}', '::1', '2026-05-18 19:09:01', NULL),
(125, 1, 'update', 'students', 7, '{\"personal_email\":\"phillippejoshua27.5@gmail.com\"}', '{\"personal_email\":\"phillippejoshua27.5@gmail.com\"}', '::1', '2026-05-18 19:09:06', NULL),
(126, 1, 'update', 'students', 7, '{\"personal_email\":\"phillippejoshua27.5@gmail.com\"}', '{\"personal_email\":\"phillippejoshua27.5@gmail.com\"}', '::1', '2026-05-18 19:09:10', NULL),
(127, 1, 'update', 'students', 7, '{\"lrn\":null}', '{\"lrn\":\"000000000002\"}', '::1', '2026-05-18 19:09:10', NULL),
(128, 1, 'update', 'students', 10, '{\"lrn\":null}', '{\"lrn\":\"000000000003\"}', '::1', '2026-05-18 19:09:15', NULL),
(129, 1, 'update', 'students', 10, '{\"personal_email\":\"phillippejoshua27.4@gmail.com\"}', '{\"personal_email\":\"phillippejoshua27.4@gmail.com\"}', '::1', '2026-05-18 19:09:15', NULL),
(130, 1, 'update', 'students', 9, '{\"lrn\":null}', '{\"lrn\":\"000000000004\"}', '::1', '2026-05-18 19:09:22', NULL),
(131, 1, 'update', 'students', 9, '{\"personal_email\":\"phillippejoshua279@gmail.com\"}', '{\"personal_email\":\"phillippejoshua279@gmail.com\"}', '::1', '2026-05-18 19:09:22', NULL),
(132, 1, 'create', 'admins', 5, NULL, '{\"full_name\":\"Kurt Michael\",\"username\":\"KurtM\",\"role\":\"admin\",\"school_email\":\"kurtmichael@sjcadmin.edu.ph\"}', '::1', '2026-05-18 19:10:56', NULL),
(133, 1, 'create', 'system_deadlines', 1, NULL, '{\"type\":\"enrollment\",\"start\":\"2026-05-19 03:29:00\",\"end\":\"2026-05-30 03:29:00\"}', '::1', '2026-05-18 19:30:13', NULL),
(134, 1, 'update', 'system_deadlines', 1, '{\"id\":1,\"school_year_id\":1,\"type\":\"enrollment\",\"start_date\":\"0000-00-00\",\"end_date\":\"0000-00-00\",\"start_datetime\":\"2026-05-19 03:29:00\",\"end_datetime\":\"2026-05-30 03:29:00\",\"notes\":\"\",\"created_by\":1,\"created_at\":\"2026-05-19 03:30:13\",\"updated_at\":\"2026-05-19 03:30:13\"}', '{\"type\":\"enrollment\",\"start\":\"2026-05-19 03:29:00\",\"end\":\"2026-05-30 03:29:00\"}', '::1', '2026-05-18 19:53:38', NULL),
(135, 1, 'create', 'registrars', 1, NULL, '{\"full_name\":\"Keith Nacel\",\"username\":\"KeithC.\",\"role\":\"registrar\",\"school_email\":\"keithnacel@sjcregistrar.edu.ph\"}', '::1', '2026-05-19 07:51:14', NULL),
(136, 1, 'create', 'principals', 1, NULL, '{\"full_name\":\"Kurt Rada\",\"username\":\"KurtR\",\"role\":\"principal\",\"school_email\":\"kurtrada@sjcprincipal.edu.ph\"}', '::1', '2026-05-19 07:56:06', NULL),
(137, 1, 'create', 'coordinators', 1, NULL, '{\"full_name\":\"Sherwin Galang\",\"username\":\"SherwinG\",\"role\":\"coordinator\",\"school_email\":\"sherwingalang@sjccoordinator.edu.ph\"}', '::1', '2026-05-19 07:58:23', NULL),
(138, 1, 'create', 'coordinators', 2, NULL, '{\"full_name\":\"Jericho Ocray\",\"username\":\"JerichoO\",\"role\":\"coordinator\",\"school_email\":\"jerichoocray@sjccoordinator.edu.ph\"}', '::1', '2026-05-19 07:59:22', NULL),
(139, 1, 'create', 'teachers', 1, NULL, '{\"full_name\":\"Denver SandCheese\",\"username\":\"DenverS\",\"role\":\"teacher\",\"school_email\":\"denversandcheese@sjcteacher.edu.ph\"}', '::1', '2026-05-19 08:00:01', NULL),
(140, 1, 'update', 'students', 13, '{\"personal_email\":\"phillippejoshua27.9@gmail.com\"}', '{\"personal_email\":\"phillippejoshua27.9@gmail.com\"}', '::1', '2026-05-20 15:15:14', NULL),
(141, 1, 'update', 'students', 13, '{\"personal_email\":\"phillippejoshua27.9@gmail.com\"}', '{\"personal_email\":\"phillippejoshua27.9@gmail.com\"}', '::1', '2026-05-20 15:15:24', NULL),
(142, 1, 'update', 'students', 13, '{\"lrn\":null}', '{\"lrn\":\"000000000005\"}', '::1', '2026-05-20 15:15:24', NULL),
(143, 1, 'update', 'students', 11, '{\"personal_email\":\"phillippejoshu.a274@gmail.com\"}', '{\"personal_email\":\"phillippejoshu.a274@gmail.com\"}', '::1', '2026-05-20 15:15:30', NULL),
(144, 1, 'update', 'students', 11, '{\"lrn\":null}', '{\"lrn\":\"000000000006\"}', '::1', '2026-05-20 15:15:30', NULL),
(145, 1, 'update', 'students', 12, '{\"lrn\":null}', '{\"lrn\":\"000000000007\"}', '::1', '2026-05-20 15:15:35', NULL),
(146, 1, 'update', 'students', 12, '{\"personal_email\":\"phillippejoshua2.75@gmail.com\"}', '{\"personal_email\":\"phillippejoshua2.75@gmail.com\"}', '::1', '2026-05-20 15:15:35', NULL),
(147, 1, 'archive', 'students', 13, NULL, NULL, '::1', '2026-05-20 15:16:01', NULL),
(148, 1, 'archive', 'students', 11, NULL, NULL, '::1', '2026-05-20 15:16:02', NULL),
(149, 1, 'archive', 'students', 12, NULL, NULL, '::1', '2026-05-20 15:16:04', NULL),
(150, 1, 'create', 'registrars', 2, NULL, '{\"full_name\":\"Artemis Arklight\",\"username\":\"ArtemisArk\",\"role\":\"registrar\",\"school_email\":\"artemisarklight@sjcregistrar.edu.ph\"}', '::1', '2026-05-20 15:16:59', NULL),
(151, 1, 'update', 'students', 14, '{\"personal_email\":\"phillippejoshua2.79@gmail.com\"}', '{\"personal_email\":\"phillippejoshua2.79@gmail.com\"}', '::1', '2026-05-20 18:18:13', NULL),
(152, 1, 'update', 'students', 14, '{\"personal_email\":\"phillippejoshua2.79@gmail.com\"}', '{\"personal_email\":\"phillippejoshua2.79@gmail.com\"}', '::1', '2026-05-20 18:18:24', NULL),
(153, 1, 'update', 'students', 14, '{\"lrn\":null}', '{\"lrn\":\"000000000008\"}', '::1', '2026-05-20 18:18:24', NULL),
(154, 1, 'archive', 'rooms', 3, '{\"id\":3,\"number\":\"103\",\"capacity\":25,\"status\":\"active\",\"created_by\":1,\"created_at\":\"2026-05-22 01:03:50\",\"updated_at\":\"2026-05-22 01:03:50\"}', '{\"status\":\"archived\"}', '::1', '2026-05-21 17:09:42', NULL),
(155, 1, 'restore', 'rooms', 3, '{\"id\":3,\"number\":\"103\",\"capacity\":25,\"status\":\"archived\",\"created_by\":1,\"created_at\":\"2026-05-22 01:03:50\",\"updated_at\":\"2026-05-22 01:09:42\"}', '{\"status\":\"active\"}', '::1', '2026-05-21 17:09:44', NULL),
(156, 1, 'archive', 'rooms', 3, '{\"id\":3,\"number\":\"103\",\"capacity\":25,\"status\":\"active\",\"created_by\":1,\"created_at\":\"2026-05-22 01:03:50\",\"updated_at\":\"2026-05-22 01:09:44\"}', '{\"status\":\"archived\"}', '::1', '2026-05-21 17:09:49', NULL),
(157, 1, 'restore', 'rooms', 3, '{\"id\":3,\"number\":\"103\",\"capacity\":25,\"status\":\"archived\",\"created_by\":1,\"created_at\":\"2026-05-22 01:03:50\",\"updated_at\":\"2026-05-22 01:09:49\"}', '{\"status\":\"active\"}', '::1', '2026-05-21 17:09:58', NULL),
(158, 1, 'create', 'rooms', 4, NULL, '{\"number\":\"104\",\"capacity\":25}', '::1', '2026-05-21 17:10:03', NULL),
(159, 1, 'create', 'rooms', 5, NULL, '{\"number\":\"105\",\"capacity\":25}', '::1', '2026-05-21 17:10:10', NULL),
(160, 1, 'update', 'coordinators', 2, '{\"role\":\"coordinator\",\"school_email\":\"jerichoocray@sjccoordinator.edu.ph\",\"personal_email\":\"columbina234@gmail.com\"}', '{\"full_name\":\"Carlos Michelle\",\"role\":\"coordinator\",\"personal_email\":\"columbina234@gmail.com\"}', '::1', '2026-05-21 17:51:44', NULL),
(161, 1, 'archive', 'coordinators', 2, NULL, NULL, '::1', '2026-05-21 17:52:22', NULL),
(162, 1, 'archive', 'coordinators', 1, NULL, NULL, '::1', '2026-05-21 17:53:45', NULL),
(163, 1, 'archive', 'registrars', 1, NULL, NULL, '::1', '2026-05-21 17:53:52', NULL),
(164, 1, 'archive', 'teachers', 1, NULL, NULL, '::1', '2026-05-21 17:53:58', NULL),
(165, 1, 'create', 'teachers', 2, NULL, '{\"full_name\":\"Perlica Clara\",\"username\":\"PerliC\",\"role\":\"teacher\",\"school_email\":\"perlicaclara@sjcteacher.edu.ph\"}', '::1', '2026-05-21 17:55:37', NULL),
(166, 1, 'create', 'coordinators', 3, NULL, '{\"full_name\":\"Felicitas Gamuella\",\"username\":\"FelicitasG\",\"role\":\"coordinator\",\"school_email\":\"felicitasgamuella@sjccoordinator.edu.ph\"}', '::1', '2026-05-21 17:56:32', NULL),
(167, 1, 'archive', 'principals', 1, NULL, NULL, '::1', '2026-05-21 17:58:14', NULL),
(168, 1, 'create', 'principals', 2, NULL, '{\"full_name\":\"Joshua Aguilar\",\"username\":\"JoshuaA\",\"role\":\"principal\",\"school_email\":\"joshuaaguilar@sjcprincipal.edu.ph\"}', '::1', '2026-05-21 17:58:46', NULL),
(169, 1, 'archive', 'coordinators', 3, NULL, NULL, '::1', '2026-05-21 18:01:07', NULL),
(170, 1, 'restore', 'coordinators', 3, NULL, NULL, '::1', '2026-05-21 18:01:16', NULL),
(171, 1, 'update', 'teachers', 2, '{\"role\":\"teacher\",\"school_email\":\"perlicaclara@sjcteacher.edu.ph\",\"personal_email\":\"columbina23.4@gmail.com\"}', '{\"full_name\":\"Perlica Clara\",\"role\":\"teacher\",\"personal_email\":\"columbina23.4@gmail.com\"}', '::1', '2026-05-21 18:03:50', NULL),
(172, 1, 'create', 'teachers', 3, NULL, '{\"full_name\":\"Filomenileia Querina\",\"username\":\"FiloQ\",\"role\":\"teacher\",\"school_email\":\"filomenileiaquerina@sjcteacher.edu.ph\"}', '::1', '2026-05-21 18:04:50', NULL),
(173, 1, 'update', 'teachers', 3, '{\"role\":\"teacher\",\"school_email\":\"filomenileiaquerina@sjcteacher.edu.ph\",\"personal_email\":\"columbina23.4@gmail.com\"}', '{\"full_name\":\"Filomenileia Querina\",\"role\":\"teacher\",\"personal_email\":\"columbina23.4@gmail.com\"}', '::1', '2026-05-21 18:14:31', NULL),
(174, 1, 'update', 'teachers', 2, '{\"role\":\"teacher\",\"school_email\":\"perlicaclara@sjcteacher.edu.ph\",\"personal_email\":\"columbina23.4@gmail.com\"}', '{\"full_name\":\"Perlica Clara\",\"role\":\"teacher\",\"personal_email\":\"columbina23.4@gmail.com\"}', '::1', '2026-05-21 18:14:33', NULL),
(175, 1, 'update', 'teachers', 3, '{\"role\":\"teacher\",\"school_email\":\"filomenileiaquerina@sjcteacher.edu.ph\",\"personal_email\":\"columbina23.4@gmail.com\"}', '{\"full_name\":\"Filomenileia Querina\",\"role\":\"teacher\",\"personal_email\":\"columbina23.4@gmail.com\"}', '::1', '2026-05-21 18:14:41', NULL),
(176, 1, 'update', 'teachers', 2, '{\"role\":\"teacher\",\"school_email\":\"perlicaclara@sjcteacher.edu.ph\",\"personal_email\":\"columbina23.4@gmail.com\"}', '{\"full_name\":\"Perlica Clara\",\"role\":\"teacher\",\"personal_email\":\"columbina23.4@gmail.com\"}', '::1', '2026-05-21 18:14:44', NULL),
(177, 1, 'archive', 'teachers', 3, NULL, NULL, '::1', '2026-05-21 18:43:43', NULL),
(178, 1, 'archive', 'teachers', 2, NULL, NULL, '::1', '2026-05-21 18:43:45', NULL),
(179, 1, 'archive', 'principals', 2, NULL, NULL, '::1', '2026-05-21 18:43:49', NULL),
(180, 1, 'archive', 'coordinators', 3, NULL, NULL, '::1', '2026-05-21 18:43:53', NULL),
(181, 1, 'create', 'coordinators', 4, NULL, '{\"full_name\":\"Samonteza Argoyle\",\"username\":\"SamonArgoy\",\"role\":\"coordinator\",\"school_email\":\"samontezaargoyle@sjccoordinator.edu.ph\"}', '::1', '2026-05-21 18:44:58', NULL),
(182, 1, 'create', 'teachers', 4, NULL, '{\"full_name\":\"Perlica Nalaya\",\"username\":\"PerlicaN\",\"role\":\"teacher\",\"school_email\":\"perlicanalaya@sjcteacher.edu.ph\"}', '::1', '2026-05-21 18:45:36', NULL),
(183, 1, 'create', 'teachers', 5, NULL, '{\"full_name\":\"Joshua Lupisan\",\"username\":\"JoshuaL\",\"role\":\"teacher\",\"school_email\":\"joshualupisan@sjcteacher.edu.ph\"}', '::1', '2026-05-21 18:46:06', NULL),
(184, 1, 'update', 'teachers', 5, '{\"role\":\"teacher\",\"school_email\":\"joshualupisan@sjcteacher.edu.ph\",\"personal_email\":\"phillippejoshua2.79@gmail.com\"}', '{\"full_name\":\"Joshua Lupisan\",\"role\":\"teacher\",\"personal_email\":\"phillippejoshua2.79@gmail.com\"}', '::1', '2026-05-21 18:46:13', NULL),
(185, 1, 'create', 'principals', 3, NULL, '{\"full_name\":\"Joshua Aguilar\",\"username\":\"JoshuaP\",\"role\":\"principal\",\"school_email\":\"joshuaaguilar2@sjcprincipal.edu.ph\"}', '::1', '2026-05-21 18:46:48', NULL),
(186, 1, 'archive', 'teachers', 5, NULL, NULL, '::1', '2026-05-21 18:54:13', NULL),
(187, 1, 'restore', 'teachers', 5, NULL, NULL, '::1', '2026-05-21 18:54:27', NULL),
(188, 1, 'activate', 'school_years', 2, NULL, '{\"label\":\"2027-2028\",\"status\":\"active\"}', '::1', '2026-05-21 19:20:12', NULL),
(189, 1, 'activate', 'school_years', 1, NULL, '{\"label\":\"2026-2027\",\"status\":\"active\"}', '::1', '2026-05-21 19:20:14', NULL),
(190, 1, 'create', 'school_years', 3, NULL, '{\"label\":\"2027-2028\",\"start\":\"2027-12-05\",\"end\":\"2028-12-05\",\"active\":0,\"confirmed\":1}', '::1', '2026-05-21 19:29:51', NULL),
(191, 1, '', 'sections', 3, '{\"room\":\"100\"}', '{\"room\":null}', '::1', '2026-05-22 09:49:28', NULL),
(192, 1, '', 'sections', 5, '{\"room\":\"100\"}', '{\"room\":null}', '::1', '2026-05-22 09:49:32', NULL),
(193, 1, 'update', 'students', 15, '{\"personal_email\":\"p.hillippejoshua27.5@gmail.com\"}', '{\"personal_email\":\"p.hillippejoshua27.5@gmail.com\"}', '::1', '2026-05-22 13:00:32', NULL),
(194, 1, 'update', 'students', 15, '{\"personal_email\":\"p.hillippejoshua27.5@gmail.com\"}', '{\"personal_email\":\"p.hillippejoshua27.5@gmail.com\"}', '::1', '2026-05-22 13:00:35', NULL),
(195, 1, 'update', 'students', 15, '{\"lrn\":null}', '{\"lrn\":\"000000000009\"}', '::1', '2026-05-22 13:00:35', NULL),
(196, 1, 'update', 'students', 16, '{\"personal_email\":\"phillippe.joshua275@gmail.com\"}', '{\"personal_email\":\"phillippe.joshua275@gmail.com\"}', '::1', '2026-05-22 13:00:43', NULL),
(197, 1, 'update', 'students', 16, '{\"lrn\":null}', '{\"lrn\":\"000000000010\"}', '::1', '2026-05-22 13:00:43', NULL),
(198, 1, '', 'sections', 2, '{\"room\":\"103\"}', '{\"room\":null}', '::1', '2026-05-22 14:37:24', NULL),
(199, 1, 'create', 'school_years', 4, NULL, '{\"label\":\"2028-2029\",\"start\":\"2028-12-05\",\"end\":\"2029-12-05\",\"active\":0,\"confirmed\":1}', '::1', '2026-05-23 16:37:48', NULL),
(200, 1, 'update', 'sections', 5, NULL, '{\"assigned_students\":25}', '::1', '2026-05-24 16:59:06', NULL),
(201, 1, 'update', 'sections', 3, NULL, '{\"assigned_students\":25}', '::1', '2026-05-24 16:59:16', NULL),
(202, 1, 'update', 'sections', 2, NULL, '{\"assigned_students\":25}', '::1', '2026-05-24 16:59:23', NULL),
(203, 1, 'update', 'sections', 1, NULL, '{\"assigned_students\":25}', '::1', '2026-05-24 16:59:29', NULL),
(204, 1, 'update', 'sections', 8, NULL, '{\"assigned_students\":25}', '::1', '2026-05-24 16:59:38', NULL),
(205, 1, 'update', 'sections', 9, NULL, '{\"assigned_students\":25}', '::1', '2026-05-24 16:59:43', NULL),
(206, 1, 'update', 'sections', 7, NULL, '{\"assigned_students\":25}', '::1', '2026-05-24 16:59:47', NULL),
(207, 1, 'update', 'sections', 6, NULL, '{\"assigned_students\":25}', '::1', '2026-05-24 16:59:52', NULL),
(208, 1, 'update', 'sections', 13, NULL, '{\"assigned_students\":25}', '::1', '2026-05-24 17:00:03', NULL),
(209, 1, 'update', 'sections', 11, NULL, '{\"assigned_students\":25}', '::1', '2026-05-24 17:00:08', NULL),
(210, 1, 'update', 'sections', 12, NULL, '{\"assigned_students\":25}', '::1', '2026-05-24 17:00:13', NULL),
(211, 1, 'update', 'sections', 10, NULL, '{\"assigned_students\":25}', '::1', '2026-05-24 17:00:18', NULL),
(212, 1, 'update', 'sections', 15, NULL, '{\"assigned_students\":25}', '::1', '2026-05-24 17:00:25', NULL),
(213, 1, 'update', 'sections', 14, NULL, '{\"assigned_students\":25}', '::1', '2026-05-24 17:00:30', NULL),
(214, 1, 'update', 'sections', 16, NULL, '{\"assigned_students\":20}', '::1', '2026-05-24 17:00:40', NULL),
(215, 1, 'update', 'sections', 17, NULL, '{\"assigned_students\":9}', '::1', '2026-05-24 17:00:53', NULL),
(216, 1, 'update', 'sections', 15, NULL, '{\"batch_removed_students\":[318,330,414,335,370,397,390,344,333,383],\"removed_count\":10}', '::1', '2026-05-24 17:01:04', NULL),
(217, 1, 'update', 'sections', 13, NULL, '{\"batch_removed_students\":[224,262,271,245,272,290,315,230,281],\"removed_count\":9}', '::1', '2026-05-24 17:01:12', NULL),
(218, 1, 'update', 'sections', 12, NULL, '{\"batch_removed_students\":[248,295,313,297,302,307,279,260,309,219,283],\"removed_count\":11}', '::1', '2026-05-24 17:01:24', NULL),
(219, 1, 'update', 'sections', 6, NULL, '{\"batch_removed_students\":[163,168,201,124,195,141,213,182,214,185],\"removed_count\":10}', '::1', '2026-05-24 17:01:35', NULL),
(220, 1, 'update', 'sections', 11, NULL, '{\"batch_removed_students\":[308,227,294,228,253,270,301,314,250,233,287],\"removed_count\":11}', '::1', '2026-05-24 17:01:49', NULL),
(221, 1, 'update', 'sections', 10, NULL, '{\"batch_removed_students\":[278,316,299,265,291,252,221,293,235],\"removed_count\":9}', '::1', '2026-05-24 17:01:58', NULL),
(222, 1, 'update', 'sections', 7, NULL, '{\"batch_removed_students\":[200,147,151,188,119,211,193,177,144,150,158,139],\"removed_count\":12}', '::1', '2026-05-24 17:02:15', NULL),
(223, 1, 'update', 'sections', 9, NULL, '{\"batch_removed_students\":[180,184,145,183,172,156,197,212,199,206,148,142,122,131],\"removed_count\":14}', '::1', '2026-05-24 17:02:27', NULL),
(224, 1, 'update', 'sections', 8, NULL, '{\"batch_removed_students\":[207,130,152,138,203,146,186,178,187,120,171],\"removed_count\":11}', '::1', '2026-05-24 17:02:38', NULL),
(225, 1, 'update', 'sections', 1, NULL, '{\"batch_removed_students\":[97,30,89,19,102,48,29],\"removed_count\":7}', '::1', '2026-05-24 17:02:45', NULL),
(226, 1, 'update', 'sections', 2, NULL, '{\"batch_removed_students\":[38,56,117,70,50,110],\"removed_count\":6}', '::1', '2026-05-24 17:02:51', NULL),
(227, 1, 'update', 'sections', 3, NULL, '{\"batch_removed_students\":[111,31,68,69,33],\"removed_count\":5}', '::1', '2026-05-24 17:02:56', NULL),
(228, 1, 'update', 'sections', 5, NULL, '{\"batch_removed_students\":[45,87,73],\"removed_count\":3}', '::1', '2026-05-24 17:03:01', NULL),
(229, 1, 'create', 'rooms', 6, NULL, '{\"number\":\"106\",\"capacity\":25}', '::1', '2026-05-24 17:06:17', NULL),
(230, 1, 'create', 'rooms', 7, NULL, '{\"number\":\"107\",\"capacity\":25}', '::1', '2026-05-24 17:06:37', NULL),
(231, 1, 'create', 'rooms', 8, NULL, '{\"number\":\"108\",\"capacity\":25}', '::1', '2026-05-24 17:06:44', NULL),
(232, 1, 'create', 'rooms', 9, NULL, '{\"number\":\"109\",\"capacity\":25}', '::1', '2026-05-24 17:06:51', NULL),
(233, 1, 'create', 'rooms', 10, NULL, '{\"number\":\"110\",\"capacity\":25}', '::1', '2026-05-24 17:06:56', NULL),
(234, 1, 'create', 'rooms', 11, NULL, '{\"number\":\"111\",\"capacity\":25}', '::1', '2026-05-24 17:07:02', NULL),
(235, 1, 'create', 'rooms', 12, NULL, '{\"number\":\"112\",\"capacity\":25}', '::1', '2026-05-24 17:07:06', NULL),
(236, 1, 'create', 'rooms', 13, NULL, '{\"number\":\"113\",\"capacity\":25}', '::1', '2026-05-24 17:07:11', NULL),
(237, 1, 'create', 'rooms', 14, NULL, '{\"number\":\"114\",\"capacity\":25}', '::1', '2026-05-24 17:07:14', NULL),
(238, 1, 'create', 'rooms', 15, NULL, '{\"number\":\"115\",\"capacity\":25}', '::1', '2026-05-24 17:07:23', NULL),
(239, 1, 'create', 'rooms', 16, NULL, '{\"number\":\"116\",\"capacity\":25}', '::1', '2026-05-24 17:07:32', NULL),
(240, 1, 'create', 'rooms', 17, NULL, '{\"number\":\"117\",\"capacity\":25}', '::1', '2026-05-24 17:07:41', NULL),
(241, 1, 'update', 'sections', 17, NULL, '{\"assigned_students\":1}', '::1', '2026-05-24 17:43:21', NULL),
(242, 1, 'update', 'sections', 5, NULL, '{\"batch_removed_students\":[47,36,105,71,21,80,95,96,99,53,52,23,61,27,101,46,112,32,79,24,20,59],\"removed_count\":22}', '::1', '2026-05-24 17:44:54', NULL),
(243, 1, 'update', 'sections', 3, NULL, '{\"batch_removed_students\":[90,66,55,44,35,39,92,67,78,77,109,43,108,106,26,22,114,104,64,25],\"removed_count\":20}', '::1', '2026-05-24 17:44:59', NULL),
(244, 1, 'update', 'sections', 2, NULL, '{\"batch_removed_students\":[63,93,115,28,42,57,81,83,76,113,62,37,82,88,49,85,41,86,74],\"removed_count\":19}', '::1', '2026-05-24 17:45:04', NULL),
(245, 1, 'update', 'sections', 1, NULL, '{\"batch_removed_students\":[18,54,40,60,91,51,100,107,65,103,98,58,34,72,116,75,94,84],\"removed_count\":18}', '::1', '2026-05-24 17:45:15', NULL),
(246, 1, 'update', 'sections', 8, NULL, '{\"batch_removed_students\":[176,153,174,196,179,169,198,181,159,191,140,215,162,175],\"removed_count\":14}', '::1', '2026-05-24 17:45:21', NULL),
(247, 1, 'update', 'sections', 9, NULL, '{\"batch_removed_students\":[190,118,134,173,136,135,129,137,149,170,205],\"removed_count\":11}', '::1', '2026-05-24 17:45:24', NULL),
(248, 1, 'update', 'sections', 7, NULL, '{\"batch_removed_students\":[154,165,217,160,209,157,166,210,121,194,202,133,208],\"removed_count\":13}', '::1', '2026-05-24 17:45:29', NULL),
(249, 1, 'update', 'sections', 6, NULL, '{\"batch_removed_students\":[125,189,128,132,216,143,155,123,127,164,167,161,126,192,204],\"removed_count\":15}', '::1', '2026-05-24 17:45:32', NULL),
(250, 1, 'update', 'sections', 13, NULL, '{\"batch_removed_students\":[274,300,312,237,231,282,285,280,268,269,255,247,244,276,243,218],\"removed_count\":16}', '::1', '2026-05-24 17:45:42', NULL),
(251, 1, 'update', 'sections', 11, NULL, '{\"batch_removed_students\":[234,238,229,267,284,223,289,236,259,222,288,232,292,264],\"removed_count\":14}', '::1', '2026-05-24 17:45:46', NULL),
(252, 1, 'update', 'sections', 12, NULL, '{\"batch_removed_students\":[306,317,241,273,277,303,258,220,261,257,304,311,242,263],\"removed_count\":14}', '::1', '2026-05-24 17:45:57', NULL),
(253, 1, 'update', 'sections', 10, NULL, '{\"batch_removed_students\":[239,298,254,296,225,305,246,240,286,226,249,275,251,256,266,310],\"removed_count\":16}', '::1', '2026-05-24 17:46:01', NULL),
(254, 1, 'update', 'sections', 15, NULL, '{\"batch_removed_students\":[416,388,363,407,325,336,348,372,323,369,413,371,364,404,400],\"removed_count\":15}', '::1', '2026-05-24 17:46:05', NULL),
(255, 1, 'update', 'sections', 14, NULL, '{\"batch_removed_students\":[366,346,358,332,360,410,380,393,351,376,394,339,354,359,356,355,353,337,408,343,350,401,391,368,319],\"removed_count\":25}', '::1', '2026-05-24 17:46:10', NULL),
(256, 1, 'update', 'sections', 16, NULL, '{\"batch_removed_students\":[365,345,382,373,334,338,374,405,396,398,329,387,367,328,347,411,342,361,331,341],\"removed_count\":20}', '::1', '2026-05-24 17:46:25', NULL),
(257, 1, 'update', 'sections', 17, NULL, '{\"batch_removed_students\":[322,381,349,17,412,326,377,402,340],\"removed_count\":9}', '::1', '2026-05-24 17:46:29', NULL),
(258, 1, 'update', 'sections', 17, NULL, '{\"assigned_students\":1}', '::1', '2026-05-24 17:47:00', NULL),
(259, 1, 'update', 'sections', 17, NULL, '{\"batch_removed_students\":[17],\"removed_count\":1}', '::1', '2026-05-24 17:47:05', NULL),
(260, 1, 'update', 'students', 17, '{\"personal_email\":\"columbina23.4@gmail.com\"}', '{\"personal_email\":\"columbina23.4@gmail.com\"}', '::1', '2026-05-24 17:47:38', NULL),
(261, 1, 'update', 'students', 17, '{\"personal_email\":\"columbina23.4@gmail.com\"}', '{\"personal_email\":\"columbina23.4@gmail.com\"}', '::1', '2026-05-24 17:47:42', NULL),
(262, 1, 'update', 'students', 17, '{\"personal_email\":\"columbina23.4@gmail.com\"}', '{\"personal_email\":\"columbina23.4@gmail.com\"}', '::1', '2026-05-24 17:47:46', NULL),
(263, 1, 'update', 'students', 17, '{\"personal_email\":\"columbina23.4@gmail.com\"}', '{\"personal_email\":\"columbina23.4@gmail.com\"}', '::1', '2026-05-24 17:48:05', NULL),
(264, 1, 'update', 'students', 17, '{\"personal_email\":\"columbina23.4@gmail.com\"}', '{\"personal_email\":\"columbina23.4@gmail.com\"}', '::1', '2026-05-24 17:48:08', NULL),
(265, 1, 'update', 'students', 17, '{\"personal_email\":\"columbina23.4@gmail.com\"}', '{\"personal_email\":\"columbina23.4@gmail.com\"}', '::1', '2026-05-24 17:48:12', NULL),
(266, 1, 'update', 'students', 17, '{\"personal_email\":\"columbina23.4@gmail.com\"}', '{\"personal_email\":\"columbina23.4@gmail.com\"}', '::1', '2026-05-24 17:48:16', NULL),
(267, 1, 'update', 'students', 17, '{\"personal_email\":\"columbina23.4@gmail.com\"}', '{\"personal_email\":\"columbina23.4@gmail.com\"}', '::1', '2026-05-24 17:48:19', NULL),
(268, 1, 'update', 'students', 17, '{\"personal_email\":\"columbina23.4@gmail.com\"}', '{\"personal_email\":\"columbina23.4@gmail.com\"}', '::1', '2026-05-24 17:48:24', NULL),
(269, 1, 'update', 'students', 17, '{\"lrn\":null}', '{\"lrn\":\"000000000800\"}', '::1', '2026-05-24 17:48:24', NULL),
(270, 1, 'update', 'sections', 17, NULL, '{\"assigned_students\":1}', '::1', '2026-05-24 17:49:29', NULL),
(271, 1, 'update', 'sections', 17, NULL, '{\"assigned_students\":19}', '::1', '2026-05-24 17:49:44', NULL),
(272, 1, 'update', 'sections', 16, NULL, '{\"assigned_students\":21}', '::1', '2026-05-24 17:49:53', NULL),
(273, 1, 'update', 'sections', 14, NULL, '{\"assigned_students\":20}', '::1', '2026-05-24 17:50:02', NULL),
(274, 1, 'update', 'sections', 15, NULL, '{\"assigned_students\":10}', '::1', '2026-05-24 17:50:15', NULL),
(275, 1, 'update', 'sections', 13, NULL, '{\"assigned_students\":25}', '::1', '2026-05-24 17:50:26', NULL),
(276, 1, 'update', 'sections', 11, NULL, '{\"assigned_students\":8}', '::1', '2026-05-24 17:50:36', NULL),
(277, 1, 'update', 'sections', 12, NULL, '{\"assigned_students\":14}', '::1', '2026-05-24 17:50:54', NULL),
(278, 1, 'update', 'sections', 10, NULL, '{\"assigned_students\":25}', '::1', '2026-05-24 17:50:58', NULL),
(279, 1, 'update', 'sections', 8, NULL, '{\"assigned_students\":9}', '::1', '2026-05-24 17:51:12', NULL),
(280, 1, 'update', 'sections', 9, NULL, '{\"assigned_students\":7}', '::1', '2026-05-24 17:51:21', NULL),
(281, 1, 'update', 'sections', 7, NULL, '{\"assigned_students\":2}', '::1', '2026-05-24 17:51:25', NULL),
(282, 1, 'update', 'sections', 6, NULL, '{\"assigned_students\":13}', '::1', '2026-05-24 17:51:41', NULL),
(283, 1, 'update', 'sections', 5, NULL, '{\"assigned_students\":25}', '::1', '2026-05-24 17:51:47', NULL),
(284, 1, 'update', 'sections', 3, NULL, '{\"assigned_students\":9}', '::1', '2026-05-24 17:52:06', NULL),
(285, 1, 'update', 'sections', 2, NULL, '{\"assigned_students\":5}', '::1', '2026-05-24 17:52:14', NULL),
(286, 1, 'update', 'sections', 5, '{\"id\":5,\"grade_level_id\":7,\"name\":\"CERTITUDE\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:24:17\",\"updated_at\":\"2026-05-22 18:03:46\",\"room\":\"100\"}', '{\"name\":\"CERTITUDE\",\"capacity\":25,\"adviser_id\":\"5\"}', '::1', '2026-05-25 08:47:06', NULL),
(287, 1, 'update', 'sections', 3, '{\"id\":3,\"grade_level_id\":7,\"name\":\"DIGNITY\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:24:03\",\"updated_at\":\"2026-05-22 18:03:52\",\"room\":\"102\"}', '{\"name\":\"DIGNITY\",\"capacity\":25,\"adviser_id\":\"4\"}', '::1', '2026-05-25 08:47:12', NULL),
(288, 1, 'update', 'teachers', 39, '{\"role\":\"teacher\",\"school_email\":\"alfonso.quizon@sjcteacher.edu.ph\",\"personal_email\":\"alfonso.quizon@gmail.com\"}', '{\"full_name\":\"Alfonso Quizon\",\"role\":\"teacher\",\"personal_email\":\"alfonso.quizon@gmail.com\"}', '::1', '2026-05-25 09:03:17', NULL),
(289, 1, 'update', 'teachers', 8, '{\"role\":\"teacher\",\"school_email\":\"ana.cruz@sjcteacher.edu.ph\",\"personal_email\":\"ana.cruz@gmail.com\"}', '{\"full_name\":\"Ana Cruz\",\"role\":\"teacher\",\"personal_email\":\"ana.cruz@gmail.com\"}', '::1', '2026-05-25 09:03:20', NULL),
(290, 1, 'update', 'teachers', 15, '{\"role\":\"teacher\",\"school_email\":\"antonio.garcia@sjcteacher.edu.ph\",\"personal_email\":\"antonio.garcia@gmail.com\"}', '{\"full_name\":\"Antonio Garcia\",\"role\":\"teacher\",\"personal_email\":\"antonio.garcia@gmail.com\"}', '::1', '2026-05-25 09:03:22', NULL),
(291, 1, 'update', 'teachers', 27, '{\"role\":\"teacher\",\"school_email\":\"arthur.salvador@sjcteacher.edu.ph\",\"personal_email\":\"arthur.salvador@gmail.com\"}', '{\"full_name\":\"Arthur Salvador\",\"role\":\"teacher\",\"personal_email\":\"arthur.salvador@gmail.com\"}', '::1', '2026-05-25 09:03:24', NULL),
(292, 1, 'update', 'teachers', 17, '{\"role\":\"teacher\",\"school_email\":\"bernardo.aquino@sjcteacher.edu.ph\",\"personal_email\":\"bernardo.aquino@gmail.com\"}', '{\"full_name\":\"Bernardo Aquino\",\"role\":\"teacher\",\"personal_email\":\"bernardo.aquino@gmail.com\"}', '::1', '2026-05-25 09:03:28', NULL),
(293, 1, 'update', 'teachers', 11, '{\"role\":\"teacher\",\"school_email\":\"carlos.torres@sjcteacher.edu.ph\",\"personal_email\":\"carlos.torres@gmail.com\"}', '{\"full_name\":\"Carlos Torres\",\"role\":\"teacher\",\"personal_email\":\"carlos.torres@gmail.com\"}', '::1', '2026-05-25 09:03:31', NULL);
INSERT INTO `audit_logs` (`id`, `admin_id`, `action`, `table_name`, `record_id`, `old_values`, `new_values`, `ip_address`, `created_at`, `user_agent`) VALUES
(294, 1, 'update', 'teachers', 16, '{\"role\":\"teacher\",\"school_email\":\"carmeni.dela-rosa@sjcteacher.edu.ph\",\"personal_email\":\"carmeni.delarosa@gmail.com\"}', '{\"full_name\":\"Carmeni Dela Rosa\",\"role\":\"teacher\",\"personal_email\":\"carmeni.delarosa@gmail.com\"}', '::1', '2026-05-25 09:03:34', NULL),
(295, 1, 'update', 'teachers', 32, '{\"role\":\"teacher\",\"school_email\":\"cecilia.aguilar@sjcteacher.edu.ph\",\"personal_email\":\"cecilia.aguilar@gmail.com\"}', '{\"full_name\":\"Cecilia Aguilar\",\"role\":\"teacher\",\"personal_email\":\"cecilia.aguilar@gmail.com\"}', '::1', '2026-05-25 09:03:37', NULL),
(296, 1, 'update', 'teachers', 20, '{\"role\":\"teacher\",\"school_email\":\"clarita.ocampo@sjcteacher.edu.ph\",\"personal_email\":\"clarita.ocampo@gmail.com\"}', '{\"full_name\":\"Clarita Ocampo\",\"role\":\"teacher\",\"personal_email\":\"clarita.ocampo@gmail.com\"}', '::1', '2026-05-25 09:04:54', NULL),
(297, 1, 'update', 'teachers', 40, '{\"role\":\"teacher\",\"school_email\":\"conchita.ureta@sjcteacher.edu.ph\",\"personal_email\":\"conchita.ureta@gmail.com\"}', '{\"full_name\":\"Conchita Ureta\",\"role\":\"teacher\",\"personal_email\":\"conchita.ureta@gmail.com\"}', '::1', '2026-05-25 09:04:57', NULL),
(298, 1, 'update', 'teachers', 29, '{\"role\":\"teacher\",\"school_email\":\"daniel.buenaventura@sjcteacher.edu.ph\",\"personal_email\":\"daniel.buenaventura@gmail.com\"}', '{\"full_name\":\"Daniel Buenaventura\",\"role\":\"teacher\",\"personal_email\":\"daniel.buenaventura@gmail.com\"}', '::1', '2026-05-25 09:05:01', NULL),
(299, 1, 'update', 'teachers', 23, '{\"role\":\"teacher\",\"school_email\":\"eduardo.ramos@sjcteacher.edu.ph\",\"personal_email\":\"eduardo.ramos@gmail.com\"}', '{\"full_name\":\"Eduardo Ramos\",\"role\":\"teacher\",\"personal_email\":\"eduardo.ramos@gmail.com\"}', '::1', '2026-05-25 09:05:09', NULL),
(300, 1, 'update', 'teachers', 18, '{\"role\":\"teacher\",\"school_email\":\"evelyn.pascual@sjcteacher.edu.ph\",\"personal_email\":\"evelyn.pascual@gmail.com\"}', '{\"full_name\":\"Evelyn Pascual\",\"role\":\"teacher\",\"personal_email\":\"evelyn.pascual@gmail.com\"}', '::1', '2026-05-25 09:21:17', NULL),
(301, 1, 'update', 'teachers', 21, '{\"role\":\"teacher\",\"school_email\":\"fernando.diaz@sjcteacher.edu.ph\",\"personal_email\":\"fernando.diaz@gmail.com\"}', '{\"full_name\":\"Fernando Diaz\",\"role\":\"teacher\",\"personal_email\":\"fernando.diaz@gmail.com\"}', '::1', '2026-05-25 09:21:20', NULL),
(302, 1, 'update', 'teachers', 26, '{\"role\":\"teacher\",\"school_email\":\"gloria.hernandez@sjcteacher.edu.ph\",\"personal_email\":\"gloria.hernandez@gmail.com\"}', '{\"full_name\":\"Gloria Hernandez\",\"role\":\"teacher\",\"personal_email\":\"gloria.hernandez@gmail.com\"}', '::1', '2026-05-25 09:21:25', NULL),
(303, 1, 'update', 'teachers', 37, '{\"role\":\"teacher\",\"school_email\":\"hector.soriano@sjcteacher.edu.ph\",\"personal_email\":\"hector.soriano@gmail.com\"}', '{\"full_name\":\"Hector Soriano\",\"role\":\"teacher\",\"personal_email\":\"hector.soriano@gmail.com\"}', '::1', '2026-05-25 09:22:27', NULL),
(304, 1, 'update', 'teachers', 34, '{\"role\":\"teacher\",\"school_email\":\"imelda.dela-cruz@sjcteacher.edu.ph\",\"personal_email\":\"imelda.delacruz@gmail.com\"}', '{\"full_name\":\"Imelda Dela Cruz\",\"role\":\"teacher\",\"personal_email\":\"imelda.delacruz@gmail.com\"}', '::1', '2026-05-25 09:22:29', NULL),
(305, 1, 'update', 'teachers', 7, '{\"role\":\"teacher\",\"school_email\":\"jose.reyes@sjcteacher.edu.ph\",\"personal_email\":\"jose.reyes@gmail.com\"}', '{\"full_name\":\"Jose Reyes\",\"role\":\"teacher\",\"personal_email\":\"jose.reyes@gmail.com\"}', '::1', '2026-05-25 09:22:32', NULL),
(306, 1, 'update', 'teachers', 10, '{\"role\":\"teacher\",\"school_email\":\"linda.flores@sjcteacher.edu.ph\",\"personal_email\":\"linda.flores@gmail.com\"}', '{\"full_name\":\"Linda Flores\",\"role\":\"teacher\",\"personal_email\":\"linda.flores@gmail.com\"}', '::1', '2026-05-25 09:22:35', NULL),
(307, 1, 'update', 'teachers', 22, '{\"role\":\"teacher\",\"school_email\":\"lourdes.castillo@sjcteacher.edu.ph\",\"personal_email\":\"lourdes.castillo@gmail.com\"}', '{\"full_name\":\"Lourdes Castillo\",\"role\":\"teacher\",\"personal_email\":\"lourdes.castillo@gmail.com\"}', '::1', '2026-05-25 09:22:40', NULL),
(308, 1, 'update', 'teachers', 33, '{\"role\":\"teacher\",\"school_email\":\"manuel.cabrera@sjcteacher.edu.ph\",\"personal_email\":\"manuel.cabrera@gmail.com\"}', '{\"full_name\":\"Manuel Cabrera\",\"role\":\"teacher\",\"personal_email\":\"manuel.cabrera@gmail.com\"}', '::1', '2026-05-25 09:22:42', NULL),
(309, 1, 'update', 'teachers', 6, '{\"role\":\"teacher\",\"school_email\":\"maria.santos@sjcteacher.edu.ph\",\"personal_email\":\"maria.santos@gmail.com\"}', '{\"full_name\":\"Maria Santos\",\"role\":\"teacher\",\"personal_email\":\"maria.santos@gmail.com\"}', '::1', '2026-05-25 09:22:46', NULL),
(310, 1, 'update', 'teachers', 24, '{\"role\":\"teacher\",\"school_email\":\"marisol.espinosa@sjcteacher.edu.ph\",\"personal_email\":\"marisol.espinosa@gmail.com\"}', '{\"full_name\":\"Marisol Espinosa\",\"role\":\"teacher\",\"personal_email\":\"marisol.espinosa@gmail.com\"}', '::1', '2026-05-25 09:22:49', NULL),
(311, 1, 'update', 'teachers', 38, '{\"role\":\"teacher\",\"school_email\":\"mercedes.tan@sjcteacher.edu.ph\",\"personal_email\":\"mercedes.tan@gmail.com\"}', '{\"full_name\":\"Mercedes Tan\",\"role\":\"teacher\",\"personal_email\":\"mercedes.tan@gmail.com\"}', '::1', '2026-05-25 09:22:51', NULL),
(312, 1, 'update', 'teachers', 13, '{\"role\":\"teacher\",\"school_email\":\"miguel.villanueva@sjcteacher.edu.ph\",\"personal_email\":\"miguel.villanueva@gmail.com\"}', '{\"full_name\":\"Miguel Villanueva\",\"role\":\"teacher\",\"personal_email\":\"miguel.villanueva@gmail.com\"}', '::1', '2026-05-25 09:22:54', NULL),
(313, 1, 'update', 'teachers', 28, '{\"role\":\"teacher\",\"school_email\":\"norma.velasquez@sjcteacher.edu.ph\",\"personal_email\":\"norma.velasquez@gmail.com\"}', '{\"full_name\":\"Norma Velasquez\",\"role\":\"teacher\",\"personal_email\":\"norma.velasquez@gmail.com\"}', '::1', '2026-05-25 09:22:57', NULL),
(314, 1, 'update', 'teachers', 36, '{\"role\":\"teacher\",\"school_email\":\"paulina.robles@sjcteacher.edu.ph\",\"personal_email\":\"paulina.robles@gmail.com\"}', '{\"full_name\":\"Paulina Robles\",\"role\":\"teacher\",\"personal_email\":\"paulina.robles@gmail.com\"}', '::1', '2026-05-25 09:23:00', NULL),
(315, 1, 'update', 'teachers', 19, '{\"role\":\"teacher\",\"school_email\":\"ramon.navarro@sjcteacher.edu.ph\",\"personal_email\":\"ramon.navarro@gmail.com\"}', '{\"full_name\":\"Ramon Navarro\",\"role\":\"teacher\",\"personal_email\":\"ramon.navarro@gmail.com\"}', '::1', '2026-05-25 09:23:02', NULL),
(316, 1, 'update', 'teachers', 31, '{\"role\":\"teacher\",\"school_email\":\"ricardo.perez@sjcteacher.edu.ph\",\"personal_email\":\"ricardo.perez@gmail.com\"}', '{\"full_name\":\"Ricardo Perez\",\"role\":\"teacher\",\"personal_email\":\"ricardo.perez@gmail.com\"}', '::1', '2026-05-25 09:23:07', NULL),
(317, 1, 'update', 'teachers', 9, '{\"role\":\"teacher\",\"school_email\":\"roberto.mendoza@sjcteacher.edu.ph\",\"personal_email\":\"roberto.mendoza@gmail.com\"}', '{\"full_name\":\"Roberto Mendoza\",\"role\":\"teacher\",\"personal_email\":\"roberto.mendoza@gmail.com\"}', '::1', '2026-05-25 09:23:09', NULL),
(318, 1, 'update', 'teachers', 25, '{\"role\":\"teacher\",\"school_email\":\"rodolfo.medina@sjcteacher.edu.ph\",\"personal_email\":\"rodolfo.medina@gmail.com\"}', '{\"full_name\":\"Rodolfo Medina\",\"role\":\"teacher\",\"personal_email\":\"rodolfo.medina@gmail.com\"}', '::1', '2026-05-25 09:23:12', NULL),
(319, 1, 'update', 'teachers', 12, '{\"role\":\"teacher\",\"school_email\":\"rosalie.bautista@sjcteacher.edu.ph\",\"personal_email\":\"rosalie.bautista@gmail.com\"}', '{\"full_name\":\"Rosalie Bautista\",\"role\":\"teacher\",\"personal_email\":\"rosalie.bautista@gmail.com\"}', '::1', '2026-05-25 09:23:14', NULL),
(320, 1, 'update', 'teachers', 30, '{\"role\":\"teacher\",\"school_email\":\"stella.miranda@sjcteacher.edu.ph\",\"personal_email\":\"stella.miranda@gmail.com\"}', '{\"full_name\":\"Stella Miranda\",\"role\":\"teacher\",\"personal_email\":\"stella.miranda@gmail.com\"}', '::1', '2026-05-25 09:23:16', NULL),
(321, 1, 'update', 'teachers', 14, '{\"role\":\"teacher\",\"school_email\":\"teresa.lim@sjcteacher.edu.ph\",\"personal_email\":\"teresa.lim@gmail.com\"}', '{\"full_name\":\"Teresa Lim\",\"role\":\"teacher\",\"personal_email\":\"teresa.lim@gmail.com\"}', '::1', '2026-05-25 09:23:18', NULL),
(322, 1, 'update', 'teachers', 35, '{\"role\":\"teacher\",\"school_email\":\"victor.enriquez@sjcteacher.edu.ph\",\"personal_email\":\"victor.enriquez@gmail.com\"}', '{\"full_name\":\"Victor Enriquez\",\"role\":\"teacher\",\"personal_email\":\"victor.enriquez@gmail.com\"}', '::1', '2026-05-25 09:23:21', NULL),
(323, 1, 'update', 'sections', 2, '{\"id\":2,\"grade_level_id\":7,\"name\":\"LOYALTY\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:23:56\",\"updated_at\":\"2026-05-22 22:37:30\",\"room\":\"103\"}', '{\"name\":\"LOYALTY\",\"capacity\":25,\"adviser_id\":\"39\"}', '::1', '2026-05-25 09:23:29', NULL),
(324, 1, 'update', 'sections', 1, '{\"id\":1,\"grade_level_id\":7,\"name\":\"OBEDIENCE\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:23:50\",\"updated_at\":\"2026-05-23 03:38:39\",\"room\":\"105\"}', '{\"name\":\"OBEDIENCE\",\"capacity\":25,\"adviser_id\":\"8\"}', '::1', '2026-05-25 09:23:34', NULL),
(325, 1, 'update', 'sections', 4, '{\"id\":4,\"grade_level_id\":7,\"name\":\"PEACE\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:24:09\",\"updated_at\":\"2026-05-25 01:14:01\",\"room\":\"106\"}', '{\"name\":\"PEACE\",\"capacity\":25,\"adviser_id\":\"15\"}', '::1', '2026-05-25 09:23:40', NULL),
(326, 1, 'update', 'sections', 8, '{\"id\":8,\"grade_level_id\":8,\"name\":\"COMPETENCE\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:25:38\",\"updated_at\":\"2026-05-22 22:41:10\",\"room\":\"104\"}', '{\"name\":\"COMPETENCE\",\"capacity\":25,\"adviser_id\":null}', '::1', '2026-05-25 09:23:44', NULL),
(327, 1, 'update', 'sections', 8, '{\"id\":8,\"grade_level_id\":8,\"name\":\"COMPETENCE\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:25:38\",\"updated_at\":\"2026-05-25 17:23:44\",\"room\":\"\"}', '{\"name\":\"COMPETENCE\",\"capacity\":25,\"adviser_id\":\"27\"}', '::1', '2026-05-25 09:23:47', NULL),
(328, 1, 'update', 'sections', 9, '{\"id\":9,\"grade_level_id\":8,\"name\":\"DISCERNMENT\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:25:52\",\"updated_at\":\"2026-05-25 01:14:05\",\"room\":\"107\"}', '{\"name\":\"DISCERNMENT\",\"capacity\":25,\"adviser_id\":\"17\"}', '::1', '2026-05-25 09:23:53', NULL),
(329, 1, 'update', 'sections', 7, '{\"id\":7,\"grade_level_id\":8,\"name\":\"PATIENCE\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:25:26\",\"updated_at\":\"2026-05-25 01:14:09\",\"room\":\"108\"}', '{\"name\":\"PATIENCE\",\"capacity\":25,\"adviser_id\":\"11\"}', '::1', '2026-05-25 09:23:59', NULL),
(330, 1, 'update', 'sections', 6, '{\"id\":6,\"grade_level_id\":8,\"name\":\"PRUDENCE\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:25:04\",\"updated_at\":\"2026-05-25 01:14:13\",\"room\":\"109\"}', '{\"name\":\"PRUDENCE\",\"capacity\":25,\"adviser_id\":\"32\"}', '::1', '2026-05-25 09:24:05', NULL),
(331, 1, 'update', 'sections', 13, '{\"id\":13,\"grade_level_id\":9,\"name\":\"COURAGE\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:26:41\",\"updated_at\":\"2026-05-25 01:14:17\",\"room\":\"110\"}', '{\"name\":\"COURAGE\",\"capacity\":25,\"adviser_id\":\"28\"}', '::1', '2026-05-25 09:24:11', NULL),
(332, 1, 'update', 'sections', 11, '{\"id\":11,\"grade_level_id\":9,\"name\":\"RIGHTEOUS\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:26:19\",\"updated_at\":\"2026-05-25 01:14:20\",\"room\":\"111\"}', '{\"name\":\"RIGHTEOUS\",\"capacity\":25,\"adviser_id\":\"16\"}', '::1', '2026-05-25 09:24:16', NULL),
(333, 1, 'update', 'sections', 12, '{\"id\":12,\"grade_level_id\":9,\"name\":\"TRANQUILITY\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:26:34\",\"updated_at\":\"2026-05-25 01:14:23\",\"room\":\"112\"}', '{\"name\":\"TRANQUILITY\",\"capacity\":25,\"adviser_id\":\"20\"}', '::1', '2026-05-25 09:24:26', NULL),
(334, 1, 'update', 'sections', 10, '{\"id\":10,\"grade_level_id\":9,\"name\":\"WISDOM\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:26:05\",\"updated_at\":\"2026-05-25 01:14:28\",\"room\":\"113\"}', '{\"name\":\"WISDOM\",\"capacity\":25,\"adviser_id\":\"40\"}', '::1', '2026-05-25 09:24:31', NULL),
(335, 1, 'update', 'sections', 15, '{\"id\":15,\"grade_level_id\":10,\"name\":\"HONESTY\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:27:05\",\"updated_at\":\"2026-05-25 01:14:31\",\"room\":\"114\"}', '{\"name\":\"HONESTY\",\"capacity\":25,\"adviser_id\":\"29\"}', '::1', '2026-05-25 09:24:37', NULL),
(336, 1, 'update', 'sections', 14, '{\"id\":14,\"grade_level_id\":10,\"name\":\"HUMILITY\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:26:52\",\"updated_at\":\"2026-05-25 01:14:34\",\"room\":\"115\"}', '{\"name\":\"HUMILITY\",\"capacity\":25,\"adviser_id\":\"23\"}', '::1', '2026-05-25 09:24:41', NULL),
(337, 1, 'update', 'sections', 16, '{\"id\":16,\"grade_level_id\":10,\"name\":\"INTEGRITY\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:27:30\",\"updated_at\":\"2026-05-25 01:14:37\",\"room\":\"116\"}', '{\"name\":\"INTEGRITY\",\"capacity\":25,\"adviser_id\":\"18\"}', '::1', '2026-05-25 09:24:45', NULL),
(338, 1, 'update', 'sections', 17, '{\"id\":17,\"grade_level_id\":10,\"name\":\"PERSEVERANCE\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:27:43\",\"updated_at\":\"2026-05-25 01:14:39\",\"room\":\"117\"}', '{\"name\":\"PERSEVERANCE\",\"capacity\":25,\"adviser_id\":\"37\"}', '::1', '2026-05-25 09:24:50', NULL),
(339, 1, 'update', 'sections', 3, '{\"id\":3,\"grade_level_id\":7,\"name\":\"DIGNITY\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:24:03\",\"updated_at\":\"2026-05-25 16:53:13\",\"room\":\"102\"}', '{\"name\":\"DIGNITY\",\"capacity\":25,\"adviser_id\":\"24\"}', '::1', '2026-05-25 09:31:23', NULL),
(340, 1, 'update', 'sections', 3, '{\"id\":3,\"grade_level_id\":7,\"name\":\"DIGNITY\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:24:03\",\"updated_at\":\"2026-05-25 16:53:13\",\"room\":\"102\"}', '{\"name\":\"DIGNITY\",\"capacity\":25,\"adviser_id\":\"4\"}', '::1', '2026-05-25 09:31:48', NULL),
(341, 1, '', 'sections', 5, '{\"room\":\"100\"}', '{\"room\":null}', '::1', '2026-05-25 09:31:53', NULL),
(342, 1, 'create', 'sections', 18, NULL, '{\"grade_level_id\":8,\"name\":\"Test\",\"capacity\":40,\"school_year_id\":1}', '::1', '2026-05-25 09:41:58', NULL),
(343, 1, 'create', 'rooms', 18, NULL, '{\"number\":\"118\",\"capacity\":0}', '::1', '2026-05-25 09:42:10', NULL),
(344, 1, 'archive', 'sections', 18, NULL, NULL, '::1', '2026-05-25 09:42:46', NULL),
(345, 1, 'activate', 'sections', 18, NULL, NULL, '::1', '2026-05-25 09:51:13', NULL),
(346, 1, 'archive', 'sections', 18, '{\"room\":\"118\"}', '{\"status\":\"archived\",\"room\":null}', '::1', '2026-05-25 09:51:19', NULL),
(347, 1, 'create', 'system_deadlines', 2, NULL, '{\"type\":\"grade_encoding_term1\",\"start\":\"2026-05-25 20:51:00\",\"end\":\"2026-07-25 20:51:00\"}', '::1', '2026-05-25 12:50:33', NULL),
(348, 1, 'update', 'system_deadlines', 2, '{\"id\":2,\"school_year_id\":1,\"type\":\"grade_encoding_term1\",\"start_date\":\"2026-05-25\",\"end_date\":\"2026-07-25\",\"start_datetime\":\"2026-05-25 20:51:00\",\"end_datetime\":\"2026-07-25 20:51:00\",\"notes\":\"\",\"created_by\":1,\"created_at\":\"2026-05-25 20:50:33\",\"updated_at\":\"2026-05-25 20:50:33\"}', '{\"type\":\"grade_encoding_term1\",\"start\":\"2026-05-26 20:51:00\",\"end\":\"2026-07-25 20:51:00\"}', '::1', '2026-05-25 13:54:26', NULL),
(349, 1, 'update', 'system_deadlines', 2, '{\"id\":2,\"school_year_id\":1,\"type\":\"grade_encoding_term1\",\"start_date\":\"2026-05-26\",\"end_date\":\"2026-07-25\",\"start_datetime\":\"2026-05-26 20:51:00\",\"end_datetime\":\"2026-07-25 20:51:00\",\"notes\":\"\",\"created_by\":1,\"created_at\":\"2026-05-25 20:50:33\",\"updated_at\":\"2026-05-25 21:54:26\"}', '{\"type\":\"grade_encoding_term1\",\"start\":\"2026-05-25 20:51:00\",\"end\":\"2026-07-25 20:51:00\"}', '::1', '2026-05-25 13:54:34', NULL),
(350, 1, 'update', 'students', 418, '{\"personal_email\":\"columbin.a234@gmail.com\"}', '{\"personal_email\":\"columbin.a234@gmail.com\"}', '::1', '2026-05-25 17:22:06', NULL),
(351, 1, 'update', 'students', 418, '{\"lrn\":null}', '{\"lrn\":\"000000008124\"}', '::1', '2026-05-25 17:22:06', NULL),
(352, 1, 'update', 'sections', 1, NULL, '{\"assigned_students\":1}', '::1', '2026-05-25 17:22:24', NULL),
(353, 1, 'update', 'sections', 5, NULL, '{\"batch_removed_students\":[45,87,73,47,36,105,71,21,80,95,96,99,53,52,23,61,27,101,46,112,32,79,24,20,59],\"removed_count\":25}', '::1', '2026-05-25 18:17:08', NULL),
(354, 1, 'update', 'sections', 3, NULL, '{\"batch_removed_students\":[111,31,68,69,33,90,66,55,44],\"removed_count\":9}', '::1', '2026-05-25 18:17:13', NULL),
(355, 1, 'update', 'sections', 2, NULL, '{\"batch_removed_students\":[35,39,92,67,78],\"removed_count\":5}', '::1', '2026-05-25 18:17:17', NULL),
(356, 1, 'update', 'sections', 1, NULL, '{\"batch_removed_students\":[418],\"removed_count\":1}', '::1', '2026-05-25 18:17:21', NULL),
(357, 1, 'update', 'sections', 8, NULL, '{\"batch_removed_students\":[207,130,152,138,203,178,187,120,171],\"removed_count\":9}', '::1', '2026-05-25 18:17:28', NULL),
(358, 1, 'update', 'sections', 9, NULL, '{\"batch_removed_students\":[146,186,176,153,174,181,159],\"removed_count\":7}', '::1', '2026-05-25 18:17:31', NULL),
(359, 1, 'update', 'sections', 7, NULL, '{\"batch_removed_students\":[179,169],\"removed_count\":2}', '::1', '2026-05-25 18:17:35', NULL),
(360, 1, 'update', 'sections', 6, NULL, '{\"batch_removed_students\":[156,197,212,199,206,148,142,122,131,190,118,134,173],\"removed_count\":13}', '::1', '2026-05-25 18:17:42', NULL),
(361, 1, 'update', 'sections', 10, NULL, '{\"batch_removed_students\":[289,236,259,222,288,232,292,264,248,279,260,309,219,283,306,317,241,273,277,303,258,220,261,257,304],\"removed_count\":25}', '::1', '2026-05-25 18:17:46', NULL),
(362, 1, 'update', 'sections', 12, NULL, '{\"batch_removed_students\":[250,233,287,234,238,229,267,284,223,295,313,297,302,307],\"removed_count\":14}', '::1', '2026-05-25 18:17:50', NULL),
(363, 1, 'update', 'sections', 11, NULL, '{\"batch_removed_students\":[308,227,294,228,253,270,301,314],\"removed_count\":8}', '::1', '2026-05-25 18:17:54', NULL),
(364, 1, 'update', 'sections', 13, NULL, '{\"batch_removed_students\":[224,262,274,300,312,237,231,282,285,280,268,269,255,247,271,245,272,290,315,230,281,244,276,243,218],\"removed_count\":25}', '::1', '2026-05-25 18:17:58', NULL),
(365, 1, 'update', 'sections', 15, NULL, '{\"batch_removed_students\":[318,330,414,343,350,322,381,349,412,361],\"removed_count\":10}', '::1', '2026-05-25 18:18:02', NULL),
(366, 1, 'update', 'sections', 14, NULL, '{\"batch_removed_students\":[335,401,391,368,319,365,345,382,373,334,338,374,405,396,398,329,387,367,328,347],\"removed_count\":20}', '::1', '2026-05-25 18:18:05', NULL),
(367, 1, 'update', 'sections', 16, NULL, '{\"batch_removed_students\":[370,400,366,346,358,332,360,410,380,393,351,376,394,339,354,359,356,355,353,337,408],\"removed_count\":21}', '::1', '2026-05-25 18:18:12', NULL),
(368, 1, 'update', 'sections', 17, NULL, '{\"batch_removed_students\":[397,390,344,333,383,416,388,363,407,325,336,348,372,323,369,413,371,364,404,17],\"removed_count\":20}', '::1', '2026-05-25 18:18:16', NULL),
(369, 1, 'archive', 'sections', 17, '{\"room\":\"117\"}', '{\"status\":\"archived\",\"room\":null}', '::1', '2026-05-25 18:18:41', NULL),
(370, 1, 'activate', 'sections', 17, NULL, NULL, '::1', '2026-05-25 18:18:58', NULL),
(371, 1, 'update', 'sections', 5, NULL, '{\"assigned_students\":25}', '::1', '2026-05-25 18:28:59', NULL),
(372, 1, 'update', 'sections', 5, NULL, '{\"batch_removed_students\":[45,87,73,47,36,105,71,21,80,95,96,99,53,52,23,61,27,101,46,112,32,79,24,20,59],\"removed_count\":25}', '::1', '2026-05-25 18:30:59', NULL),
(373, 1, 'update', 'sections', 2, NULL, '{\"assigned_students\":1}', '::1', '2026-05-25 18:31:14', NULL),
(374, 1, 'update', 'sections', 2, NULL, '{\"batch_removed_students\":[87],\"removed_count\":1}', '::1', '2026-05-25 18:31:27', NULL),
(375, 1, 'update', 'sections', 1, NULL, '{\"assigned_students\":3}', '::1', '2026-05-25 18:32:29', NULL),
(376, 1, 'archive', 'students', 1, NULL, NULL, '::1', '2026-05-29 12:07:53', NULL),
(377, 1, 'archive', 'students', 7, NULL, NULL, '::1', '2026-05-29 12:07:55', NULL),
(378, 1, 'restore', 'students', 1, NULL, NULL, '::1', '2026-05-29 12:07:58', NULL),
(379, 1, 'archive', 'students', 1, NULL, NULL, '::1', '2026-05-29 12:08:02', NULL),
(380, 1, 'update', 'students', 419, '{\"personal_email\":\"phillippe.joshua27.9@gmail.com\"}', '{\"personal_email\":\"phillippe.joshua27.9@gmail.com\"}', '::1', '2026-05-29 12:08:13', NULL),
(381, 1, 'update', 'students', 419, '{\"lrn\":null}', '{\"lrn\":\"000000000435\"}', '::1', '2026-05-29 12:08:13', NULL),
(382, 1, 'deactivate', 'subjects', 6, NULL, NULL, '::1', '2026-05-29 12:14:39', NULL),
(383, 1, 'activate', 'subjects', 6, NULL, NULL, '::1', '2026-05-29 12:14:40', NULL),
(384, 1, 'archive', 'curriculum', 1, NULL, NULL, '::1', '2026-05-29 12:14:48', NULL),
(385, 1, 'create', 'curriculum', 37, NULL, '{\"school_year_id\":1,\"grade_level_id\":7,\"subject_id\":6}', '::1', '2026-05-29 12:14:54', NULL),
(386, 1, 'create', 'rooms', 19, NULL, '{\"number\":\"119\",\"capacity\":0}', '::1', '2026-05-29 12:19:23', NULL),
(387, 1, 'create', 'rooms', 20, NULL, '{\"number\":\"120\",\"capacity\":0}', '::1', '2026-05-29 12:19:33', NULL),
(388, 1, 'update', 'sections', 8, NULL, '{\"assigned_students\":1}', '::1', '2026-05-29 12:25:42', NULL),
(389, 1, 'archive', 'rooms', 20, '{\"id\":20,\"number\":\"120\",\"capacity\":0,\"status\":\"active\",\"created_by\":1,\"created_at\":\"2026-05-29 20:19:33\",\"updated_at\":\"2026-05-29 20:19:33\"}', '{\"status\":\"archived\"}', '::1', '2026-05-30 04:14:22', NULL),
(390, 1, 'restore', 'rooms', 20, '{\"id\":20,\"number\":\"120\",\"capacity\":0,\"status\":\"archived\",\"created_by\":1,\"created_at\":\"2026-05-29 20:19:33\",\"updated_at\":\"2026-05-30 12:14:22\"}', '{\"status\":\"active\"}', '::1', '2026-05-30 04:14:26', NULL),
(391, 1, 'create', 'sections', 19, NULL, '{\"grade_level_id\":8,\"name\":\"Nyapollo\",\"capacity\":40,\"school_year_id\":1}', '::1', '2026-05-30 04:20:16', NULL),
(392, 1, 'archive', 'sections', 19, '{\"room\":null}', '{\"status\":\"archived\",\"room\":null}', '::1', '2026-05-30 04:20:25', NULL),
(393, 1, 'activate', 'sections', 19, NULL, NULL, '::1', '2026-05-30 04:20:30', NULL),
(394, 1, 'archive', 'sections', 19, '{\"room\":null}', '{\"status\":\"archived\",\"room\":null}', '::1', '2026-05-30 04:20:38', NULL),
(395, 1, 'update', 'sections', 12, '{\"id\":12,\"grade_level_id\":9,\"name\":\"TRANQUILITY\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:26:34\",\"updated_at\":\"2026-05-25 17:26:58\",\"room\":\"112\"}', '{\"name\":\"TRANQUILITY\",\"capacity\":40,\"adviser_id\":\"20\"}', '::1', '2026-05-30 04:24:01', NULL),
(396, 1, 'update', 'sections', 12, '{\"id\":12,\"grade_level_id\":9,\"name\":\"TRANQUILITY\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:26:34\",\"updated_at\":\"2026-05-25 17:26:58\",\"room\":\"112\"}', '{\"name\":\"TRANQUILITY\",\"capacity\":25,\"adviser_id\":\"20\"}', '::1', '2026-05-30 04:24:12', NULL),
(397, 1, '', 'sections', 19, '{\"id\":19,\"name\":\"Nyapollo\",\"grade_level_id\":8}', NULL, '::1', '2026-05-30 04:28:18', NULL),
(398, 1, '', 'sections', 18, '{\"id\":18,\"name\":\"Test\",\"grade_level_id\":8}', NULL, '::1', '2026-05-30 04:28:22', NULL),
(399, 1, 'create', 'sections', 20, NULL, '{\"grade_level_id\":8,\"name\":\"Nyapollo\",\"capacity\":25,\"school_year_id\":1}', '::1', '2026-05-30 04:28:32', NULL),
(400, 1, 'archive', 'sections', 20, '{\"room\":null}', '{\"status\":\"archived\",\"room\":null}', '::1', '2026-05-30 04:28:36', NULL),
(401, 1, '', 'sections', 20, '{\"id\":20,\"name\":\"Nyapollo\",\"grade_level_id\":8}', NULL, '::1', '2026-05-30 04:28:42', NULL),
(402, 1, 'create', 'rooms', 21, NULL, '{\"number\":\"121\",\"capacity\":0}', '::1', '2026-05-30 04:29:52', NULL),
(403, 1, 'archive', 'rooms', 21, '{\"id\":21,\"number\":\"121\",\"capacity\":0,\"status\":\"active\",\"created_by\":1,\"created_at\":\"2026-05-30 12:29:52\",\"updated_at\":\"2026-05-30 12:29:52\"}', '{\"status\":\"archived\"}', '::1', '2026-05-30 04:29:56', NULL),
(404, 1, 'update', 'sections', 5, NULL, '{\"assigned_students\":10}', '::1', '2026-05-30 04:34:27', NULL),
(405, 1, 'create', 'sections', 21, NULL, '{\"grade_level_id\":8,\"name\":\"Test\",\"capacity\":25,\"school_year_id\":1}', '::1', '2026-05-30 04:34:54', NULL),
(406, 1, 'archive', 'sections', 21, '{\"room\":null}', '{\"status\":\"archived\",\"room\":null}', '::1', '2026-05-30 04:34:57', NULL),
(407, 1, 'restore', 'rooms', 21, '{\"id\":21,\"number\":\"121\",\"capacity\":0,\"status\":\"archived\",\"created_by\":1,\"created_at\":\"2026-05-30 12:29:52\",\"updated_at\":\"2026-05-30 12:29:56\"}', '{\"status\":\"active\"}', '::1', '2026-05-30 04:36:16', NULL),
(408, 1, 'archive', 'rooms', 21, '{\"id\":21,\"number\":\"121\",\"capacity\":0,\"status\":\"active\",\"created_by\":1,\"created_at\":\"2026-05-30 12:29:52\",\"updated_at\":\"2026-05-30 12:36:16\"}', '{\"status\":\"archived\"}', '::1', '2026-05-30 04:36:20', NULL),
(409, 1, '', 'rooms', 21, '{\"id\":21,\"number\":\"121\",\"capacity\":0,\"status\":\"archived\",\"created_by\":1,\"created_at\":\"2026-05-30 12:29:52\",\"updated_at\":\"2026-05-30 12:36:20\"}', NULL, '::1', '2026-05-30 04:36:26', NULL),
(410, 1, 'create', 'rooms', 22, NULL, '{\"number\":\"121\",\"capacity\":0}', '::1', '2026-05-30 04:42:03', NULL),
(411, 1, 'archive', 'rooms', 22, '{\"id\":22,\"number\":\"121\",\"capacity\":0,\"status\":\"active\",\"created_by\":1,\"created_at\":\"2026-05-30 12:42:03\",\"updated_at\":\"2026-05-30 12:42:03\"}', '{\"status\":\"archived\"}', '::1', '2026-05-30 04:42:06', NULL),
(412, 1, '', 'rooms', 22, '{\"id\":22,\"number\":\"121\",\"capacity\":0,\"status\":\"archived\",\"created_by\":1,\"created_at\":\"2026-05-30 12:42:03\",\"updated_at\":\"2026-05-30 12:42:06\"}', NULL, '::1', '2026-05-30 04:42:14', NULL),
(413, 1, '', 'sections', 21, '{\"id\":21,\"name\":\"Test\",\"grade_level_id\":8}', NULL, '::1', '2026-05-30 04:42:41', NULL),
(414, 1, 'create', 'rooms', 23, NULL, '{\"number\":\"121\",\"capacity\":0}', '::1', '2026-05-30 04:46:59', NULL),
(415, 1, 'create', 'sections', 22, NULL, '{\"grade_level_id\":10,\"name\":\"test\",\"capacity\":25,\"school_year_id\":1}', '::1', '2026-05-30 04:47:03', NULL),
(416, 1, 'archive', 'sections', 22, '{\"room\":null}', '{\"status\":\"archived\",\"room\":null}', '::1', '2026-05-30 04:47:07', NULL),
(417, 1, 'archive', 'rooms', 23, '{\"id\":23,\"number\":\"121\",\"capacity\":0,\"status\":\"active\",\"created_by\":1,\"created_at\":\"2026-05-30 12:46:59\",\"updated_at\":\"2026-05-30 12:46:59\"}', '{\"status\":\"archived\"}', '::1', '2026-05-30 04:47:12', NULL),
(418, 1, '', 'rooms', 23, '{\"id\":23,\"number\":\"121\",\"capacity\":0,\"status\":\"archived\",\"created_by\":1,\"created_at\":\"2026-05-30 12:46:59\",\"updated_at\":\"2026-05-30 12:47:12\"}', NULL, '::1', '2026-05-30 04:47:18', NULL),
(419, 1, '', 'sections', 22, '{\"id\":22,\"name\":\"test\",\"grade_level_id\":10}', NULL, '::1', '2026-05-30 04:47:27', NULL),
(420, 1, 'create', 'sections', 23, NULL, '{\"grade_level_id\":10,\"name\":\"test\",\"capacity\":25,\"school_year_id\":1}', '::1', '2026-05-30 04:49:54', NULL),
(421, 1, 'archive', 'sections', 23, '{\"room\":null}', '{\"status\":\"archived\",\"room\":null}', '::1', '2026-05-30 04:49:57', NULL),
(422, 1, 'create', 'rooms', 24, NULL, '{\"number\":\"121\",\"capacity\":0}', '::1', '2026-05-30 04:50:02', NULL),
(423, 1, 'archive', 'rooms', 24, '{\"id\":24,\"number\":\"121\",\"capacity\":0,\"status\":\"active\",\"created_by\":1,\"created_at\":\"2026-05-30 12:50:02\",\"updated_at\":\"2026-05-30 12:50:02\"}', '{\"status\":\"archived\"}', '::1', '2026-05-30 04:50:04', NULL),
(424, 1, 'delete', 'sections', 23, '{\"id\":23,\"name\":\"test\",\"grade_level_id\":10}', NULL, '::1', '2026-05-30 04:50:09', NULL),
(425, 1, 'delete', 'rooms', 24, '{\"id\":24,\"number\":\"121\",\"capacity\":0,\"status\":\"archived\",\"created_by\":1,\"created_at\":\"2026-05-30 12:50:02\",\"updated_at\":\"2026-05-30 12:50:04\"}', NULL, '::1', '2026-05-30 04:50:13', NULL),
(426, 1, 'update', 'students', 418, '{\"lrn\":\"000000008124\"}', '{\"lrn\":\"000000008125\"}', '::1', '2026-05-30 05:16:24', NULL),
(427, 1, 'update', 'students', 418, '{\"personal_email\":\"columbin.a234@gmail.com\"}', '{\"personal_email\":\"c.olumbin.a234@gmail.com\"}', '::1', '2026-05-30 05:17:27', NULL),
(428, 1, 'update', 'students', 45, '{\"personal_email\":\"julian.alcantara@gmail.com\",\"_student_name\":\"Julian Alcantara\",\"_student_lrn\":\"000000000038\"}', '{\"personal_email\":\"julianalcantara@gmail.com\"}', '::1', '2026-05-30 20:48:44', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(429, 1, 'deactivate', 'subjects', 6, NULL, NULL, '::1', '2026-05-30 20:59:58', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(430, 1, 'activate', 'subjects', 6, NULL, NULL, '::1', '2026-05-30 20:59:59', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(431, 1, 'archive', 'curriculum', 37, NULL, NULL, '::1', '2026-05-30 21:08:49', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(432, 1, 'create', 'curriculum', 38, NULL, '{\"school_year_id\":1,\"grade_level_id\":7,\"subject_id\":6}', '::1', '2026-05-30 21:08:51', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(433, 1, 'archive', 'curriculum', 38, NULL, NULL, '::1', '2026-05-31 06:02:34', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(434, 1, 'create', 'curriculum', 39, NULL, '{\"school_year_id\":1,\"grade_level_id\":7,\"subject_id\":6}', '::1', '2026-05-31 06:02:36', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(435, 1, 'create', 'curriculum', 40, NULL, '{\"school_year_id\":1,\"grade_level_id\":8,\"subject_id\":6}', '::1', '2026-05-31 06:07:25', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(436, 1, 'archive', 'curriculum', 40, NULL, NULL, '::1', '2026-05-31 06:07:26', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(437, 1, 'create', 'system_deadlines', 3, NULL, '{\"type\":\"payments\",\"start\":\"2026-05-31 14:50:00\",\"end\":\"2026-06-10 15:00:00\"}', '::1', '2026-05-31 06:49:23', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(438, 1, 'update', 'system_deadlines', 1, '{\"id\":1,\"school_year_id\":1,\"type\":\"enrollment\",\"start_date\":\"2026-05-19\",\"end_date\":\"2026-05-30\",\"start_datetime\":\"2026-05-19 03:29:00\",\"end_datetime\":\"2026-05-30 03:29:00\",\"notes\":\"\",\"created_by\":1,\"created_at\":\"2026-05-19 03:30:13\",\"updated_at\":\"2026-05-19 03:53:38\"}', '{\"type\":\"enrollment\",\"start\":\"2026-05-19 03:29:00\",\"end\":\"2026-07-30 03:29:00\"}', '::1', '2026-05-31 06:49:35', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(439, 1, 'update', 'sections', 8, NULL, '{\"assigned_students\":18}', '::1', '2026-05-31 08:49:53', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36 Edg/148.0.0.0'),
(440, 1, 'update', 'sections', 8, '{\"id\":8,\"grade_level_id\":8,\"name\":\"COMPETENCE\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:25:38\",\"updated_at\":\"2026-05-25 17:26:41\",\"room\":\"106\"}', '{\"name\":\"COMPETENCE\",\"capacity\":25,\"adviser_id\":\"27\"}', '::1', '2026-05-31 08:49:56', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36 Edg/148.0.0.0'),
(441, 1, 'update', 'sections', 9, NULL, '{\"assigned_students\":1}', '::1', '2026-05-31 10:25:03', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(442, 1, 'update', 'students', 421, '{\"lrn\":\"\",\"_student_name\":\"Keith Canilang\",\"_student_lrn\":null}', '{\"lrn\":\"000000002348\"}', '::1', '2026-05-31 10:25:26', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(443, 1, 'update', 'coordinators', 8, '{\"role\":\"coordinator\",\"school_email\":\"benedict.ong@sjccoordinator.edu.ph\",\"personal_email\":\"benedict.ong@gmail.com\"}', '{\"full_name\":\"Benedict Ong\",\"role\":\"coordinator\",\"personal_email\":\"columbi.na23.4@gmail.com\"}', '::1', '2026-05-31 15:09:31', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(444, 1, 'update', 'coordinators', 5, '{\"role\":\"coordinator\",\"school_email\":\"elena.zabala@sjccoordinator.edu.ph\",\"personal_email\":\"elena.zabala@gmail.com\"}', '{\"full_name\":\"Elena Zabala\",\"role\":\"coordinator\",\"personal_email\":\"co.lumbina234@gmail.com\"}', '::1', '2026-05-31 15:09:45', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(445, 1, 'update', 'coordinators', 9, '{\"role\":\"coordinator\",\"school_email\":\"jessica.bulan@sjccoordinator.edu.ph\",\"personal_email\":\"jessica.bulan@gmail.com\"}', '{\"full_name\":\"Jessica Bulan\",\"role\":\"coordinator\",\"personal_email\":\"c.olumbina23.4@gmail.com\"}', '::1', '2026-05-31 15:09:58', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(446, 1, 'update', 'coordinators', 11, '{\"role\":\"coordinator\",\"school_email\":\"lorena.yap@sjccoordinator.edu.ph\",\"personal_email\":\"lorena.yap@gmail.com\"}', '{\"full_name\":\"Lorena Yap\",\"role\":\"coordinator\",\"personal_email\":\"c.olum.bin.a234@gmail.com\"}', '::1', '2026-05-31 15:10:12', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(447, 1, 'update', 'coordinators', 7, '{\"role\":\"coordinator\",\"school_email\":\"maricel.jimenez@sjccoordinator.edu.ph\",\"personal_email\":\"maricel.jimenez@gmail.com\"}', '{\"full_name\":\"Maricel Jimenez\",\"role\":\"coordinator\",\"personal_email\":\"colu.m.bina23.4@gmail.com\"}', '::1', '2026-05-31 15:10:32', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(448, 1, 'update', 'coordinators', 10, '{\"role\":\"coordinator\",\"school_email\":\"renato.segovia@sjccoordinator.edu.ph\",\"personal_email\":\"renato.segovia@gmail.com\"}', '{\"full_name\":\"Renato Segovia\",\"role\":\"coordinator\",\"personal_email\":\"c.olum.bin.a23.4@gmail.com\"}', '::1', '2026-05-31 15:10:43', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(449, 1, 'update', 'coordinators', 6, '{\"role\":\"coordinator\",\"school_email\":\"ronaldo.ilagan@sjccoordinator.edu.ph\",\"personal_email\":\"ronaldo.ilagan@gmail.com\"}', '{\"full_name\":\"Ronaldo Ilagan\",\"role\":\"coordinator\",\"personal_email\":\"columbin.a23.4@gmail.com\"}', '::1', '2026-05-31 15:13:31', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(450, 1, 'update', 'sections', 3, NULL, '{\"assigned_students\":21}', '::1', '2026-05-31 15:15:57', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(451, 1, 'update', 'sections', 2, NULL, '{\"assigned_students\":20}', '::1', '2026-05-31 15:16:06', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(452, 1, 'update', 'sections', 2, '{\"id\":2,\"grade_level_id\":7,\"name\":\"LOYALTY\",\"status\":\"active\",\"created_at\":\"2026-05-17 03:23:56\",\"updated_at\":\"2026-05-25 17:26:30\",\"room\":\"103\"}', '{\"name\":\"LOYALTY\",\"capacity\":25,\"adviser_id\":\"39\"}', '::1', '2026-05-31 15:16:07', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(453, 1, 'update', 'sections', 1, NULL, '{\"assigned_students\":19}', '::1', '2026-05-31 15:16:22', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(454, 1, 'update', 'sections', 4, NULL, '{\"assigned_students\":14}', '::1', '2026-05-31 15:16:33', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(455, 1, 'update', 'sections', 9, NULL, '{\"assigned_students\":19}', '::1', '2026-05-31 15:16:45', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(456, 1, 'update', 'sections', 7, NULL, '{\"assigned_students\":20}', '::1', '2026-05-31 15:16:53', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(457, 1, 'update', 'sections', 6, NULL, '{\"assigned_students\":20}', '::1', '2026-05-31 15:17:01', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(458, 1, 'update', 'sections', 13, NULL, '{\"assigned_students\":22}', '::1', '2026-05-31 15:17:08', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(459, 1, 'update', 'sections', 11, NULL, '{\"assigned_students\":25}', '::1', '2026-05-31 15:17:22', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(460, 1, 'update', 'sections', 12, NULL, '{\"assigned_students\":9}', '::1', '2026-05-31 15:17:32', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(461, 1, 'update', 'sections', 10, NULL, '{\"assigned_students\":9}', '::1', '2026-05-31 15:17:45', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(462, 1, 'update', 'sections', 15, NULL, '{\"assigned_students\":20}', '::1', '2026-05-31 15:17:53', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(463, 1, 'update', 'sections', 14, NULL, '{\"assigned_students\":16}', '::1', '2026-05-31 15:18:04', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(464, 1, 'update', 'sections', 16, NULL, '{\"assigned_students\":15}', '::1', '2026-05-31 15:18:14', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(465, 1, 'update', 'sections', 17, NULL, '{\"assigned_students\":20}', '::1', '2026-05-31 15:18:20', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(466, 1, 'update', 'teachers', 39, '{\"role\":\"teacher\",\"school_email\":\"alfonsoquizon@sjcteacher.edu.ph\",\"personal_email\":\"alfonso.quizon@gmail.com\"}', '{\"full_name\":\"Alfonso Quizon\",\"role\":\"teacher\",\"personal_email\":\"alfonso.quizon@gmail.com\"}', '::1', '2026-05-31 19:26:54', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(467, 1, 'update', 'teachers', 22, '{\"role\":\"teacher\",\"school_email\":\"lourdescastillo@sjcteacher.edu.ph\",\"personal_email\":\"lourdes.castillo@gmail.com\"}', '{\"full_name\":\"Lourdes Castillo\",\"role\":\"teacher\",\"personal_email\":\"lourdes.castillo@gmail.com\"}', '::1', '2026-05-31 19:26:57', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(468, 1, 'update', 'teachers', 19, '{\"role\":\"teacher\",\"school_email\":\"ramonnavarro@sjcteacher.edu.ph\",\"personal_email\":\"ramon.navarro@gmail.com\"}', '{\"full_name\":\"Ramon Navarro\",\"role\":\"teacher\",\"personal_email\":\"ramon.navarro@gmail.com\"}', '::1', '2026-05-31 19:27:05', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(469, 1, 'update', 'teachers', 19, '{\"role\":\"teacher\",\"school_email\":\"ramonnavarro@sjcteacher.edu.ph\",\"personal_email\":\"ramon.navarro@gmail.com\"}', '{\"full_name\":\"Ramon Navarro\",\"role\":\"teacher\",\"personal_email\":\"ramon.navarro@gmail.com\"}', '::1', '2026-05-31 19:27:11', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(470, 1, 'update', 'teachers', 14, '{\"role\":\"teacher\",\"school_email\":\"teresalim@sjcteacher.edu.ph\",\"personal_email\":\"teresa.lim@gmail.com\"}', '{\"full_name\":\"Teresa Lim\",\"role\":\"teacher\",\"personal_email\":\"teresa.lim@gmail.com\"}', '::1', '2026-05-31 19:27:16', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(471, 1, 'update', 'teachers', 27, '{\"role\":\"teacher\",\"school_email\":\"arthursalvador@sjcteacher.edu.ph\",\"personal_email\":\"arthur.salvador@gmail.com\"}', '{\"full_name\":\"Arthur Salvador\",\"role\":\"teacher\",\"personal_email\":\"arthur.salvador@gmail.com\"}', '::1', '2026-05-31 19:27:22', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(472, 1, 'update', 'teachers', 31, '{\"role\":\"teacher\",\"school_email\":\"ricardoperez@sjcteacher.edu.ph\",\"personal_email\":\"ricardo.perez@gmail.com\"}', '{\"full_name\":\"Ricardo Perez\",\"role\":\"teacher\",\"personal_email\":\"ricardo.perez@gmail.com\"}', '::1', '2026-05-31 19:27:25', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(473, 1, 'update', 'teachers', 12, '{\"role\":\"teacher\",\"school_email\":\"rosaliebautista@sjcteacher.edu.ph\",\"personal_email\":\"rosalie.bautista@gmail.com\"}', '{\"full_name\":\"Rosalie Bautista\",\"role\":\"teacher\",\"personal_email\":\"rosalie.bautista@gmail.com\"}', '::1', '2026-05-31 19:27:27', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(474, 1, 'update', 'teachers', 15, '{\"role\":\"teacher\",\"school_email\":\"antoniogarcia@sjcteacher.edu.ph\",\"personal_email\":\"antonio.garcia@gmail.com\"}', '{\"full_name\":\"Antonio Garcia\",\"role\":\"teacher\",\"personal_email\":\"antonio.garcia@gmail.com\"}', '::1', '2026-05-31 19:27:31', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(475, 1, 'update', 'teachers', 23, '{\"role\":\"teacher\",\"school_email\":\"eduardoramos@sjcteacher.edu.ph\",\"personal_email\":\"eduardo.ramos@gmail.com\"}', '{\"full_name\":\"Eduardo Ramos\",\"role\":\"teacher\",\"personal_email\":\"eduardo.ramos@gmail.com\"}', '::1', '2026-05-31 19:27:34', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(476, 1, 'update', 'teachers', 21, '{\"role\":\"teacher\",\"school_email\":\"fernandodiaz@sjcteacher.edu.ph\",\"personal_email\":\"fernando.diaz@gmail.com\"}', '{\"full_name\":\"Fernando Diaz\",\"role\":\"teacher\",\"personal_email\":\"fernando.diaz@gmail.com\"}', '::1', '2026-05-31 19:27:36', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(477, 1, 'update', 'teachers', 21, '{\"role\":\"teacher\",\"school_email\":\"fernandodiaz@sjcteacher.edu.ph\",\"personal_email\":\"fernando.diaz@gmail.com\"}', '{\"full_name\":\"Fernando Diaz\",\"role\":\"teacher\",\"personal_email\":\"fernando.diaz@gmail.com\"}', '::1', '2026-05-31 19:27:40', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(478, 1, 'update', 'teachers', 34, '{\"role\":\"teacher\",\"school_email\":\"imeldadelacruz@sjcteacher.edu.ph\",\"personal_email\":\"imelda.delacruz@gmail.com\"}', '{\"full_name\":\"Imelda Dela Cruz\",\"role\":\"teacher\",\"personal_email\":\"imelda.delacruz@gmail.com\"}', '::1', '2026-05-31 19:27:43', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(479, 1, 'update', 'teachers', 13, '{\"role\":\"teacher\",\"school_email\":\"miguelvillanueva@sjcteacher.edu.ph\",\"personal_email\":\"miguel.villanueva@gmail.com\"}', '{\"full_name\":\"Miguel Villanueva\",\"role\":\"teacher\",\"personal_email\":\"miguel.villanueva@gmail.com\"}', '::1', '2026-05-31 19:27:47', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(480, 1, 'update', 'teachers', 9, '{\"role\":\"teacher\",\"school_email\":\"robertomendoza@sjcteacher.edu.ph\",\"personal_email\":\"roberto.mendoza@gmail.com\"}', '{\"full_name\":\"Roberto Mendoza\",\"role\":\"teacher\",\"personal_email\":\"roberto.mendoza@gmail.com\"}', '::1', '2026-05-31 19:27:50', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(481, 1, 'update', 'teachers', 17, '{\"role\":\"teacher\",\"school_email\":\"bernardoaquino@sjcteacher.edu.ph\",\"personal_email\":\"bernardo.aquino@gmail.com\"}', '{\"full_name\":\"Bernardo Aquino\",\"role\":\"teacher\",\"personal_email\":\"bernardo.aquino@gmail.com\"}', '::1', '2026-05-31 19:27:55', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(482, 1, 'update', 'teachers', 18, '{\"role\":\"teacher\",\"school_email\":\"evelynpascual@sjcteacher.edu.ph\",\"personal_email\":\"evelyn.pascual@gmail.com\"}', '{\"full_name\":\"Evelyn Pascual\",\"role\":\"teacher\",\"personal_email\":\"evelyn.pascual@gmail.com\"}', '::1', '2026-05-31 19:27:57', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(483, 1, 'update', 'teachers', 7, '{\"role\":\"teacher\",\"school_email\":\"josereyes@sjcteacher.edu.ph\",\"personal_email\":\"jose.reyes@gmail.com\"}', '{\"full_name\":\"Jose Reyes\",\"role\":\"teacher\",\"personal_email\":\"jose.reyes@gmail.com\"}', '::1', '2026-05-31 19:28:00', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(484, 1, 'update', 'teachers', 6, '{\"role\":\"teacher\",\"school_email\":\"mariasantos@sjcteacher.edu.ph\",\"personal_email\":\"maria.santos@gmail.com\"}', '{\"full_name\":\"Maria Santos\",\"role\":\"teacher\",\"personal_email\":\"maria.santos@gmail.com\"}', '::1', '2026-05-31 19:28:03', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(485, 1, 'update', 'teachers', 6, '{\"role\":\"teacher\",\"school_email\":\"mariasantos@sjcteacher.edu.ph\",\"personal_email\":\"maria.santos@gmail.com\"}', '{\"full_name\":\"Maria Santos\",\"role\":\"teacher\",\"personal_email\":\"maria.santos@gmail.com\"}', '::1', '2026-05-31 19:28:07', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(486, 1, 'update', 'teachers', 7, '{\"role\":\"teacher\",\"school_email\":\"josereyes@sjcteacher.edu.ph\",\"personal_email\":\"jose.reyes@gmail.com\"}', '{\"full_name\":\"Jose Reyes\",\"role\":\"teacher\",\"personal_email\":\"jose.reyes@gmail.com\"}', '::1', '2026-05-31 19:28:09', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(487, 1, 'update', 'teachers', 25, '{\"role\":\"teacher\",\"school_email\":\"rodolfomedina@sjcteacher.edu.ph\",\"personal_email\":\"rodolfo.medina@gmail.com\"}', '{\"full_name\":\"Rodolfo Medina\",\"role\":\"teacher\",\"personal_email\":\"rodolfo.medina@gmail.com\"}', '::1', '2026-05-31 19:28:12', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1');
INSERT INTO `audit_logs` (`id`, `admin_id`, `action`, `table_name`, `record_id`, `old_values`, `new_values`, `ip_address`, `created_at`, `user_agent`) VALUES
(488, 1, 'update', 'teachers', 20, '{\"role\":\"teacher\",\"school_email\":\"claritaocampo@sjcteacher.edu.ph\",\"personal_email\":\"clarita.ocampo@gmail.com\"}', '{\"full_name\":\"Clarita Ocampo\",\"role\":\"teacher\",\"personal_email\":\"clarita.ocampo@gmail.com\"}', '::1', '2026-05-31 19:28:16', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(489, 1, 'update', 'teachers', 16, '{\"role\":\"teacher\",\"school_email\":\"carmenidelarosa@sjcteacher.edu.ph\",\"personal_email\":\"carmeni.delarosa@gmail.com\"}', '{\"full_name\":\"Carmeni Dela Rosa\",\"role\":\"teacher\",\"personal_email\":\"carmeni.delarosa@gmail.com\"}', '::1', '2026-05-31 19:28:19', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(490, 1, 'update', 'teachers', 32, '{\"role\":\"teacher\",\"school_email\":\"ceciliaaguilar@sjcteacher.edu.ph\",\"personal_email\":\"cecilia.aguilar@gmail.com\"}', '{\"full_name\":\"Cecilia Aguilar\",\"role\":\"teacher\",\"personal_email\":\"cecilia.aguilar@gmail.com\"}', '::1', '2026-05-31 19:28:22', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(491, 1, 'update', 'teachers', 26, '{\"role\":\"teacher\",\"school_email\":\"gloriahernandez@sjcteacher.edu.ph\",\"personal_email\":\"gloria.hernandez@gmail.com\"}', '{\"full_name\":\"Gloria Hernandez\",\"role\":\"teacher\",\"personal_email\":\"gloria.hernandez@gmail.com\"}', '::1', '2026-05-31 19:28:25', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(492, 1, 'update', 'teachers', 10, '{\"role\":\"teacher\",\"school_email\":\"lindaflores@sjcteacher.edu.ph\",\"personal_email\":\"linda.flores@gmail.com\"}', '{\"full_name\":\"Linda Flores\",\"role\":\"teacher\",\"personal_email\":\"linda.flores@gmail.com\"}', '::1', '2026-05-31 19:28:28', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(493, 1, 'update', 'teachers', 33, '{\"role\":\"teacher\",\"school_email\":\"manuelcabrera@sjcteacher.edu.ph\",\"personal_email\":\"manuel.cabrera@gmail.com\"}', '{\"full_name\":\"Manuel Cabrera\",\"role\":\"teacher\",\"personal_email\":\"manuel.cabrera@gmail.com\"}', '::1', '2026-05-31 19:28:31', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(494, 1, 'update', 'teachers', 33, '{\"role\":\"teacher\",\"school_email\":\"manuelcabrera@sjcteacher.edu.ph\",\"personal_email\":\"manuel.cabrera@gmail.com\"}', '{\"full_name\":\"Manuel Cabrera\",\"role\":\"teacher\",\"personal_email\":\"manuel.cabrera@gmail.com\"}', '::1', '2026-05-31 19:28:35', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(495, 1, 'update', 'teachers', 24, '{\"role\":\"teacher\",\"school_email\":\"marisolespinosa@sjcteacher.edu.ph\",\"personal_email\":\"marisol.espinosa@gmail.com\"}', '{\"full_name\":\"Marisol Espinosa\",\"role\":\"teacher\",\"personal_email\":\"marisol.espinosa@gmail.com\"}', '::1', '2026-05-31 19:28:38', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(496, 1, 'update', 'teachers', 38, '{\"role\":\"teacher\",\"school_email\":\"mercedestan@sjcteacher.edu.ph\",\"personal_email\":\"mercedes.tan@gmail.com\"}', '{\"full_name\":\"Mercedes Tan\",\"role\":\"teacher\",\"personal_email\":\"mercedes.tan@gmail.com\"}', '::1', '2026-05-31 19:28:42', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(497, 1, 'update', 'teachers', 16, '{\"role\":\"teacher\",\"school_email\":\"carmenidelarosa@sjcteacher.edu.ph\",\"personal_email\":\"carmeni.delarosa@gmail.com\"}', '{\"full_name\":\"Carmeni Dela Rosa\",\"role\":\"teacher\",\"personal_email\":\"carmeni.delarosa@gmail.com\"}', '::1', '2026-05-31 19:30:30', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(498, 1, 'update', 'teachers', 32, '{\"role\":\"teacher\",\"school_email\":\"ceciliaaguilar@sjcteacher.edu.ph\",\"personal_email\":\"cecilia.aguilar@gmail.com\"}', '{\"full_name\":\"Cecilia Aguilar\",\"role\":\"teacher\",\"personal_email\":\"cecilia.aguilar@gmail.com\"}', '::1', '2026-05-31 19:30:34', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(499, 1, 'update', 'teachers', 26, '{\"role\":\"teacher\",\"school_email\":\"gloriahernandez@sjcteacher.edu.ph\",\"personal_email\":\"gloria.hernandez@gmail.com\"}', '{\"full_name\":\"Gloria Hernandez\",\"role\":\"teacher\",\"personal_email\":\"gloria.hernandez@gmail.com\"}', '::1', '2026-05-31 19:30:37', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(500, 1, 'update', 'teachers', 10, '{\"role\":\"teacher\",\"school_email\":\"lindaflores@sjcteacher.edu.ph\",\"personal_email\":\"linda.flores@gmail.com\"}', '{\"full_name\":\"Linda Flores\",\"role\":\"teacher\",\"personal_email\":\"linda.flores@gmail.com\"}', '::1', '2026-05-31 19:30:42', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(501, 1, 'update', 'teachers', 33, '{\"role\":\"teacher\",\"school_email\":\"manuelcabrera@sjcteacher.edu.ph\",\"personal_email\":\"manuel.cabrera@gmail.com\"}', '{\"full_name\":\"Manuel Cabrera\",\"role\":\"teacher\",\"personal_email\":\"manuel.cabrera@gmail.com\"}', '::1', '2026-05-31 19:30:46', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(502, 1, 'update', 'teachers', 24, '{\"role\":\"teacher\",\"school_email\":\"marisolespinosa@sjcteacher.edu.ph\",\"personal_email\":\"marisol.espinosa@gmail.com\"}', '{\"full_name\":\"Marisol Espinosa\",\"role\":\"teacher\",\"personal_email\":\"marisol.espinosa@gmail.com\"}', '::1', '2026-05-31 19:30:49', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(503, 1, 'update', 'teachers', 38, '{\"role\":\"teacher\",\"school_email\":\"mercedestan@sjcteacher.edu.ph\",\"personal_email\":\"mercedes.tan@gmail.com\"}', '{\"full_name\":\"Mercedes Tan\",\"role\":\"teacher\",\"personal_email\":\"mercedes.tan@gmail.com\"}', '::1', '2026-05-31 19:30:53', 'Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1'),
(504, 1, 'update', 'sections', 5, NULL, '{\"batch_removed_students\":[73,47,36,105,71,21,80,95,96,99],\"removed_count\":10}', '::1', '2026-05-31 20:28:10', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(505, 1, 'update', 'sections', 5, NULL, '{\"assigned_students\":1}', '::1', '2026-05-31 20:28:18', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(506, 1, 'update', 'sections', 5, NULL, '{\"assigned_students\":7}', '::1', '2026-05-31 20:31:30', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(507, 1, 'update', 'sections', 5, NULL, '{\"batch_removed_students\":[102],\"removed_count\":1}', '::1', '2026-05-31 20:37:20', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(508, 1, 'update', 'students', 423, '{\"lrn\":\"\",\"_student_name\":\"QueerBalasin Saichou\",\"_student_lrn\":null}', '{\"lrn\":\"000000234574\"}', '::1', '2026-05-31 20:38:02', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(509, 1, 'update', 'sections', 8, NULL, '{\"assigned_students\":1}', '::1', '2026-06-01 00:03:43', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(510, 1, 'update', 'students', 424, '{\"lrn\":\"\",\"_student_name\":\"Quarbloy Quarbloy\",\"_student_lrn\":null}', '{\"lrn\":\"000006745674\"}', '::1', '2026-06-01 00:04:08', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0'),
(511, 1, 'update', 'cafeteria_settings', 1, '{\"max_topup_amount\":\"0.00\"}', '{\"max_topup_amount\":250}', '::1', '2026-07-23 17:30:20', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36 OPR/133.0.0.0'),
(512, 1, '', 'student_wallets', 73, '{\"balance\":0}', '{\"balance\":250,\"note\":\"\"}', '::1', '2026-07-23 17:30:32', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36 OPR/133.0.0.0'),
(513, 1, '', 'student_wallets', 73, '{\"balance\":250}', '{\"balance\":0,\"note\":\"\"}', '::1', '2026-07-23 17:30:37', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36 OPR/133.0.0.0');

-- --------------------------------------------------------

--
-- Table structure for table `cafeteria_inventory`
--

CREATE TABLE `cafeteria_inventory` (
  `id` int(11) NOT NULL,
  `product_id` int(11) NOT NULL COMMENT 'FK -> cafeteria_products.id',
  `quantity` int(11) NOT NULL DEFAULT 0 COMMENT 'Stock count for the finished product',
  `low_stock_threshold` int(11) NOT NULL DEFAULT 10,
  `updated_by` int(11) DEFAULT NULL COMMENT 'admin id who last updated stock',
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Stock quantity per cafeteria product';

-- --------------------------------------------------------

--
-- Table structure for table `cafeteria_products`
--

CREATE TABLE `cafeteria_products` (
  `id` int(11) NOT NULL,
  `name` varchar(150) NOT NULL,
  `category` enum('meal','snack','drink','other') NOT NULL DEFAULT 'other',
  `price` decimal(10,2) NOT NULL DEFAULT 0.00,
  `status` enum('active','archived') NOT NULL DEFAULT 'active',
  `created_by` int(11) DEFAULT NULL COMMENT 'admin id who created the item',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Cafeteria food menu items and prices';

-- --------------------------------------------------------

--
-- Table structure for table `cafeteria_settings`
--

CREATE TABLE `cafeteria_settings` (
  `id` int(11) NOT NULL,
  `max_topup_amount` decimal(10,2) NOT NULL DEFAULT 0.00 COMMENT '0 = no limit on Add Funds transactions',
  `updated_by` int(11) DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Cafeteria wallet configuration (max top-up per transaction)';

--
-- Dumping data for table `cafeteria_settings`
--

INSERT INTO `cafeteria_settings` (`id`, `max_topup_amount`, `updated_by`, `updated_at`) VALUES
(1, 250.00, 1, '2026-07-23 17:30:20');

-- --------------------------------------------------------

--
-- Table structure for table `cashiers`
--

CREATE TABLE `cashiers` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL COMMENT 'FK → users.id',
  `first_name` varchar(100) NOT NULL,
  `middle_name` varchar(100) DEFAULT NULL,
  `last_name` varchar(100) NOT NULL,
  `full_name` varchar(200) DEFAULT NULL COMMENT 'Kept for display convenience',
  `employee_id` varchar(50) DEFAULT NULL COMMENT 'School employee number',
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `is_archived` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='One row per cashier staff member';

--
-- Dumping data for table `cashiers`
--

INSERT INTO `cashiers` (`id`, `user_id`, `first_name`, `middle_name`, `last_name`, `full_name`, `employee_id`, `is_active`, `created_at`, `updated_at`, `is_archived`) VALUES
(1, 4, 'Carlos', NULL, 'Menendez', 'Carlos Menendez', 'EMP-FD855F', 1, '2026-05-17 17:52:54', '2026-05-21 18:41:26', 0);

-- --------------------------------------------------------

--
-- Table structure for table `class_schedules`
--

CREATE TABLE `class_schedules` (
  `id` int(11) NOT NULL,
  `ssy_id` int(11) NOT NULL COMMENT 'FK → section_school_years.id',
  `subject_id` int(11) NOT NULL COMMENT 'FK → subjects.id',
  `teacher_id` int(11) DEFAULT NULL COMMENT 'FK → teachers.id',
  `days` varchar(60) NOT NULL COMMENT 'e.g. Monday-Wednesday-Friday',
  `start_time` time NOT NULL,
  `end_time` time NOT NULL,
  `room` varchar(80) DEFAULT NULL,
  `created_by` int(11) DEFAULT NULL COMMENT 'FK → registrars.id',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Per-section class schedule rows managed by Registrar';

--
-- Dumping data for table `class_schedules`
--

INSERT INTO `class_schedules` (`id`, `ssy_id`, `subject_id`, `teacher_id`, `days`, `start_time`, `end_time`, `room`, `created_by`, `created_at`, `updated_at`) VALUES
(122, 17, 33, NULL, 'Monday', '07:30:00', '08:30:00', '117', 1, '2026-05-29 18:34:15', '2026-05-29 18:34:15'),
(123, 17, 33, NULL, 'Tuesday', '07:30:00', '08:30:00', '117', 1, '2026-05-29 18:34:15', '2026-05-29 18:34:15'),
(124, 17, 33, NULL, 'Wednesday', '07:30:00', '08:30:00', '117', 1, '2026-05-29 18:34:15', '2026-05-29 18:34:15'),
(125, 17, 33, NULL, 'Thursday', '07:30:00', '08:30:00', '117', 1, '2026-05-29 18:34:15', '2026-05-29 18:34:15'),
(126, 17, 33, NULL, 'Friday', '07:30:00', '08:30:00', '117', 1, '2026-05-29 18:34:15', '2026-05-29 18:34:15'),
(127, 17, 25, NULL, 'Monday', '09:30:00', '10:30:00', '117', 1, '2026-05-29 18:34:47', '2026-05-29 18:34:47'),
(128, 17, 25, NULL, 'Tuesday', '09:30:00', '10:30:00', '117', 1, '2026-05-29 18:34:47', '2026-05-29 18:34:47'),
(129, 17, 25, NULL, 'Wednesday', '09:30:00', '10:30:00', '117', 1, '2026-05-29 18:34:47', '2026-05-29 18:34:47'),
(130, 17, 25, NULL, 'Thursday', '09:30:00', '10:30:00', '117', 1, '2026-05-29 18:34:47', '2026-05-29 18:34:47'),
(131, 17, 25, NULL, 'Friday', '09:30:00', '10:30:00', '117', 1, '2026-05-29 18:34:47', '2026-05-29 18:34:47'),
(132, 17, 28, NULL, 'Monday', '10:30:00', '11:30:00', '117', 1, '2026-05-29 18:35:03', '2026-05-29 18:35:03'),
(133, 17, 28, NULL, 'Tuesday', '10:30:00', '11:30:00', '117', 1, '2026-05-29 18:35:03', '2026-05-29 18:35:03'),
(134, 17, 28, NULL, 'Wednesday', '10:30:00', '11:30:00', '117', 1, '2026-05-29 18:35:03', '2026-05-29 18:35:03'),
(135, 17, 28, NULL, 'Thursday', '10:30:00', '11:30:00', '117', 1, '2026-05-29 18:35:03', '2026-05-29 18:35:03'),
(136, 17, 28, NULL, 'Friday', '10:30:00', '11:30:00', '117', 1, '2026-05-29 18:35:03', '2026-05-29 18:35:03'),
(137, 17, 34, NULL, 'Monday', '11:30:00', '12:30:00', '117', 1, '2026-05-29 18:35:32', '2026-05-29 18:35:32'),
(138, 17, 34, NULL, 'Friday', '11:30:00', '12:30:00', '117', 1, '2026-05-29 18:35:32', '2026-05-29 18:35:32'),
(139, 17, 26, NULL, 'Monday', '12:30:00', '13:00:00', '117', 1, '2026-05-29 18:35:56', '2026-05-29 18:35:56'),
(140, 17, 26, NULL, 'Tuesday', '12:30:00', '13:00:00', '117', 1, '2026-05-29 18:35:56', '2026-05-29 18:35:56'),
(141, 17, 26, NULL, 'Wednesday', '12:30:00', '13:00:00', '117', 1, '2026-05-29 18:35:56', '2026-05-29 18:35:56'),
(142, 17, 26, NULL, 'Thursday', '12:30:00', '13:00:00', '117', 1, '2026-05-29 18:35:56', '2026-05-29 18:35:56'),
(143, 17, 26, NULL, 'Friday', '12:30:00', '13:00:00', '117', 1, '2026-05-29 18:35:56', '2026-05-29 18:35:56'),
(144, 17, 27, NULL, 'Tuesday', '14:30:00', '15:30:00', '117', 1, '2026-05-29 18:36:41', '2026-05-29 18:36:41'),
(145, 17, 27, NULL, 'Wednesday', '14:30:00', '15:30:00', '117', 1, '2026-05-29 18:36:41', '2026-05-29 18:36:41'),
(146, 17, 27, NULL, 'Thursday', '14:30:00', '15:30:00', '117', 1, '2026-05-29 18:36:41', '2026-05-29 18:36:41'),
(147, 17, 35, NULL, 'Monday', '14:30:00', '15:30:00', '117', 1, '2026-05-29 18:37:10', '2026-05-29 18:37:10'),
(148, 17, 35, NULL, 'Friday', '14:30:00', '15:30:00', '117', 1, '2026-05-29 18:37:10', '2026-05-29 18:37:10'),
(149, 15, 33, NULL, 'Friday', '07:30:00', '08:30:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(150, 15, 25, NULL, 'Friday', '09:30:00', '10:30:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(151, 15, 28, NULL, 'Friday', '10:30:00', '11:30:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(152, 15, 34, NULL, 'Friday', '11:30:00', '12:30:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(153, 15, 26, NULL, 'Friday', '12:30:00', '13:00:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(154, 15, 35, NULL, 'Friday', '14:30:00', '15:30:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(155, 15, 33, NULL, 'Monday', '07:30:00', '08:30:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(156, 15, 25, NULL, 'Monday', '09:30:00', '10:30:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(157, 15, 28, NULL, 'Monday', '10:30:00', '11:30:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(158, 15, 34, NULL, 'Monday', '11:30:00', '12:30:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(159, 15, 26, NULL, 'Monday', '12:30:00', '13:00:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(160, 15, 35, NULL, 'Monday', '14:30:00', '15:30:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(161, 15, 33, NULL, 'Thursday', '07:30:00', '08:30:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(162, 15, 25, NULL, 'Thursday', '09:30:00', '10:30:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(163, 15, 28, NULL, 'Thursday', '10:30:00', '11:30:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(164, 15, 26, NULL, 'Thursday', '12:30:00', '13:00:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(165, 15, 27, NULL, 'Thursday', '14:30:00', '15:30:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(166, 15, 33, NULL, 'Tuesday', '07:30:00', '08:30:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(167, 15, 25, NULL, 'Tuesday', '09:30:00', '10:30:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(168, 15, 28, NULL, 'Tuesday', '10:30:00', '11:30:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(169, 15, 26, NULL, 'Tuesday', '12:30:00', '13:00:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(170, 15, 27, NULL, 'Tuesday', '14:30:00', '15:30:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(171, 15, 33, NULL, 'Wednesday', '07:30:00', '08:30:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(172, 15, 25, NULL, 'Wednesday', '09:30:00', '10:30:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(173, 15, 28, NULL, 'Wednesday', '10:30:00', '11:30:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(174, 15, 26, NULL, 'Wednesday', '12:30:00', '13:00:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(175, 15, 27, NULL, 'Wednesday', '14:30:00', '15:30:00', '117', 1, '2026-05-29 18:37:41', '2026-05-29 18:37:41'),
(176, 14, 33, NULL, 'Friday', '07:30:00', '08:30:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(177, 14, 25, NULL, 'Friday', '09:30:00', '10:30:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(178, 14, 28, NULL, 'Friday', '10:30:00', '11:30:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(179, 14, 34, NULL, 'Friday', '11:30:00', '12:30:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(180, 14, 26, NULL, 'Friday', '12:30:00', '13:00:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(181, 14, 35, NULL, 'Friday', '14:30:00', '15:30:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(182, 14, 33, NULL, 'Monday', '07:30:00', '08:30:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(183, 14, 25, NULL, 'Monday', '09:30:00', '10:30:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(184, 14, 28, NULL, 'Monday', '10:30:00', '11:30:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(185, 14, 34, NULL, 'Monday', '11:30:00', '12:30:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(186, 14, 26, NULL, 'Monday', '12:30:00', '13:00:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(187, 14, 35, NULL, 'Monday', '14:30:00', '15:30:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(188, 14, 33, NULL, 'Thursday', '07:30:00', '08:30:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(189, 14, 25, NULL, 'Thursday', '09:30:00', '10:30:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(190, 14, 28, NULL, 'Thursday', '10:30:00', '11:30:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(191, 14, 26, NULL, 'Thursday', '12:30:00', '13:00:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(192, 14, 27, NULL, 'Thursday', '14:30:00', '15:30:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(193, 14, 33, NULL, 'Tuesday', '07:30:00', '08:30:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(194, 14, 25, NULL, 'Tuesday', '09:30:00', '10:30:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(195, 14, 28, NULL, 'Tuesday', '10:30:00', '11:30:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(196, 14, 26, NULL, 'Tuesday', '12:30:00', '13:00:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(197, 14, 27, NULL, 'Tuesday', '14:30:00', '15:30:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(198, 14, 33, NULL, 'Wednesday', '07:30:00', '08:30:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(199, 14, 25, NULL, 'Wednesday', '09:30:00', '10:30:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(200, 14, 28, NULL, 'Wednesday', '10:30:00', '11:30:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(201, 14, 26, NULL, 'Wednesday', '12:30:00', '13:00:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(202, 14, 27, NULL, 'Wednesday', '14:30:00', '15:30:00', '117', 1, '2026-05-29 18:38:01', '2026-05-29 18:38:01'),
(203, 16, 33, NULL, 'Friday', '07:30:00', '08:30:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(204, 16, 25, NULL, 'Friday', '09:30:00', '10:30:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(205, 16, 28, NULL, 'Friday', '10:30:00', '11:30:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(206, 16, 34, NULL, 'Friday', '11:30:00', '12:30:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(207, 16, 26, NULL, 'Friday', '12:30:00', '13:00:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(208, 16, 35, NULL, 'Friday', '14:30:00', '15:30:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(209, 16, 33, NULL, 'Monday', '07:30:00', '08:30:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(210, 16, 25, NULL, 'Monday', '09:30:00', '10:30:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(211, 16, 28, NULL, 'Monday', '10:30:00', '11:30:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(212, 16, 34, NULL, 'Monday', '11:30:00', '12:30:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(213, 16, 26, NULL, 'Monday', '12:30:00', '13:00:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(214, 16, 35, NULL, 'Monday', '14:30:00', '15:30:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(215, 16, 33, NULL, 'Thursday', '07:30:00', '08:30:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(216, 16, 25, NULL, 'Thursday', '09:30:00', '10:30:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(217, 16, 28, NULL, 'Thursday', '10:30:00', '11:30:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(218, 16, 26, NULL, 'Thursday', '12:30:00', '13:00:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(219, 16, 27, NULL, 'Thursday', '14:30:00', '15:30:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(220, 16, 33, NULL, 'Tuesday', '07:30:00', '08:30:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(221, 16, 25, NULL, 'Tuesday', '09:30:00', '10:30:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(222, 16, 28, NULL, 'Tuesday', '10:30:00', '11:30:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(223, 16, 26, NULL, 'Tuesday', '12:30:00', '13:00:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(224, 16, 27, NULL, 'Tuesday', '14:30:00', '15:30:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(225, 16, 33, NULL, 'Wednesday', '07:30:00', '08:30:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(226, 16, 25, NULL, 'Wednesday', '09:30:00', '10:30:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(227, 16, 28, NULL, 'Wednesday', '10:30:00', '11:30:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(228, 16, 26, NULL, 'Wednesday', '12:30:00', '13:00:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(229, 16, 27, NULL, 'Wednesday', '14:30:00', '15:30:00', '117', 1, '2026-05-29 18:38:19', '2026-05-29 18:38:19'),
(230, 5, 6, NULL, 'Monday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:06:53', '2026-05-29 19:06:53'),
(231, 5, 6, NULL, 'Tuesday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:06:53', '2026-05-29 19:06:53'),
(232, 5, 6, NULL, 'Wednesday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:06:53', '2026-05-29 19:06:53'),
(233, 5, 6, NULL, 'Thursday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:06:53', '2026-05-29 19:06:53'),
(234, 5, 6, NULL, 'Friday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:06:53', '2026-05-29 19:06:53'),
(235, 5, 1, NULL, 'Tuesday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:07:09', '2026-05-29 19:07:09'),
(236, 5, 1, NULL, 'Wednesday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:07:09', '2026-05-29 19:07:09'),
(237, 5, 1, NULL, 'Thursday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:07:09', '2026-05-29 19:07:09'),
(238, 5, 4, NULL, 'Monday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:07:27', '2026-05-29 19:07:27'),
(239, 5, 4, NULL, 'Friday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:07:27', '2026-05-29 19:07:27'),
(240, 5, 7, NULL, 'Friday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:07:44', '2026-05-29 19:07:44'),
(241, 5, 2, NULL, 'Monday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:08:02', '2026-05-29 19:08:02'),
(242, 5, 2, NULL, 'Tuesday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:08:02', '2026-05-29 19:08:02'),
(243, 5, 2, NULL, 'Wednesday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:08:02', '2026-05-29 19:08:02'),
(244, 5, 2, NULL, 'Thursday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:08:02', '2026-05-29 19:08:02'),
(245, 5, 3, NULL, 'Tuesday', '11:30:00', '12:00:00', '100', 1, '2026-05-29 19:08:28', '2026-05-29 19:08:28'),
(246, 5, 8, NULL, 'Tuesday', '14:30:00', '15:30:00', '100', 1, '2026-05-29 19:09:12', '2026-05-29 19:09:12'),
(247, 5, 8, NULL, 'Wednesday', '14:30:00', '15:30:00', '100', 1, '2026-05-29 19:09:12', '2026-05-29 19:09:12'),
(248, 5, 8, NULL, 'Thursday', '14:30:00', '15:30:00', '100', 1, '2026-05-29 19:09:12', '2026-05-29 19:09:12'),
(249, 5, 8, NULL, 'Friday', '14:30:00', '15:30:00', '100', 1, '2026-05-29 19:09:12', '2026-05-29 19:09:12'),
(250, 5, 5, 5, 'Monday', '12:00:00', '13:00:00', '100', 1, '2026-05-29 19:09:32', '2026-05-31 20:30:53'),
(251, 3, 6, NULL, 'Friday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:14:54', '2026-05-29 19:14:54'),
(252, 3, 4, NULL, 'Friday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:14:54', '2026-05-29 19:14:54'),
(253, 3, 7, NULL, 'Friday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:14:54', '2026-05-29 19:14:54'),
(254, 3, 8, NULL, 'Friday', '14:30:00', '15:30:00', '100', 1, '2026-05-29 19:14:54', '2026-05-29 19:14:54'),
(255, 3, 6, NULL, 'Monday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:14:54', '2026-05-29 19:14:54'),
(256, 3, 4, NULL, 'Monday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:14:54', '2026-05-29 19:14:54'),
(257, 3, 2, NULL, 'Monday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:14:54', '2026-05-29 19:14:54'),
(258, 3, 5, NULL, 'Monday', '12:00:00', '13:00:00', '100', 1, '2026-05-29 19:14:54', '2026-05-31 20:30:35'),
(259, 3, 6, NULL, 'Thursday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:14:54', '2026-05-29 19:14:54'),
(260, 3, 1, NULL, 'Thursday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:14:54', '2026-05-29 19:14:54'),
(261, 3, 2, NULL, 'Thursday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:14:54', '2026-05-29 19:14:54'),
(262, 3, 8, NULL, 'Thursday', '14:30:00', '15:30:00', '100', 1, '2026-05-29 19:14:54', '2026-05-29 19:14:54'),
(263, 3, 6, NULL, 'Tuesday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:14:54', '2026-05-29 19:14:54'),
(264, 3, 1, NULL, 'Tuesday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:14:54', '2026-05-29 19:14:54'),
(265, 3, 2, NULL, 'Tuesday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:14:54', '2026-05-29 19:14:54'),
(266, 3, 3, NULL, 'Tuesday', '11:30:00', '12:00:00', '100', 1, '2026-05-29 19:14:54', '2026-05-29 19:14:54'),
(267, 3, 8, NULL, 'Tuesday', '14:30:00', '15:30:00', '100', 1, '2026-05-29 19:14:54', '2026-05-29 19:14:54'),
(268, 3, 6, NULL, 'Wednesday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:14:54', '2026-05-29 19:14:54'),
(269, 3, 1, NULL, 'Wednesday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:14:54', '2026-05-29 19:14:54'),
(270, 3, 2, NULL, 'Wednesday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:14:54', '2026-05-29 19:14:54'),
(271, 3, 8, NULL, 'Wednesday', '14:30:00', '15:30:00', '100', 1, '2026-05-29 19:14:54', '2026-05-29 19:14:54'),
(272, 2, 6, NULL, 'Friday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:14:54', '2026-05-29 19:14:54'),
(273, 2, 4, NULL, 'Friday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:14:54', '2026-05-29 19:14:54'),
(274, 2, 7, NULL, 'Friday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(275, 2, 8, NULL, 'Friday', '14:30:00', '15:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(276, 2, 6, NULL, 'Monday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(277, 2, 4, NULL, 'Monday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(278, 2, 2, NULL, 'Monday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(279, 2, 5, NULL, 'Monday', '12:00:00', '13:00:00', '100', 1, '2026-05-29 19:14:55', '2026-05-31 20:30:37'),
(280, 2, 6, NULL, 'Thursday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(281, 2, 1, NULL, 'Thursday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(282, 2, 2, NULL, 'Thursday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(283, 2, 8, NULL, 'Thursday', '14:30:00', '15:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(284, 2, 6, NULL, 'Tuesday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(285, 2, 1, NULL, 'Tuesday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(286, 2, 2, NULL, 'Tuesday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(287, 2, 3, NULL, 'Tuesday', '11:30:00', '12:00:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(288, 2, 8, NULL, 'Tuesday', '14:30:00', '15:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(289, 2, 6, NULL, 'Wednesday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(290, 2, 1, NULL, 'Wednesday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(291, 2, 2, NULL, 'Wednesday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(292, 2, 8, NULL, 'Wednesday', '14:30:00', '15:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(293, 1, 6, NULL, 'Friday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(294, 1, 4, NULL, 'Friday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(295, 1, 7, NULL, 'Friday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(296, 1, 8, NULL, 'Friday', '14:30:00', '15:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(297, 1, 6, NULL, 'Monday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(298, 1, 4, NULL, 'Monday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(299, 1, 2, NULL, 'Monday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(300, 1, 5, NULL, 'Monday', '12:00:00', '13:00:00', '100', 1, '2026-05-29 19:14:55', '2026-05-31 20:30:46'),
(301, 1, 6, NULL, 'Thursday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(302, 1, 1, NULL, 'Thursday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(303, 1, 2, NULL, 'Thursday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(304, 1, 8, NULL, 'Thursday', '14:30:00', '15:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(305, 1, 6, NULL, 'Tuesday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(306, 1, 1, NULL, 'Tuesday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(307, 1, 2, NULL, 'Tuesday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(308, 1, 3, NULL, 'Tuesday', '11:30:00', '12:00:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(309, 1, 8, NULL, 'Tuesday', '14:30:00', '15:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(310, 1, 6, NULL, 'Wednesday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(311, 1, 1, NULL, 'Wednesday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(312, 1, 2, NULL, 'Wednesday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(313, 1, 8, NULL, 'Wednesday', '14:30:00', '15:30:00', '100', 1, '2026-05-29 19:14:55', '2026-05-29 19:14:55'),
(335, 4, 6, NULL, 'Friday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:19:18', '2026-05-29 19:19:18'),
(336, 4, 4, NULL, 'Friday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:19:18', '2026-05-29 19:19:18'),
(337, 4, 7, NULL, 'Friday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:19:18', '2026-05-29 19:19:18'),
(338, 4, 8, NULL, 'Friday', '14:30:00', '15:30:00', '100', 1, '2026-05-29 19:19:18', '2026-05-29 19:19:18'),
(339, 4, 6, NULL, 'Monday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:19:18', '2026-05-29 19:19:18'),
(340, 4, 4, NULL, 'Monday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:19:18', '2026-05-29 19:19:18'),
(341, 4, 2, NULL, 'Monday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:19:18', '2026-05-29 19:19:18'),
(342, 4, 5, 37, 'Monday', '12:00:00', '13:00:00', '100', 1, '2026-05-29 19:19:18', '2026-05-31 08:44:02'),
(343, 4, 6, NULL, 'Thursday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:19:18', '2026-05-29 19:19:18'),
(344, 4, 1, NULL, 'Thursday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:19:18', '2026-05-29 19:19:18'),
(345, 4, 2, NULL, 'Thursday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:19:18', '2026-05-29 19:19:18'),
(346, 4, 8, NULL, 'Thursday', '14:30:00', '15:30:00', '100', 1, '2026-05-29 19:19:18', '2026-05-29 19:19:18'),
(347, 4, 6, NULL, 'Tuesday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:19:18', '2026-05-29 19:19:18'),
(348, 4, 1, NULL, 'Tuesday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:19:18', '2026-05-29 19:19:18'),
(349, 4, 2, NULL, 'Tuesday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:19:18', '2026-05-29 19:19:18'),
(350, 4, 3, NULL, 'Tuesday', '11:30:00', '12:00:00', '100', 1, '2026-05-29 19:19:18', '2026-05-29 19:19:18'),
(351, 4, 8, NULL, 'Tuesday', '14:30:00', '15:30:00', '100', 1, '2026-05-29 19:19:18', '2026-05-29 19:19:18'),
(352, 4, 6, NULL, 'Wednesday', '07:00:00', '08:30:00', '100', 1, '2026-05-29 19:19:18', '2026-05-29 19:19:18'),
(353, 4, 1, NULL, 'Wednesday', '08:30:00', '09:30:00', '100', 1, '2026-05-29 19:19:18', '2026-05-29 19:19:18'),
(354, 4, 2, NULL, 'Wednesday', '10:30:00', '11:30:00', '100', 1, '2026-05-29 19:19:18', '2026-05-29 19:19:18'),
(355, 4, 8, NULL, 'Wednesday', '14:30:00', '15:30:00', '100', 1, '2026-05-29 19:19:18', '2026-05-29 19:19:18'),
(356, 8, 14, NULL, 'Monday', '07:00:00', '08:00:00', '106', 1, '2026-05-30 16:00:24', '2026-05-30 16:00:24'),
(357, 8, 14, NULL, 'Tuesday', '07:00:00', '08:00:00', '106', 1, '2026-05-30 16:00:24', '2026-05-30 16:00:24'),
(358, 8, 14, NULL, 'Wednesday', '07:00:00', '08:00:00', '106', 1, '2026-05-30 16:00:24', '2026-05-30 16:00:24'),
(359, 8, 14, NULL, 'Thursday', '07:00:00', '08:00:00', '106', 1, '2026-05-30 16:00:24', '2026-05-30 16:00:24'),
(360, 8, 14, NULL, 'Friday', '07:00:00', '08:00:00', '106', 1, '2026-05-30 16:00:24', '2026-05-30 16:00:24'),
(361, 8, 9, NULL, 'Monday', '08:30:00', '09:00:00', '106', 1, '2026-05-30 16:00:36', '2026-05-30 16:00:36'),
(362, 8, 9, NULL, 'Tuesday', '08:30:00', '09:00:00', '106', 1, '2026-05-30 16:00:36', '2026-05-30 16:00:36'),
(363, 8, 9, NULL, 'Wednesday', '08:30:00', '09:00:00', '106', 1, '2026-05-30 16:00:36', '2026-05-30 16:00:36'),
(364, 8, 9, NULL, 'Thursday', '08:30:00', '09:00:00', '106', 1, '2026-05-30 16:00:36', '2026-05-30 16:00:36'),
(365, 8, 9, NULL, 'Friday', '08:30:00', '09:00:00', '106', 1, '2026-05-30 16:00:36', '2026-05-30 16:00:36'),
(366, 8, 12, NULL, 'Monday', '09:00:00', '09:30:00', '106', 1, '2026-05-30 16:00:50', '2026-05-30 16:00:50'),
(367, 8, 12, NULL, 'Tuesday', '09:00:00', '09:30:00', '106', 1, '2026-05-30 16:00:50', '2026-05-30 16:00:50'),
(368, 8, 12, NULL, 'Wednesday', '09:00:00', '09:30:00', '106', 1, '2026-05-30 16:00:50', '2026-05-30 16:00:50'),
(369, 8, 12, NULL, 'Thursday', '09:00:00', '09:30:00', '106', 1, '2026-05-30 16:00:50', '2026-05-30 16:00:50'),
(370, 8, 12, NULL, 'Friday', '09:00:00', '09:30:00', '106', 1, '2026-05-30 16:00:50', '2026-05-30 16:00:50'),
(371, 8, 15, NULL, 'Monday', '09:30:00', '10:00:00', '106', 1, '2026-05-30 16:01:01', '2026-05-30 16:01:01'),
(372, 8, 15, NULL, 'Tuesday', '09:30:00', '10:00:00', '106', 1, '2026-05-30 16:01:02', '2026-05-30 16:01:02'),
(373, 8, 15, NULL, 'Wednesday', '09:30:00', '10:00:00', '106', 1, '2026-05-30 16:01:02', '2026-05-30 16:01:02'),
(374, 8, 15, NULL, 'Thursday', '09:30:00', '10:00:00', '106', 1, '2026-05-30 16:01:02', '2026-05-30 16:01:02'),
(375, 8, 15, NULL, 'Friday', '09:30:00', '10:00:00', '106', 1, '2026-05-30 16:01:02', '2026-05-30 16:01:02'),
(376, 8, 10, NULL, 'Monday', '10:00:00', '11:00:00', '106', 1, '2026-05-30 16:01:31', '2026-05-30 16:01:31'),
(377, 8, 10, NULL, 'Tuesday', '10:00:00', '11:00:00', '106', 1, '2026-05-30 16:01:31', '2026-05-30 16:01:31'),
(378, 8, 10, NULL, 'Wednesday', '10:00:00', '11:00:00', '106', 1, '2026-05-30 16:01:31', '2026-05-30 16:01:31'),
(379, 8, 10, NULL, 'Thursday', '10:00:00', '11:00:00', '106', 1, '2026-05-30 16:01:31', '2026-05-30 16:01:31'),
(380, 8, 10, NULL, 'Friday', '10:00:00', '11:00:00', '106', 1, '2026-05-30 16:01:31', '2026-05-30 16:01:31'),
(381, 8, 11, NULL, 'Monday', '13:00:00', '13:30:00', '106', 1, '2026-05-30 16:01:49', '2026-05-30 16:01:49'),
(382, 8, 11, NULL, 'Tuesday', '13:00:00', '13:30:00', '106', 1, '2026-05-30 16:01:49', '2026-05-30 16:01:49'),
(383, 8, 11, NULL, 'Wednesday', '13:00:00', '13:30:00', '106', 1, '2026-05-30 16:01:49', '2026-05-30 16:01:49'),
(384, 8, 11, NULL, 'Thursday', '13:00:00', '13:30:00', '106', 1, '2026-05-30 16:01:49', '2026-05-30 16:01:49'),
(385, 8, 11, NULL, 'Friday', '13:00:00', '13:30:00', '106', 1, '2026-05-30 16:01:49', '2026-05-30 16:01:49'),
(386, 8, 16, NULL, 'Monday', '13:30:00', '14:30:00', '106', 1, '2026-05-30 16:02:02', '2026-05-30 16:02:02'),
(387, 8, 16, NULL, 'Tuesday', '13:30:00', '14:30:00', '106', 1, '2026-05-30 16:02:02', '2026-05-30 16:02:02'),
(388, 8, 16, NULL, 'Wednesday', '13:30:00', '14:30:00', '106', 1, '2026-05-30 16:02:02', '2026-05-30 16:02:02'),
(389, 8, 16, NULL, 'Thursday', '13:30:00', '14:30:00', '106', 1, '2026-05-30 16:02:02', '2026-05-30 16:02:02'),
(390, 8, 16, NULL, 'Friday', '13:30:00', '14:30:00', '106', 1, '2026-05-30 16:02:02', '2026-05-30 16:02:02'),
(391, 8, 13, 5, 'Monday', '15:30:00', '16:30:00', '106', 1, '2026-05-30 16:02:23', '2026-05-31 08:43:38'),
(392, 8, 13, 5, 'Tuesday', '15:30:00', '16:30:00', '106', 1, '2026-05-30 16:02:23', '2026-05-31 08:43:38'),
(393, 8, 13, 5, 'Wednesday', '15:30:00', '16:30:00', '106', 1, '2026-05-30 16:02:24', '2026-05-31 08:43:38'),
(394, 8, 13, 5, 'Thursday', '15:30:00', '16:30:00', '106', 1, '2026-05-30 16:02:24', '2026-05-31 08:43:38'),
(395, 8, 13, 5, 'Friday', '15:30:00', '16:30:00', '106', 1, '2026-05-30 16:02:24', '2026-05-31 08:43:38'),
(396, 9, 14, NULL, 'Friday', '07:00:00', '08:00:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(397, 9, 9, NULL, 'Friday', '08:30:00', '09:00:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(398, 9, 12, NULL, 'Friday', '09:00:00', '09:30:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(399, 9, 15, NULL, 'Friday', '09:30:00', '10:00:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(400, 9, 10, NULL, 'Friday', '10:00:00', '11:00:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(401, 9, 11, NULL, 'Friday', '13:00:00', '13:30:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(402, 9, 16, NULL, 'Friday', '13:30:00', '14:30:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(403, 9, 13, 36, 'Friday', '15:30:00', '16:30:00', '106', 1, '2026-05-30 16:19:19', '2026-05-31 08:44:11'),
(404, 9, 14, NULL, 'Monday', '07:00:00', '08:00:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(405, 9, 9, NULL, 'Monday', '08:30:00', '09:00:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(406, 9, 12, NULL, 'Monday', '09:00:00', '09:30:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(407, 9, 15, NULL, 'Monday', '09:30:00', '10:00:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(408, 9, 10, NULL, 'Monday', '10:00:00', '11:00:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(409, 9, 11, NULL, 'Monday', '13:00:00', '13:30:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(410, 9, 16, NULL, 'Monday', '13:30:00', '14:30:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(411, 9, 13, 36, 'Monday', '15:30:00', '16:30:00', '106', 1, '2026-05-30 16:19:19', '2026-05-31 08:44:11'),
(412, 9, 14, NULL, 'Thursday', '07:00:00', '08:00:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(413, 9, 9, NULL, 'Thursday', '08:30:00', '09:00:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(414, 9, 12, NULL, 'Thursday', '09:00:00', '09:30:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(415, 9, 15, NULL, 'Thursday', '09:30:00', '10:00:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(416, 9, 10, NULL, 'Thursday', '10:00:00', '11:00:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(417, 9, 11, NULL, 'Thursday', '13:00:00', '13:30:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(418, 9, 16, NULL, 'Thursday', '13:30:00', '14:30:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(419, 9, 13, 36, 'Thursday', '15:30:00', '16:30:00', '106', 1, '2026-05-30 16:19:19', '2026-05-31 08:44:11'),
(420, 9, 14, NULL, 'Tuesday', '07:00:00', '08:00:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(421, 9, 9, NULL, 'Tuesday', '08:30:00', '09:00:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(422, 9, 12, NULL, 'Tuesday', '09:00:00', '09:30:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(423, 9, 15, NULL, 'Tuesday', '09:30:00', '10:00:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(424, 9, 10, NULL, 'Tuesday', '10:00:00', '11:00:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(425, 9, 11, NULL, 'Tuesday', '13:00:00', '13:30:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(426, 9, 16, NULL, 'Tuesday', '13:30:00', '14:30:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(427, 9, 13, 36, 'Tuesday', '15:30:00', '16:30:00', '106', 1, '2026-05-30 16:19:19', '2026-05-31 08:44:11'),
(428, 9, 14, NULL, 'Wednesday', '07:00:00', '08:00:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(429, 9, 9, NULL, 'Wednesday', '08:30:00', '09:00:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(430, 9, 12, NULL, 'Wednesday', '09:00:00', '09:30:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(431, 9, 15, NULL, 'Wednesday', '09:30:00', '10:00:00', '106', 1, '2026-05-30 16:19:19', '2026-05-30 16:19:19'),
(432, 9, 10, NULL, 'Wednesday', '10:00:00', '11:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(433, 9, 11, NULL, 'Wednesday', '13:00:00', '13:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(434, 9, 16, NULL, 'Wednesday', '13:30:00', '14:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(435, 9, 13, 36, 'Wednesday', '15:30:00', '16:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-31 08:44:11'),
(436, 7, 14, NULL, 'Friday', '07:00:00', '08:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(437, 7, 9, NULL, 'Friday', '08:30:00', '09:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(438, 7, 12, NULL, 'Friday', '09:00:00', '09:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(439, 7, 15, NULL, 'Friday', '09:30:00', '10:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(440, 7, 10, NULL, 'Friday', '10:00:00', '11:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(441, 7, 11, NULL, 'Friday', '13:00:00', '13:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(442, 7, 16, NULL, 'Friday', '13:30:00', '14:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(443, 7, 13, 28, 'Friday', '15:30:00', '16:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-31 08:44:10'),
(444, 7, 14, NULL, 'Monday', '07:00:00', '08:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(445, 7, 9, NULL, 'Monday', '08:30:00', '09:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(446, 7, 12, NULL, 'Monday', '09:00:00', '09:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(447, 7, 15, NULL, 'Monday', '09:30:00', '10:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(448, 7, 10, NULL, 'Monday', '10:00:00', '11:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(449, 7, 11, NULL, 'Monday', '13:00:00', '13:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(450, 7, 16, NULL, 'Monday', '13:30:00', '14:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(451, 7, 13, 28, 'Monday', '15:30:00', '16:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-31 08:44:10'),
(452, 7, 14, NULL, 'Thursday', '07:00:00', '08:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(453, 7, 9, NULL, 'Thursday', '08:30:00', '09:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(454, 7, 12, NULL, 'Thursday', '09:00:00', '09:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(455, 7, 15, NULL, 'Thursday', '09:30:00', '10:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(456, 7, 10, NULL, 'Thursday', '10:00:00', '11:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(457, 7, 11, NULL, 'Thursday', '13:00:00', '13:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(458, 7, 16, NULL, 'Thursday', '13:30:00', '14:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(459, 7, 13, 28, 'Thursday', '15:30:00', '16:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-31 08:44:10'),
(460, 7, 14, NULL, 'Tuesday', '07:00:00', '08:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(461, 7, 9, NULL, 'Tuesday', '08:30:00', '09:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(462, 7, 12, NULL, 'Tuesday', '09:00:00', '09:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(463, 7, 15, NULL, 'Tuesday', '09:30:00', '10:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(464, 7, 10, NULL, 'Tuesday', '10:00:00', '11:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(465, 7, 11, NULL, 'Tuesday', '13:00:00', '13:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(466, 7, 16, NULL, 'Tuesday', '13:30:00', '14:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(467, 7, 13, 28, 'Tuesday', '15:30:00', '16:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-31 08:44:10'),
(468, 7, 14, NULL, 'Wednesday', '07:00:00', '08:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(469, 7, 9, NULL, 'Wednesday', '08:30:00', '09:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(470, 7, 12, NULL, 'Wednesday', '09:00:00', '09:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(471, 7, 15, NULL, 'Wednesday', '09:30:00', '10:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(472, 7, 10, NULL, 'Wednesday', '10:00:00', '11:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(473, 7, 11, NULL, 'Wednesday', '13:00:00', '13:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(474, 7, 16, NULL, 'Wednesday', '13:30:00', '14:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(475, 7, 13, 28, 'Wednesday', '15:30:00', '16:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-31 08:44:10'),
(476, 6, 14, NULL, 'Friday', '07:00:00', '08:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(477, 6, 9, NULL, 'Friday', '08:30:00', '09:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(478, 6, 12, NULL, 'Friday', '09:00:00', '09:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(479, 6, 15, NULL, 'Friday', '09:30:00', '10:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(480, 6, 10, NULL, 'Friday', '10:00:00', '11:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(481, 6, 11, NULL, 'Friday', '13:00:00', '13:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(482, 6, 16, NULL, 'Friday', '13:30:00', '14:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(483, 6, 13, 37, 'Friday', '15:30:00', '16:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-31 08:44:10'),
(484, 6, 14, NULL, 'Monday', '07:00:00', '08:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(485, 6, 9, NULL, 'Monday', '08:30:00', '09:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(486, 6, 12, NULL, 'Monday', '09:00:00', '09:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(487, 6, 15, NULL, 'Monday', '09:30:00', '10:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(488, 6, 10, NULL, 'Monday', '10:00:00', '11:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(489, 6, 11, NULL, 'Monday', '13:00:00', '13:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(490, 6, 16, NULL, 'Monday', '13:30:00', '14:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(491, 6, 13, 37, 'Monday', '15:30:00', '16:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-31 08:44:10'),
(492, 6, 14, NULL, 'Thursday', '07:00:00', '08:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(493, 6, 9, NULL, 'Thursday', '08:30:00', '09:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(494, 6, 12, NULL, 'Thursday', '09:00:00', '09:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(495, 6, 15, NULL, 'Thursday', '09:30:00', '10:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(496, 6, 10, NULL, 'Thursday', '10:00:00', '11:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(497, 6, 11, NULL, 'Thursday', '13:00:00', '13:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(498, 6, 16, NULL, 'Thursday', '13:30:00', '14:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(499, 6, 13, 37, 'Thursday', '15:30:00', '16:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-31 08:44:10'),
(500, 6, 14, NULL, 'Tuesday', '07:00:00', '08:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(501, 6, 9, NULL, 'Tuesday', '08:30:00', '09:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(502, 6, 12, NULL, 'Tuesday', '09:00:00', '09:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(503, 6, 15, NULL, 'Tuesday', '09:30:00', '10:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(504, 6, 10, NULL, 'Tuesday', '10:00:00', '11:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(505, 6, 11, NULL, 'Tuesday', '13:00:00', '13:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(506, 6, 16, NULL, 'Tuesday', '13:30:00', '14:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(507, 6, 13, 37, 'Tuesday', '15:30:00', '16:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-31 08:44:10'),
(508, 6, 14, NULL, 'Wednesday', '07:00:00', '08:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(509, 6, 9, NULL, 'Wednesday', '08:30:00', '09:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(510, 6, 12, NULL, 'Wednesday', '09:00:00', '09:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(511, 6, 15, NULL, 'Wednesday', '09:30:00', '10:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(512, 6, 10, NULL, 'Wednesday', '10:00:00', '11:00:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(513, 6, 11, NULL, 'Wednesday', '13:00:00', '13:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(514, 6, 16, NULL, 'Wednesday', '13:30:00', '14:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-30 16:19:20'),
(515, 6, 13, 37, 'Wednesday', '15:30:00', '16:30:00', '106', 1, '2026-05-30 16:19:20', '2026-05-31 08:44:10'),
(516, 13, 22, NULL, 'Monday', '07:30:00', '08:30:00', '110', 1, '2026-05-30 16:19:47', '2026-05-30 16:19:47'),
(517, 13, 22, NULL, 'Tuesday', '07:30:00', '08:30:00', '110', 1, '2026-05-30 16:19:47', '2026-05-30 16:19:47'),
(518, 13, 22, NULL, 'Wednesday', '07:30:00', '08:30:00', '110', 1, '2026-05-30 16:19:47', '2026-05-30 16:19:47'),
(519, 13, 22, NULL, 'Thursday', '07:30:00', '08:30:00', '110', 1, '2026-05-30 16:19:47', '2026-05-30 16:19:47'),
(520, 13, 22, NULL, 'Friday', '07:30:00', '08:30:00', '110', 1, '2026-05-30 16:19:47', '2026-05-30 16:19:47'),
(521, 13, 17, NULL, 'Monday', '08:30:00', '09:00:00', '110', 1, '2026-05-30 16:20:07', '2026-05-30 16:20:07'),
(522, 13, 17, NULL, 'Tuesday', '08:30:00', '09:00:00', '110', 1, '2026-05-30 16:20:07', '2026-05-30 16:20:07'),
(523, 13, 17, NULL, 'Wednesday', '08:30:00', '09:00:00', '110', 1, '2026-05-30 16:20:07', '2026-05-30 16:20:07'),
(524, 13, 17, NULL, 'Thursday', '08:30:00', '09:00:00', '110', 1, '2026-05-30 16:20:07', '2026-05-30 16:20:07'),
(525, 13, 17, NULL, 'Friday', '08:30:00', '09:00:00', '110', 1, '2026-05-30 16:20:07', '2026-05-30 16:20:07'),
(526, 13, 20, NULL, 'Monday', '09:30:00', '10:00:00', '110', 1, '2026-05-30 16:25:09', '2026-05-30 16:25:09'),
(527, 13, 20, NULL, 'Tuesday', '09:30:00', '10:00:00', '110', 1, '2026-05-30 16:25:09', '2026-05-30 16:25:09'),
(528, 13, 20, NULL, 'Wednesday', '09:30:00', '10:00:00', '110', 1, '2026-05-30 16:25:09', '2026-05-30 16:25:09'),
(529, 13, 20, NULL, 'Thursday', '09:30:00', '10:00:00', '110', 1, '2026-05-30 16:25:09', '2026-05-30 16:25:09'),
(530, 13, 20, NULL, 'Friday', '09:30:00', '10:00:00', '110', 1, '2026-05-30 16:25:09', '2026-05-30 16:25:09'),
(531, 13, 23, NULL, 'Monday', '11:00:00', '11:30:00', '110', 1, '2026-05-30 16:25:21', '2026-05-30 16:25:21'),
(532, 13, 23, NULL, 'Tuesday', '11:00:00', '11:30:00', '110', 1, '2026-05-30 16:25:21', '2026-05-30 16:25:21'),
(533, 13, 23, NULL, 'Wednesday', '11:00:00', '11:30:00', '110', 1, '2026-05-30 16:25:21', '2026-05-30 16:25:21'),
(534, 13, 23, NULL, 'Thursday', '11:00:00', '11:30:00', '110', 1, '2026-05-30 16:25:21', '2026-05-30 16:25:21'),
(535, 13, 23, NULL, 'Friday', '11:00:00', '11:30:00', '110', 1, '2026-05-30 16:25:21', '2026-05-30 16:25:21'),
(536, 13, 18, NULL, 'Monday', '12:00:00', '13:00:00', '110', 1, '2026-05-30 16:25:39', '2026-05-30 16:25:39'),
(537, 13, 18, NULL, 'Tuesday', '12:00:00', '13:00:00', '110', 1, '2026-05-30 16:25:39', '2026-05-30 16:25:39'),
(538, 13, 18, NULL, 'Wednesday', '12:00:00', '13:00:00', '110', 1, '2026-05-30 16:25:39', '2026-05-30 16:25:39'),
(539, 13, 18, NULL, 'Thursday', '12:00:00', '13:00:00', '110', 1, '2026-05-30 16:25:39', '2026-05-30 16:25:39'),
(540, 13, 18, NULL, 'Friday', '12:00:00', '13:00:00', '110', 1, '2026-05-30 16:25:39', '2026-05-30 16:25:39'),
(541, 13, 19, NULL, 'Monday', '13:30:00', '14:00:00', '110', 1, '2026-05-30 16:25:46', '2026-05-30 16:25:46'),
(542, 13, 19, NULL, 'Tuesday', '13:30:00', '14:00:00', '110', 1, '2026-05-30 16:25:46', '2026-05-30 16:25:46'),
(543, 13, 19, NULL, 'Wednesday', '13:30:00', '14:00:00', '110', 1, '2026-05-30 16:25:46', '2026-05-30 16:25:46'),
(544, 13, 19, NULL, 'Thursday', '13:30:00', '14:00:00', '110', 1, '2026-05-30 16:25:46', '2026-05-30 16:25:46'),
(545, 13, 19, NULL, 'Friday', '13:30:00', '14:00:00', '110', 1, '2026-05-30 16:25:46', '2026-05-30 16:25:46'),
(546, 13, 24, NULL, 'Monday', '14:10:00', '14:30:00', '110', 1, '2026-05-30 16:26:16', '2026-05-30 16:26:16'),
(547, 13, 24, NULL, 'Tuesday', '14:10:00', '14:30:00', '110', 1, '2026-05-30 16:26:16', '2026-05-30 16:26:16'),
(548, 13, 24, NULL, 'Wednesday', '14:10:00', '14:30:00', '110', 1, '2026-05-30 16:26:16', '2026-05-30 16:26:16'),
(549, 13, 24, NULL, 'Thursday', '14:10:00', '14:30:00', '110', 1, '2026-05-30 16:26:16', '2026-05-30 16:26:16'),
(550, 13, 24, NULL, 'Friday', '14:10:00', '14:30:00', '110', 1, '2026-05-30 16:26:16', '2026-05-30 16:26:16'),
(551, 13, 21, 29, 'Monday', '14:30:00', '15:30:00', '110', 1, '2026-05-30 16:26:25', '2026-05-31 08:44:10'),
(552, 13, 21, 29, 'Tuesday', '14:30:00', '15:30:00', '110', 1, '2026-05-30 16:26:25', '2026-05-31 08:44:10'),
(553, 13, 21, 29, 'Wednesday', '14:30:00', '15:30:00', '110', 1, '2026-05-30 16:26:25', '2026-05-31 08:44:10'),
(554, 13, 21, 29, 'Thursday', '14:30:00', '15:30:00', '110', 1, '2026-05-30 16:26:25', '2026-05-31 08:44:10'),
(555, 13, 21, 29, 'Friday', '14:30:00', '15:30:00', '110', 1, '2026-05-30 16:26:25', '2026-05-31 08:44:10'),
(556, 10, 22, NULL, 'Friday', '07:30:00', '08:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(557, 10, 17, NULL, 'Friday', '08:30:00', '09:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(558, 10, 20, NULL, 'Friday', '09:30:00', '10:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(559, 10, 23, NULL, 'Friday', '11:00:00', '11:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(560, 10, 18, NULL, 'Friday', '12:00:00', '13:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(561, 10, 19, NULL, 'Friday', '13:30:00', '14:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(562, 10, 24, NULL, 'Friday', '14:10:00', '14:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(563, 10, 21, 28, 'Friday', '14:30:00', '15:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-31 08:44:07'),
(564, 10, 22, NULL, 'Monday', '07:30:00', '08:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(565, 10, 17, NULL, 'Monday', '08:30:00', '09:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(566, 10, 20, NULL, 'Monday', '09:30:00', '10:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(567, 10, 23, NULL, 'Monday', '11:00:00', '11:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(568, 10, 18, NULL, 'Monday', '12:00:00', '13:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(569, 10, 19, NULL, 'Monday', '13:30:00', '14:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(570, 10, 24, NULL, 'Monday', '14:10:00', '14:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(571, 10, 21, 28, 'Monday', '14:30:00', '15:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-31 08:44:07'),
(572, 10, 22, NULL, 'Thursday', '07:30:00', '08:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(573, 10, 17, NULL, 'Thursday', '08:30:00', '09:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(574, 10, 20, NULL, 'Thursday', '09:30:00', '10:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(575, 10, 23, NULL, 'Thursday', '11:00:00', '11:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(576, 10, 18, NULL, 'Thursday', '12:00:00', '13:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(577, 10, 19, NULL, 'Thursday', '13:30:00', '14:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(578, 10, 24, NULL, 'Thursday', '14:10:00', '14:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(579, 10, 21, 28, 'Thursday', '14:30:00', '15:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-31 08:44:07'),
(580, 10, 22, NULL, 'Tuesday', '07:30:00', '08:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(581, 10, 17, NULL, 'Tuesday', '08:30:00', '09:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(582, 10, 20, NULL, 'Tuesday', '09:30:00', '10:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(583, 10, 23, NULL, 'Tuesday', '11:00:00', '11:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(584, 10, 18, NULL, 'Tuesday', '12:00:00', '13:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(585, 10, 19, NULL, 'Tuesday', '13:30:00', '14:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(586, 10, 24, NULL, 'Tuesday', '14:10:00', '14:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(587, 10, 21, 28, 'Tuesday', '14:30:00', '15:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-31 08:44:07'),
(588, 10, 22, NULL, 'Wednesday', '07:30:00', '08:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(589, 10, 17, NULL, 'Wednesday', '08:30:00', '09:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(590, 10, 20, NULL, 'Wednesday', '09:30:00', '10:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(591, 10, 23, NULL, 'Wednesday', '11:00:00', '11:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(592, 10, 18, NULL, 'Wednesday', '12:00:00', '13:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(593, 10, 19, NULL, 'Wednesday', '13:30:00', '14:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(594, 10, 24, NULL, 'Wednesday', '14:10:00', '14:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(595, 10, 21, 28, 'Wednesday', '14:30:00', '15:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-31 08:44:07'),
(596, 12, 22, NULL, 'Friday', '07:30:00', '08:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(597, 12, 17, NULL, 'Friday', '08:30:00', '09:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(598, 12, 20, NULL, 'Friday', '09:30:00', '10:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42');
INSERT INTO `class_schedules` (`id`, `ssy_id`, `subject_id`, `teacher_id`, `days`, `start_time`, `end_time`, `room`, `created_by`, `created_at`, `updated_at`) VALUES
(599, 12, 23, NULL, 'Friday', '11:00:00', '11:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(600, 12, 18, NULL, 'Friday', '12:00:00', '13:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(601, 12, 19, NULL, 'Friday', '13:30:00', '14:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(602, 12, 24, NULL, 'Friday', '14:10:00', '14:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(603, 12, 21, 36, 'Friday', '14:30:00', '15:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-31 08:44:08'),
(604, 12, 22, NULL, 'Monday', '07:30:00', '08:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(605, 12, 17, NULL, 'Monday', '08:30:00', '09:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(606, 12, 20, NULL, 'Monday', '09:30:00', '10:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(607, 12, 23, NULL, 'Monday', '11:00:00', '11:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(608, 12, 18, NULL, 'Monday', '12:00:00', '13:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(609, 12, 19, NULL, 'Monday', '13:30:00', '14:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(610, 12, 24, NULL, 'Monday', '14:10:00', '14:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(611, 12, 21, 36, 'Monday', '14:30:00', '15:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-31 08:44:08'),
(612, 12, 22, NULL, 'Thursday', '07:30:00', '08:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(613, 12, 17, NULL, 'Thursday', '08:30:00', '09:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(614, 12, 20, NULL, 'Thursday', '09:30:00', '10:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(615, 12, 23, NULL, 'Thursday', '11:00:00', '11:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(616, 12, 18, NULL, 'Thursday', '12:00:00', '13:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(617, 12, 19, NULL, 'Thursday', '13:30:00', '14:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(618, 12, 24, NULL, 'Thursday', '14:10:00', '14:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(619, 12, 21, 36, 'Thursday', '14:30:00', '15:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-31 08:44:08'),
(620, 12, 22, NULL, 'Tuesday', '07:30:00', '08:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(621, 12, 17, NULL, 'Tuesday', '08:30:00', '09:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(622, 12, 20, NULL, 'Tuesday', '09:30:00', '10:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(623, 12, 23, NULL, 'Tuesday', '11:00:00', '11:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(624, 12, 18, NULL, 'Tuesday', '12:00:00', '13:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(625, 12, 19, NULL, 'Tuesday', '13:30:00', '14:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(626, 12, 24, NULL, 'Tuesday', '14:10:00', '14:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(627, 12, 21, 36, 'Tuesday', '14:30:00', '15:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-31 08:44:08'),
(628, 12, 22, NULL, 'Wednesday', '07:30:00', '08:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(629, 12, 17, NULL, 'Wednesday', '08:30:00', '09:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(630, 12, 20, NULL, 'Wednesday', '09:30:00', '10:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(631, 12, 23, NULL, 'Wednesday', '11:00:00', '11:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(632, 12, 18, NULL, 'Wednesday', '12:00:00', '13:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(633, 12, 19, NULL, 'Wednesday', '13:30:00', '14:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(634, 12, 24, NULL, 'Wednesday', '14:10:00', '14:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(635, 12, 21, 36, 'Wednesday', '14:30:00', '15:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-31 08:44:08'),
(636, 11, 22, NULL, 'Friday', '07:30:00', '08:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(637, 11, 17, NULL, 'Friday', '08:30:00', '09:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(638, 11, 20, NULL, 'Friday', '09:30:00', '10:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(639, 11, 23, NULL, 'Friday', '11:00:00', '11:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(640, 11, 18, NULL, 'Friday', '12:00:00', '13:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(641, 11, 19, NULL, 'Friday', '13:30:00', '14:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(642, 11, 24, NULL, 'Friday', '14:10:00', '14:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(643, 11, 21, 8, 'Friday', '14:30:00', '15:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-31 08:44:09'),
(644, 11, 22, NULL, 'Monday', '07:30:00', '08:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(645, 11, 17, NULL, 'Monday', '08:30:00', '09:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(646, 11, 20, NULL, 'Monday', '09:30:00', '10:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(647, 11, 23, NULL, 'Monday', '11:00:00', '11:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(648, 11, 18, NULL, 'Monday', '12:00:00', '13:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(649, 11, 19, NULL, 'Monday', '13:30:00', '14:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(650, 11, 24, NULL, 'Monday', '14:10:00', '14:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(651, 11, 21, 8, 'Monday', '14:30:00', '15:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-31 08:44:09'),
(652, 11, 22, NULL, 'Thursday', '07:30:00', '08:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(653, 11, 17, NULL, 'Thursday', '08:30:00', '09:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(654, 11, 20, NULL, 'Thursday', '09:30:00', '10:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(655, 11, 23, NULL, 'Thursday', '11:00:00', '11:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(656, 11, 18, NULL, 'Thursday', '12:00:00', '13:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(657, 11, 19, NULL, 'Thursday', '13:30:00', '14:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(658, 11, 24, NULL, 'Thursday', '14:10:00', '14:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(659, 11, 21, 8, 'Thursday', '14:30:00', '15:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-31 08:44:09'),
(660, 11, 22, NULL, 'Tuesday', '07:30:00', '08:30:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(661, 11, 17, NULL, 'Tuesday', '08:30:00', '09:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(662, 11, 20, NULL, 'Tuesday', '09:30:00', '10:00:00', '110', 1, '2026-05-30 16:26:42', '2026-05-30 16:26:42'),
(663, 11, 23, NULL, 'Tuesday', '11:00:00', '11:30:00', '110', 1, '2026-05-30 16:26:43', '2026-05-30 16:26:43'),
(664, 11, 18, NULL, 'Tuesday', '12:00:00', '13:00:00', '110', 1, '2026-05-30 16:26:43', '2026-05-30 16:26:43'),
(665, 11, 19, NULL, 'Tuesday', '13:30:00', '14:00:00', '110', 1, '2026-05-30 16:26:43', '2026-05-30 16:26:43'),
(666, 11, 24, NULL, 'Tuesday', '14:10:00', '14:30:00', '110', 1, '2026-05-30 16:26:43', '2026-05-30 16:26:43'),
(667, 11, 21, 8, 'Tuesday', '14:30:00', '15:30:00', '110', 1, '2026-05-30 16:26:43', '2026-05-31 08:44:09'),
(668, 11, 22, NULL, 'Wednesday', '07:30:00', '08:30:00', '110', 1, '2026-05-30 16:26:43', '2026-05-30 16:26:43'),
(669, 11, 17, NULL, 'Wednesday', '08:30:00', '09:00:00', '110', 1, '2026-05-30 16:26:43', '2026-05-30 16:26:43'),
(670, 11, 20, NULL, 'Wednesday', '09:30:00', '10:00:00', '110', 1, '2026-05-30 16:26:43', '2026-05-30 16:26:43'),
(671, 11, 23, NULL, 'Wednesday', '11:00:00', '11:30:00', '110', 1, '2026-05-30 16:26:43', '2026-05-30 16:26:43'),
(672, 11, 18, NULL, 'Wednesday', '12:00:00', '13:00:00', '110', 1, '2026-05-30 16:26:43', '2026-05-30 16:26:43'),
(673, 11, 19, NULL, 'Wednesday', '13:30:00', '14:00:00', '110', 1, '2026-05-30 16:26:43', '2026-05-30 16:26:43'),
(674, 11, 24, NULL, 'Wednesday', '14:10:00', '14:30:00', '110', 1, '2026-05-30 16:26:43', '2026-05-30 16:26:43'),
(675, 11, 21, 8, 'Wednesday', '14:30:00', '15:30:00', '110', 1, '2026-05-30 16:26:43', '2026-05-31 08:44:09');

-- --------------------------------------------------------

--
-- Table structure for table `coordinators`
--

CREATE TABLE `coordinators` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL COMMENT 'FK → users.id',
  `first_name` varchar(100) NOT NULL,
  `middle_name` varchar(100) DEFAULT NULL,
  `last_name` varchar(100) NOT NULL,
  `full_name` varchar(200) DEFAULT NULL COMMENT 'Kept for display convenience',
  `employee_id` varchar(50) DEFAULT NULL COMMENT 'School employee number',
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `is_archived` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='One row per coordinator staff member';

--
-- Dumping data for table `coordinators`
--

INSERT INTO `coordinators` (`id`, `user_id`, `first_name`, `middle_name`, `last_name`, `full_name`, `employee_id`, `is_active`, `created_at`, `updated_at`, `is_archived`) VALUES
(1, 12, 'Sherwin', NULL, 'Galang', 'Sherwin Galang', 'EMP-67AE32', 1, '2026-05-19 07:58:19', '2026-05-21 18:43:04', 1),
(2, 13, 'Carlos', NULL, 'Michelle', 'Carlos Michelle', 'EMP-67AE33', 1, '2026-05-19 07:59:18', '2026-05-21 18:43:09', 1),
(3, 18, 'Felicitas', NULL, 'Gamuella', 'Felicitas Gamuella', 'EMP-67AE34', 1, '2026-05-21 17:56:28', '2026-05-21 18:43:53', 1),
(4, 21, 'Samonteza', NULL, 'Argoyle', 'Samonteza Argoyle', NULL, 1, '2026-05-21 18:44:54', '2026-05-21 18:44:54', 0),
(5, 465, 'Elena', NULL, 'Zabala', 'Elena Zabala', 'EMP-B10001', 1, '2026-05-25 00:00:00', '2026-05-25 00:00:00', 0),
(6, 466, 'Ronaldo', NULL, 'Ilagan', 'Ronaldo Ilagan', 'EMP-B10002', 1, '2026-05-25 00:00:00', '2026-05-25 00:00:00', 0),
(7, 467, 'Maricel', NULL, 'Jimenez', 'Maricel Jimenez', 'EMP-B10003', 1, '2026-05-25 00:00:00', '2026-05-25 00:00:00', 0),
(8, 468, 'Benedict', NULL, 'Ong', 'Benedict Ong', 'EMP-B10004', 1, '2026-05-25 00:00:00', '2026-05-25 00:00:00', 0),
(9, 469, 'Jessica', NULL, 'Bulan', 'Jessica Bulan', 'EMP-B10005', 1, '2026-05-25 00:00:00', '2026-05-25 00:00:00', 0),
(10, 470, 'Renato', NULL, 'Segovia', 'Renato Segovia', 'EMP-B10006', 1, '2026-05-25 00:00:00', '2026-05-25 00:00:00', 0),
(11, 471, 'Lorena', NULL, 'Yap', 'Lorena Yap', 'EMP-B10007', 1, '2026-05-25 00:00:00', '2026-05-25 00:00:00', 0);

-- --------------------------------------------------------

--
-- Table structure for table `coordinator_actions`
--

CREATE TABLE `coordinator_actions` (
  `id` int(11) NOT NULL,
  `grade_id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `ssy_id` int(11) NOT NULL,
  `subject_id` int(11) NOT NULL,
  `coordinator_id` int(11) NOT NULL,
  `action` enum('approved','revision_requested') NOT NULL,
  `comment` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `coordinator_actions`
--

INSERT INTO `coordinator_actions` (`id`, `grade_id`, `student_id`, `ssy_id`, `subject_id`, `coordinator_id`, `action`, `comment`, `created_at`) VALUES
(1, 1, 87, 5, 5, 4, 'approved', NULL, '2026-05-25 16:18:57'),
(2, 3, 47, 5, 5, 4, 'approved', NULL, '2026-05-25 16:18:57'),
(3, 4, 52, 5, 5, 4, 'approved', NULL, '2026-05-25 16:18:57'),
(4, 5, 27, 5, 5, 4, 'approved', NULL, '2026-05-25 16:18:57'),
(5, 6, 112, 5, 5, 4, 'approved', NULL, '2026-05-25 16:18:57'),
(6, 7, 32, 5, 5, 4, 'approved', NULL, '2026-05-25 16:18:57'),
(7, 8, 92, 5, 5, 4, 'approved', NULL, '2026-05-25 16:18:57'),
(8, 9, 67, 5, 5, 4, 'approved', NULL, '2026-05-25 16:18:57'),
(9, 10, 77, 5, 5, 4, 'approved', NULL, '2026-05-25 16:18:57'),
(10, 11, 22, 5, 5, 4, 'approved', NULL, '2026-05-25 16:18:57'),
(11, 12, 117, 5, 5, 4, 'approved', NULL, '2026-05-25 16:18:57'),
(12, 13, 42, 5, 5, 4, 'approved', NULL, '2026-05-25 16:18:57'),
(13, 14, 57, 5, 5, 4, 'approved', NULL, '2026-05-25 16:18:57'),
(14, 15, 62, 5, 5, 4, 'approved', NULL, '2026-05-25 16:18:57'),
(15, 16, 37, 5, 5, 4, 'approved', NULL, '2026-05-25 16:18:58'),
(16, 17, 82, 5, 5, 4, 'approved', NULL, '2026-05-25 16:18:58'),
(17, 18, 97, 5, 5, 4, 'approved', NULL, '2026-05-25 16:18:58'),
(18, 19, 102, 5, 5, 4, 'approved', NULL, '2026-05-25 16:18:58'),
(19, 20, 107, 5, 5, 4, 'approved', NULL, '2026-05-25 16:18:58'),
(20, 21, 72, 5, 5, 4, 'approved', NULL, '2026-05-25 16:18:58'),
(21, 62, 99, 2, 5, 4, 'approved', NULL, '2026-05-25 16:19:08'),
(22, 63, 79, 2, 5, 4, 'approved', NULL, '2026-05-25 16:19:08'),
(23, 64, 24, 2, 5, 4, 'approved', NULL, '2026-05-25 16:19:08'),
(24, 65, 59, 2, 5, 4, 'approved', NULL, '2026-05-25 16:19:08'),
(25, 66, 69, 2, 5, 4, 'approved', NULL, '2026-05-25 16:19:08'),
(26, 67, 44, 2, 5, 4, 'approved', NULL, '2026-05-25 16:19:08'),
(27, 68, 39, 2, 5, 4, 'approved', NULL, '2026-05-25 16:19:08'),
(28, 69, 109, 2, 5, 4, 'approved', NULL, '2026-05-25 16:19:08'),
(29, 70, 114, 2, 5, 4, 'approved', NULL, '2026-05-25 16:19:08'),
(30, 71, 104, 2, 5, 4, 'approved', NULL, '2026-05-25 16:19:08'),
(31, 72, 64, 2, 5, 4, 'approved', NULL, '2026-05-25 16:19:08'),
(32, 73, 49, 2, 5, 4, 'approved', NULL, '2026-05-25 16:19:08'),
(33, 74, 74, 2, 5, 4, 'approved', NULL, '2026-05-25 16:19:08'),
(34, 75, 89, 2, 5, 4, 'approved', NULL, '2026-05-25 16:19:08'),
(35, 76, 19, 2, 5, 4, 'approved', NULL, '2026-05-25 16:19:08'),
(36, 77, 29, 2, 5, 4, 'approved', NULL, '2026-05-25 16:19:08'),
(37, 78, 54, 2, 5, 4, 'approved', NULL, '2026-05-25 16:19:08'),
(38, 79, 34, 2, 5, 4, 'approved', NULL, '2026-05-25 16:19:08'),
(39, 80, 94, 2, 5, 4, 'approved', NULL, '2026-05-25 16:19:08'),
(40, 81, 84, 2, 5, 4, 'approved', NULL, '2026-05-25 16:19:08'),
(41, 104, 418, 1, 5, 4, 'approved', NULL, '2026-05-25 18:34:29'),
(42, 102, 45, 1, 5, 4, 'revision_requested', NULL, '2026-05-25 18:34:54'),
(43, 103, 87, 1, 5, 4, 'revision_requested', NULL, '2026-05-25 18:34:54'),
(44, 104, 418, 1, 5, 4, 'approved', NULL, '2026-05-25 19:08:28'),
(45, 103, 87, 1, 5, 4, 'revision_requested', NULL, '2026-05-25 19:08:30'),
(46, 102, 45, 1, 5, 4, 'revision_requested', NULL, '2026-05-25 19:08:31'),
(47, 102, 45, 1, 5, 4, 'approved', NULL, '2026-05-25 19:59:26'),
(48, 103, 87, 1, 5, 4, 'approved', NULL, '2026-05-25 19:59:27'),
(49, 102, 45, 1, 5, 4, 'approved', NULL, '2026-05-25 20:27:54'),
(50, 103, 87, 1, 5, 4, 'approved', NULL, '2026-05-25 20:27:54'),
(51, 104, 418, 1, 5, 4, 'approved', NULL, '2026-05-25 20:27:54'),
(52, 104, 418, 1, 5, 4, 'approved', NULL, '2026-05-25 20:39:22'),
(53, 104, 418, 1, 5, 4, 'revision_requested', NULL, '2026-05-25 20:49:03'),
(54, 104, 418, 1, 5, 4, 'approved', NULL, '2026-05-25 20:51:04'),
(55, 144, 419, 8, 13, 4, 'approved', NULL, '2026-05-31 10:32:50'),
(56, 126, 207, 8, 13, 4, 'approved', NULL, '2026-05-31 11:13:22'),
(57, 127, 130, 8, 13, 4, 'approved', NULL, '2026-05-31 11:13:22'),
(58, 128, 152, 8, 13, 4, 'approved', NULL, '2026-05-31 11:13:22'),
(59, 129, 138, 8, 13, 4, 'approved', NULL, '2026-05-31 11:13:22'),
(60, 130, 203, 8, 13, 4, 'approved', NULL, '2026-05-31 11:13:22'),
(61, 131, 146, 8, 13, 4, 'approved', NULL, '2026-05-31 11:13:22'),
(62, 132, 186, 8, 13, 4, 'approved', NULL, '2026-05-31 11:13:22'),
(63, 133, 178, 8, 13, 4, 'approved', NULL, '2026-05-31 11:13:22'),
(64, 134, 187, 8, 13, 4, 'approved', NULL, '2026-05-31 11:13:22'),
(65, 135, 153, 8, 13, 4, 'approved', NULL, '2026-05-31 11:13:22'),
(66, 136, 174, 8, 13, 4, 'approved', NULL, '2026-05-31 11:13:22'),
(67, 137, 196, 8, 13, 4, 'approved', NULL, '2026-05-31 11:13:22'),
(68, 138, 179, 8, 13, 4, 'approved', NULL, '2026-05-31 11:13:22'),
(69, 139, 169, 8, 13, 4, 'approved', NULL, '2026-05-31 11:13:22'),
(70, 140, 198, 8, 13, 4, 'approved', NULL, '2026-05-31 11:13:22'),
(71, 141, 181, 8, 13, 4, 'approved', NULL, '2026-05-31 11:13:22'),
(72, 142, 159, 8, 13, 4, 'approved', NULL, '2026-05-31 11:13:22'),
(73, 143, 191, 8, 13, 4, 'approved', NULL, '2026-05-31 11:13:22'),
(74, 1, 87, 5, 5, 4, 'approved', NULL, '2026-05-31 20:50:09'),
(75, 3, 47, 5, 5, 4, 'approved', NULL, '2026-05-31 20:50:09'),
(76, 4, 52, 5, 5, 4, 'approved', NULL, '2026-05-31 20:50:09'),
(77, 5, 27, 5, 5, 4, 'approved', NULL, '2026-05-31 20:50:09'),
(78, 6, 112, 5, 5, 4, 'approved', NULL, '2026-05-31 20:50:09'),
(79, 7, 32, 5, 5, 4, 'approved', NULL, '2026-05-31 20:50:09'),
(80, 8, 92, 5, 5, 4, 'approved', NULL, '2026-05-31 20:50:09'),
(81, 9, 67, 5, 5, 4, 'approved', NULL, '2026-05-31 20:50:09'),
(82, 10, 77, 5, 5, 4, 'approved', NULL, '2026-05-31 20:50:09'),
(83, 11, 22, 5, 5, 4, 'approved', NULL, '2026-05-31 20:50:09'),
(84, 12, 117, 5, 5, 4, 'revision_requested', NULL, '2026-05-31 20:50:14'),
(85, 13, 42, 5, 5, 4, 'revision_requested', NULL, '2026-05-31 20:50:14'),
(86, 14, 57, 5, 5, 4, 'revision_requested', NULL, '2026-05-31 20:50:14'),
(87, 15, 62, 5, 5, 4, 'revision_requested', NULL, '2026-05-31 20:50:14'),
(88, 16, 37, 5, 5, 4, 'revision_requested', NULL, '2026-05-31 20:50:14'),
(89, 17, 82, 5, 5, 4, 'revision_requested', NULL, '2026-05-31 20:50:14'),
(90, 18, 97, 5, 5, 4, 'revision_requested', NULL, '2026-05-31 20:50:14'),
(91, 19, 102, 5, 5, 4, 'revision_requested', NULL, '2026-05-31 20:50:14'),
(92, 183, 48, 5, 5, 4, 'revision_requested', NULL, '2026-05-31 20:50:14'),
(93, 190, 40, 5, 5, 4, 'revision_requested', NULL, '2026-05-31 20:50:14'),
(94, 184, 60, 5, 5, 4, 'revision_requested', NULL, '2026-05-31 20:50:14'),
(95, 185, 423, 5, 5, 4, 'revision_requested', NULL, '2026-05-31 20:50:14'),
(96, 20, 107, 5, 5, 4, 'revision_requested', NULL, '2026-05-31 20:50:14'),
(97, 21, 72, 5, 5, 4, 'revision_requested', NULL, '2026-05-31 20:50:14'),
(98, 186, 75, 5, 5, 4, 'revision_requested', NULL, '2026-05-31 20:50:14'),
(99, 187, 94, 5, 5, 4, 'revision_requested', NULL, '2026-05-31 20:50:14'),
(100, 188, 84, 5, 5, 4, 'revision_requested', NULL, '2026-05-31 20:50:14'),
(101, 18, 97, 5, 5, 4, 'approved', NULL, '2026-05-31 21:07:43'),
(102, 183, 48, 5, 5, 4, 'approved', NULL, '2026-05-31 21:07:43'),
(103, 190, 40, 5, 5, 4, 'approved', NULL, '2026-05-31 21:07:43'),
(104, 184, 60, 5, 5, 4, 'approved', NULL, '2026-05-31 21:07:43'),
(105, 185, 423, 5, 5, 4, 'approved', NULL, '2026-05-31 21:07:43'),
(106, 186, 75, 5, 5, 4, 'approved', NULL, '2026-05-31 21:07:43'),
(107, 187, 94, 5, 5, 4, 'approved', NULL, '2026-05-31 21:07:43'),
(108, 188, 84, 5, 5, 4, 'approved', NULL, '2026-05-31 21:07:43'),
(109, 221, 424, 8, 13, 4, 'approved', NULL, '2026-06-01 00:06:42');

-- --------------------------------------------------------

--
-- Table structure for table `coordinator_assignment_logs`
--

CREATE TABLE `coordinator_assignment_logs` (
  `id` int(11) NOT NULL,
  `curriculum_id` int(11) NOT NULL COMMENT 'FK → curriculum.id',
  `old_coordinator` int(11) DEFAULT NULL COMMENT 'FK → coordinators.id (previous)',
  `new_coordinator` int(11) DEFAULT NULL COMMENT 'FK → coordinators.id (new)',
  `changed_by` int(11) DEFAULT NULL COMMENT 'FK → principals.id',
  `note` varchar(500) DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Immutable log of every coordinator assignment/re-assignment by the Principal';

--
-- Dumping data for table `coordinator_assignment_logs`
--

INSERT INTO `coordinator_assignment_logs` (`id`, `curriculum_id`, `old_coordinator`, `new_coordinator`, `changed_by`, `note`, `ip_address`, `created_at`) VALUES
(1, 1, NULL, 1, 1, NULL, '::1', '2026-05-19 07:58:41'),
(2, 9, NULL, 1, 1, NULL, '::1', '2026-05-19 07:58:41'),
(3, 17, NULL, 1, 1, NULL, '::1', '2026-05-19 07:58:41'),
(4, 36, NULL, 1, 1, NULL, '::1', '2026-05-19 07:58:41'),
(5, 2, NULL, 2, 1, NULL, '::1', '2026-05-19 07:59:30'),
(6, 10, NULL, 2, 1, NULL, '::1', '2026-05-19 07:59:30'),
(7, 18, NULL, 2, 1, NULL, '::1', '2026-05-19 07:59:30'),
(8, 26, NULL, 2, 1, NULL, '::1', '2026-05-19 07:59:30'),
(9, 1, 1, NULL, 2, NULL, '::1', '2026-05-21 18:00:14'),
(10, 9, 1, NULL, 2, NULL, '::1', '2026-05-21 18:00:14'),
(11, 17, 1, NULL, 2, NULL, '::1', '2026-05-21 18:00:14'),
(12, 36, 1, NULL, 2, NULL, '::1', '2026-05-21 18:00:14'),
(13, 2, 2, NULL, 2, NULL, '::1', '2026-05-21 18:00:17'),
(14, 10, 2, NULL, 2, NULL, '::1', '2026-05-21 18:00:17'),
(15, 18, 2, NULL, 2, NULL, '::1', '2026-05-21 18:00:17'),
(16, 26, 2, NULL, 2, NULL, '::1', '2026-05-21 18:00:17'),
(17, 1, NULL, 3, 2, NULL, '::1', '2026-05-21 18:03:16'),
(18, 9, NULL, 3, 2, NULL, '::1', '2026-05-21 18:03:16'),
(19, 17, NULL, 3, 2, NULL, '::1', '2026-05-21 18:03:16'),
(20, 36, NULL, 3, 2, NULL, '::1', '2026-05-21 18:03:16'),
(21, 1, 3, NULL, 2, NULL, '::1', '2026-05-21 18:04:13'),
(22, 9, 3, NULL, 2, NULL, '::1', '2026-05-21 18:04:13'),
(23, 17, 3, NULL, 2, NULL, '::1', '2026-05-21 18:04:13'),
(24, 36, 3, NULL, 2, NULL, '::1', '2026-05-21 18:04:13'),
(25, 8, NULL, 3, 2, NULL, '::1', '2026-05-21 18:04:16'),
(26, 16, NULL, 3, 2, NULL, '::1', '2026-05-21 18:04:16'),
(27, 24, NULL, 3, 2, NULL, '::1', '2026-05-21 18:04:16'),
(28, 29, NULL, 3, 2, NULL, '::1', '2026-05-21 18:04:16'),
(29, 8, 3, 4, 3, NULL, '::1', '2026-05-21 18:49:35'),
(30, 16, 3, 4, 3, NULL, '::1', '2026-05-21 18:49:35'),
(31, 24, 3, 4, 3, NULL, '::1', '2026-05-21 18:49:35'),
(32, 29, 3, 4, 3, NULL, '::1', '2026-05-21 18:49:35'),
(33, 1, NULL, 9, 3, NULL, '::1', '2026-05-25 16:17:30'),
(34, 9, NULL, 9, 3, NULL, '::1', '2026-05-25 16:17:30'),
(35, 17, NULL, 9, 3, NULL, '::1', '2026-05-25 16:17:30'),
(36, 36, NULL, 9, 3, NULL, '::1', '2026-05-25 16:17:30'),
(37, 2, NULL, 6, 3, NULL, '::1', '2026-05-25 16:17:34'),
(38, 10, NULL, 6, 3, NULL, '::1', '2026-05-25 16:17:34'),
(39, 18, NULL, 6, 3, NULL, '::1', '2026-05-25 16:17:34'),
(40, 26, NULL, 6, 3, NULL, '::1', '2026-05-25 16:17:34'),
(41, 3, NULL, 5, 3, NULL, '::1', '2026-05-25 16:17:40'),
(42, 11, NULL, 5, 3, NULL, '::1', '2026-05-25 16:17:40'),
(43, 19, NULL, 5, 3, NULL, '::1', '2026-05-25 16:17:40'),
(44, 27, NULL, 5, 3, NULL, '::1', '2026-05-25 16:17:40'),
(45, 4, NULL, 11, 3, NULL, '::1', '2026-05-25 16:17:43'),
(46, 12, NULL, 11, 3, NULL, '::1', '2026-05-25 16:17:43'),
(47, 20, NULL, 11, 3, NULL, '::1', '2026-05-25 16:17:43'),
(48, 28, NULL, 11, 3, NULL, '::1', '2026-05-25 16:17:43'),
(49, 5, NULL, 10, 3, NULL, '::1', '2026-05-25 16:17:46'),
(50, 13, NULL, 10, 3, NULL, '::1', '2026-05-25 16:17:46'),
(51, 21, NULL, 10, 3, NULL, '::1', '2026-05-25 16:17:46'),
(52, 32, NULL, 10, 3, NULL, '::1', '2026-05-25 16:17:46'),
(53, 6, NULL, 8, 3, NULL, '::1', '2026-05-25 16:17:51'),
(54, 14, NULL, 8, 3, NULL, '::1', '2026-05-25 16:17:51'),
(55, 22, NULL, 8, 3, NULL, '::1', '2026-05-25 16:17:51'),
(56, 31, NULL, 8, 3, NULL, '::1', '2026-05-25 16:17:51'),
(57, 7, NULL, 7, 3, NULL, '::1', '2026-05-25 16:18:01'),
(58, 15, NULL, 7, 3, NULL, '::1', '2026-05-25 16:18:01'),
(59, 23, NULL, 7, 3, NULL, '::1', '2026-05-25 16:18:01'),
(60, 30, NULL, 7, 3, NULL, '::1', '2026-05-25 16:18:01');

-- --------------------------------------------------------

--
-- Table structure for table `curriculum`
--

CREATE TABLE `curriculum` (
  `id` int(11) NOT NULL,
  `school_year_id` int(11) NOT NULL,
  `grade_level_id` int(11) NOT NULL,
  `subject_id` int(11) NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_by` int(11) NOT NULL COMMENT 'FK → admins.id',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `coordinator_id` int(11) DEFAULT NULL COMMENT 'FK → coordinators.id — assigned by Principal; one per curriculum entry',
  `assigned_by` int(11) DEFAULT NULL COMMENT 'FK → principals.id — who made the assignment',
  `assigned_at` datetime DEFAULT NULL COMMENT 'Timestamp of last assignment change'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `curriculum`
--

INSERT INTO `curriculum` (`id`, `school_year_id`, `grade_level_id`, `subject_id`, `is_active`, `created_by`, `created_at`, `updated_at`, `coordinator_id`, `assigned_by`, `assigned_at`) VALUES
(2, 1, 7, 1, 1, 1, '2026-05-16 20:02:01', '2026-05-25 16:17:34', 6, 3, '2026-05-26 00:17:34'),
(3, 1, 7, 4, 1, 1, '2026-05-16 20:02:02', '2026-05-25 16:17:40', 5, 3, '2026-05-26 00:17:40'),
(4, 1, 7, 7, 1, 1, '2026-05-16 20:02:03', '2026-05-25 16:17:43', 11, 3, '2026-05-26 00:17:43'),
(5, 1, 7, 2, 1, 1, '2026-05-16 20:02:03', '2026-05-25 16:17:46', 10, 3, '2026-05-26 00:17:46'),
(6, 1, 7, 3, 1, 1, '2026-05-16 20:02:04', '2026-05-25 16:17:51', 8, 3, '2026-05-26 00:17:51'),
(7, 1, 7, 8, 1, 1, '2026-05-16 20:02:04', '2026-05-25 16:18:01', 7, 3, '2026-05-26 00:18:01'),
(8, 1, 7, 5, 1, 1, '2026-05-16 20:02:07', '2026-05-21 18:49:35', 4, 3, '2026-05-22 02:49:35'),
(9, 1, 8, 14, 1, 1, '2026-05-16 20:02:08', '2026-05-25 16:17:30', 9, 3, '2026-05-26 00:17:30'),
(10, 1, 8, 9, 1, 1, '2026-05-16 20:02:08', '2026-05-25 16:17:34', 6, 3, '2026-05-26 00:17:34'),
(11, 1, 8, 12, 1, 1, '2026-05-16 20:02:08', '2026-05-25 16:17:40', 5, 3, '2026-05-26 00:17:40'),
(12, 1, 8, 15, 1, 1, '2026-05-16 20:02:09', '2026-05-25 16:17:43', 11, 3, '2026-05-26 00:17:43'),
(13, 1, 8, 10, 1, 1, '2026-05-16 20:02:09', '2026-05-25 16:17:46', 10, 3, '2026-05-26 00:17:46'),
(14, 1, 8, 11, 1, 1, '2026-05-16 20:02:11', '2026-05-25 16:17:51', 8, 3, '2026-05-26 00:17:51'),
(15, 1, 8, 16, 1, 1, '2026-05-16 20:02:11', '2026-05-25 16:18:01', 7, 3, '2026-05-26 00:18:01'),
(16, 1, 8, 13, 1, 1, '2026-05-16 20:02:13', '2026-05-21 18:49:35', 4, 3, '2026-05-22 02:49:35'),
(17, 1, 9, 22, 1, 1, '2026-05-16 20:02:15', '2026-05-25 16:17:30', 9, 3, '2026-05-26 00:17:30'),
(18, 1, 9, 17, 1, 1, '2026-05-16 20:02:15', '2026-05-25 16:17:34', 6, 3, '2026-05-26 00:17:34'),
(19, 1, 9, 20, 1, 1, '2026-05-16 20:02:16', '2026-05-25 16:17:40', 5, 3, '2026-05-26 00:17:40'),
(20, 1, 9, 23, 1, 1, '2026-05-16 20:02:16', '2026-05-25 16:17:43', 11, 3, '2026-05-26 00:17:43'),
(21, 1, 9, 18, 1, 1, '2026-05-16 20:02:17', '2026-05-25 16:17:46', 10, 3, '2026-05-26 00:17:46'),
(22, 1, 9, 19, 1, 1, '2026-05-16 20:02:18', '2026-05-25 16:17:51', 8, 3, '2026-05-26 00:17:51'),
(23, 1, 9, 24, 1, 1, '2026-05-16 20:02:19', '2026-05-25 16:18:01', 7, 3, '2026-05-26 00:18:01'),
(24, 1, 9, 21, 1, 1, '2026-05-16 20:02:20', '2026-05-21 18:49:35', 4, 3, '2026-05-22 02:49:35'),
(26, 1, 10, 25, 1, 1, '2026-05-16 20:02:24', '2026-05-25 16:17:34', 6, 3, '2026-05-26 00:17:34'),
(27, 1, 10, 28, 1, 1, '2026-05-16 20:02:25', '2026-05-25 16:17:40', 5, 3, '2026-05-26 00:17:40'),
(28, 1, 10, 34, 1, 1, '2026-05-16 20:02:25', '2026-05-25 16:17:43', 11, 3, '2026-05-26 00:17:43'),
(29, 1, 10, 32, 1, 1, '2026-05-16 20:02:29', '2026-05-21 18:49:35', 4, 3, '2026-05-22 02:49:35'),
(30, 1, 10, 35, 1, 1, '2026-05-16 20:02:29', '2026-05-25 16:18:01', 7, 3, '2026-05-26 00:18:01'),
(31, 1, 10, 27, 1, 1, '2026-05-16 20:02:30', '2026-05-25 16:17:51', 8, 3, '2026-05-26 00:17:51'),
(32, 1, 10, 26, 1, 1, '2026-05-16 20:02:32', '2026-05-25 16:17:46', 10, 3, '2026-05-26 00:17:46'),
(36, 1, 10, 33, 1, 1, '2026-05-16 20:02:40', '2026-05-25 16:17:30', 9, 3, '2026-05-26 00:17:30'),
(39, 1, 7, 6, 1, 1, '2026-05-31 06:02:36', '2026-05-31 06:02:36', NULL, NULL, NULL);

-- --------------------------------------------------------

--
-- Table structure for table `enrollments`
--

CREATE TABLE `enrollments` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL COMMENT 'FK → students.id',
  `school_year_id` int(11) NOT NULL COMMENT 'FK → school_years.id',
  `grade_level_id` int(11) NOT NULL COMMENT 'FK → grade_levels.id',
  `section_sy_id` int(11) DEFAULT NULL COMMENT 'FK → section_school_years.id — assigned section',
  `status` enum('pending','registered','enrolled','unregistered','archived') NOT NULL DEFAULT 'pending',
  `enrollment_type` enum('new','transferee','returning') NOT NULL DEFAULT 'new',
  `processed_by` int(11) DEFAULT NULL COMMENT 'FK → registrars.id',
  `processed_at` datetime DEFAULT NULL,
  `notes` text DEFAULT NULL,
  `unregistered_reason` varchar(500) DEFAULT NULL COMMENT 'Reason supplied by registrar when setting status = unregistered',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='One enrollment record per student per school year — the canonical status source';

--
-- Dumping data for table `enrollments`
--

INSERT INTO `enrollments` (`id`, `student_id`, `school_year_id`, `grade_level_id`, `section_sy_id`, `status`, `enrollment_type`, `processed_by`, `processed_at`, `notes`, `unregistered_reason`, `created_at`, `updated_at`) VALUES
(1, 9, 1, 8, NULL, 'enrolled', 'new', NULL, '2026-05-19 16:51:10', NULL, NULL, '2026-05-19 08:50:01', '2026-05-19 08:51:10'),
(2, 10, 1, 7, NULL, 'registered', 'new', NULL, NULL, NULL, NULL, '2026-05-19 08:50:01', '2026-05-19 08:50:01'),
(3, 7, 1, 7, NULL, 'registered', 'new', 1, '2026-05-21 17:02:40', NULL, NULL, '2026-05-21 09:02:40', '2026-05-21 09:02:40'),
(4, 14, 1, 8, NULL, 'registered', 'new', 1, '2026-05-21 18:06:23', NULL, NULL, '2026-05-21 10:06:23', '2026-05-21 10:06:23'),
(6, 16, 1, 7, NULL, 'registered', 'new', 1, '2026-05-22 15:30:50', NULL, NULL, '2026-05-22 07:30:50', '2026-05-22 07:30:50'),
(7, 15, 1, 7, NULL, 'pending', 'new', 1, '2026-05-24 09:40:31', NULL, 'Test', '2026-05-24 01:33:55', '2026-05-24 01:40:31'),
(8, 17, 1, 10, 17, 'enrolled', 'new', NULL, '2026-05-25 00:19:11', NULL, NULL, '2026-05-24 07:23:04', '2026-05-31 15:18:20'),
(9, 18, 1, 7, 4, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:33'),
(10, 19, 1, 7, 2, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(11, 20, 1, 7, 3, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:15:57'),
(12, 21, 1, 7, NULL, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 20:28:10'),
(13, 22, 1, 7, 2, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:06'),
(14, 23, 1, 7, 2, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:06'),
(15, 24, 1, 7, 3, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:15:57'),
(16, 25, 1, 7, 2, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:06'),
(17, 26, 1, 7, 2, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:06'),
(18, 27, 1, 7, NULL, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 18:30:59'),
(19, 28, 1, 7, 1, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(20, 29, 1, 7, 4, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:33'),
(21, 30, 1, 7, 3, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(22, 31, 1, 7, 3, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:15:57'),
(23, 32, 1, 7, 3, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:15:57'),
(24, 33, 1, 7, 3, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:15:57'),
(25, 34, 1, 7, 4, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:33'),
(26, 35, 1, 7, 3, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(27, 36, 1, 7, NULL, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 20:28:10'),
(28, 37, 1, 7, 1, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:22'),
(29, 38, 1, 7, 2, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:06'),
(30, 39, 1, 7, 3, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:15:57'),
(31, 40, 1, 7, 5, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 20:31:30'),
(32, 41, 1, 7, 1, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:22'),
(33, 42, 1, 7, 1, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:22'),
(34, 43, 1, 7, 2, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:06'),
(35, 44, 1, 7, 3, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:15:57'),
(36, 45, 1, 7, 1, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 18:32:29'),
(37, 46, 1, 7, 3, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:15:57'),
(38, 47, 1, 7, NULL, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 20:28:10'),
(39, 48, 1, 7, 5, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 20:31:30'),
(40, 49, 1, 7, 1, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:22'),
(41, 50, 1, 7, 2, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:06'),
(42, 51, 1, 7, 4, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(43, 52, 1, 7, 2, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:06'),
(44, 53, 1, 7, 3, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:15:57'),
(45, 54, 1, 7, 4, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:33'),
(46, 55, 1, 7, 3, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(47, 56, 1, 7, 2, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:06'),
(48, 57, 1, 7, 1, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:22'),
(49, 58, 1, 7, 4, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:33'),
(50, 59, 1, 7, 3, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:15:57'),
(51, 60, 1, 7, 5, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 20:31:30'),
(52, 61, 1, 7, NULL, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 18:30:59'),
(53, 62, 1, 7, 1, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:22'),
(54, 63, 1, 7, 2, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:06'),
(55, 64, 1, 7, 2, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(56, 65, 1, 7, 4, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:33'),
(57, 66, 1, 7, 3, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:15:57'),
(58, 67, 1, 7, 5, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(59, 68, 1, 7, 3, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:15:57'),
(60, 69, 1, 7, 3, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:15:57'),
(61, 70, 1, 7, 2, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:06'),
(62, 71, 1, 7, NULL, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 20:28:10'),
(63, 72, 1, 7, 4, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:33'),
(64, 73, 1, 7, NULL, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 20:28:10'),
(65, 74, 1, 7, 1, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:22'),
(66, 75, 1, 7, 5, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 20:31:30'),
(67, 76, 1, 7, 1, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:22'),
(68, 77, 1, 7, 2, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:06'),
(69, 78, 1, 7, 2, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:06'),
(70, 79, 1, 7, 3, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:15:57'),
(71, 80, 1, 7, NULL, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 20:28:10'),
(72, 81, 1, 7, 1, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:22'),
(73, 82, 1, 7, 1, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:22'),
(74, 83, 1, 7, 1, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(75, 84, 1, 7, 5, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 20:31:30'),
(76, 85, 1, 7, 1, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:22'),
(77, 86, 1, 7, 1, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:22'),
(78, 87, 1, 7, 1, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 18:32:29'),
(79, 88, 1, 7, 1, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(80, 89, 1, 7, 2, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(81, 90, 1, 7, 3, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(82, 91, 1, 7, 4, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(83, 92, 1, 7, 3, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:15:57'),
(84, 93, 1, 7, 2, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:06'),
(85, 94, 1, 7, 5, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 20:31:30'),
(86, 95, 1, 7, NULL, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 20:28:10'),
(87, 96, 1, 7, NULL, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 20:28:10'),
(88, 97, 1, 7, 5, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(89, 98, 1, 7, 4, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:33'),
(90, 99, 1, 7, NULL, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 20:28:10'),
(91, 100, 1, 7, 4, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:33'),
(92, 101, 1, 7, 3, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:15:57'),
(93, 102, 1, 7, NULL, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 20:37:20'),
(94, 103, 1, 7, 4, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:33'),
(95, 104, 1, 7, 2, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(96, 105, 1, 7, NULL, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 20:28:10'),
(97, 106, 1, 7, 1, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:22'),
(98, 107, 1, 7, 4, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:33'),
(99, 108, 1, 7, 1, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(100, 109, 1, 7, 2, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(101, 110, 1, 7, 2, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:06'),
(102, 111, 1, 7, 3, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:15:57'),
(103, 112, 1, 7, 3, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:15:57'),
(104, 113, 1, 7, 1, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(105, 114, 1, 7, 2, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(106, 115, 1, 7, 1, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:22'),
(107, 116, 1, 7, 4, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(108, 117, 1, 7, 2, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:06'),
(109, 118, 1, 8, 9, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:45'),
(110, 119, 1, 8, 7, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(111, 120, 1, 8, 6, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:01'),
(112, 121, 1, 8, 9, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(113, 122, 1, 8, 9, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:45'),
(114, 123, 1, 8, 7, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(115, 124, 1, 8, 6, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:01'),
(116, 125, 1, 8, 9, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(117, 126, 1, 8, 6, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(118, 127, 1, 8, 7, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(119, 128, 1, 8, 8, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(120, 129, 1, 8, 7, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:53'),
(121, 130, 1, 8, 8, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 08:49:53'),
(122, 131, 1, 8, 9, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:45'),
(123, 132, 1, 8, 8, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(124, 133, 1, 8, 6, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:01'),
(125, 134, 1, 8, 9, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:45'),
(126, 135, 1, 8, 7, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(127, 136, 1, 8, 7, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:53'),
(128, 137, 1, 8, 7, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:53'),
(129, 138, 1, 8, 8, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 08:49:53'),
(130, 139, 1, 8, 7, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(131, 140, 1, 8, 6, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:01'),
(132, 141, 1, 8, 6, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:01'),
(133, 142, 1, 8, 9, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:45'),
(134, 143, 1, 8, 7, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(135, 144, 1, 8, 7, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:53'),
(136, 145, 1, 8, 9, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(137, 146, 1, 8, 8, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 08:49:53'),
(138, 147, 1, 8, 7, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(139, 148, 1, 8, 9, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:45'),
(140, 149, 1, 8, 7, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:53'),
(141, 150, 1, 8, 7, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:53'),
(142, 151, 1, 8, 7, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(143, 152, 1, 8, 8, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(144, 153, 1, 8, 8, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 08:49:53'),
(145, 154, 1, 8, 6, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(146, 155, 1, 8, 7, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(147, 156, 1, 8, 9, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:45'),
(148, 157, 1, 8, 9, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(149, 158, 1, 8, 7, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:53'),
(150, 159, 1, 8, 8, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 08:49:53'),
(151, 160, 1, 8, 6, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:01'),
(152, 161, 1, 8, 9, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(153, 162, 1, 8, 9, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:45'),
(154, 163, 1, 8, 6, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:01'),
(155, 164, 1, 8, 8, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(156, 165, 1, 8, 6, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:01'),
(157, 166, 1, 8, 6, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(158, 167, 1, 8, 7, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(159, 168, 1, 8, 6, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:01'),
(160, 169, 1, 8, 8, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 08:49:53'),
(161, 170, 1, 8, 7, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:53'),
(162, 171, 1, 8, 6, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:01'),
(163, 172, 1, 8, 9, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:45'),
(164, 173, 1, 8, 7, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:53'),
(165, 174, 1, 8, 8, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 08:49:53'),
(166, 175, 1, 8, 9, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:45'),
(167, 176, 1, 8, 6, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:01'),
(168, 177, 1, 8, 7, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:53'),
(169, 178, 1, 8, 8, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 08:49:53'),
(170, 179, 1, 8, 8, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 08:49:53'),
(171, 180, 1, 8, 9, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:45'),
(172, 181, 1, 8, 8, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 08:49:53'),
(173, 182, 1, 8, 6, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(174, 183, 1, 8, 9, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:45'),
(175, 184, 1, 8, 9, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:45'),
(176, 185, 1, 8, 9, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(177, 186, 1, 8, 8, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 08:49:53'),
(178, 187, 1, 8, 8, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 08:49:53'),
(179, 188, 1, 8, 7, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:53'),
(180, 189, 1, 8, 9, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(181, 190, 1, 8, 9, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:45'),
(182, 191, 1, 8, 8, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 08:49:53'),
(183, 192, 1, 8, 8, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(184, 193, 1, 8, 7, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:53'),
(185, 194, 1, 8, 6, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(186, 195, 1, 8, 6, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:01'),
(187, 196, 1, 8, 8, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(188, 197, 1, 8, 9, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(189, 198, 1, 8, 8, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 08:49:53'),
(190, 199, 1, 8, 9, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:45'),
(191, 200, 1, 8, 7, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:53'),
(192, 201, 1, 8, 6, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:01'),
(193, 202, 1, 8, 6, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(194, 203, 1, 8, 8, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 08:49:53'),
(195, 204, 1, 8, 8, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(196, 205, 1, 8, 7, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:53'),
(197, 206, 1, 8, 9, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:45'),
(198, 207, 1, 8, 8, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 08:49:53'),
(199, 208, 1, 8, 6, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:01'),
(200, 209, 1, 8, 6, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:01'),
(201, 210, 1, 8, 6, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(202, 211, 1, 8, 7, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(203, 212, 1, 8, 9, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:16:45'),
(204, 213, 1, 8, 6, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:01'),
(205, 214, 1, 8, 6, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(206, 215, 1, 8, 6, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:01'),
(207, 216, 1, 8, 8, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(208, 217, 1, 8, 6, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:01'),
(209, 218, 1, 9, 13, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:08'),
(210, 219, 1, 9, 10, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:45'),
(211, 220, 1, 9, 12, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(212, 221, 1, 9, 13, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(213, 222, 1, 9, 11, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:22'),
(214, 223, 1, 9, 11, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(215, 224, 1, 9, 11, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:22'),
(216, 225, 1, 9, 13, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(217, 226, 1, 9, 10, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(218, 227, 1, 9, 11, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(219, 228, 1, 9, 11, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:22'),
(220, 229, 1, 9, 11, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:22'),
(221, 230, 1, 9, 13, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:08'),
(222, 231, 1, 9, 13, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:08'),
(223, 232, 1, 9, 12, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(224, 233, 1, 9, 11, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:22'),
(225, 234, 1, 9, 11, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:22'),
(226, 235, 1, 9, 11, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(227, 236, 1, 9, 11, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:22'),
(228, 237, 1, 9, 13, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(229, 238, 1, 9, 11, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:22'),
(230, 239, 1, 9, 11, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(231, 240, 1, 9, 12, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(232, 241, 1, 9, 10, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:45'),
(233, 242, 1, 9, 10, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(234, 243, 1, 9, 13, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:08'),
(235, 244, 1, 9, 13, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:08'),
(236, 245, 1, 9, 13, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(237, 246, 1, 9, 10, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(238, 247, 1, 9, 13, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:08'),
(239, 248, 1, 9, 12, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(240, 249, 1, 9, 13, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(241, 250, 1, 9, 11, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:22'),
(242, 251, 1, 9, 11, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(243, 252, 1, 9, 12, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(244, 253, 1, 9, 11, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:22'),
(245, 254, 1, 9, 10, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(246, 255, 1, 9, 13, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:08'),
(247, 256, 1, 9, 12, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(248, 257, 1, 9, 13, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(249, 258, 1, 9, 10, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(250, 259, 1, 9, 11, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(251, 260, 1, 9, 10, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:45'),
(252, 261, 1, 9, 13, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(253, 262, 1, 9, 11, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:22'),
(254, 263, 1, 9, 11, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(255, 264, 1, 9, 12, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(256, 265, 1, 9, 13, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(257, 266, 1, 9, 10, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(258, 267, 1, 9, 11, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(259, 268, 1, 9, 13, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:08'),
(260, 269, 1, 9, 13, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(261, 270, 1, 9, 11, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:22'),
(262, 271, 1, 9, 13, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:08'),
(263, 272, 1, 9, 13, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:08'),
(264, 273, 1, 9, 10, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:45'),
(265, 274, 1, 9, 11, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:22'),
(266, 275, 1, 9, 11, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(267, 276, 1, 9, 13, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:08'),
(268, 277, 1, 9, 13, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(269, 278, 1, 9, 10, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(270, 279, 1, 9, 10, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:45'),
(271, 280, 1, 9, 13, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:08'),
(272, 281, 1, 9, 13, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(273, 282, 1, 9, 13, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:08'),
(274, 283, 1, 9, 10, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:45'),
(275, 284, 1, 9, 11, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:22'),
(276, 285, 1, 9, 13, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(277, 286, 1, 9, 10, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(278, 287, 1, 9, 11, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(279, 288, 1, 9, 11, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:22'),
(280, 289, 1, 9, 11, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:22'),
(281, 290, 1, 9, 13, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:08'),
(282, 291, 1, 9, 11, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(283, 292, 1, 9, 12, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(284, 293, 1, 9, 13, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(285, 294, 1, 9, 11, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:22'),
(286, 295, 1, 9, 12, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:32'),
(287, 296, 1, 9, 12, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(288, 297, 1, 9, 12, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:32'),
(289, 298, 1, 9, 10, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(290, 299, 1, 9, 11, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(291, 300, 1, 9, 13, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:08'),
(292, 301, 1, 9, 11, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:22'),
(293, 302, 1, 9, 12, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:32'),
(294, 303, 1, 9, 11, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(295, 304, 1, 9, 12, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(296, 305, 1, 9, 13, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(297, 306, 1, 9, 10, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(298, 307, 1, 9, 12, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:32'),
(299, 308, 1, 9, 11, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:22'),
(300, 309, 1, 9, 10, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:45'),
(301, 310, 1, 9, 10, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(302, 311, 1, 9, 11, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(303, 312, 1, 9, 13, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:08'),
(304, 313, 1, 9, 12, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:32'),
(305, 314, 1, 9, 11, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:22'),
(306, 315, 1, 9, 13, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:08'),
(307, 316, 1, 9, 12, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(308, 317, 1, 9, 10, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:45'),
(309, 318, 1, 10, 14, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(310, 319, 1, 10, 17, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:20'),
(311, 320, 1, 10, 16, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(312, 321, 1, 10, NULL, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 18:18:41'),
(313, 322, 1, 10, 17, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:20'),
(314, 323, 1, 10, 15, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(315, 324, 1, 10, 16, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(316, 325, 1, 10, 15, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:53'),
(317, 326, 1, 10, 14, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(318, 327, 1, 10, 15, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(319, 328, 1, 10, 17, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:20'),
(320, 329, 1, 10, 16, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:14'),
(321, 330, 1, 10, 14, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(322, 331, 1, 10, 17, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:20'),
(323, 332, 1, 10, 14, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:04'),
(324, 333, 1, 10, 15, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:53'),
(325, 334, 1, 10, 16, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:14'),
(326, 335, 1, 10, 15, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(327, 336, 1, 10, 15, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:53'),
(328, 337, 1, 10, 14, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:04'),
(329, 338, 1, 10, 16, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:14'),
(330, 339, 1, 10, 14, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:04'),
(331, 340, 1, 10, 16, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(332, 341, 1, 10, 17, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:20'),
(333, 342, 1, 10, 17, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:20'),
(334, 343, 1, 10, 14, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:04'),
(335, 344, 1, 10, 15, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:53'),
(336, 345, 1, 10, 17, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:20'),
(337, 346, 1, 10, 14, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(338, 347, 1, 10, 17, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:20'),
(339, 348, 1, 10, 15, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:53'),
(340, 349, 1, 10, 17, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:20'),
(341, 350, 1, 10, 16, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:14'),
(342, 351, 1, 10, 16, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:14'),
(343, 352, 1, 10, 16, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(344, 353, 1, 10, 14, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:04'),
(345, 354, 1, 10, 14, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(346, 355, 1, 10, 14, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:04'),
(347, 356, 1, 10, 14, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:04'),
(348, 357, 1, 10, NULL, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 18:18:41'),
(349, 358, 1, 10, 14, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(350, 359, 1, 10, 14, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:04'),
(351, 360, 1, 10, 14, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:04'),
(352, 361, 1, 10, 17, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:20'),
(353, 362, 1, 10, 14, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(354, 363, 1, 10, 15, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(355, 364, 1, 10, 15, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:53'),
(356, 365, 1, 10, 17, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:20'),
(357, 366, 1, 10, 14, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(358, 367, 1, 10, 17, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:20'),
(359, 368, 1, 10, 17, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:20'),
(360, 369, 1, 10, 15, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:53'),
(361, 370, 1, 10, 14, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(362, 371, 1, 10, 15, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(363, 372, 1, 10, 15, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:53'),
(364, 373, 1, 10, 16, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:14'),
(365, 374, 1, 10, 16, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:14'),
(366, 375, 1, 10, 15, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(367, 376, 1, 10, 16, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(368, 377, 1, 10, NULL, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 18:18:41'),
(369, 378, 1, 10, 14, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(370, 379, 1, 10, 15, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(371, 380, 1, 10, 16, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(372, 381, 1, 10, 17, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:20'),
(373, 382, 1, 10, 16, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:14'),
(374, 383, 1, 10, 15, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(375, 384, 1, 10, 16, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(376, 385, 1, 10, NULL, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 18:18:41'),
(377, 386, 1, 10, 14, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(378, 387, 1, 10, 17, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:20'),
(379, 388, 1, 10, 15, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:53'),
(380, 389, 1, 10, NULL, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 18:18:41'),
(381, 390, 1, 10, 15, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:53'),
(382, 391, 1, 10, 17, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:20'),
(383, 392, 1, 10, 16, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(384, 393, 1, 10, 16, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:14'),
(385, 394, 1, 10, 14, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(386, 395, 1, 10, 15, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(387, 396, 1, 10, 16, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(388, 397, 1, 10, 15, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:53'),
(389, 398, 1, 10, 16, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:14'),
(390, 399, 1, 10, 15, 'enrolled', 'returning', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(391, 400, 1, 10, 15, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:53'),
(392, 401, 1, 10, 17, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:20'),
(393, 402, 1, 10, 14, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(394, 403, 1, 10, 15, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(395, 404, 1, 10, 15, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:53'),
(396, 405, 1, 10, 16, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:14'),
(397, 406, 1, 10, 14, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(398, 407, 1, 10, 15, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00');
INSERT INTO `enrollments` (`id`, `student_id`, `school_year_id`, `grade_level_id`, `section_sy_id`, `status`, `enrollment_type`, `processed_by`, `processed_at`, `notes`, `unregistered_reason`, `created_at`, `updated_at`) VALUES
(399, 408, 1, 10, 14, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:04'),
(400, 409, 1, 10, NULL, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 18:18:41'),
(401, 410, 1, 10, 16, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:14'),
(402, 411, 1, 10, 17, 'enrolled', 'transferee', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:20'),
(403, 412, 1, 10, 17, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:18:20'),
(404, 413, 1, 10, 15, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:53'),
(405, 414, 1, 10, 14, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(406, 415, 1, 10, 15, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 00:00:00'),
(407, 416, 1, 10, 15, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-31 15:17:53'),
(408, 417, 1, 10, NULL, 'enrolled', 'new', 2, '2026-05-25 08:00:00', NULL, NULL, '2026-05-24 23:00:00', '2026-05-25 18:18:41'),
(409, 418, 1, 7, 1, 'enrolled', 'new', NULL, '2026-05-26 01:19:12', NULL, NULL, '2026-05-25 10:50:24', '2026-05-25 18:32:29'),
(410, 419, 1, 8, 8, 'enrolled', 'new', NULL, '2026-05-29 20:00:55', NULL, NULL, '2026-05-28 13:57:31', '2026-05-29 12:25:42'),
(411, 421, 1, 8, 9, 'enrolled', 'new', NULL, '2026-05-31 18:23:59', NULL, NULL, '2026-05-31 04:18:03', '2026-05-31 10:25:03'),
(412, 423, 1, 7, 5, 'enrolled', 'new', NULL, '2026-06-01 04:22:00', NULL, NULL, '2026-05-31 14:13:40', '2026-05-31 20:28:18'),
(413, 424, 1, 8, 8, 'enrolled', 'new', NULL, '2026-06-01 08:01:53', NULL, NULL, '2026-05-31 17:58:35', '2026-06-01 00:03:43');

-- --------------------------------------------------------

--
-- Table structure for table `enrollment_logs`
--

CREATE TABLE `enrollment_logs` (
  `id` int(11) NOT NULL,
  `enrollment_id` int(11) NOT NULL COMMENT 'FK → enrollments.id',
  `student_id` int(11) NOT NULL COMMENT 'FK → students.id (denormalized for speed)',
  `changed_by` int(11) DEFAULT NULL COMMENT 'FK → registrars.id',
  `old_status` enum('pending','registered','enrolled','unregistered','archived') DEFAULT NULL,
  `new_status` enum('pending','enrolled','unregistered','archived') NOT NULL,
  `notes` text DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Immutable audit log for every enrollment status change';

--
-- Dumping data for table `enrollment_logs`
--

INSERT INTO `enrollment_logs` (`id`, `enrollment_id`, `student_id`, `changed_by`, `old_status`, `new_status`, `notes`, `ip_address`, `created_at`) VALUES
(1, 1, 9, 1, 'pending', 'enrolled', 'Enrollment confirmed via payment approval by cashier.', '::1', '2026-05-19 08:51:10'),
(2, 7, 15, 1, 'registered', 'pending', 'Rejected by registrar — awaiting student resubmission. Reason: Test', '::1', '2026-05-24 07:40:31'),
(3, 8, 17, 1, 'registered', 'enrolled', 'Enrollment confirmed via payment approval by cashier.', '::1', '2026-05-24 16:19:11'),
(5, 409, 418, 1, 'registered', 'pending', 'Rejected by registrar — awaiting student resubmission. Reason: test', '::1', '2026-05-25 17:02:27'),
(6, 409, 418, 1, 'pending', 'pending', 'Rejected by registrar — awaiting student resubmission. Reason: testing', '::1', '2026-05-25 17:17:08'),
(7, 409, 418, 1, 'pending', '', 'Registration accepted by registrar.', '::1', '2026-05-25 17:17:45'),
(8, 409, 418, 1, 'registered', 'enrolled', 'Enrollment confirmed via payment approval by cashier.', '::1', '2026-05-25 17:19:12'),
(9, 410, 419, 1, 'registered', 'enrolled', 'Enrollment confirmed via payment approval by cashier.', '::1', '2026-05-29 12:00:55'),
(10, 411, 421, 1, 'registered', 'enrolled', 'Enrollment confirmed via payment approval by cashier.', '::1', '2026-05-31 10:23:59'),
(11, 412, 423, 1, 'registered', 'enrolled', 'Enrollment confirmed via payment approval by cashier.', '::1', '2026-05-31 20:22:00'),
(12, 413, 424, 1, 'registered', 'enrolled', 'Enrollment confirmed via payment approval by cashier.', '::1', '2026-06-01 00:01:53');

-- --------------------------------------------------------

--
-- Table structure for table `grade_levels`
--

CREATE TABLE `grade_levels` (
  `id` int(11) NOT NULL,
  `level` tinyint(4) NOT NULL COMMENT '1 through 10',
  `display_name` varchar(50) NOT NULL COMMENT 'e.g. Grade 7',
  `is_active` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `grade_levels`
--

INSERT INTO `grade_levels` (`id`, `level`, `display_name`, `is_active`) VALUES
(7, 7, 'Grade 7', 1),
(8, 8, 'Grade 8', 1),
(9, 9, 'Grade 9', 1),
(10, 10, 'Grade 10', 1);

-- --------------------------------------------------------

--
-- Table structure for table `guardians`
--

CREATE TABLE `guardians` (
  `id` int(11) NOT NULL COMMENT 'PK',
  `full_name` varchar(255) NOT NULL,
  `guardian_type` enum('biological_parent','adoptive_parent','foster_guardian','court_appointed_guardian','step_parent','grandparent','uncle_aunt','sibling','other') NOT NULL DEFAULT 'biological_parent',
  `sex` enum('male','female','not_specified') DEFAULT 'not_specified',
  `religion` varchar(100) DEFAULT NULL,
  `occupation` varchar(200) DEFAULT NULL,
  `employer` varchar(255) DEFAULT NULL,
  `home_address` varchar(500) DEFAULT NULL,
  `city` varchar(150) DEFAULT NULL,
  `province` varchar(150) DEFAULT NULL,
  `zip_code` char(4) DEFAULT NULL,
  `comm_method` enum('Phone','Email','Both') DEFAULT NULL,
  `mobile_number` varchar(15) DEFAULT NULL COMMENT 'Stored as 09XXXXXXXXX',
  `email_address` varchar(255) DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1 COMMENT '0 = deactivated / no longer guardian',
  `is_deceased` tinyint(1) NOT NULL DEFAULT 0 COMMENT '1 = deceased — kept for history',
  `deceased_date` date DEFAULT NULL,
  `is_restricted` tinyint(1) NOT NULL DEFAULT 0 COMMENT '1 = Do Not Release student to this person',
  `restriction_reason` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Real-world guardian persons — linked to students via student_guardians';

--
-- Dumping data for table `guardians`
--

INSERT INTO `guardians` (`id`, `full_name`, `guardian_type`, `sex`, `religion`, `occupation`, `employer`, `home_address`, `city`, `province`, `zip_code`, `comm_method`, `mobile_number`, `email_address`, `is_active`, `is_deceased`, `deceased_date`, `is_restricted`, `restriction_reason`, `created_at`, `updated_at`) VALUES
(1, 'Yakamoto Suzune Aguilar', 'biological_parent', 'not_specified', NULL, NULL, NULL, 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '2577', 'Email', NULL, 'yakamoto234@gmail.com', 1, 0, NULL, 0, NULL, '2026-05-17 13:07:07', '2026-05-17 13:07:07'),
(2, 'Joshua Phillippe L. Aguilar', 'biological_parent', 'not_specified', NULL, 'Artist', NULL, 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '2566', 'Email', NULL, 'phillippejoshua278@gmail.com', 1, 0, NULL, 0, NULL, '2026-05-17 15:39:22', '2026-05-17 15:39:22'),
(3, 'Stephanie C. Aguilar', 'biological_parent', 'not_specified', NULL, 'Psychologist', NULL, 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '2566', 'Email', NULL, 'stephanievillon2566@gmail.com', 1, 0, NULL, 0, NULL, '2026-05-17 15:39:22', '2026-05-17 15:39:22'),
(4, 'Samonteza Wakali Sasha', 'biological_parent', 'not_specified', NULL, 'Dentistry', NULL, 'Blk 22 Lot 15 Neverdeci Laquinto Street Havanias', 'City of Caloocan', 'None', '1447', 'Email', NULL, 'juju2344@gmail.com', 1, 0, NULL, 0, NULL, '2026-05-18 18:15:20', '2026-05-18 18:15:20'),
(5, 'Samonteza Wakali Sasha', 'biological_parent', 'not_specified', NULL, 'Dentistry', NULL, 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '2566', 'Email', NULL, 'phillippejoshua278@gmail.com', 1, 0, NULL, 0, NULL, '2026-05-18 18:54:33', '2026-05-18 18:54:33'),
(6, 'Yakamoto Suzune Aguilar', 'biological_parent', 'not_specified', NULL, 'Artist', NULL, 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '2566', 'Email', NULL, 'juju2344@gmail.com', 1, 0, NULL, 0, NULL, '2026-05-18 18:54:33', '2026-05-18 18:54:33'),
(7, 'Kurt Rada', 'biological_parent', 'not_specified', NULL, 'AFP', NULL, 'Blk 12 Lot 15 Mahal ni Keith si Merl Dela Pena Street', 'City of Caloocan', 'Abra', '2566', 'Email', NULL, 'kurtrada005@gmail.com', 1, 0, NULL, 0, NULL, '2026-05-18 19:04:41', '2026-05-18 19:04:41'),
(8, 'Ryan Menalo Samonteza', 'biological_parent', 'not_specified', NULL, 'Artist', NULL, 'Blk 30 Lot 15 Shamrock Street Castlespring heights Subdivision', 'City of Caloocan', 'None', '1000', 'Email', NULL, 'ryanmenalo@gmail.com', 1, 0, NULL, 0, NULL, '2026-05-20 18:10:49', '2026-05-20 18:10:49'),
(9, 'Saraya Miquella Samonteza', 'biological_parent', 'not_specified', NULL, 'House wife', NULL, 'Blk 30 Lot 15 Shamrock Street Castlespring heights Subdivision', 'City of Caloocan', 'None', '1000', 'Email', NULL, 'ryanmenalo@gmail.com', 1, 0, NULL, 0, NULL, '2026-05-20 18:10:49', '2026-05-20 18:10:49'),
(10, 'Joshua Phillippe L. Aguilar', 'biological_parent', 'not_specified', NULL, 'Artist', NULL, 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '2576', 'Email', NULL, 'phillipenaaguilarpa@gmail.com', 1, 0, NULL, 0, NULL, '2026-05-22 11:19:04', '2026-05-22 11:19:04'),
(11, 'Jaja Quipella Samonellia', 'biological_parent', 'not_specified', NULL, 'Analytics', NULL, 'Blk 12 Lot 15 Mahal ni Keith si Merl Dela Pena Street', 'City of Caloocan', 'Metro Manila', '2576', 'Email', NULL, 'himashihimashi@gmail.com', 1, 0, NULL, 0, NULL, '2026-05-22 12:49:10', '2026-05-22 12:49:10'),
(12, 'Yagoo', 'biological_parent', 'not_specified', NULL, 'CEO', NULL, 'Blk 89 Lot 67 Hololive Cover inc', 'City of Caloocan', 'NCR Metro Manila', '2577', 'Email', NULL, 'sanseisuisei@gmail.com', 1, 0, NULL, 0, NULL, '2026-05-24 07:50:04', '2026-05-24 07:50:04'),
(13, 'Samonteza Wakali Sasha', 'biological_parent', 'not_specified', NULL, 'ANALYTICS', NULL, 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '2566', 'Email', NULL, 'juju2344@gmail.com', 1, 0, NULL, 0, NULL, '2026-05-25 16:36:25', '2026-05-25 16:36:25'),
(14, 'Ingrid Vulpisofglia', 'biological_parent', 'not_specified', NULL, 'Mafia Assassin', NULL, 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '2566', 'Email', NULL, 'vulpisfogliaingrid@gmail.com', 1, 0, NULL, 0, NULL, '2026-05-28 18:57:53', '2026-05-28 18:57:53'),
(15, 'Matono Sinako Samini', 'biological_parent', 'not_specified', NULL, 'Shinto Priest', NULL, 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '2566', 'Email', NULL, 'matonosinako@gmail.com', 1, 0, NULL, 0, NULL, '2026-05-28 18:57:53', '2026-05-28 18:57:53'),
(16, 'Dokutah', 'biological_parent', 'not_specified', NULL, 'Dokutah', NULL, 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '2566', 'Email', NULL, 'dokutah@gmail.com', 1, 0, NULL, 0, NULL, '2026-05-28 18:57:53', '2026-05-28 18:57:53'),
(17, 'Keith Nacel Canilang', 'biological_parent', 'not_specified', NULL, 'Student', NULL, 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '5600', 'Email', NULL, 'keithnacelcanilang@gmail.com', 1, 0, NULL, 0, NULL, '2026-05-31 09:54:02', '2026-05-31 09:54:02'),
(18, 'Joshua Phillippe L. Aguilar', 'biological_parent', 'not_specified', NULL, 'Artist', NULL, 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '2566', 'Email', NULL, 'joshuaaguilar@gmail.com', 1, 0, NULL, 0, NULL, '2026-05-31 09:59:53', '2026-05-31 09:59:53'),
(19, 'Phillippe Aguilar', 'biological_parent', 'not_specified', NULL, 'Student', NULL, 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '1447', 'Email', NULL, 'phillippejoshua278@gmail.com', 1, 0, NULL, 0, NULL, '2026-05-31 20:01:49', '2026-05-31 20:01:49'),
(20, 'Joshua Phillippe L. Aguilar', 'biological_parent', 'not_specified', NULL, 'Student', NULL, 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '2566', 'Email', NULL, 'yakamoto234@gmail.com', 1, 0, NULL, 0, NULL, '2026-05-31 20:06:30', '2026-05-31 20:06:30'),
(21, 'Joshua Phillippe L. Aguilar', 'biological_parent', 'not_specified', NULL, 'Student', NULL, 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '2566', 'Email', NULL, 'phillippejoshua278@gmail.com', 1, 0, NULL, 0, NULL, '2026-05-31 23:55:24', '2026-05-31 23:55:24');

-- --------------------------------------------------------

--
-- Table structure for table `guardian_audit_log`
--

CREATE TABLE `guardian_audit_log` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL COMMENT 'FK → students.id',
  `guardian_id` int(11) DEFAULT NULL COMMENT 'FK → guardians.id (null if guardian deleted)',
  `changed_by` int(11) DEFAULT NULL COMMENT 'FK → admins.id',
  `action` enum('guardian_added','guardian_updated','guardian_removed','guardian_deceased_marked','guardian_restricted','guardian_unrestricted','custody_changed','permissions_changed','priority_changed','pickup_auth_changed') NOT NULL,
  `field_changed` varchar(100) DEFAULT NULL COMMENT 'Specific field if a targeted update',
  `old_value` text DEFAULT NULL,
  `new_value` text DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `session_note` varchar(500) DEFAULT NULL COMMENT 'e.g. "Court order 2026-03 received"',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Immutable audit log — all guardian record changes';

--
-- Dumping data for table `guardian_audit_log`
--

INSERT INTO `guardian_audit_log` (`id`, `student_id`, `guardian_id`, `changed_by`, `action`, `field_changed`, `old_value`, `new_value`, `ip_address`, `session_note`, `created_at`) VALUES
(2, 7, 2, NULL, 'guardian_added', NULL, NULL, '{\"name\":\"Joshua Phillippe L. Aguilar\",\"relationship\":\"Father\",\"comm_method\":\"Email\"}', '::1', NULL, '2026-05-17 15:39:22'),
(3, 7, 3, NULL, 'guardian_added', NULL, NULL, '{\"name\":\"Stephanie C. Aguilar\",\"relationship\":\"Mother\",\"comm_method\":\"Email\"}', '::1', NULL, '2026-05-17 15:39:22'),
(5, 9, 5, NULL, 'guardian_added', NULL, NULL, '{\"name\":\"Samonteza Wakali Sasha\",\"relationship\":\"Mother\",\"comm_method\":\"Email\"}', '::1', NULL, '2026-05-18 18:54:33'),
(6, 9, 6, NULL, 'guardian_added', NULL, NULL, '{\"name\":\"Yakamoto Suzune Aguilar\",\"relationship\":\"Father\",\"comm_method\":\"Email\"}', '::1', NULL, '2026-05-18 18:54:33'),
(7, 10, 7, NULL, 'guardian_added', NULL, NULL, '{\"name\":\"Kurt Rada\",\"relationship\":\"Mother\",\"comm_method\":\"Email\"}', '::1', NULL, '2026-05-18 19:04:41'),
(8, 14, 8, NULL, 'guardian_added', NULL, NULL, '{\"name\":\"Ryan Menalo Samonteza\",\"relationship\":\"Father\",\"comm_method\":\"Email\"}', '192.168.68.157', NULL, '2026-05-20 18:10:49'),
(9, 14, 9, NULL, 'guardian_added', NULL, NULL, '{\"name\":\"Saraya Miquella Samonteza\",\"relationship\":\"Mother\",\"comm_method\":\"Email\"}', '192.168.68.157', NULL, '2026-05-20 18:10:49'),
(10, 15, 10, NULL, 'guardian_added', NULL, NULL, '{\"name\":\"Joshua Phillippe L. Aguilar\",\"relationship\":\"Father\",\"comm_method\":\"Email\"}', '::1', NULL, '2026-05-22 11:19:04'),
(11, 16, 11, NULL, 'guardian_added', NULL, NULL, '{\"name\":\"Jaja Quipella Samonellia\",\"relationship\":\"Mother\",\"comm_method\":\"Email\"}', '::1', NULL, '2026-05-22 12:49:10'),
(12, 17, 12, NULL, 'guardian_added', NULL, NULL, '{\"name\":\"Yagoo\",\"relationship\":\"Father\",\"comm_method\":\"Email\"}', '::1', NULL, '2026-05-24 07:50:04'),
(13, 418, 13, NULL, 'guardian_added', NULL, NULL, '{\"name\":\"Samonteza Wakali Sasha\",\"relationship\":\"Mother\",\"comm_method\":\"Email\"}', '::1', NULL, '2026-05-25 16:36:25'),
(14, 419, 14, NULL, 'guardian_added', NULL, NULL, '{\"name\":\"Ingrid Vulpisofglia\",\"relationship\":\"Mother\",\"comm_method\":\"Email\"}', '::1', NULL, '2026-05-28 18:57:53'),
(15, 419, 15, NULL, 'guardian_added', NULL, NULL, '{\"name\":\"Matono Sinako Samini\",\"relationship\":\"Father\",\"comm_method\":\"Email\"}', '::1', NULL, '2026-05-28 18:57:53'),
(16, 419, 16, NULL, 'guardian_added', NULL, NULL, '{\"name\":\"Dokutah\",\"relationship\":\"Legal Guardian\",\"comm_method\":\"Email\"}', '::1', NULL, '2026-05-28 18:57:53'),
(18, 421, 18, NULL, 'guardian_added', NULL, NULL, '{\"name\":\"Joshua Phillippe L. Aguilar\",\"relationship\":\"Father\",\"comm_method\":\"Email\"}', '::1', NULL, '2026-05-31 09:59:53'),
(20, 423, 20, NULL, 'guardian_added', NULL, NULL, '{\"name\":\"Joshua Phillippe L. Aguilar\",\"relationship\":\"Father\",\"comm_method\":\"Email\"}', '::1', NULL, '2026-05-31 20:06:30'),
(21, 424, 21, NULL, 'guardian_added', NULL, NULL, '{\"name\":\"Joshua Phillippe L. Aguilar\",\"relationship\":\"Father\",\"comm_method\":\"Email\"}', '::1', NULL, '2026-05-31 23:55:24');

-- --------------------------------------------------------

--
-- Table structure for table `otp_attempts`
--

CREATE TABLE `otp_attempts` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL COMMENT 'FK → users.id',
  `attempt_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `ip_address` varchar(45) DEFAULT NULL,
  `succeeded` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `otp_verifications`
--

CREATE TABLE `otp_verifications` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL COMMENT 'FK → students.id',
  `otp_hash` varchar(64) NOT NULL COMMENT 'SHA-256 of the 6-digit OTP',
  `sent_to` varchar(255) NOT NULL COMMENT 'Email address OTP was sent to',
  `purpose` enum('returning_verify','email_confirm') NOT NULL DEFAULT 'returning_verify',
  `expires_at` datetime NOT NULL,
  `used_at` datetime DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='OTP codes for returning-student identity verification';

-- --------------------------------------------------------

--
-- Table structure for table `password_reset_tokens`
--

CREATE TABLE `password_reset_tokens` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL COMMENT 'FK → users.id',
  `token_hash` varchar(64) NOT NULL COMMENT 'SHA-256 hash of the raw token',
  `expires_at` datetime NOT NULL,
  `used_at` datetime DEFAULT NULL COMMENT 'Set when the token is consumed',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Dumping data for table `password_reset_tokens`
--

INSERT INTO `password_reset_tokens` (`id`, `user_id`, `token_hash`, `expires_at`, `used_at`, `created_at`) VALUES
(1, 1, '819ef8dd9c59867ddfc8a370c5a3ae3dc0e0b35ccb4781d7fcb5fa36f840ffbb', '2036-05-16 17:26:41', '2026-05-16 23:27:54', '2026-05-16 15:26:41'),
(3, 2, 'b3041cd402be7a65cf90ccfd6ab03a7731ea60da99fdca548ad6bd9897b08070', '2036-05-17 17:28:53', '2026-05-17 23:29:22', '2026-05-17 15:28:53'),
(4, 6, 'e41a4b3cb86d16a224046e5dd47590552222f5f5dfe970006ef1b78ccc24a106', '2036-05-18 20:56:58', '2026-05-19 02:57:25', '2026-05-18 18:56:58'),
(5, 21, '0e876db11791fa295634940b5cedad95ed23196fbc22b10d6958b1d8610e77f2', '2036-05-22 22:43:17', '2026-05-22 22:43:56', '2026-05-22 14:43:17'),
(6, 29, 'd20f475dcac16217ed219b6f3c7ca4cce2f4e8d2b90cbb1b7c13feeb9f089401', '2036-05-25 20:42:55', '2026-05-25 20:43:19', '2026-05-25 12:42:55'),
(7, 22, 'c333f2be14c012e8af2558242949715c517c6fef5ff53967b64eff9827ae396a', '2036-05-26 00:22:17', '2026-05-26 00:23:20', '2026-05-25 16:22:17'),
(8, 473, 'f2de6535cf3a7e927b7819549363778e6540d9e0f466b2e920711ec10891c9c4', '2036-05-31 18:41:48', '2026-05-31 18:42:32', '2026-05-31 10:41:48'),
(9, 468, 'd4ad0d3d96692721cee4d88f11b1e546e9792d983456712be1df50521135220f', '2036-05-31 23:28:15', '2026-05-31 23:28:41', '2026-05-31 15:28:15'),
(10, 465, 'aded750dde1f934d9af5f617d19118f14e83b9669294ac6243deb9eae4286462', '2036-06-01 03:19:03', '2026-06-01 03:19:35', '2026-05-31 19:19:03');

-- --------------------------------------------------------

--
-- Table structure for table `payment_due_notices`
--

CREATE TABLE `payment_due_notices` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL COMMENT 'FK → students.id',
  `school_year_id` int(11) NOT NULL COMMENT 'FK → school_years.id',
  `amount_due` decimal(10,2) NOT NULL COMMENT 'Amount the student is required to pay',
  `due_datetime` datetime NOT NULL COMMENT 'Deadline for payment',
  `notice_message` text DEFAULT NULL,
  `status` enum('pending','paid','cancelled') NOT NULL DEFAULT 'pending' COMMENT 'Status of the notice',
  `assigned_by` int(11) NOT NULL COMMENT 'FK → cashiers.id — cashier who created the notice',
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Payment due notices created by cashiers and emailed to students.';

-- --------------------------------------------------------

--
-- Table structure for table `payment_submissions`
--

CREATE TABLE `payment_submissions` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL COMMENT 'FK → students.id',
  `school_year_id` int(11) NOT NULL COMMENT 'FK → school_years.id',
  `reference_number` varchar(100) NOT NULL COMMENT 'GCash reference number entered by student',
  `payment_type` enum('full','partial') NOT NULL DEFAULT 'partial',
  `payment_channel` enum('gcash','bank_transfer') NOT NULL DEFAULT 'gcash' COMMENT 'Payment method used by student',
  `bank_name` varchar(100) DEFAULT NULL COMMENT 'Bank name for bank_transfer submissions (e.g. BDO)',
  `amount` decimal(10,2) DEFAULT NULL COMMENT 'Amount entered by student (optional)',
  `proof_image_path` varchar(1000) NOT NULL COMMENT 'Relative path to uploaded receipt image',
  `proof_image_name` varchar(500) NOT NULL,
  `proof_image_mime` varchar(100) NOT NULL,
  `proof_image_size_kb` int(11) DEFAULT NULL,
  `status` enum('uploaded','under_review','verified','rejected','reflected_to_enrollment') NOT NULL DEFAULT 'uploaded',
  `cashier_id` int(11) DEFAULT NULL COMMENT 'FK → cashiers.id',
  `reviewed_at` datetime DEFAULT NULL,
  `rejection_reason` text DEFAULT NULL,
  `confirmed_amount` decimal(10,2) DEFAULT NULL COMMENT 'Amount as confirmed by cashier',
  `receipt_pdf_path` varchar(1000) DEFAULT NULL,
  `submitted_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `review_started_at` datetime DEFAULT NULL,
  `confirmed_at` datetime DEFAULT NULL,
  `reflected_to_enrollment_at` datetime DEFAULT NULL,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `ip_address` varchar(45) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='One row per student GCash payment proof upload. Cashier reviews and updates status.';

--
-- Dumping data for table `payment_submissions`
--

INSERT INTO `payment_submissions` (`id`, `student_id`, `school_year_id`, `reference_number`, `payment_type`, `payment_channel`, `bank_name`, `amount`, `proof_image_path`, `proof_image_name`, `proof_image_mime`, `proof_image_size_kb`, `status`, `cashier_id`, `reviewed_at`, `rejection_reason`, `confirmed_amount`, `receipt_pdf_path`, `submitted_at`, `review_started_at`, `confirmed_at`, `reflected_to_enrollment_at`, `updated_at`, `ip_address`) VALUES
(1, 7, 1, '4509834759834', 'partial', 'gcash', NULL, NULL, 'uploads/payment_proofs/student_7/pay_6a0a0e8e4439f3.28794367.png', 'resibo.png', 'image/png', 147, 'rejected', 1, '2026-05-18 02:57:24', 'No amount declared', NULL, NULL, '2026-05-17 18:53:02', '2026-05-18 02:54:39', NULL, NULL, '2026-05-17 18:57:24', '::1'),
(3, 7, 1, '1242353452346', 'full', 'gcash', NULL, 50000.00, 'uploads/payment_proofs/student_7/pay_6a0a1def4168f1.40494996.png', 'resibo.png', 'image/png', 147, 'verified', 1, '2026-05-18 04:00:08', NULL, NULL, NULL, '2026-05-17 19:58:39', '2026-05-18 03:59:28', '2026-05-18 04:00:08', NULL, '2026-05-17 20:00:08', '::1'),
(5, 9, 1, '5432543543543', 'partial', 'gcash', NULL, 5000.00, 'uploads/payment_proofs/student_9/pay_6a0c116676a0a9.59907825.png', 'resibo.png', 'image/png', 147, 'verified', 1, '2026-05-19 15:29:58', NULL, NULL, NULL, '2026-05-19 07:29:42', '2026-05-19 15:29:47', '2026-05-19 15:29:58', NULL, '2026-05-19 07:29:58', '::1'),
(6, 9, 1, '5675686856785', 'full', 'gcash', NULL, 5000.00, 'uploads/payment_proofs/student_9/pay_6a0c144bad92b0.62015865.png', 'resibo.png', 'image/png', 147, 'verified', 1, '2026-05-19 16:28:39', NULL, NULL, NULL, '2026-05-19 07:42:03', '2026-05-19 15:42:26', '2026-05-19 16:28:39', NULL, '2026-05-19 08:28:39', '::1'),
(8, 9, 1, '3464523464325', 'partial', 'gcash', NULL, 5000.00, 'uploads/payment_proofs/student_9/pay_6a0c21e8118762.08633893.png', 'resibo.png', 'image/png', 147, 'verified', 1, '2026-05-19 16:40:26', NULL, NULL, NULL, '2026-05-19 08:40:08', '2026-05-19 16:40:23', '2026-05-19 16:40:26', NULL, '2026-05-19 08:40:26', '::1'),
(9, 9, 1, '3453246236423', 'partial', 'gcash', NULL, 5000.00, 'uploads/payment_proofs/student_9/pay_6a0c228c6b5858.28113187.png', 'resibo.png', 'image/png', 147, 'verified', 1, '2026-05-19 16:43:02', NULL, NULL, NULL, '2026-05-19 08:42:52', '2026-05-19 16:42:57', '2026-05-19 16:43:02', NULL, '2026-05-19 08:43:02', '::1'),
(10, 9, 1, '4654645645263', 'partial', 'gcash', NULL, 5000.00, 'uploads/payment_proofs/student_9/pay_6a0c22d766fdf3.96991442.png', 'resibo.png', 'image/png', 147, 'reflected_to_enrollment', 1, '2026-05-19 16:51:10', NULL, NULL, NULL, '2026-05-19 08:44:07', '2026-05-19 16:51:09', '2026-05-19 16:51:10', NULL, '2026-05-19 08:51:10', '::1'),
(11, 14, 1, '6545645646456', 'partial', 'gcash', NULL, 5000.00, 'uploads/payment_proofs/student_14/pay_6a0dfc129fdbf9.52003094.png', 'images.png', 'image/png', 9, 'rejected', 1, '2026-05-21 02:23:31', 'Wrong reference number', NULL, NULL, '2026-05-20 18:23:14', '2026-05-21 02:23:19', NULL, NULL, '2026-05-20 18:23:31', '192.168.68.157'),
(12, 14, 1, '6756475467567', 'partial', 'gcash', NULL, 5000.00, 'uploads/payment_proofs/student_14/pay_6a0dfd232ada14.61596098.png', 'images.png', 'image/png', 9, 'verified', 1, '2026-05-21 02:28:00', NULL, NULL, NULL, '2026-05-20 18:27:47', '2026-05-21 02:27:52', '2026-05-21 02:28:00', NULL, '2026-05-20 18:28:00', '192.168.68.157'),
(13, 14, 1, '2534634634563', 'partial', 'gcash', NULL, 4999.97, 'uploads/payment_proofs/student_14/pay_6a0dffd9690638.61423895.png', 'images.png', 'image/png', 9, 'verified', 1, '2026-05-21 02:39:36', NULL, NULL, NULL, '2026-05-20 18:39:21', '2026-05-21 02:39:30', '2026-05-21 02:39:36', NULL, '2026-05-20 18:39:36', '192.168.68.157'),
(14, 14, 1, '8576974569734', 'partial', 'gcash', NULL, 5000.00, 'uploads/payment_proofs/student_14/pay_6a0e01a3a825a5.44453689.png', 'images.png', 'image/png', 9, 'verified', 1, '2026-05-21 02:47:06', NULL, NULL, NULL, '2026-05-20 18:46:59', '2026-05-21 02:47:03', '2026-05-21 02:47:06', NULL, '2026-05-20 18:47:06', '192.168.68.157'),
(15, 14, 1, '4325234623464', 'partial', 'gcash', NULL, 5000.00, 'uploads/payment_proofs/student_14/pay_6a0e026ad79fd8.84914989.png', 'resibo.png', 'image/png', 147, 'verified', 1, '2026-05-21 02:50:24', NULL, NULL, NULL, '2026-05-20 18:50:18', '2026-05-21 02:50:23', '2026-05-21 02:50:24', NULL, '2026-05-20 18:50:24', '::1'),
(16, 17, 1, '5234623452345', 'partial', 'gcash', NULL, 5000.00, 'uploads/payment_proofs/student_17/pay_6a1308a23c6c60.83890962.png', 'resibo.png', 'image/png', 147, 'reflected_to_enrollment', 1, '2026-05-25 00:19:11', NULL, NULL, NULL, '2026-05-24 14:18:10', '2026-05-24 22:18:13', '2026-05-25 00:19:11', NULL, '2026-05-24 16:19:11', '::1'),
(17, 418, 1, '1242135123512', 'partial', 'gcash', NULL, 5000.00, 'uploads/payment_proofs/student_418/pay_6a147e00da1866.79653532.png', 'resibo.png', 'image/png', 147, 'reflected_to_enrollment', 1, '2026-05-26 01:19:12', NULL, NULL, NULL, '2026-05-25 16:51:12', '2026-05-26 01:19:10', '2026-05-26 01:19:12', NULL, '2026-05-25 17:19:12', '::1'),
(19, 419, 1, '45345654634564356534', 'partial', 'bank_transfer', 'BDO', 4999.95, 'uploads/payment_proofs/student_419/pay_6a19776c66d7e8.53797166.jpg', 'Money-Transfer-Receipt-.jpg', 'image/jpeg', 148, 'rejected', 1, '2026-05-29 19:31:58', 'Test', NULL, NULL, '2026-05-29 11:24:28', '2026-05-29 19:24:34', NULL, NULL, '2026-05-29 11:31:58', '::1'),
(20, 419, 1, '45234623465234632454', 'partial', 'bank_transfer', 'BDO', 5000.00, 'uploads/payment_proofs/student_419/pay_6a197b33e54605.83225283.jpg', 'Money-Transfer-Receipt-.jpg', 'image/jpeg', 148, 'rejected', 1, '2026-05-29 19:51:33', 'Test', NULL, NULL, '2026-05-29 11:40:35', '2026-05-29 19:40:40', NULL, NULL, '2026-05-29 11:51:33', '::1'),
(21, 419, 1, '12314345436234324334', 'full', 'bank_transfer', 'BDO', 5000.00, 'uploads/payment_proofs/student_419/pay_6a197e3d754fc4.18585608.jpg', 'Money-Transfer-Receipt-.jpg', 'image/jpeg', 148, 'rejected', 1, '2026-05-29 19:59:50', 'Test', NULL, NULL, '2026-05-29 11:53:33', '2026-05-29 19:53:37', NULL, NULL, '2026-05-29 11:59:50', '::1'),
(22, 419, 1, '32546433453425234523', 'full', 'bank_transfer', 'BDO', 5000.00, 'uploads/payment_proofs/student_419/pay_6a197fe41c1b61.44329199.jpg', 'Money-Transfer-Receipt-.jpg', 'image/jpeg', 148, 'reflected_to_enrollment', 1, '2026-05-29 20:00:55', NULL, NULL, NULL, '2026-05-29 12:00:36', '2026-05-29 20:00:50', '2026-05-29 20:00:55', NULL, '2026-05-29 12:00:55', '::1'),
(23, 419, 1, '4523452345234', 'partial', 'gcash', NULL, 5000.00, 'uploads/payment_proofs/student_419/pay_6a1980edf1a118.87219348.png', 'resibo.png', 'image/png', 147, 'verified', 1, '2026-05-29 20:05:11', NULL, NULL, NULL, '2026-05-29 12:05:01', '2026-05-29 20:05:09', '2026-05-29 20:05:11', NULL, '2026-05-29 12:05:11', '::1'),
(24, 418, 1, '34521345234623452345', 'full', 'bank_transfer', 'BDO', 5000.00, 'uploads/payment_proofs/student_418/pay_6a1be196618183.20121618.jpg', 'Money-Transfer-Receipt-.jpg', 'image/jpeg', 148, 'verified', 1, '2026-05-31 16:06:57', NULL, NULL, NULL, '2026-05-31 07:21:58', '2026-05-31 16:06:54', '2026-05-31 16:06:57', NULL, '2026-05-31 08:06:57', '::1'),
(25, 421, 1, '94237502983475893454', 'partial', 'bank_transfer', 'BDO', 5000.00, 'uploads/payment_proofs/student_421/pay_6a1c0bb7af8a03.43174976.jpg', 'Money-Transfer-Receipt-.jpg', 'image/jpeg', 148, 'reflected_to_enrollment', 1, '2026-05-31 18:23:59', NULL, NULL, NULL, '2026-05-31 10:21:43', '2026-05-31 18:23:11', '2026-05-31 18:23:59', NULL, '2026-05-31 10:23:59', '::1'),
(26, 423, 1, '23543534252345234652', 'partial', 'bank_transfer', 'BDO', 5000.00, 'uploads/payment_proofs/student_423/pay_6a1c98277f38d1.15982180.png', 'Bank Receipt Mock.png', 'image/png', 64, 'reflected_to_enrollment', 1, '2026-06-01 04:22:00', NULL, NULL, NULL, '2026-05-31 20:20:55', '2026-06-01 04:21:51', '2026-06-01 04:22:00', NULL, '2026-05-31 20:22:00', '::1'),
(27, 424, 1, '3253656523453', 'partial', 'gcash', NULL, 5000.00, 'uploads/payment_proofs/student_424/pay_6a1ccbe4e83bc0.74222975.png', 'Gcash Receipt Mock.png', 'image/png', 147, 'reflected_to_enrollment', 1, '2026-06-01 08:01:53', NULL, NULL, NULL, '2026-06-01 00:01:40', '2026-06-01 08:01:45', '2026-06-01 08:01:53', NULL, '2026-06-01 00:01:53', '::1');

-- --------------------------------------------------------

--
-- Table structure for table `principals`
--

CREATE TABLE `principals` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL COMMENT 'FK → users.id',
  `first_name` varchar(100) NOT NULL,
  `middle_name` varchar(100) DEFAULT NULL,
  `last_name` varchar(100) NOT NULL,
  `full_name` varchar(200) DEFAULT NULL COMMENT 'Kept for display convenience',
  `employee_id` varchar(50) DEFAULT NULL COMMENT 'School employee number',
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `is_archived` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='One row per principal staff member';

--
-- Dumping data for table `principals`
--

INSERT INTO `principals` (`id`, `user_id`, `first_name`, `middle_name`, `last_name`, `full_name`, `employee_id`, `is_active`, `created_at`, `updated_at`, `is_archived`) VALUES
(1, 11, 'Kurt', NULL, 'Rada', 'Kurt Rada', NULL, 1, '2026-05-19 07:56:02', '2026-05-21 17:58:14', 1),
(2, 19, 'Joshua', NULL, 'Aguilar', 'Joshua Aguilar', NULL, 1, '2026-05-21 17:58:42', '2026-05-21 18:43:49', 1),
(3, 25, 'Joshua', NULL, 'Aguilar', 'Joshua Aguilar', NULL, 1, '2026-05-21 18:46:44', '2026-05-21 18:46:44', 0);

-- --------------------------------------------------------

--
-- Table structure for table `principal_notifications`
--

CREATE TABLE `principal_notifications` (
  `id` int(11) NOT NULL,
  `recipient_type` enum('coordinator','teacher','principal','registrar') NOT NULL DEFAULT 'principal',
  `recipient_id` int(11) NOT NULL DEFAULT 1,
  `type` enum('grade_submitted','grade_approved','revision_requested','approved_by_coordinator','revision_by_principal','approved_by_head') NOT NULL,
  `grade_id` int(11) NOT NULL,
  `student_name` varchar(200) DEFAULT NULL,
  `subject_name` varchar(200) DEFAULT NULL,
  `section_name` varchar(100) DEFAULT NULL,
  `comment` text DEFAULT NULL,
  `is_read` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `principal_notifications`
--

INSERT INTO `principal_notifications` (`id`, `recipient_type`, `recipient_id`, `type`, `grade_id`, `student_name`, `subject_name`, `section_name`, `comment`, `is_read`, `created_at`) VALUES
(1, 'teacher', 5, '', 81, 'Zamora, Victor', 'VALUES EDUCATION', 'LOYALTY', NULL, 0, '2026-05-25 17:45:44'),
(3, 'teacher', 5, '', 70, 'Dionisio, Bianca', 'VALUES EDUCATION', 'LOYALTY', NULL, 0, '2026-05-25 17:45:44'),
(5, 'teacher', 5, '', 69, 'Cervantes, Monica', 'VALUES EDUCATION', 'LOYALTY', NULL, 0, '2026-05-25 17:45:44'),
(7, 'teacher', 5, '', 68, 'Cabral, Peter', 'VALUES EDUCATION', 'LOYALTY', NULL, 0, '2026-05-25 17:45:44'),
(9, 'teacher', 5, '', 67, 'Borromeo, Hannah', 'VALUES EDUCATION', 'LOYALTY', NULL, 0, '2026-05-25 17:45:44'),
(11, 'teacher', 5, '', 66, 'Beltran, Martin', 'VALUES EDUCATION', 'LOYALTY', NULL, 0, '2026-05-25 17:45:44'),
(13, 'teacher', 5, '', 65, 'Bautista, Julia', 'VALUES EDUCATION', 'LOYALTY', NULL, 0, '2026-05-25 17:45:44'),
(15, 'teacher', 5, '', 64, 'Bautista, Angelica', 'VALUES EDUCATION', 'LOYALTY', NULL, 0, '2026-05-25 17:45:44'),
(17, 'teacher', 5, '', 63, 'Bautista, Andrea', 'VALUES EDUCATION', 'LOYALTY', NULL, 0, '2026-05-25 17:45:44'),
(19, 'teacher', 5, '', 71, 'Dionisio, Joshua', 'VALUES EDUCATION', 'LOYALTY', NULL, 0, '2026-05-25 17:45:44'),
(21, 'teacher', 5, '', 72, 'Dionisio, Natalie', 'VALUES EDUCATION', 'LOYALTY', NULL, 0, '2026-05-25 17:45:44'),
(23, 'teacher', 5, '', 80, 'Zamora, Ramon', 'VALUES EDUCATION', 'LOYALTY', NULL, 0, '2026-05-25 17:45:44'),
(25, 'teacher', 5, '', 79, 'Villanueva, Dominic', 'VALUES EDUCATION', 'LOYALTY', NULL, 0, '2026-05-25 17:45:44'),
(27, 'teacher', 5, '', 78, 'Paglinawan, Diana', 'VALUES EDUCATION', 'LOYALTY', NULL, 0, '2026-05-25 17:45:44'),
(29, 'teacher', 5, '', 77, 'Padilla, David', 'VALUES EDUCATION', 'LOYALTY', NULL, 0, '2026-05-25 17:45:44'),
(31, 'teacher', 5, '', 76, 'Orozco, John', 'VALUES EDUCATION', 'LOYALTY', NULL, 0, '2026-05-25 17:45:44'),
(33, 'teacher', 5, '', 75, 'Montoya, Jane', 'VALUES EDUCATION', 'LOYALTY', NULL, 0, '2026-05-25 17:45:44'),
(35, 'teacher', 5, '', 74, 'Macaraeg, Julian', 'VALUES EDUCATION', 'LOYALTY', NULL, 0, '2026-05-25 17:45:44'),
(37, 'teacher', 5, '', 73, 'Lim, Elena', 'VALUES EDUCATION', 'LOYALTY', NULL, 0, '2026-05-25 17:45:44'),
(39, 'teacher', 5, '', 62, 'Austria, Hannah', 'VALUES EDUCATION', 'LOYALTY', NULL, 0, '2026-05-25 17:45:44'),
(41, 'teacher', 5, '', 21, 'Yap, Eduardo', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-25 17:45:50'),
(43, 'teacher', 5, '', 20, 'Tabios, Paolo', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-25 17:45:50'),
(45, 'teacher', 5, '', 19, 'Padilla, Anthony', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-25 17:45:50'),
(47, 'teacher', 5, '', 18, 'Macaraeg, Richard', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-25 17:45:50'),
(49, 'teacher', 5, '', 17, 'Gonzales, Victoria', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-25 17:45:50'),
(51, 'teacher', 5, '', 16, 'Gonzales, Lance', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-25 17:45:50'),
(53, 'teacher', 5, '', 7, 'Barroga, Lydia', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-25 17:45:50'),
(55, 'teacher', 5, '', 6, 'Barrientos, Maricel', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-25 17:45:50'),
(57, 'teacher', 5, '', 5, 'Balboa, Maricel', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-25 17:45:50'),
(59, 'teacher', 5, '', 4, 'Ayala, Hannah', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-25 17:45:50'),
(61, 'teacher', 5, '', 3, 'Aldana, Leo', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-25 17:45:50'),
(63, 'teacher', 5, '', 8, 'Cabrido, Anthony', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-25 17:45:50'),
(65, 'teacher', 5, '', 9, 'Cabrido, Hannah', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-25 17:45:50'),
(67, 'teacher', 5, '', 10, 'Cayabyab, Karen', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-25 17:45:50'),
(69, 'teacher', 5, '', 11, 'De Guzman, Eduardo', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-25 17:45:50'),
(71, 'teacher', 5, '', 12, 'Duran, Angelica', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-25 17:45:50'),
(73, 'teacher', 5, '', 13, 'Ferrer, Gilbert', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-25 17:45:50'),
(75, 'teacher', 5, '', 14, 'Ferrer, Mabel', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-25 17:45:50'),
(77, 'teacher', 5, '', 15, 'Gonzales, Daniel', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-25 17:45:50'),
(79, 'teacher', 5, '', 1, 'Aldana, Alice', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-25 17:45:50'),
(81, 'teacher', 5, '', 104, 'Rosenthal, Aki', 'VALUES EDUCATION', 'OBEDIENCE', NULL, 0, '2026-05-25 18:38:00'),
(82, 'registrar', 1, '', 104, 'Rosenthal, Aki', 'VALUES EDUCATION', 'OBEDIENCE', NULL, 0, '2026-05-25 18:38:00'),
(84, 'teacher', 5, '', 104, 'Rosenthal, Aki', 'VALUES EDUCATION', 'OBEDIENCE', NULL, 0, '2026-05-25 19:12:45'),
(85, 'registrar', 1, '', 104, 'Rosenthal, Aki', 'VALUES EDUCATION', 'OBEDIENCE', NULL, 0, '2026-05-25 19:12:45');

-- --------------------------------------------------------

--
-- Table structure for table `privacy_consents`
--

CREATE TABLE `privacy_consents` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL COMMENT 'FK → students.id',
  `consent_type` enum('data_privacy','info_accuracy') NOT NULL,
  `accepted` tinyint(1) NOT NULL DEFAULT 1,
  `ip_address` varchar(45) DEFAULT NULL,
  `user_agent` varchar(500) DEFAULT NULL,
  `accepted_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Immutable log of student consent events';

--
-- Dumping data for table `privacy_consents`
--

INSERT INTO `privacy_consents` (`id`, `student_id`, `consent_type`, `accepted`, `ip_address`, `user_agent`, `accepted_at`) VALUES
(3, 7, 'data_privacy', 1, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-17 15:39:31'),
(4, 7, 'info_accuracy', 1, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-17 15:39:31'),
(7, 9, 'data_privacy', 1, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-18 18:54:42'),
(8, 9, 'info_accuracy', 1, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-18 18:54:42'),
(9, 10, 'data_privacy', 1, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-18 19:04:57'),
(10, 10, 'info_accuracy', 1, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-18 19:04:57'),
(11, 14, 'data_privacy', 1, '192.168.68.157', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-20 18:11:05'),
(12, 14, 'info_accuracy', 1, '192.168.68.157', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-20 18:11:05'),
(13, 15, 'data_privacy', 1, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-22 11:20:51'),
(14, 15, 'info_accuracy', 1, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-22 11:20:51'),
(15, 16, 'data_privacy', 1, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-22 12:49:19'),
(16, 16, 'info_accuracy', 1, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-22 12:49:19'),
(17, 17, 'data_privacy', 1, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-24 07:51:18'),
(18, 17, 'info_accuracy', 1, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-24 07:51:18'),
(19, 418, 'data_privacy', 1, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-25 16:36:47'),
(20, 418, 'info_accuracy', 1, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-25 16:36:47'),
(21, 419, 'data_privacy', 1, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-28 18:58:08'),
(22, 419, 'info_accuracy', 1, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-28 18:58:08'),
(25, 421, 'data_privacy', 1, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-31 10:00:02'),
(26, 421, 'info_accuracy', 1, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-31 10:00:02'),
(29, 423, 'data_privacy', 1, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-31 20:06:38'),
(30, 423, 'info_accuracy', 1, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-31 20:06:38'),
(31, 424, 'data_privacy', 1, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-31 23:55:46'),
(32, 424, 'info_accuracy', 1, '::1', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36 OPR/131.0.0.0', '2026-05-31 23:55:46');

-- --------------------------------------------------------

--
-- Table structure for table `registrars`
--

CREATE TABLE `registrars` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL COMMENT 'FK → users.id',
  `first_name` varchar(100) NOT NULL,
  `middle_name` varchar(100) DEFAULT NULL,
  `last_name` varchar(100) NOT NULL,
  `employee_id` varchar(50) DEFAULT NULL COMMENT 'School employee number',
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `is_archived` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='One row per registrar staff member';

--
-- Dumping data for table `registrars`
--

INSERT INTO `registrars` (`id`, `user_id`, `first_name`, `middle_name`, `last_name`, `employee_id`, `is_active`, `created_at`, `updated_at`, `is_archived`) VALUES
(1, 9, 'Keith', NULL, 'Nacel', NULL, 1, '2026-05-19 07:51:10', '2026-05-21 17:53:52', 1),
(2, 15, 'Artemis', NULL, 'Arklight', NULL, 1, '2026-05-20 15:16:54', '2026-05-20 15:16:54', 0);

-- --------------------------------------------------------

--
-- Table structure for table `registration_documents`
--

CREATE TABLE `registration_documents` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL COMMENT 'FK → students.id',
  `school_year_id` int(11) NOT NULL COMMENT 'FK → school_years.id',
  `doc_type` enum('report_card','birth_certificate','good_moral','form_137','id_picture','baptismal_certificate','other') NOT NULL,
  `file_name` varchar(500) NOT NULL,
  `file_path` varchar(1000) NOT NULL COMMENT 'Server-side relative path',
  `file_size_kb` int(11) DEFAULT NULL,
  `mime_type` varchar(100) DEFAULT NULL,
  `status` enum('pending','approved','rejected') NOT NULL DEFAULT 'pending',
  `reviewed_by` int(11) DEFAULT NULL COMMENT 'FK → admins.id',
  `reviewed_at` datetime DEFAULT NULL,
  `notes` text DEFAULT NULL,
  `uploaded_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Required documents uploaded during Step 3 of registration';

-- --------------------------------------------------------

--
-- Table structure for table `remember_me_tokens`
--

CREATE TABLE `remember_me_tokens` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL COMMENT 'FK → users.id',
  `token_hash` varchar(64) NOT NULL COMMENT 'SHA-256 hash of the raw cookie token',
  `expires_at` datetime NOT NULL COMMENT 'Cookie + token expiry — 30 days from creation',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Persistent "Remember Me" tokens — one row per device per user';

-- --------------------------------------------------------

--
-- Table structure for table `role_redirects`
--

CREATE TABLE `role_redirects` (
  `role` enum('super_admin','admin','registrar','principal','coordinator','cashier','teacher','student','parent') NOT NULL,
  `redirect_url` varchar(500) NOT NULL COMMENT 'Relative or absolute URL',
  `label` varchar(100) DEFAULT NULL COMMENT 'Human-readable description',
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `role_redirects`
--

INSERT INTO `role_redirects` (`role`, `redirect_url`, `label`, `updated_at`) VALUES
('super_admin', '../../Admin Class Management/adminclass.html', 'Super Admin Dashboard', '2026-04-14 17:32:22'),
('admin', '../../Admin Class Management/adminclass.html', 'Admin Dashboard', '2026-04-14 17:32:22'),
('registrar', '../../Registrar/Registrar Register/Registrar_Enrollment.php', 'Registrar Home', '2026-05-02 12:05:35'),
('principal', '../../Principal/Principal Grades/principalgrades.html', 'Principal Grades View', '2026-04-13 17:31:10'),
('coordinator', '../../Coordinator/Coordinator Grades/CoordinatorGrades.html', 'Coordinator Grades View', '2026-04-13 17:31:10'),
('cashier', '../../Cashier/Cashier Management/CashierManagement.php', 'Cashier Dashboard', '2026-05-15 16:53:53'),
('teacher', '../../Teacher/Teacher Grade Encoding/teachergrade.html', 'Teacher Class View', '2026-05-15 21:15:33'),
('student', '../Student/student.html', 'Student Portal', '2026-04-13 17:31:10'),
('parent', '../Parent/parent_dashboard.html', 'Parent Dashboard', '2026-04-13 17:31:10');

-- --------------------------------------------------------

--
-- Table structure for table `rooms`
--

CREATE TABLE `rooms` (
  `id` int(11) NOT NULL,
  `number` varchar(20) NOT NULL COMMENT 'Room number/label, digits only',
  `capacity` int(11) NOT NULL DEFAULT 40,
  `status` enum('active','archived') NOT NULL DEFAULT 'active',
  `created_by` int(11) DEFAULT NULL COMMENT 'admin id who created the room',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `rooms`
--

INSERT INTO `rooms` (`id`, `number`, `capacity`, `status`, `created_by`, `created_at`, `updated_at`) VALUES
(1, '100', 25, 'active', 1, '2026-05-21 16:59:29', '2026-05-21 16:59:29'),
(2, '102', 25, 'active', 1, '2026-05-21 16:59:51', '2026-05-21 16:59:51'),
(3, '103', 25, 'active', 1, '2026-05-21 17:03:50', '2026-05-21 17:09:58'),
(4, '104', 25, 'active', 1, '2026-05-21 17:10:03', '2026-05-21 17:10:03'),
(5, '105', 25, 'active', 1, '2026-05-21 17:10:10', '2026-05-21 17:10:10'),
(6, '106', 25, 'active', 1, '2026-05-24 17:06:17', '2026-05-24 17:06:17'),
(7, '107', 25, 'active', 1, '2026-05-24 17:06:37', '2026-05-24 17:06:37'),
(8, '108', 25, 'active', 1, '2026-05-24 17:06:44', '2026-05-24 17:06:44'),
(9, '109', 25, 'active', 1, '2026-05-24 17:06:51', '2026-05-24 17:06:51'),
(10, '110', 25, 'active', 1, '2026-05-24 17:06:56', '2026-05-24 17:06:56'),
(11, '111', 25, 'active', 1, '2026-05-24 17:07:02', '2026-05-24 17:07:02'),
(12, '112', 25, 'active', 1, '2026-05-24 17:07:06', '2026-05-24 17:07:06'),
(13, '113', 25, 'active', 1, '2026-05-24 17:07:11', '2026-05-24 17:07:11'),
(14, '114', 25, 'active', 1, '2026-05-24 17:07:14', '2026-05-24 17:07:14'),
(15, '115', 25, 'active', 1, '2026-05-24 17:07:23', '2026-05-24 17:07:23'),
(16, '116', 25, 'active', 1, '2026-05-24 17:07:32', '2026-05-24 17:07:32'),
(17, '117', 25, 'active', 1, '2026-05-24 17:07:41', '2026-05-24 17:07:41'),
(18, '118', 0, 'active', 1, '2026-05-25 09:42:10', '2026-05-25 09:42:10'),
(19, '119', 0, 'active', 1, '2026-05-29 12:19:23', '2026-05-29 12:19:23'),
(20, '120', 0, 'active', 1, '2026-05-29 12:19:33', '2026-05-30 04:14:26');

-- --------------------------------------------------------

--
-- Table structure for table `school_years`
--

CREATE TABLE `school_years` (
  `id` int(11) NOT NULL,
  `label` varchar(20) NOT NULL COMMENT 'e.g. 2025-2026',
  `start_date` date NOT NULL,
  `end_date` date NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 0,
  `created_by` int(11) NOT NULL COMMENT 'FK → admins.id',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `is_finalized` tinyint(1) NOT NULL DEFAULT 0,
  `is_confirmed` tinyint(1) NOT NULL DEFAULT 0 COMMENT '1 = admin confirmed & locked (editable again after end_date)',
  `status` enum('upcoming','active','completed') NOT NULL DEFAULT 'upcoming'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `school_years`
--

INSERT INTO `school_years` (`id`, `label`, `start_date`, `end_date`, `is_active`, `created_by`, `created_at`, `is_finalized`, `is_confirmed`, `status`) VALUES
(1, '2026-2027', '2026-05-17', '2027-05-17', 1, 1, '2026-05-16 18:34:16', 0, 1, 'active'),
(3, '2027-2028', '2027-12-05', '2028-12-05', 0, 1, '2026-05-21 19:29:51', 0, 1, 'upcoming'),
(4, '2028-2029', '2028-12-05', '2029-12-05', 0, 1, '2026-05-23 16:37:48', 0, 1, 'upcoming');

-- --------------------------------------------------------

--
-- Table structure for table `sections`
--

CREATE TABLE `sections` (
  `id` int(11) NOT NULL,
  `grade_level_id` int(11) NOT NULL,
  `name` varchar(100) NOT NULL COMMENT 'e.g. Apollo, Sampaguita',
  `status` enum('active','archived') NOT NULL DEFAULT 'active',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `room` varchar(50) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `sections`
--

INSERT INTO `sections` (`id`, `grade_level_id`, `name`, `status`, `created_at`, `updated_at`, `room`) VALUES
(1, 7, 'OBEDIENCE', 'active', '2026-05-16 19:23:50', '2026-05-25 09:26:34', '104'),
(2, 7, 'LOYALTY', 'active', '2026-05-16 19:23:56', '2026-05-25 09:26:30', '103'),
(3, 7, 'DIGNITY', 'active', '2026-05-16 19:24:03', '2026-05-25 08:53:13', '102'),
(4, 7, 'PEACE', 'active', '2026-05-16 19:24:09', '2026-05-25 09:26:37', '105'),
(5, 7, 'CERTITUDE', 'active', '2026-05-16 19:24:17', '2026-05-25 09:32:04', '100'),
(6, 8, 'PRUDENCE', 'active', '2026-05-16 19:25:04', '2026-05-25 09:26:50', '109'),
(7, 8, 'PATIENCE', 'active', '2026-05-16 19:25:26', '2026-05-25 09:26:47', '108'),
(8, 8, 'COMPETENCE', 'active', '2026-05-16 19:25:38', '2026-05-25 09:26:41', '106'),
(9, 8, 'DISCERNMENT', 'active', '2026-05-16 19:25:52', '2026-05-25 09:26:44', '107'),
(10, 9, 'WISDOM', 'active', '2026-05-16 19:26:05', '2026-05-25 09:27:00', '113'),
(11, 9, 'RIGHTEOUS', 'active', '2026-05-16 19:26:19', '2026-05-25 09:26:55', '111'),
(12, 9, 'TRANQUILITY', 'active', '2026-05-16 19:26:34', '2026-05-25 09:26:58', '112'),
(13, 9, 'COURAGE', 'active', '2026-05-16 19:26:41', '2026-05-25 09:26:52', '110'),
(14, 10, 'HUMILITY', 'active', '2026-05-16 19:26:52', '2026-05-25 09:27:07', '115'),
(15, 10, 'HONESTY', 'active', '2026-05-16 19:27:05', '2026-05-25 09:27:03', '114'),
(16, 10, 'INTEGRITY', 'active', '2026-05-16 19:27:30', '2026-05-25 09:27:09', '116'),
(17, 10, 'PERSEVERANCE', 'active', '2026-05-16 19:27:43', '2026-05-29 15:50:15', '117');

-- --------------------------------------------------------

--
-- Table structure for table `section_school_years`
--

CREATE TABLE `section_school_years` (
  `id` int(11) NOT NULL,
  `section_id` int(11) NOT NULL,
  `school_year_id` int(11) NOT NULL,
  `capacity` int(11) NOT NULL DEFAULT 40,
  `enrolled_count` int(11) NOT NULL DEFAULT 0 COMMENT 'Maintained by enrollment module triggers',
  `adviser_id` int(11) DEFAULT NULL COMMENT 'FK → teachers.id, optional at creation',
  `status` enum('open','closed','archived') NOT NULL DEFAULT 'open',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `section_school_years`
--

INSERT INTO `section_school_years` (`id`, `section_id`, `school_year_id`, `capacity`, `enrolled_count`, `adviser_id`, `status`, `created_at`, `updated_at`) VALUES
(1, 1, 1, 25, 22, 8, 'open', '2026-05-16 19:23:50', '2026-05-31 15:16:22'),
(2, 2, 1, 25, 20, 39, 'open', '2026-05-16 19:23:56', '2026-05-31 15:16:06'),
(3, 3, 1, 25, 21, 4, 'open', '2026-05-16 19:24:03', '2026-05-31 15:15:57'),
(4, 4, 1, 25, 14, 15, 'open', '2026-05-16 19:24:09', '2026-05-31 15:16:33'),
(5, 5, 1, 25, 7, 5, 'open', '2026-05-16 19:24:17', '2026-05-31 20:37:20'),
(6, 6, 1, 25, 20, 32, 'open', '2026-05-16 19:25:04', '2026-05-31 15:17:01'),
(7, 7, 1, 25, 20, 11, 'open', '2026-05-16 19:25:26', '2026-05-31 15:16:53'),
(8, 8, 1, 25, 20, 27, 'open', '2026-05-16 19:25:38', '2026-06-01 00:03:43'),
(9, 9, 1, 25, 20, 17, 'open', '2026-05-16 19:25:52', '2026-05-31 15:16:45'),
(10, 10, 1, 25, 9, 40, 'open', '2026-05-16 19:26:05', '2026-05-31 15:17:45'),
(11, 11, 1, 25, 25, 16, 'open', '2026-05-16 19:26:19', '2026-05-31 15:17:22'),
(12, 12, 1, 25, 9, 20, 'open', '2026-05-16 19:26:34', '2026-05-31 15:17:32'),
(13, 13, 1, 25, 22, 28, 'open', '2026-05-16 19:26:41', '2026-05-31 15:17:08'),
(14, 14, 1, 25, 16, 23, 'open', '2026-05-16 19:26:52', '2026-05-31 15:18:04'),
(15, 15, 1, 25, 20, 29, 'open', '2026-05-16 19:27:05', '2026-05-31 15:17:53'),
(16, 16, 1, 25, 15, 18, 'open', '2026-05-16 19:27:30', '2026-05-31 15:18:14'),
(17, 17, 1, 25, 21, 37, 'open', '2026-05-16 19:27:43', '2026-05-31 15:18:20');

--
-- Triggers `section_school_years`
--
DELIMITER $$
CREATE TRIGGER `trg_capacity_check` BEFORE UPDATE ON `section_school_years` FOR EACH ROW BEGIN
  IF NEW.enrolled_count > NEW.capacity THEN
    SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'Section capacity exceeded.';
  END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `students`
--

CREATE TABLE `students` (
  `id` int(11) NOT NULL,
  `user_id` int(11) DEFAULT NULL COMMENT 'FK → users.id — set after portal account is created',
  `lrn` varchar(12) DEFAULT NULL COMMENT 'Learner Reference Number (12-digit DepEd LRN)',
  `first_name` varchar(100) NOT NULL,
  `middle_name` varchar(100) DEFAULT NULL,
  `last_name` varchar(100) NOT NULL,
  `sex` enum('male','female') NOT NULL,
  `date_of_birth` date NOT NULL,
  `place_of_birth` varchar(255) DEFAULT NULL,
  `nationality` varchar(100) DEFAULT NULL,
  `religion` varchar(100) DEFAULT NULL,
  `address` varchar(500) NOT NULL,
  `city` varchar(150) NOT NULL,
  `province` varchar(150) NOT NULL,
  `zip_code` char(4) NOT NULL,
  `personal_email` varchar(255) NOT NULL COMMENT 'Gmail / Yahoo — OTP destination',
  `enrollment_type` enum('new','transferee','returning') NOT NULL DEFAULT 'new',
  `grade_level_id` int(11) NOT NULL COMMENT 'FK → grade_levels.id',
  `registration_status` enum('pending','registered','verified','enrolled','archived','rejected') NOT NULL DEFAULT 'pending',
  `data_last_updated` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `is_archived` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='One row per student — the canonical student identity record';

--
-- Dumping data for table `students`
--

INSERT INTO `students` (`id`, `user_id`, `lrn`, `first_name`, `middle_name`, `last_name`, `sex`, `date_of_birth`, `place_of_birth`, `nationality`, `religion`, `address`, `city`, `province`, `zip_code`, `personal_email`, `enrollment_type`, `grade_level_id`, `registration_status`, `data_last_updated`, `created_at`, `updated_at`, `is_archived`) VALUES
(7, 3, '000000000002', 'Perlica', 'Villon', 'Aguilar', 'female', '2001-12-05', 'Caloocan City', 'Filipino', 'Catholic', 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '2566', 'phillippejoshua27.5@gmail.com', 'new', 7, 'pending', '2026-05-29 12:07:55', '2026-05-17 15:38:15', '2026-05-29 12:07:55', 1),
(9, 6, '000000000004', 'Wise', 'Belle', 'Ramuela', 'female', '2015-05-11', 'Caloocan City', 'Filipino', 'Catholic', 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '2566', 'phillippejoshua279@gmail.com', 'new', 8, 'pending', '2026-05-22 12:43:14', '2026-05-18 18:53:52', '2026-05-22 12:43:14', 0),
(10, 7, '000000000003', 'Sumalanka', 'Samonela', 'Cruz', 'male', '2012-07-07', 'Caloocan City', 'Filipino', 'Catholic', 'Blk 12 Lot 15 Mahal ni Keith si Merl Dela Pena Street', 'City of Caloocan', 'Abra', '2566', 'phillippejoshua27.4@gmail.com', 'new', 7, 'pending', '2026-05-22 13:16:09', '2026-05-18 19:04:10', '2026-05-22 07:16:09', 0),
(11, NULL, '000000000006', 'Arklight', NULL, 'Menendez', 'male', '2009-05-05', 'Caloocan City', 'Filipino', NULL, 'Blk 15 Lot 21 Quezburn Machelletes 78 street Muenez Drive', 'City of Caloocan', 'None', '1445', 'phillippejoshu.a274@gmail.com', 'new', 8, 'pending', '2026-05-20 15:16:02', '2026-05-19 15:13:08', '2026-05-20 15:16:02', 1),
(12, NULL, '000000000007', 'Crylight', NULL, 'Requirella', 'female', '2003-05-05', 'Caloocan City', 'Filipino', 'Catholic', 'Blk 29 Lot 28 Quezrnos Maletes Drive 88 Majumin Santa Cruz', 'City of Caloocan', 'None', '2566', 'phillippejoshua2.75@gmail.com', 'new', 8, 'pending', '2026-05-20 15:16:04', '2026-05-19 16:01:12', '2026-05-20 15:16:04', 1),
(13, NULL, '000000000005', 'Artemis', NULL, 'Arklight', 'female', '2001-12-05', 'Caloocan City', 'Filipino', 'Catholic', 'Blk 19 Lot 38 Quezborn Santos City 86 balete Drive', 'City of Caloocan', 'None', '2566', 'phillippejoshua27.9@gmail.com', 'new', 8, 'pending', '2026-05-20 15:16:01', '2026-05-19 16:11:44', '2026-05-20 15:16:01', 1),
(14, 16, '000000000008', 'Mabel', 'Sarula', 'Samonteza', 'female', '2011-12-05', 'Caloocan City', 'Filipino', 'Catholic', 'Blk 30 Lot 15 Shamrock Street Castlespring heights Subdivision', 'City of Caloocan', 'None', '1000', 'phillippejoshua2.79@gmail.com', 'new', 8, 'pending', '2026-05-22 13:16:02', '2026-05-20 18:07:03', '2026-05-22 07:16:02', 0),
(15, 27, '000000000009', 'Quaterlyn', NULL, 'Requiem', 'female', '2009-06-05', 'Caloocan City', 'Filipino', NULL, 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '2576', 'p.hillippejoshua27.5@gmail.com', 'new', 7, 'rejected', '2026-05-28 19:48:36', '2026-05-22 11:18:39', '2026-05-28 19:48:36', 0),
(16, 28, '000000000010', 'Frieren', NULL, 'Samontella', 'male', '2002-01-01', 'Caloocan City', 'Filipino', NULL, 'Blk 12 Lot 15 Mahal ni Keith si Merl Dela Pena Street', 'City of Caloocan', 'NCR / Metro Manila', '2576', 'phillippe.joshua275@gmail.com', 'new', 7, 'registered', '2026-05-22 13:30:50', '2026-05-22 12:48:25', '2026-05-22 07:30:50', 0),
(17, 29, '000000000800', 'Suisei', NULL, 'Hoshimachi', 'female', '2002-12-06', 'Caloocan City', 'Filipino', 'Catholic', 'Blk 89 Lot 67 Hololive Cover inc', 'City of Caloocan', 'NCR / Metro Manila', '2577', 'columbina23.4@gmail.com', 'new', 10, 'enrolled', '2026-05-24 17:48:24', '2026-05-24 07:48:42', '2026-05-24 17:48:24', 0),
(18, 30, '000000000011', 'Andrei', 'De Guzman', 'Paglinawan', 'male', '2012-12-04', 'Valenzuela City', 'Filipino', 'Christian', 'Blk 6 Lot 7 Pansy Lane Sunrise Village', 'Valenzuela City', 'NCR / Metro Manila', '1422', 'andrei.paglinawan@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(19, 31, '000000000012', 'John', 'Lopez', 'Orozco', 'male', '2013-04-15', 'Valenzuela City', 'Filipino', 'Catholic', 'Blk 11 Lot 23 Ilang-Ilang Street Lakeview Estates', 'Valenzuela City', 'None', '1447', 'john.orozco@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(20, 32, '000000000013', 'Danielle', NULL, 'Bautista', 'female', '2013-02-03', 'Quezon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 3 Lot 24 Zinnia Street Sunrise Village', 'Quezon City', 'NCR / Metro Manila', '1405', 'danielle.bautista@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(21, 33, '000000000014', 'Philip', 'Santos', 'Almeda', 'male', '2014-10-28', 'Navotas City', 'Filipino', 'Catholic', 'Blk 15 Lot 25 Lotus Street Heritage Park Subdivision', 'Navotas City', 'NCR / Metro Manila', '1440', 'philip.almeda@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(22, 34, '000000000015', 'Eduardo', 'Navarro', 'De Guzman', 'male', '2013-03-12', 'Navotas City', 'Filipino', 'Iglesia ni Cristo', 'Blk 44 Lot 21 Gumamela Road Camarin North Subdivision', 'Navotas City', 'NCR / Metro Manila', '1430', 'eduardo.deguzman@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(23, 35, '000000000016', 'Lance', 'De Leon', 'Balboa', 'male', '2014-12-18', 'Malabon City', 'Filipino', 'Catholic', 'Blk 3 Lot 26 Waling-Waling Street Masinag Heights', 'Malabon City', 'None', '1447', 'lance.balboa@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(24, 36, '000000000017', 'Angelica', NULL, 'Bautista', 'female', '2014-12-11', 'Malabon City', 'Filipino', NULL, 'Blk 17 Lot 5 Pansy Lane Harmony Village', 'Malabon City', 'None', '1410', 'angelica.bautista@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(25, 37, '000000000018', 'Veronica', NULL, 'Dionisio', 'female', '2013-06-08', 'Malabon City', 'Filipino', 'Catholic', 'Blk 10 Lot 21 Bougainvillea Drive Greenfield Residences', 'Malabon City', 'None', '1401', 'veronica.dionisio@gmail.com', 'returning', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(26, 38, '000000000019', 'Angelica', 'Gonzalez', 'De Guzman', 'female', '2014-05-18', 'City of Caloocan', 'Filipino', 'Islam', 'Blk 50 Lot 21 Waling-Waling Street Heritage Park Subdivision', 'City of Caloocan', 'NCR / Metro Manila', '1430', 'angelica.deguzman@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(27, 39, '000000000020', 'Maricel', 'Ramos', 'Balboa', 'female', '2014-05-17', 'Malabon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 33 Lot 20 Calachuchi Lane Castlespring Heights Subdivision', 'Malabon City', 'NCR / Metro Manila', '1430', 'maricel.balboa@gmail.com', 'returning', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(28, 40, '000000000021', 'Diana', NULL, 'Ferrer', 'female', '2014-01-20', 'Navotas City', 'Filipino', 'Catholic', 'Blk 20 Lot 8 Jasmine Lane Bagumbong Residences', 'Navotas City', 'None', '1400', 'diana.ferrer@gmail.com', 'returning', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(29, 41, '000000000022', 'David', 'Aquino', 'Padilla', 'male', '2014-03-05', 'Quezon City', 'Filipino', 'Islam', 'Blk 28 Lot 7 Calachuchi Lane Harmony Village', 'Quezon City', 'NCR / Metro Manila', '1404', 'david.padilla@gmail.com', 'returning', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(30, 42, '000000000023', 'Lucia', 'Gonzalez', 'Mercado', 'female', '2014-08-04', 'Malabon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 36 Lot 8 Pansy Lane Crystal Valley Subdivision', 'Malabon City', 'NCR / Metro Manila', '1401', 'lucia.mercado@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(31, 43, '000000000024', 'Carlo', 'Andrade', 'Beltran', 'male', '2013-02-17', 'Malabon City', 'Filipino', 'Christian', 'Blk 9 Lot 24 Makopa Drive Bagumbong Residences', 'Malabon City', 'None', '1430', 'carlo.beltran@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(32, 44, '000000000025', 'Lydia', 'Ocampo', 'Barroga', 'female', '2013-06-14', 'Quezon City', 'Filipino', 'Catholic', 'Blk 42 Lot 4 Jasmine Lane Masinag Heights', 'Quezon City', 'None', '1440', 'lydia.barroga@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(33, 45, '000000000026', 'Caroline', 'Lopez', 'Benedicto', 'female', '2013-03-14', 'Malabon City', 'Filipino', 'Born Again', 'Blk 5 Lot 15 Dahlia Drive Crystal Valley Subdivision', 'Malabon City', 'None', '1420', 'caroline.benedicto@gmail.com', 'returning', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(34, 46, '000000000027', 'Dominic', NULL, 'Villanueva', 'male', '2012-03-14', 'Quezon City', 'Filipino', 'Christian', 'Blk 11 Lot 13 Sampaguita Street Masinag Heights', 'Quezon City', 'None', '1403', 'dominic.villanueva@gmail.com', 'returning', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(35, 47, '000000000028', 'Monica', 'Ramos', 'Cabral', 'female', '2014-11-23', 'Quezon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 4 Lot 19 Jasmine Lane Harmony Village', 'Quezon City', 'NCR / Metro Manila', '1403', 'monica.cabral@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(36, 48, '000000000029', 'Angela', 'Jimenez', 'Alejo', 'female', '2014-03-02', 'Valenzuela City', 'Filipino', 'Catholic', 'Blk 44 Lot 28 Pansy Lane Masinag Heights', 'Valenzuela City', 'NCR / Metro Manila', '1402', 'angela.alejo@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(37, 49, '000000000030', 'Lance', 'Mendoza', 'Gonzales', 'male', '2012-07-22', 'Valenzuela City', 'Filipino', 'Born Again', 'Blk 21 Lot 8 Champaca Road Masinag Heights', 'Valenzuela City', 'None', '1404', 'lance.gonzales@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(38, 50, '000000000031', 'Matthew', 'Reyes', 'Dumlao', 'male', '2012-01-15', 'Valenzuela City', 'Filipino', 'Islam', 'Blk 17 Lot 5 Adelfa Street Heritage Park Subdivision', 'Valenzuela City', 'NCR / Metro Manila', '1401', 'matthew.dumlao@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(39, 51, '000000000032', 'Peter', 'Santos', 'Cabral', 'male', '2014-12-10', 'Valenzuela City', 'Filipino', 'Islam', 'Blk 43 Lot 4 Rosal Avenue Panorama Heights', 'Valenzuela City', 'NCR / Metro Manila', '1430', 'peter.cabral@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(40, 52, '000000000033', 'Emmanuel', 'De Leon', 'Paglinawan', 'male', '2013-10-07', 'Navotas City', 'Filipino', NULL, 'Blk 33 Lot 16 Champaca Road Sta. Monica Hills', 'Navotas City', 'NCR / Metro Manila', '1430', 'emmanuel.paglinawan@gmail.com', 'returning', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(41, 53, '000000000034', 'Dominic', 'De Leon', 'Macapagal', 'male', '2012-01-11', 'Malabon City', 'Filipino', NULL, 'Blk 46 Lot 14 Sampaguita Street Heritage Park Subdivision', 'Malabon City', 'None', '1402', 'dominic.macapagal@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(42, 54, '000000000035', 'Gilbert', 'Estrada', 'Ferrer', 'male', '2014-09-05', 'Quezon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 3 Lot 29 Adelfa Street Bagumbong Residences', 'Quezon City', 'NCR / Metro Manila', '1400', 'gilbert.ferrer@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(43, 55, '000000000036', 'Emmanuel', NULL, 'Cipriano', 'male', '2013-10-24', 'Malabon City', 'Filipino', 'Born Again', 'Blk 2 Lot 6 Waling-Waling Street Greenfield Residences', 'Malabon City', 'NCR / Metro Manila', '1402', 'emmanuel.cipriano@gmail.com', 'returning', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(44, 56, '000000000037', 'Hannah', 'Padilla', 'Borromeo', 'female', '2012-07-28', 'City of Caloocan', 'Filipino', 'Born Again', 'Blk 30 Lot 12 Lotus Street Sta. Monica Hills', 'City of Caloocan', 'None', '1403', 'hannah.borromeo@gmail.com', 'returning', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(45, 57, '000000000038', 'Julian', NULL, 'Alcantara', 'male', '2013-06-09', 'City of Caloocan', 'Filipino', NULL, 'Blk 44 Lot 27 Waling-Waling Street Crystal Valley Subdivision', 'City of Caloocan', 'None', '1405', 'julianalcantara@gmail.com', 'new', 7, 'enrolled', '2026-05-30 20:48:44', '2026-05-24 23:00:00', '2026-05-30 20:48:44', 0),
(46, 58, '000000000039', 'Lorenzo', 'De Leon', 'Barrientos', 'male', '2012-02-20', 'Quezon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 33 Lot 4 Marigold Avenue Camarin North Subdivision', 'Quezon City', 'None', '1440', 'lorenzo.barrientos@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(47, 59, '000000000040', 'Leo', NULL, 'Aldana', 'male', '2012-09-26', 'Valenzuela City', 'Filipino', 'Christian', 'Blk 43 Lot 30 Waling-Waling Street Camarin North Subdivision', 'Valenzuela City', 'NCR / Metro Manila', '1405', 'leo.aldana@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(48, 60, '000000000041', 'Charlene', NULL, 'Padilla', 'female', '2014-05-22', 'Quezon City', 'Filipino', NULL, 'Blk 9 Lot 7 Ilang-Ilang Street Novaliches Proper', 'Quezon City', 'None', '1410', 'charlene.padilla@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(49, 61, '000000000042', 'Elena', 'Fernandez', 'Lim', 'female', '2014-01-10', 'Navotas City', 'Filipino', 'Islam', 'Blk 21 Lot 15 Zinnia Street Golden Villa Subdivision', 'Navotas City', 'NCR / Metro Manila', '1410', 'elena.lim@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(50, 62, '000000000043', 'Vincent', NULL, 'Duran', 'male', '2014-03-22', 'City of Caloocan', 'Filipino', NULL, 'Blk 22 Lot 3 Pansy Lane Novaliches Proper', 'City of Caloocan', 'None', '1421', 'vincent.duran@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(51, 63, '000000000044', 'Frances', 'Aguilar', 'Samonte', 'female', '2012-04-16', 'Valenzuela City', 'Filipino', 'Christian', 'Blk 37 Lot 7 Marigold Avenue Golden Villa Subdivision', 'Valenzuela City', 'NCR / Metro Manila', '1420', 'frances.samonte@gmail.com', 'returning', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(52, 64, '000000000045', 'Hannah', NULL, 'Ayala', 'female', '2012-02-25', 'Quezon City', 'Filipino', NULL, 'Blk 4 Lot 18 Pansy Lane Sta. Monica Hills', 'Quezon City', 'NCR / Metro Manila', '1402', 'hannah.ayala@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(53, 65, '000000000046', 'Sean', NULL, 'Austria', 'male', '2014-09-18', 'Valenzuela City', 'Filipino', 'Christian', 'Blk 47 Lot 29 Ilang-Ilang Street Sta. Monica Hills', 'Valenzuela City', 'None', '1447', 'sean.austria@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(54, 66, '000000000047', 'Diana', NULL, 'Paglinawan', 'female', '2013-05-25', 'Malabon City', 'Filipino', 'Islam', 'Blk 16 Lot 9 Zinnia Street Heritage Park Subdivision', 'Malabon City', 'None', '1447', 'diana.paglinawan@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(55, 67, '000000000048', 'Grace', 'Villanueva', 'Borromeo', 'female', '2014-02-05', 'Malabon City', 'Filipino', NULL, 'Blk 14 Lot 3 Ilang-Ilang Street Masinag Heights', 'Malabon City', 'NCR / Metro Manila', '1410', 'grace.borromeo@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(56, 68, '000000000049', 'Sofia', 'Cruz', 'Dumlao', 'female', '2013-07-25', 'Valenzuela City', 'Filipino', 'Islam', 'Blk 1 Lot 12 Lotus Street Greenfield Residences', 'Valenzuela City', 'NCR / Metro Manila', '1447', 'sofia.dumlao@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(57, 69, '000000000050', 'Mabel', NULL, 'Ferrer', 'female', '2014-10-08', 'Quezon City', 'Filipino', 'Christian', 'Blk 25 Lot 11 Marigold Avenue Harmony Village', 'Quezon City', 'NCR / Metro Manila', '1404', 'mabel.ferrer@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(58, 70, '000000000051', 'Stephen', 'Mendoza', 'Velasco', 'male', '2014-01-13', 'Valenzuela City', 'Filipino', NULL, 'Blk 30 Lot 6 Jasmine Lane Panorama Heights', 'Valenzuela City', 'NCR / Metro Manila', '1401', 'stephen.velasco@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(59, 71, '000000000052', 'Julia', 'Espinosa', 'Bautista', 'female', '2013-05-25', 'Quezon City', 'Filipino', 'Christian', 'Blk 35 Lot 2 Adelfa Street Bagumbong Residences', 'Quezon City', 'None', '1401', 'julia.bautista@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(60, 72, '000000000053', 'Anthony', 'De Guzman', 'Reyes', 'male', '2012-01-20', 'Malabon City', 'Filipino', 'Christian', 'Blk 37 Lot 7 Zinnia Street Harmony Village', 'Malabon City', 'NCR / Metro Manila', '1402', 'anthony.reyes@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(61, 73, '000000000054', 'Leia', 'Ramos', 'Balboa', 'female', '2014-02-25', 'Malabon City', 'Filipino', 'Islam', 'Blk 20 Lot 19 Marigold Avenue Masinag Heights', 'Malabon City', 'None', '1401', 'leia.balboa@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(62, 74, '000000000055', 'Daniel', NULL, 'Gonzales', 'male', '2014-04-04', 'Navotas City', 'Filipino', 'Islam', 'Blk 23 Lot 18 Ilang-Ilang Street Novaliches Proper', 'Navotas City', 'NCR / Metro Manila', '1447', 'daniel.gonzales@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(63, 75, '000000000056', 'Angelica', 'Aguilar', 'Esquivel', 'female', '2013-08-04', 'Quezon City', 'Filipino', 'Christian', 'Blk 28 Lot 6 Champaca Road Camarin North Subdivision', 'Quezon City', 'None', '1430', 'angelica.esquivel@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(64, 76, '000000000057', 'Natalie', NULL, 'Dionisio', 'female', '2014-05-11', 'Malabon City', 'Filipino', 'Christian', 'Blk 30 Lot 19 Marigold Avenue Lakeview Estates', 'Malabon City', 'NCR / Metro Manila', '1404', 'natalie.dionisio@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(65, 77, '000000000058', 'Tristan', 'Iglesias', 'Tabios', 'male', '2012-06-26', 'Navotas City', 'Filipino', 'Islam', 'Blk 18 Lot 18 Sampaguita Street Sunrise Village', 'Navotas City', 'None', '1404', 'tristan.tabios@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(66, 78, '000000000059', 'David', NULL, 'Benedicto', 'male', '2013-09-25', 'Malabon City', 'Filipino', NULL, 'Blk 2 Lot 3 Lotus Street Bagumbong Residences', 'Malabon City', 'None', '1430', 'david.benedicto@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(67, 79, '000000000060', 'Hannah', NULL, 'Cabrido', 'female', '2013-08-18', 'Valenzuela City', 'Filipino', NULL, 'Blk 23 Lot 23 Zinnia Street Panorama Heights', 'Valenzuela City', 'None', '1410', 'hannah.cabrido@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(68, 80, '000000000061', 'Irene', 'Cruz', 'Beltran', 'female', '2013-02-24', 'Valenzuela City', 'Filipino', 'Born Again', 'Blk 18 Lot 24 Lotus Street Heritage Park Subdivision', 'Valenzuela City', 'NCR / Metro Manila', '1403', 'irene.beltran@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(69, 81, '000000000062', 'Martin', 'Dela Cruz', 'Beltran', 'male', '2012-12-18', 'Malabon City', 'Filipino', 'Catholic', 'Blk 45 Lot 5 Makopa Drive Heritage Park Subdivision', 'Malabon City', 'None', '1400', 'martin.beltran@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(70, 82, '000000000063', 'Marcus', 'Espinosa', 'Duran', 'male', '2012-01-09', 'Quezon City', 'Filipino', 'Christian', 'Blk 37 Lot 21 Jasmine Lane Castlespring Heights Subdivision', 'Quezon City', 'NCR / Metro Manila', '1401', 'marcus.duran@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(71, 83, '000000000064', 'Matthew', NULL, 'Almeda', 'male', '2012-09-25', 'Quezon City', 'Filipino', 'Islam', 'Blk 29 Lot 10 Ilang-Ilang Street Panorama Heights', 'Quezon City', 'NCR / Metro Manila', '1447', 'matthew.almeda@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(72, 84, '000000000065', 'Eduardo', NULL, 'Yap', 'male', '2014-04-09', 'City of Caloocan', 'Filipino', 'Born Again', 'Blk 11 Lot 1 Ilang-Ilang Street Golden Villa Subdivision', 'City of Caloocan', 'NCR / Metro Manila', '1403', 'eduardo.yap@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(73, 85, '000000000066', 'Jasmine', 'Padilla', 'Aldana', 'female', '2013-12-28', 'Quezon City', 'Filipino', 'Born Again', 'Blk 41 Lot 19 Calachuchi Lane Masinag Heights', 'Quezon City', 'NCR / Metro Manila', '1430', 'jasmine.aldana@gmail.com', 'returning', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(74, 86, '000000000067', 'Julian', 'De Leon', 'Macaraeg', 'male', '2012-02-02', 'Malabon City', 'Filipino', NULL, 'Blk 19 Lot 15 Dahlia Drive Golden Villa Subdivision', 'Malabon City', 'None', '1422', 'julian.macaraeg@gmail.com', 'returning', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(75, 87, '000000000068', 'Lucia', 'Lopez', 'Yap', 'female', '2013-08-03', 'Valenzuela City', 'Filipino', NULL, 'Blk 17 Lot 1 Gumamela Road Bagumbong Residences', 'Valenzuela City', 'NCR / Metro Manila', '1410', 'lucia.yap@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(76, 88, '000000000069', 'Luis', 'Reyes', 'Fontanilla', 'male', '2012-08-17', 'Quezon City', 'Filipino', 'Islam', 'Blk 32 Lot 3 Makopa Drive Lakeview Estates', 'Quezon City', 'None', '1402', 'luis.fontanilla@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(77, 89, '000000000070', 'Karen', NULL, 'Cayabyab', 'female', '2012-06-14', 'Quezon City', 'Filipino', 'Christian', 'Blk 36 Lot 2 Zinnia Street Heritage Park Subdivision', 'Quezon City', 'None', '1430', 'karen.cayabyab@gmail.com', 'returning', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(78, 90, '000000000071', 'Irene', 'Reyes', 'Cayabyab', 'female', '2013-09-27', 'City of Caloocan', 'Filipino', 'Catholic', 'Blk 24 Lot 20 Makopa Drive Novaliches Proper', 'City of Caloocan', 'None', '1410', 'irene.cayabyab@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(79, 91, '000000000072', 'Andrea', 'Bernardo', 'Bautista', 'female', '2013-08-23', 'Quezon City', 'Filipino', NULL, 'Blk 16 Lot 23 Bougainvillea Drive Panorama Heights', 'Quezon City', 'NCR / Metro Manila', '1400', 'andrea.bautista@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(80, 92, '000000000073', 'Raymond', 'Santos', 'Almeda', 'male', '2012-08-04', 'Malabon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 18 Lot 14 Makopa Drive Golden Villa Subdivision', 'Malabon City', 'None', '1440', 'raymond.almeda@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(81, 93, '000000000074', 'Sean', 'Cruz', 'Flores', 'male', '2014-09-24', 'Malabon City', 'Filipino', 'Christian', 'Blk 33 Lot 9 Sampaguita Street Panorama Heights', 'Malabon City', 'NCR / Metro Manila', '1404', 'sean.flores@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(82, 94, '000000000075', 'Victoria', NULL, 'Gonzales', 'female', '2013-03-15', 'Valenzuela City', 'Filipino', 'Iglesia ni Cristo', 'Blk 35 Lot 13 Zinnia Street Lakeview Estates', 'Valenzuela City', 'None', '1405', 'victoria.gonzales@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(83, 95, '000000000076', 'Kyle', 'Torres', 'Fontanilla', 'male', '2013-01-11', 'Quezon City', 'Filipino', NULL, 'Blk 42 Lot 5 Makopa Drive Crystal Valley Subdivision', 'Quezon City', 'None', '1410', 'kyle.fontanilla@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(84, 96, '000000000077', 'Victor', 'Torres', 'Zamora', 'male', '2012-08-04', 'Valenzuela City', 'Filipino', NULL, 'Blk 42 Lot 5 Gumamela Road Golden Villa Subdivision', 'Valenzuela City', 'None', '1400', 'victor.zamora@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(85, 97, '000000000078', 'Kate', NULL, 'Lim', 'female', '2014-02-28', 'Navotas City', 'Filipino', NULL, 'Blk 49 Lot 16 Jasmine Lane Camarin North Subdivision', 'Navotas City', 'None', '1405', 'kate.lim@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(86, 98, '000000000079', 'Kyle', NULL, 'Macapagal', 'male', '2013-04-24', 'City of Caloocan', 'Filipino', NULL, 'Blk 7 Lot 15 Bougainvillea Drive Harmony Village', 'City of Caloocan', 'None', '1401', 'kyle.macapagal@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(87, 99, '000000000080', 'Alice', 'Andrade', 'Aldana', 'female', '2013-06-12', 'Quezon City', 'Filipino', 'Islam', 'Blk 44 Lot 26 Bougainvillea Drive Castlespring Heights Subdivision', 'Quezon City', 'NCR / Metro Manila', '1403', 'alice.aldana@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(88, 100, '000000000081', 'David', NULL, 'Lim', 'male', '2014-11-08', 'Quezon City', 'Filipino', 'Christian', 'Blk 30 Lot 9 Sampaguita Street Greenfield Residences', 'Quezon City', 'NCR / Metro Manila', '1403', 'david.lim@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(89, 101, '000000000082', 'Jane', 'Aquino', 'Montoya', 'female', '2013-06-19', 'Navotas City', 'Filipino', 'Iglesia ni Cristo', 'Blk 20 Lot 7 Marigold Avenue Sta. Monica Hills', 'Navotas City', 'None', '1440', 'jane.montoya@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(90, 102, '000000000083', 'Caroline', 'Estrada', 'Benedicto', 'female', '2014-05-23', 'Navotas City', 'Filipino', 'Christian', 'Blk 37 Lot 28 Jasmine Lane Camarin North Subdivision', 'Navotas City', 'NCR / Metro Manila', '1430', 'caroline.benedicto102@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(91, 103, '000000000084', 'Jane', NULL, 'Robles', 'female', '2014-06-08', 'Malabon City', 'Filipino', NULL, 'Blk 44 Lot 27 Rosal Avenue Novaliches Proper', 'Malabon City', 'None', '1430', 'jane.robles@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(92, 104, '000000000085', 'Anthony', NULL, 'Cabrido', 'male', '2012-10-12', 'Malabon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 12 Lot 7 Rosal Avenue Greenfield Residences', 'Malabon City', 'NCR / Metro Manila', '1404', 'anthony.cabrido@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(93, 105, '000000000086', 'Sara', NULL, 'Esquivel', 'female', '2012-05-27', 'Quezon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 30 Lot 3 Rosal Avenue Greenfield Residences', 'Quezon City', 'None', '1440', 'sara.esquivel@gmail.com', 'returning', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(94, 106, '000000000087', 'Ramon', NULL, 'Zamora', 'male', '2014-06-03', 'Quezon City', 'Filipino', 'Islam', 'Blk 24 Lot 22 Champaca Road Camarin North Subdivision', 'Quezon City', 'NCR / Metro Manila', '1404', 'ramon.zamora@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(95, 107, '000000000088', 'Leia', NULL, 'Andres', 'female', '2013-01-20', 'Valenzuela City', 'Filipino', 'Born Again', 'Blk 41 Lot 27 Zinnia Street Harmony Village', 'Valenzuela City', 'None', '1422', 'leia.andres@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(96, 108, '000000000089', 'Lydia', 'Andrade', 'Aquino', 'female', '2013-08-04', 'City of Caloocan', 'Filipino', 'Born Again', 'Blk 24 Lot 22 Ilang-Ilang Street Camarin North Subdivision', 'City of Caloocan', 'NCR / Metro Manila', '1421', 'lydia.aquino@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(97, 109, '000000000090', 'Richard', 'Iglesias', 'Macaraeg', 'male', '2014-07-09', 'City of Caloocan', 'Filipino', 'Christian', 'Blk 16 Lot 28 Adelfa Street Heritage Park Subdivision', 'City of Caloocan', 'None', '1403', 'richard.macaraeg@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(98, 110, '000000000091', 'Sofia', NULL, 'Tuason', 'female', '2013-01-13', 'Navotas City', 'Filipino', 'Christian', 'Blk 14 Lot 21 Sampaguita Street Crystal Valley Subdivision', 'Navotas City', 'NCR / Metro Manila', '1401', 'sofia.tuason@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(99, 111, '000000000092', 'Hannah', NULL, 'Austria', 'female', '2012-02-27', 'Valenzuela City', 'Filipino', 'Born Again', 'Blk 15 Lot 11 Rosal Avenue Greenfield Residences', 'Valenzuela City', 'NCR / Metro Manila', '1422', 'hannah.austria@gmail.com', 'returning', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(100, 112, '000000000093', 'Marco', NULL, 'Tabios', 'male', '2012-09-09', 'Malabon City', 'Filipino', 'Catholic', 'Blk 23 Lot 26 Pansy Lane Camarin North Subdivision', 'Malabon City', 'NCR / Metro Manila', '1430', 'marco.tabios@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(101, 113, '000000000094', 'Alexandra', 'Bernardo', 'Barrientos', 'female', '2014-07-17', 'City of Caloocan', 'Filipino', 'Christian', 'Blk 33 Lot 19 Dahlia Drive Golden Villa Subdivision', 'City of Caloocan', 'NCR / Metro Manila', '1420', 'alexandra.barrientos@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(102, 114, '000000000095', 'Anthony', NULL, 'Padilla', 'male', '2014-09-10', 'Quezon City', 'Filipino', 'Christian', 'Blk 28 Lot 22 Dahlia Drive Golden Villa Subdivision', 'Quezon City', 'NCR / Metro Manila', '1400', 'anthony.padilla@gmail.com', 'returning', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(103, 115, '000000000096', 'Anna', 'Mendoza', 'Tuason', 'female', '2012-02-05', 'Navotas City', 'Filipino', 'Islam', 'Blk 30 Lot 17 Ilang-Ilang Street Heritage Park Subdivision', 'Navotas City', 'None', '1410', 'anna.tuason@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(104, 116, '000000000097', 'Joshua', 'De Guzman', 'Dionisio', 'male', '2013-06-27', 'Quezon City', 'Filipino', NULL, 'Blk 28 Lot 11 Champaca Road Lakeview Estates', 'Quezon City', 'None', '1410', 'joshua.dionisio@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(105, 117, '000000000098', 'Theodore', 'Aquino', 'Alfonso', 'male', '2012-07-04', 'Navotas City', 'Filipino', 'Catholic', 'Blk 36 Lot 18 Waling-Waling Street Novaliches Proper', 'Navotas City', 'NCR / Metro Manila', '1421', 'theodore.alfonso@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(106, 118, '000000000099', 'Raymond', NULL, 'Cipriano', 'male', '2013-12-02', 'Navotas City', 'Filipino', 'Catholic', 'Blk 14 Lot 5 Makopa Drive Bagumbong Residences', 'Navotas City', 'None', '1405', 'raymond.cipriano@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(107, 119, '000000000100', 'Paolo', 'Bautista', 'Tabios', 'male', '2013-10-08', 'Quezon City', 'Filipino', NULL, 'Blk 18 Lot 1 Bougainvillea Drive Panorama Heights', 'Quezon City', 'NCR / Metro Manila', '1422', 'paolo.tabios@gmail.com', 'returning', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(108, 120, '000000000101', 'Kate', 'Torres', 'Cipriano', 'female', '2012-10-22', 'Quezon City', 'Filipino', NULL, 'Blk 2 Lot 3 Calachuchi Lane Masinag Heights', 'Quezon City', 'NCR / Metro Manila', '1402', 'kate.cipriano@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(109, 121, '000000000102', 'Monica', 'Dela Cruz', 'Cervantes', 'female', '2014-06-25', 'Valenzuela City', 'Filipino', 'Born Again', 'Blk 40 Lot 2 Gumamela Road Panorama Heights', 'Valenzuela City', 'NCR / Metro Manila', '1400', 'monica.cervantes@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(110, 122, '000000000103', 'Maria', 'Garcia', 'Enriquez', 'female', '2013-04-25', 'Valenzuela City', 'Filipino', 'Christian', 'Blk 44 Lot 22 Makopa Drive Sunrise Village', 'Valenzuela City', 'NCR / Metro Manila', '1405', 'maria.enriquez@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(111, 123, '000000000104', 'Amanda', 'Mendoza', 'Beltran', 'female', '2012-01-07', 'Navotas City', 'Filipino', 'Born Again', 'Blk 19 Lot 11 Dahlia Drive Crystal Valley Subdivision', 'Navotas City', 'NCR / Metro Manila', '1447', 'amanda.beltran@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(112, 124, '000000000105', 'Maricel', 'Lopez', 'Barrientos', 'female', '2014-04-17', 'Valenzuela City', 'Filipino', 'Christian', 'Blk 3 Lot 14 Sampaguita Street Golden Villa Subdivision', 'Valenzuela City', 'None', '1401', 'maricel.barrientos@gmail.com', 'returning', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(113, 125, '000000000106', 'Miguel', 'Fernandez', 'Fontanilla', 'male', '2014-11-14', 'Navotas City', 'Filipino', 'Catholic', 'Blk 11 Lot 26 Zinnia Street Sta. Monica Hills', 'Navotas City', 'NCR / Metro Manila', '1410', 'miguel.fontanilla@gmail.com', 'returning', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(114, 126, '000000000107', 'Bianca', NULL, 'Dionisio', 'female', '2012-07-19', 'Quezon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 15 Lot 11 Bougainvillea Drive Heritage Park Subdivision', 'Quezon City', 'NCR / Metro Manila', '1410', 'bianca.dionisio@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(115, 127, '000000000108', 'Xavier', 'Reyes', 'Esquivel', 'male', '2013-06-24', 'Malabon City', 'Filipino', 'Born Again', 'Blk 12 Lot 20 Rosal Avenue Greenfield Residences', 'Malabon City', 'NCR / Metro Manila', '1401', 'xavier.esquivel@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(116, 128, '000000000109', 'Jacob', NULL, 'Yap', 'male', '2013-08-25', 'Valenzuela City', 'Filipino', 'Islam', 'Blk 40 Lot 11 Waling-Waling Street Castlespring Heights Subdivision', 'Valenzuela City', 'None', '1430', 'jacob.yap@gmail.com', 'transferee', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(117, 129, '000000000110', 'Angelica', 'Dela Cruz', 'Duran', 'female', '2013-10-02', 'Navotas City', 'Filipino', 'Christian', 'Blk 4 Lot 12 Lotus Street Heritage Park Subdivision', 'Navotas City', 'NCR / Metro Manila', '1404', 'angelica.duran@gmail.com', 'new', 7, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(118, 130, '000000000111', 'Victor', 'Lopez', 'De Guzman', 'male', '2013-01-15', 'Valenzuela City', 'Filipino', 'Islam', 'Blk 10 Lot 2 Zinnia Street Heritage Park Subdivision', 'Valenzuela City', 'NCR / Metro Manila', '1405', 'victor.deguzman@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(119, 131, '000000000112', 'Beatrice', 'Andrade', 'Esquivel', 'female', '2011-12-15', 'Quezon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 25 Lot 14 Waling-Waling Street Novaliches Proper', 'Quezon City', 'NCR / Metro Manila', '1405', 'beatrice.esquivel@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(120, 132, '000000000113', 'Neil', 'Lopez', 'Alfonso', 'male', '2013-07-10', 'Navotas City', 'Filipino', 'Catholic', 'Blk 10 Lot 30 Adelfa Street Panorama Heights', 'Navotas City', 'NCR / Metro Manila', '1405', 'neil.alfonso@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(121, 133, '000000000114', 'Christina', NULL, 'Hernandez', 'female', '2011-05-18', 'Quezon City', 'Filipino', NULL, 'Blk 48 Lot 22 Gumamela Road Novaliches Proper', 'Quezon City', 'None', '1402', 'christina.hernandez@gmail.com', 'transferee', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(122, 134, '000000000115', 'Rosa', 'Dela Cruz', 'Danao', 'female', '2011-04-11', 'Quezon City', 'Filipino', 'Born Again', 'Blk 19 Lot 28 Dahlia Drive Sunrise Village', 'Quezon City', 'NCR / Metro Manila', '1403', 'rosa.danao@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(123, 135, '000000000116', 'Oliver', NULL, 'Tolentino', 'male', '2011-10-13', 'Malabon City', 'Filipino', NULL, 'Blk 11 Lot 24 Zinnia Street Crystal Valley Subdivision', 'Malabon City', 'NCR / Metro Manila', '1402', 'oliver.tolentino@gmail.com', 'transferee', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(124, 136, '000000000117', 'Leah', NULL, 'Montoya', 'female', '2012-10-10', 'Quezon City', 'Filipino', 'Born Again', 'Blk 31 Lot 29 Calachuchi Lane Lakeview Estates', 'Quezon City', 'NCR / Metro Manila', '1421', 'leah.montoya@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(125, 137, '000000000118', 'Natalie', 'Fernandez', 'Robles', 'female', '2013-09-14', 'Malabon City', 'Filipino', 'Islam', 'Blk 17 Lot 2 Makopa Drive Sta. Monica Hills', 'Malabon City', 'NCR / Metro Manila', '1447', 'natalie.robles@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(126, 138, '000000000119', 'Stella', 'Torres', 'Villanueva', 'female', '2013-02-10', 'City of Caloocan', 'Filipino', 'Christian', 'Blk 10 Lot 27 Ilang-Ilang Street Heritage Park Subdivision', 'City of Caloocan', 'NCR / Metro Manila', '1404', 'stella.villanueva@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(127, 139, '000000000120', 'Samuel', 'Aguilar', 'Tolentino', 'male', '2012-01-13', 'Valenzuela City', 'Filipino', 'Christian', 'Blk 24 Lot 8 Sampaguita Street Lakeview Estates', 'Valenzuela City', 'None', '1403', 'samuel.tolentino@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(128, 140, '000000000121', 'Neil', 'Andrade', 'Salas', 'male', '2012-08-23', 'Malabon City', 'Filipino', 'Islam', 'Blk 6 Lot 1 Champaca Road Bagumbong Residences', 'Malabon City', 'None', '1420', 'neil.salas@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(129, 141, '000000000122', 'Xavier', 'Dela Cruz', 'Dionisio', 'male', '2011-05-04', 'City of Caloocan', 'Filipino', NULL, 'Blk 30 Lot 3 Dahlia Drive Sta. Monica Hills', 'City of Caloocan', 'NCR / Metro Manila', '1410', 'xavier.dionisio@gmail.com', 'transferee', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(130, 142, '000000000123', 'Sheila', 'Magno', 'Alcantara', 'female', '2011-12-05', 'Navotas City', 'Filipino', 'Islam', 'Blk 37 Lot 14 Bougainvillea Drive Novaliches Proper', 'Navotas City', 'None', '1400', 'sheila.alcantara@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(131, 143, '000000000124', 'Xavier', 'Jimenez', 'Danao', 'male', '2013-09-26', 'Valenzuela City', 'Filipino', 'Christian', 'Blk 25 Lot 12 Champaca Road Harmony Village', 'Valenzuela City', 'NCR / Metro Manila', '1410', 'xavier.danao@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(132, 144, '000000000125', 'Patrick', 'De Guzman', 'Salas', 'male', '2013-11-21', 'City of Caloocan', 'Filipino', 'Catholic', 'Blk 22 Lot 27 Bougainvillea Drive Sta. Monica Hills', 'City of Caloocan', 'None', '1402', 'patrick.salas@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(133, 145, '000000000126', 'Patricia', 'Bernardo', 'Macapagal', 'female', '2011-12-25', 'Quezon City', 'Filipino', 'Born Again', 'Blk 13 Lot 29 Jasmine Lane Lakeview Estates', 'Quezon City', 'NCR / Metro Manila', '1404', 'patricia.macapagal@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(134, 146, '000000000127', 'Rosa', NULL, 'De Villa', 'female', '2013-08-09', 'City of Caloocan', 'Filipino', 'Iglesia ni Cristo', 'Blk 4 Lot 28 Waling-Waling Street Panorama Heights', 'City of Caloocan', 'NCR / Metro Manila', '1404', 'rosa.devilla@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(135, 147, '000000000128', 'Peter', NULL, 'Dionisio', 'male', '2013-08-13', 'Navotas City', 'Filipino', NULL, 'Blk 34 Lot 9 Gumamela Road Harmony Village', 'Navotas City', 'NCR / Metro Manila', '1420', 'peter.dionisio@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(136, 148, '000000000129', 'Beatrice', 'Santos', 'Dionisio', 'female', '2011-09-10', 'Navotas City', 'Filipino', 'Iglesia ni Cristo', 'Blk 20 Lot 15 Ilang-Ilang Street Castlespring Heights Subdivision', 'Navotas City', 'NCR / Metro Manila', '1401', 'beatrice.dionisio@gmail.com', 'transferee', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(137, 149, '000000000130', 'Katrina', 'Torres', 'Doria', 'female', '2012-10-14', 'Navotas City', 'Filipino', NULL, 'Blk 24 Lot 17 Bougainvillea Drive Crystal Valley Subdivision', 'Navotas City', 'NCR / Metro Manila', '1401', 'katrina.doria@gmail.com', 'transferee', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(138, 150, '000000000131', 'Ryan', 'De Guzman', 'Aldana', 'male', '2013-06-12', 'Quezon City', 'Filipino', 'Born Again', 'Blk 24 Lot 12 Zinnia Street Greenfield Residences', 'Quezon City', 'NCR / Metro Manila', '1422', 'ryan.aldana@gmail.com', 'transferee', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(139, 151, '000000000132', 'Gabriel', 'Espinosa', 'Esteban', 'male', '2013-05-08', 'City of Caloocan', 'Filipino', 'Born Again', 'Blk 25 Lot 30 Dahlia Drive Panorama Heights', 'City of Caloocan', 'NCR / Metro Manila', '1440', 'gabriel.esteban@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(140, 152, '000000000133', 'Michelle', NULL, 'Bautista', 'female', '2012-12-16', 'Malabon City', 'Filipino', 'Catholic', 'Blk 46 Lot 15 Gumamela Road Greenfield Residences', 'Malabon City', 'NCR / Metro Manila', '1402', 'michelle.bautista@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(141, 153, '000000000134', 'Katrina', 'Lopez', 'Orozco', 'female', '2012-05-28', 'Malabon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 8 Lot 7 Rosal Avenue Bagumbong Residences', 'Malabon City', 'NCR / Metro Manila', '1447', 'katrina.orozco@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(142, 154, '000000000135', 'Alice', 'Estrada', 'Danao', 'female', '2012-09-05', 'Valenzuela City', 'Filipino', 'Iglesia ni Cristo', 'Blk 46 Lot 24 Makopa Drive Sunrise Village', 'Valenzuela City', 'NCR / Metro Manila', '1401', 'alice.danao@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(143, 155, '000000000136', 'Lydia', 'Bernardo', 'Santos', 'female', '2012-11-03', 'Quezon City', 'Filipino', 'Islam', 'Blk 50 Lot 18 Bougainvillea Drive Greenfield Residences', 'Quezon City', 'None', '1430', 'lydia.santos@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(144, 156, '000000000137', 'Ronald', NULL, 'Esquivel', 'male', '2011-02-17', 'Malabon City', 'Filipino', 'Born Again', 'Blk 46 Lot 8 Adelfa Street Sunrise Village', 'Malabon City', 'None', '1402', 'ronald.esquivel@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(145, 157, '000000000138', 'Beatrice', 'Lopez', 'Borja', 'female', '2012-03-21', 'Navotas City', 'Filipino', NULL, 'Blk 38 Lot 5 Bougainvillea Drive Novaliches Proper', 'Navotas City', 'NCR / Metro Manila', '1421', 'beatrice.borja@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(146, 158, '000000000139', 'Tiffany', NULL, 'Aldana', 'female', '2011-02-02', 'Valenzuela City', 'Filipino', 'Born Again', 'Blk 27 Lot 20 Sampaguita Street Golden Villa Subdivision', 'Valenzuela City', 'None', '1430', 'tiffany.aldana@gmail.com', 'transferee', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(147, 159, '000000000140', 'Jennifer', 'Salazar', 'Duran', 'female', '2013-07-10', 'Quezon City', 'Filipino', 'Catholic', 'Blk 27 Lot 16 Zinnia Street Bagumbong Residences', 'Quezon City', 'NCR / Metro Manila', '1440', 'jennifer.duran@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(148, 160, '000000000141', 'Claudine', NULL, 'Cayabyab', 'female', '2012-12-28', 'Navotas City', 'Filipino', 'Iglesia ni Cristo', 'Blk 7 Lot 11 Pansy Lane Golden Villa Subdivision', 'Navotas City', 'None', '1402', 'claudine.cayabyab@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(149, 161, '000000000142', 'Luis', 'Bautista', 'Doria', 'male', '2011-05-13', 'Valenzuela City', 'Filipino', 'Born Again', 'Blk 37 Lot 24 Waling-Waling Street Bagumbong Residences', 'Valenzuela City', 'None', '1403', 'luis.doria@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(150, 162, '000000000143', 'Tristan', 'Villanueva', 'Esquivel', 'male', '2012-08-01', 'City of Caloocan', 'Filipino', 'Christian', 'Blk 14 Lot 19 Adelfa Street Crystal Valley Subdivision', 'City of Caloocan', 'None', '1421', 'tristan.esquivel@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(151, 163, '000000000144', 'Marcus', 'Santos', 'Enriquez', 'male', '2013-11-16', 'Navotas City', 'Filipino', 'Christian', 'Blk 17 Lot 24 Adelfa Street Greenfield Residences', 'Navotas City', 'NCR / Metro Manila', '1401', 'marcus.enriquez@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(152, 164, '000000000145', 'Leah', 'Magno', 'Aldana', 'female', '2013-04-12', 'Valenzuela City', 'Filipino', 'Christian', 'Blk 49 Lot 18 Champaca Road Sta. Monica Hills', 'Valenzuela City', 'None', '1401', 'leah.aldana@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(153, 165, '000000000146', 'Francis', 'Salazar', 'Andres', 'male', '2012-09-12', 'Malabon City', 'Filipino', 'Islam', 'Blk 3 Lot 2 Jasmine Lane Castlespring Heights Subdivision', 'Malabon City', 'NCR / Metro Manila', '1422', 'francis.andres@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0);
INSERT INTO `students` (`id`, `user_id`, `lrn`, `first_name`, `middle_name`, `last_name`, `sex`, `date_of_birth`, `place_of_birth`, `nationality`, `religion`, `address`, `city`, `province`, `zip_code`, `personal_email`, `enrollment_type`, `grade_level_id`, `registration_status`, `data_last_updated`, `created_at`, `updated_at`, `is_archived`) VALUES
(154, 166, '000000000147', 'Nicole', 'Mendoza', 'Esteban', 'female', '2013-03-11', 'Valenzuela City', 'Filipino', 'Christian', 'Blk 48 Lot 27 Lotus Street Camarin North Subdivision', 'Valenzuela City', 'None', '1402', 'nicole.esteban@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(155, 167, '000000000148', 'Reyna', 'Iglesias', 'Soriano', 'female', '2013-10-10', 'Quezon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 27 Lot 19 Lotus Street Greenfield Residences', 'Quezon City', 'NCR / Metro Manila', '1405', 'reyna.soriano@gmail.com', 'transferee', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(156, 168, '000000000149', 'Theodore', NULL, 'Borja', 'male', '2013-10-08', 'City of Caloocan', 'Filipino', 'Islam', 'Blk 40 Lot 25 Marigold Avenue Castlespring Heights Subdivision', 'City of Caloocan', 'None', '1402', 'theodore.borja@gmail.com', 'transferee', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(157, 169, '000000000150', 'Angelo', NULL, 'Fontanilla', 'male', '2011-04-01', 'Quezon City', 'Filipino', 'Born Again', 'Blk 14 Lot 14 Makopa Drive Sta. Monica Hills', 'Quezon City', 'None', '1410', 'angelo.fontanilla@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(158, 170, '000000000151', 'Gabriel', 'Espinosa', 'Esteban', 'male', '2013-08-17', 'Quezon City', 'Filipino', 'Christian', 'Blk 22 Lot 18 Adelfa Street Novaliches Proper', 'Quezon City', 'None', '1402', 'gabriel.esteban170@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(159, 171, '000000000152', 'Patricia', NULL, 'Barroga', 'female', '2012-09-10', 'Malabon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 45 Lot 23 Makopa Drive Lakeview Estates', 'Malabon City', 'None', '1447', 'patricia.barroga@gmail.com', 'transferee', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(160, 172, '000000000153', 'Katrina', NULL, 'Flores', 'female', '2013-05-10', 'City of Caloocan', 'Filipino', 'Iglesia ni Cristo', 'Blk 10 Lot 10 Jasmine Lane Panorama Heights', 'City of Caloocan', 'None', '1410', 'katrina.flores@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(161, 173, '000000000154', 'Paolo', 'De Leon', 'Villanueva', 'male', '2013-08-07', 'Malabon City', 'Filipino', NULL, 'Blk 7 Lot 20 Pansy Lane Bagumbong Residences', 'Malabon City', 'None', '1421', 'paolo.villanueva@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(162, 174, '000000000155', 'Xavier', 'Andrade', 'Beltran', 'male', '2011-07-11', 'Quezon City', 'Filipino', 'Born Again', 'Blk 36 Lot 30 Bougainvillea Drive Masinag Heights', 'Quezon City', 'NCR / Metro Manila', '1430', 'xavier.beltran@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(163, 175, '000000000156', 'Patricia', 'Dela Cruz', 'Macaraeg', 'female', '2012-05-21', 'City of Caloocan', 'Filipino', 'Islam', 'Blk 48 Lot 24 Jasmine Lane Castlespring Heights Subdivision', 'City of Caloocan', 'NCR / Metro Manila', '1430', 'patricia.macaraeg@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(164, 176, '000000000157', 'Elena', NULL, 'Villanueva', 'female', '2012-08-06', 'Navotas City', 'Filipino', 'Iglesia ni Cristo', 'Blk 7 Lot 30 Waling-Waling Street Panorama Heights', 'Navotas City', 'NCR / Metro Manila', '1400', 'elena.villanueva@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(165, 177, '000000000158', 'Sofia', 'Bernardo', 'Esteban', 'female', '2013-08-09', 'Malabon City', 'Filipino', 'Born Again', 'Blk 42 Lot 9 Bougainvillea Drive Crystal Valley Subdivision', 'Malabon City', 'NCR / Metro Manila', '1405', 'sofia.esteban@gmail.com', 'transferee', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(166, 178, '000000000159', 'Jasmine', NULL, 'Fontanilla', 'female', '2011-03-20', 'Quezon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 43 Lot 4 Bougainvillea Drive Castlespring Heights Subdivision', 'Quezon City', 'None', '1421', 'jasmine.fontanilla@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(167, 179, '000000000160', 'Julia', 'De Leon', 'Villanueva', 'female', '2012-04-15', 'Navotas City', 'Filipino', 'Islam', 'Blk 1 Lot 9 Adelfa Street Harmony Village', 'Navotas City', 'None', '1404', 'julia.villanueva@gmail.com', 'transferee', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(168, 180, '000000000161', 'Carlo', 'Dela Cruz', 'Mercado', 'male', '2011-07-22', 'Valenzuela City', 'Filipino', 'Catholic', 'Blk 19 Lot 12 Pansy Lane Bagumbong Residences', 'Valenzuela City', 'None', '1440', 'carlo.mercado@gmail.com', 'transferee', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(169, 181, '000000000162', 'Thomas', 'Mendoza', 'Ayala', 'male', '2012-07-23', 'Valenzuela City', 'Filipino', 'Islam', 'Blk 14 Lot 25 Pansy Lane Novaliches Proper', 'Valenzuela City', 'None', '1447', 'thomas.ayala@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(170, 182, '000000000163', 'Xavier', 'Estrada', 'Doria', 'male', '2011-10-04', 'City of Caloocan', 'Filipino', 'Islam', 'Blk 21 Lot 28 Zinnia Street Heritage Park Subdivision', 'City of Caloocan', 'NCR / Metro Manila', '1422', 'xavier.doria@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(171, 183, '000000000164', 'Timothy', NULL, 'Almeda', 'male', '2012-01-15', 'Malabon City', 'Filipino', 'Islam', 'Blk 30 Lot 22 Lotus Street Harmony Village', 'Malabon City', 'None', '1420', 'timothy.almeda@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(172, 184, '000000000165', 'Ramon', NULL, 'Borja', 'male', '2013-04-19', 'City of Caloocan', 'Filipino', 'Iglesia ni Cristo', 'Blk 35 Lot 2 Gumamela Road Golden Villa Subdivision', 'City of Caloocan', 'NCR / Metro Manila', '1410', 'ramon.borja@gmail.com', 'transferee', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(173, 185, '000000000166', 'Marcus', 'Bernardo', 'Delotavo', 'male', '2013-12-21', 'Quezon City', 'Filipino', 'Christian', 'Blk 25 Lot 13 Gumamela Road Novaliches Proper', 'Quezon City', 'None', '1410', 'marcus.delotavo@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(174, 186, '000000000167', 'Paolo', 'Lopez', 'Aquino', 'male', '2012-09-05', 'Malabon City', 'Filipino', 'Catholic', 'Blk 30 Lot 22 Ilang-Ilang Street Sunrise Village', 'Malabon City', 'NCR / Metro Manila', '1447', 'paolo.aquino@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(175, 187, '000000000168', 'Gabrielle', 'Bernardo', 'Benedicto', 'female', '2012-04-24', 'City of Caloocan', 'Filipino', NULL, 'Blk 50 Lot 30 Sampaguita Street Bagumbong Residences', 'City of Caloocan', 'NCR / Metro Manila', '1447', 'gabrielle.benedicto@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(176, 188, '000000000169', 'Christian', 'Gonzalez', 'Andres', 'male', '2013-11-23', 'City of Caloocan', 'Filipino', 'Catholic', 'Blk 15 Lot 18 Calachuchi Lane Greenfield Residences', 'City of Caloocan', 'NCR / Metro Manila', '1440', 'christian.andres@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(177, 189, '000000000170', 'Gabriel', NULL, 'Esquivel', 'male', '2011-12-19', 'Navotas City', 'Filipino', 'Iglesia ni Cristo', 'Blk 43 Lot 17 Pansy Lane Masinag Heights', 'Navotas City', 'None', '1403', 'gabriel.esquivel@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(178, 190, '000000000171', 'Jade', 'Magno', 'Alejo', 'female', '2013-03-21', 'Quezon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 43 Lot 13 Waling-Waling Street Harmony Village', 'Quezon City', 'None', '1400', 'jade.alejo@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(179, 191, '000000000172', 'Lydia', 'Castillo', 'Ayala', 'female', '2013-08-08', 'Malabon City', 'Filipino', 'Born Again', 'Blk 4 Lot 18 Ilang-Ilang Street Masinag Heights', 'Malabon City', 'None', '1440', 'lydia.ayala@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(180, 192, '000000000173', 'Rafael', 'Espinosa', 'Benedicto', 'male', '2013-02-15', 'Navotas City', 'Filipino', NULL, 'Blk 4 Lot 9 Marigold Avenue Novaliches Proper', 'Navotas City', 'NCR / Metro Manila', '1421', 'rafael.benedicto@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(181, 193, '000000000174', 'Daniel', NULL, 'Barroga', 'male', '2013-12-22', 'Valenzuela City', 'Filipino', 'Born Again', 'Blk 22 Lot 10 Sampaguita Street Bagumbong Residences', 'Valenzuela City', 'NCR / Metro Manila', '1420', 'daniel.barroga@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(182, 194, '000000000175', 'Felix', NULL, 'Paglinawan', 'male', '2012-04-23', 'Valenzuela City', 'Filipino', 'Born Again', 'Blk 50 Lot 10 Marigold Avenue Golden Villa Subdivision', 'Valenzuela City', 'NCR / Metro Manila', '1410', 'felix.paglinawan@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(183, 195, '000000000176', 'Jessica', 'Villanueva', 'Borja', 'female', '2012-08-04', 'Quezon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 3 Lot 19 Pansy Lane Harmony Village', 'Quezon City', 'None', '1403', 'jessica.borja@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(184, 196, '000000000177', 'Alexander', 'Magno', 'Borja', 'male', '2013-12-14', 'Navotas City', 'Filipino', 'Iglesia ni Cristo', 'Blk 37 Lot 27 Pansy Lane Golden Villa Subdivision', 'Navotas City', 'NCR / Metro Manila', '1403', 'alexander.borja@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(185, 197, '000000000178', 'Irene', NULL, 'Reyes', 'female', '2013-11-24', 'Quezon City', 'Filipino', NULL, 'Blk 11 Lot 5 Makopa Drive Castlespring Heights Subdivision', 'Quezon City', 'None', '1402', 'irene.reyes@gmail.com', 'transferee', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(186, 198, '000000000179', 'Xavier', NULL, 'Aldana', 'male', '2011-11-02', 'City of Caloocan', 'Filipino', NULL, 'Blk 46 Lot 5 Sampaguita Street Bagumbong Residences', 'City of Caloocan', 'None', '1402', 'xavier.aldana@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(187, 199, '000000000180', 'Leia', 'Ocampo', 'Alejo', 'female', '2013-08-22', 'Quezon City', 'Filipino', 'Islam', 'Blk 1 Lot 1 Champaca Road Sunrise Village', 'Quezon City', 'NCR / Metro Manila', '1400', 'leia.alejo@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(188, 200, '000000000181', 'Alexandra', NULL, 'Esquivel', 'female', '2013-07-26', 'Malabon City', 'Filipino', 'Islam', 'Blk 13 Lot 20 Champaca Road Sta. Monica Hills', 'Malabon City', 'NCR / Metro Manila', '1401', 'alexandra.esquivel@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(189, 201, '000000000182', 'Isabelle', 'Estrada', 'Salas', 'female', '2012-08-19', 'Malabon City', 'Filipino', NULL, 'Blk 6 Lot 21 Jasmine Lane Heritage Park Subdivision', 'Malabon City', 'NCR / Metro Manila', '1404', 'isabelle.salas@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(190, 202, '000000000183', 'Lisa', 'Andrade', 'De Guzman', 'female', '2013-01-23', 'Malabon City', 'Filipino', 'Christian', 'Blk 22 Lot 19 Dahlia Drive Sunrise Village', 'Malabon City', 'NCR / Metro Manila', '1420', 'lisa.deguzman@gmail.com', 'transferee', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(191, 203, '000000000184', 'Kevin', NULL, 'Bautista', 'male', '2013-10-16', 'Navotas City', 'Filipino', NULL, 'Blk 35 Lot 19 Jasmine Lane Castlespring Heights Subdivision', 'Navotas City', 'NCR / Metro Manila', '1401', 'kevin.bautista@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(192, 204, '000000000185', 'Alexandra', 'Bernardo', 'Zamora', 'female', '2013-07-03', 'Navotas City', 'Filipino', 'Born Again', 'Blk 25 Lot 22 Waling-Waling Street Masinag Heights', 'Navotas City', 'NCR / Metro Manila', '1422', 'alexandra.zamora@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(193, 205, '000000000186', 'David', NULL, 'Esquivel', 'male', '2012-01-04', 'Quezon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 40 Lot 20 Marigold Avenue Greenfield Residences', 'Quezon City', 'NCR / Metro Manila', '1401', 'david.esquivel@gmail.com', 'transferee', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(194, 206, '000000000187', 'Alice', 'Gonzalez', 'Macapagal', 'female', '2012-04-12', 'Valenzuela City', 'Filipino', 'Born Again', 'Blk 43 Lot 13 Gumamela Road Greenfield Residences', 'Valenzuela City', 'None', '1410', 'alice.macapagal@gmail.com', 'transferee', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(195, 207, '000000000188', 'Hannah', 'De Leon', 'Orozco', 'female', '2011-07-23', 'Malabon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 1 Lot 10 Zinnia Street Lakeview Estates', 'Malabon City', 'None', '1405', 'hannah.orozco@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(196, 208, '000000000189', 'Caroline', 'Garcia', 'Austria', 'female', '2012-09-18', 'Valenzuela City', 'Filipino', 'Catholic', 'Blk 36 Lot 3 Waling-Waling Street Sta. Monica Hills', 'Valenzuela City', 'None', '1401', 'caroline.austria@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(197, 209, '000000000190', 'Adriana', 'Reyes', 'Cabral', 'female', '2011-12-18', 'Malabon City', 'Filipino', 'Christian', 'Blk 18 Lot 10 Champaca Road Golden Villa Subdivision', 'Malabon City', 'NCR / Metro Manila', '1430', 'adriana.cabral@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(198, 210, '000000000191', 'Christian', 'Garcia', 'Balboa', 'male', '2012-08-26', 'City of Caloocan', 'Filipino', 'Born Again', 'Blk 32 Lot 20 Calachuchi Lane Golden Villa Subdivision', 'City of Caloocan', 'None', '1404', 'christian.balboa@gmail.com', 'transferee', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(199, 211, '000000000192', 'Gabriel', 'Fernandez', 'Cabrido', 'male', '2012-10-13', 'Navotas City', 'Filipino', 'Christian', 'Blk 42 Lot 20 Rosal Avenue Panorama Heights', 'Navotas City', 'None', '1405', 'gabriel.cabrido@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(200, 212, '000000000193', 'Emma', 'Fernandez', 'Duran', 'female', '2012-05-24', 'Quezon City', 'Filipino', 'Christian', 'Blk 26 Lot 12 Dahlia Drive Camarin North Subdivision', 'Quezon City', 'NCR / Metro Manila', '1405', 'emma.duran@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(201, 213, '000000000194', 'James', NULL, 'Montoya', 'male', '2011-12-15', 'Malabon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 5 Lot 27 Ilang-Ilang Street Novaliches Proper', 'Malabon City', 'None', '1447', 'james.montoya@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(202, 214, '000000000195', 'Claire', 'De Leon', 'Macapagal', 'female', '2013-03-23', 'Quezon City', 'Filipino', 'Christian', 'Blk 31 Lot 19 Marigold Avenue Sunrise Village', 'Quezon City', 'None', '1401', 'claire.macapagal@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(203, 215, '000000000196', 'Sofia', NULL, 'Aldana', 'female', '2012-12-26', 'Valenzuela City', 'Filipino', 'Born Again', 'Blk 23 Lot 6 Jasmine Lane Camarin North Subdivision', 'Valenzuela City', 'NCR / Metro Manila', '1401', 'sofia.aldana@gmail.com', 'transferee', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(204, 216, '000000000197', 'Karen', NULL, 'Zamora', 'female', '2011-01-04', 'Navotas City', 'Filipino', NULL, 'Blk 38 Lot 23 Pansy Lane Golden Villa Subdivision', 'Navotas City', 'NCR / Metro Manila', '1421', 'karen.zamora@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(205, 217, '000000000198', 'Lourdes', NULL, 'Dumlao', 'female', '2013-12-17', 'Malabon City', 'Filipino', 'Christian', 'Blk 27 Lot 30 Gumamela Road Heritage Park Subdivision', 'Malabon City', 'None', '1400', 'lourdes.dumlao@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(206, 218, '000000000199', 'Paolo', 'Salazar', 'Cabrido', 'male', '2011-09-16', 'Navotas City', 'Filipino', 'Christian', 'Blk 29 Lot 11 Gumamela Road Panorama Heights', 'Navotas City', 'None', '1401', 'paolo.cabrido@gmail.com', 'transferee', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(207, 219, '000000000200', 'Enrique', NULL, 'Alcantara', 'male', '2013-02-22', 'Malabon City', 'Filipino', 'Born Again', 'Blk 22 Lot 18 Ilang-Ilang Street Golden Villa Subdivision', 'Malabon City', 'NCR / Metro Manila', '1421', 'enrique.alcantara@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(208, 220, '000000000201', 'Raphael', 'Navarro', 'Macapagal', 'male', '2013-07-13', 'City of Caloocan', 'Filipino', 'Islam', 'Blk 1 Lot 23 Calachuchi Lane Bagumbong Residences', 'City of Caloocan', 'NCR / Metro Manila', '1420', 'raphael.macapagal@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(209, 221, '000000000202', 'Angelica', 'Torres', 'Fontanilla', 'female', '2013-03-12', 'Navotas City', 'Filipino', 'Catholic', 'Blk 32 Lot 17 Waling-Waling Street Camarin North Subdivision', 'Navotas City', 'NCR / Metro Manila', '1420', 'angelica.fontanilla@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(210, 222, '000000000203', 'Lourdes', 'Estrada', 'Gonzales', 'female', '2012-10-06', 'Navotas City', 'Filipino', 'Born Again', 'Blk 16 Lot 10 Dahlia Drive Castlespring Heights Subdivision', 'Navotas City', 'NCR / Metro Manila', '1430', 'lourdes.gonzales@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(211, 223, '000000000204', 'Claudine', 'Mendoza', 'Esquivel', 'female', '2011-10-13', 'Quezon City', 'Filipino', NULL, 'Blk 42 Lot 30 Bougainvillea Drive Sunrise Village', 'Quezon City', 'NCR / Metro Manila', '1420', 'claudine.esquivel@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(212, 224, '000000000205', 'Timothy', 'Espinosa', 'Cabral', 'male', '2012-10-02', 'Navotas City', 'Filipino', 'Born Again', 'Blk 25 Lot 18 Makopa Drive Masinag Heights', 'Navotas City', 'NCR / Metro Manila', '1420', 'timothy.cabral@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(213, 225, '000000000206', 'Mabel', NULL, 'Orozco', 'female', '2012-03-03', 'Valenzuela City', 'Filipino', 'Born Again', 'Blk 18 Lot 8 Lotus Street Castlespring Heights Subdivision', 'Valenzuela City', 'NCR / Metro Manila', '1447', 'mabel.orozco@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(214, 226, '000000000207', 'Tiffany', NULL, 'Paglinawan', 'female', '2012-09-17', 'City of Caloocan', 'Filipino', 'Islam', 'Blk 24 Lot 18 Jasmine Lane Greenfield Residences', 'City of Caloocan', 'NCR / Metro Manila', '1404', 'tiffany.paglinawan@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(215, 227, '000000000208', 'Sofia', NULL, 'Bautista', 'female', '2011-12-27', 'Malabon City', 'Filipino', 'Christian', 'Blk 6 Lot 15 Dahlia Drive Greenfield Residences', 'Malabon City', 'None', '1400', 'sofia.bautista@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(216, 228, '000000000209', 'Joseph', NULL, 'Samonte', 'male', '2013-06-28', 'Valenzuela City', 'Filipino', 'Islam', 'Blk 14 Lot 27 Calachuchi Lane Greenfield Residences', 'Valenzuela City', 'None', '1402', 'joseph.samonte@gmail.com', 'new', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(217, 229, '000000000210', 'Paolo', 'Lopez', 'Ferrer', 'male', '2011-06-23', 'Navotas City', 'Filipino', 'Iglesia ni Cristo', 'Blk 33 Lot 29 Dahlia Drive Castlespring Heights Subdivision', 'Navotas City', 'None', '1422', 'paolo.ferrer@gmail.com', 'returning', 8, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(218, 230, '000000000211', 'Angela', NULL, 'Borromeo', 'female', '2010-12-28', 'Malabon City', 'Filipino', NULL, 'Blk 16 Lot 25 Marigold Avenue Golden Villa Subdivision', 'Malabon City', 'NCR / Metro Manila', '1402', 'angela.borromeo@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(219, 231, '000000000212', 'Luis', 'Gonzalez', 'Macapagal', 'male', '2010-11-26', 'City of Caloocan', 'Filipino', NULL, 'Blk 24 Lot 15 Makopa Drive Lakeview Estates', 'City of Caloocan', 'None', '1421', 'luis.macapagal@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(220, 232, '000000000213', 'Dominic', NULL, 'Padilla', 'male', '2012-11-23', 'Navotas City', 'Filipino', 'Islam', 'Blk 28 Lot 27 Calachuchi Lane Golden Villa Subdivision', 'Navotas City', 'NCR / Metro Manila', '1447', 'dominic.padilla@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(221, 233, '000000000214', 'Julia', 'Lopez', 'Soriano', 'female', '2012-03-19', 'Quezon City', 'Filipino', 'Catholic', 'Blk 41 Lot 26 Zinnia Street Crystal Valley Subdivision', 'Quezon City', 'None', '1430', 'julia.soriano@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(222, 234, '000000000215', 'Hector', 'Garcia', 'Doria', 'male', '2010-12-05', 'Navotas City', 'Filipino', 'Catholic', 'Blk 17 Lot 3 Adelfa Street Novaliches Proper', 'Navotas City', 'NCR / Metro Manila', '1404', 'hector.doria@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(223, 235, '000000000216', 'Benedict', 'Ramos', 'De Villa', 'male', '2012-04-14', 'City of Caloocan', 'Filipino', 'Born Again', 'Blk 9 Lot 19 Pansy Lane Sunrise Village', 'City of Caloocan', 'NCR / Metro Manila', '1400', 'benedict.devilla@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(224, 236, '000000000217', 'Adriana', NULL, 'Abella', 'female', '2010-07-23', 'Malabon City', 'Filipino', 'Born Again', 'Blk 47 Lot 26 Dahlia Drive Heritage Park Subdivision', 'Malabon City', 'None', '1401', 'adriana.abella@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(225, 237, '000000000218', 'Leia', 'Fernandez', 'Tolentino', 'female', '2010-11-22', 'Malabon City', 'Filipino', 'Islam', 'Blk 42 Lot 6 Zinnia Street Lakeview Estates', 'Malabon City', 'NCR / Metro Manila', '1421', 'leia.tolentino@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(226, 238, '000000000219', 'Gilbert', 'Ocampo', 'Velasco', 'male', '2011-04-03', 'City of Caloocan', 'Filipino', 'Catholic', 'Blk 25 Lot 12 Ilang-Ilang Street Lakeview Estates', 'City of Caloocan', 'NCR / Metro Manila', '1447', 'gilbert.velasco@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(227, 239, '000000000220', 'Lance', 'De Guzman', 'Borromeo', 'male', '2012-10-20', 'Valenzuela City', 'Filipino', NULL, 'Blk 43 Lot 29 Lotus Street Bagumbong Residences', 'Valenzuela City', 'None', '1447', 'lance.borromeo@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(228, 240, '000000000221', 'Ramon', 'Salazar', 'Cabral', 'male', '2010-08-13', 'City of Caloocan', 'Filipino', NULL, 'Blk 34 Lot 29 Sampaguita Street Lakeview Estates', 'City of Caloocan', 'NCR / Metro Manila', '1420', 'ramon.cabral@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(229, 241, '000000000222', 'Christina', NULL, 'De Guzman', 'female', '2012-07-12', 'Valenzuela City', 'Filipino', 'Christian', 'Blk 50 Lot 3 Sampaguita Street Camarin North Subdivision', 'Valenzuela City', 'NCR / Metro Manila', '1447', 'christina.deguzman@gmail.com', 'returning', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(230, 242, '000000000223', 'Adrian', 'Yap', 'Borja', 'male', '2010-07-17', 'Navotas City', 'Filipino', NULL, 'Blk 41 Lot 18 Rosal Avenue Panorama Heights', 'Navotas City', 'None', '1410', 'adrian.borja@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(231, 243, '000000000224', 'Michael', 'Cruz', 'Almeda', 'male', '2010-09-11', 'Quezon City', 'Filipino', NULL, 'Blk 16 Lot 2 Pansy Lane Heritage Park Subdivision', 'Quezon City', 'NCR / Metro Manila', '1404', 'michael.almeda@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(232, 244, '000000000225', 'Cecilia', 'Andrade', 'Dumlao', 'female', '2011-11-24', 'Malabon City', 'Filipino', NULL, 'Blk 1 Lot 6 Makopa Drive Lakeview Estates', 'Malabon City', 'NCR / Metro Manila', '1400', 'cecilia.dumlao@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(233, 245, '000000000226', 'Donna', 'Reyes', 'Danao', 'female', '2011-12-04', 'City of Caloocan', 'Filipino', 'Christian', 'Blk 5 Lot 9 Gumamela Road Golden Villa Subdivision', 'City of Caloocan', 'None', '1447', 'donna.danao@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(234, 246, '000000000227', 'Rosa', 'Torres', 'Danao', 'female', '2012-03-12', 'Malabon City', 'Filipino', 'Catholic', 'Blk 44 Lot 24 Dahlia Drive Bagumbong Residences', 'Malabon City', 'None', '1447', 'rosa.danao246@gmail.com', 'returning', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(235, 247, '000000000228', 'Anthony', NULL, 'Tabios', 'male', '2010-01-16', 'Navotas City', 'Filipino', 'Born Again', 'Blk 3 Lot 18 Ilang-Ilang Street Bagumbong Residences', 'Navotas City', 'None', '1402', 'anthony.tabios@gmail.com', 'returning', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(236, 248, '000000000229', 'Hannah', NULL, 'Delotavo', 'female', '2011-05-27', 'City of Caloocan', 'Filipino', 'Islam', 'Blk 4 Lot 6 Pansy Lane Greenfield Residences', 'City of Caloocan', 'None', '1401', 'hannah.delotavo@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(237, 249, '000000000230', 'Raphael', NULL, 'Alfonso', 'male', '2011-05-11', 'City of Caloocan', 'Filipino', 'Iglesia ni Cristo', 'Blk 37 Lot 26 Lotus Street Harmony Village', 'City of Caloocan', 'None', '1400', 'raphael.alfonso@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(238, 250, '000000000231', 'Stephen', 'Iglesias', 'Danao', 'male', '2010-12-18', 'Malabon City', 'Filipino', 'Christian', 'Blk 35 Lot 12 Sampaguita Street Lakeview Estates', 'Malabon City', 'NCR / Metro Manila', '1400', 'stephen.danao@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(239, 251, '000000000232', 'Philip', NULL, 'Tabios', 'male', '2011-02-07', 'Valenzuela City', 'Filipino', 'Christian', 'Blk 10 Lot 23 Champaca Road Heritage Park Subdivision', 'Valenzuela City', 'NCR / Metro Manila', '1410', 'philip.tabios@gmail.com', 'returning', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(240, 252, '000000000233', 'Kevin', NULL, 'Tuason', 'male', '2011-12-12', 'Quezon City', 'Filipino', 'Catholic', 'Blk 41 Lot 27 Marigold Avenue Heritage Park Subdivision', 'Quezon City', 'NCR / Metro Manila', '1422', 'kevin.tuason@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(241, 253, '000000000234', 'Ronald', NULL, 'Mercado', 'male', '2010-05-09', 'Navotas City', 'Filipino', NULL, 'Blk 29 Lot 9 Pansy Lane Heritage Park Subdivision', 'Navotas City', 'None', '1440', 'ronald.mercado@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(242, 254, '000000000235', 'Gabriel', NULL, 'Robles', 'male', '2010-03-04', 'Malabon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 35 Lot 12 Calachuchi Lane Golden Villa Subdivision', 'Malabon City', 'None', '1420', 'gabriel.robles@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(243, 255, '000000000236', 'Natalie', NULL, 'Borja', 'female', '2010-03-26', 'Navotas City', 'Filipino', 'Iglesia ni Cristo', 'Blk 46 Lot 8 Adelfa Street Masinag Heights', 'Navotas City', 'NCR / Metro Manila', '1403', 'natalie.borja@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(244, 256, '000000000237', 'Matthew', NULL, 'Borja', 'male', '2010-01-13', 'Quezon City', 'Filipino', 'Christian', 'Blk 9 Lot 4 Sampaguita Street Crystal Valley Subdivision', 'Quezon City', 'NCR / Metro Manila', '1401', 'matthew.borja@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(245, 257, '000000000238', 'Francis', NULL, 'Barroga', 'male', '2011-11-21', 'City of Caloocan', 'Filipino', 'Catholic', 'Blk 13 Lot 29 Zinnia Street Greenfield Residences', 'City of Caloocan', 'None', '1401', 'francis.barroga@gmail.com', 'returning', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(246, 258, '000000000239', 'Dominic', NULL, 'Tuason', 'male', '2011-02-02', 'Quezon City', 'Filipino', 'Islam', 'Blk 47 Lot 13 Makopa Drive Crystal Valley Subdivision', 'Quezon City', 'NCR / Metro Manila', '1402', 'dominic.tuason@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(247, 259, '000000000240', 'Maria', 'Yap', 'Barrientos', 'female', '2010-05-09', 'Quezon City', 'Filipino', 'Islam', 'Blk 16 Lot 21 Lotus Street Golden Villa Subdivision', 'Quezon City', 'NCR / Metro Manila', '1400', 'maria.barrientos@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(248, 260, '000000000241', 'Stella', 'De Leon', 'Duran', 'female', '2011-03-14', 'Malabon City', 'Filipino', 'Islam', 'Blk 25 Lot 26 Adelfa Street Golden Villa Subdivision', 'Malabon City', 'NCR / Metro Manila', '1430', 'stella.duran@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(249, 261, '000000000242', 'Katrina', 'Espinosa', 'Velasco', 'female', '2011-05-06', 'City of Caloocan', 'Filipino', 'Born Again', 'Blk 50 Lot 9 Jasmine Lane Greenfield Residences', 'City of Caloocan', 'None', '1422', 'katrina.velasco@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(250, 262, '000000000243', 'Sara', NULL, 'Cipriano', 'female', '2010-03-04', 'Malabon City', 'Filipino', 'Islam', 'Blk 48 Lot 2 Pansy Lane Camarin North Subdivision', 'Malabon City', 'NCR / Metro Manila', '1404', 'sara.cipriano@gmail.com', 'returning', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(251, 263, '000000000244', 'Laura', NULL, 'Villanueva', 'female', '2010-03-08', 'Valenzuela City', 'Filipino', NULL, 'Blk 38 Lot 1 Adelfa Street Camarin North Subdivision', 'Valenzuela City', 'None', '1447', 'laura.villanueva@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(252, 264, '000000000245', 'Jerome', NULL, 'Soriano', 'male', '2011-09-10', 'Malabon City', 'Filipino', 'Catholic', 'Blk 39 Lot 8 Sampaguita Street Sunrise Village', 'Malabon City', 'None', '1400', 'jerome.soriano@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(253, 265, '000000000246', 'Abigail', NULL, 'Cervantes', 'female', '2010-03-11', 'Malabon City', 'Filipino', 'Catholic', 'Blk 46 Lot 30 Rosal Avenue Greenfield Residences', 'Malabon City', 'None', '1400', 'abigail.cervantes@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(254, 266, '000000000247', 'Xavier', 'Aquino', 'Tan', 'male', '2011-12-22', 'Quezon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 11 Lot 24 Ilang-Ilang Street Greenfield Residences', 'Quezon City', 'NCR / Metro Manila', '1405', 'xavier.tan@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(255, 267, '000000000248', 'Joanna', NULL, 'Barrientos', 'female', '2012-12-20', 'Navotas City', 'Filipino', 'Islam', 'Blk 25 Lot 10 Lotus Street Castlespring Heights Subdivision', 'Navotas City', 'NCR / Metro Manila', '1430', 'joanna.barrientos@gmail.com', 'returning', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(256, 268, '000000000249', 'Aaron', NULL, 'Yap', 'male', '2012-07-28', 'Valenzuela City', 'Filipino', 'Islam', 'Blk 40 Lot 8 Dahlia Drive Golden Villa Subdivision', 'Valenzuela City', 'NCR / Metro Manila', '1402', 'aaron.yap@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(257, 269, '000000000250', 'Neil', 'Estrada', 'Paglinawan', 'male', '2011-03-21', 'City of Caloocan', 'Filipino', 'Catholic', 'Blk 16 Lot 23 Gumamela Road Lakeview Estates', 'City of Caloocan', 'None', '1420', 'neil.paglinawan@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(258, 270, '000000000251', 'Caroline', 'Fernandez', 'Padilla', 'female', '2011-12-14', 'Malabon City', 'Filipino', 'Christian', 'Blk 25 Lot 4 Makopa Drive Greenfield Residences', 'Malabon City', 'None', '1420', 'caroline.padilla@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(259, 271, '000000000252', 'Hector', 'Torres', 'Doria', 'male', '2010-05-01', 'Navotas City', 'Filipino', 'Catholic', 'Blk 25 Lot 6 Gumamela Road Sunrise Village', 'Navotas City', 'None', '1401', 'hector.doria271@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(260, 272, '000000000253', 'Oliver', NULL, 'Hernandez', 'male', '2011-12-01', 'Quezon City', 'Filipino', 'Christian', 'Blk 7 Lot 11 Calachuchi Lane Bagumbong Residences', 'Quezon City', 'NCR / Metro Manila', '1422', 'oliver.hernandez@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(261, 273, '000000000254', 'Stella', NULL, 'Padilla', 'female', '2012-05-22', 'Navotas City', 'Filipino', 'Catholic', 'Blk 37 Lot 18 Makopa Drive Castlespring Heights Subdivision', 'Navotas City', 'None', '1403', 'stella.padilla@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(262, 274, '000000000255', 'Paul', 'Dela Cruz', 'Abella', 'male', '2012-11-20', 'Quezon City', 'Filipino', 'Catholic', 'Blk 41 Lot 10 Gumamela Road Golden Villa Subdivision', 'Quezon City', 'NCR / Metro Manila', '1401', 'paul.abella@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(263, 275, '000000000256', 'Michael', 'Iglesias', 'Salas', 'male', '2012-05-03', 'Valenzuela City', 'Filipino', 'Iglesia ni Cristo', 'Blk 24 Lot 6 Zinnia Street Crystal Valley Subdivision', 'Valenzuela City', 'None', '1402', 'michael.salas@gmail.com', 'returning', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(264, 276, '000000000257', 'Melissa', 'Santos', 'Dumlao', 'female', '2011-10-02', 'Malabon City', 'Filipino', NULL, 'Blk 35 Lot 14 Pansy Lane Sunrise Village', 'Malabon City', 'NCR / Metro Manila', '1401', 'melissa.dumlao@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(265, 277, '000000000258', 'Rafael', 'Lopez', 'Santos', 'male', '2012-08-19', 'Malabon City', 'Filipino', 'Catholic', 'Blk 46 Lot 2 Rosal Avenue Heritage Park Subdivision', 'Malabon City', 'None', '1404', 'rafael.santos@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(266, 278, '000000000259', 'Elena', NULL, 'Yap', 'female', '2010-04-05', 'City of Caloocan', 'Filipino', NULL, 'Blk 41 Lot 5 Champaca Road Lakeview Estates', 'City of Caloocan', 'None', '1401', 'elena.yap@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(267, 279, '000000000260', 'Dominic', 'Lopez', 'De Guzman', 'male', '2011-05-17', 'Quezon City', 'Filipino', NULL, 'Blk 34 Lot 26 Ilang-Ilang Street Heritage Park Subdivision', 'Quezon City', 'NCR / Metro Manila', '1447', 'dominic.deguzman@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(268, 280, '000000000261', 'Danielle', 'Magno', 'Ayala', 'female', '2010-02-19', 'City of Caloocan', 'Filipino', 'Iglesia ni Cristo', 'Blk 17 Lot 13 Makopa Drive Camarin North Subdivision', 'City of Caloocan', 'None', '1421', 'danielle.ayala@gmail.com', 'returning', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(269, 281, '000000000262', 'Alicia', 'Bernardo', 'Barrientos', 'female', '2012-10-22', 'Quezon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 4 Lot 24 Makopa Drive Panorama Heights', 'Quezon City', 'NCR / Metro Manila', '1410', 'alicia.barrientos@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(270, 282, '000000000263', 'Alexandra', NULL, 'Cervantes', 'female', '2011-05-09', 'Quezon City', 'Filipino', 'Born Again', 'Blk 48 Lot 15 Waling-Waling Street Panorama Heights', 'Quezon City', 'NCR / Metro Manila', '1403', 'alexandra.cervantes@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(271, 283, '000000000264', 'Bianca', 'Yap', 'Barroga', 'female', '2011-12-16', 'Valenzuela City', 'Filipino', 'Islam', 'Blk 5 Lot 10 Marigold Avenue Castlespring Heights Subdivision', 'Valenzuela City', 'None', '1400', 'bianca.barroga@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(272, 284, '000000000265', 'Jacob', NULL, 'Barroga', 'male', '2010-01-08', 'City of Caloocan', 'Filipino', 'Iglesia ni Cristo', 'Blk 18 Lot 12 Zinnia Street Sunrise Village', 'City of Caloocan', 'None', '1400', 'jacob.barroga@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(273, 285, '000000000266', 'Charlene', 'Estrada', 'Montoya', 'female', '2011-10-15', 'Malabon City', 'Filipino', 'Islam', 'Blk 11 Lot 27 Champaca Road Harmony Village', 'Malabon City', 'None', '1422', 'charlene.montoya@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(274, 286, '000000000267', 'Marcus', 'Castillo', 'Alcantara', 'male', '2012-04-28', 'Malabon City', 'Filipino', 'Born Again', 'Blk 27 Lot 17 Sampaguita Street Sta. Monica Hills', 'Malabon City', 'NCR / Metro Manila', '1430', 'marcus.alcantara@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(275, 287, '000000000268', 'Theodore', 'Castillo', 'Velasco', 'male', '2012-01-08', 'Navotas City', 'Filipino', NULL, 'Blk 28 Lot 29 Marigold Avenue Sta. Monica Hills', 'Navotas City', 'None', '1440', 'theodore.velasco@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(276, 288, '000000000269', 'Monica', 'Dela Cruz', 'Borja', 'female', '2012-09-27', 'Valenzuela City', 'Filipino', 'Catholic', 'Blk 43 Lot 27 Adelfa Street Sunrise Village', 'Valenzuela City', 'None', '1422', 'monica.borja@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(277, 289, '000000000270', 'Jennifer', 'Aquino', 'Montoya', 'female', '2011-05-21', 'Navotas City', 'Filipino', NULL, 'Blk 42 Lot 10 Calachuchi Lane Castlespring Heights Subdivision', 'Navotas City', 'None', '1404', 'jennifer.montoya@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(278, 290, '000000000271', 'Carlo', NULL, 'Samonte', 'male', '2012-07-22', 'Navotas City', 'Filipino', 'Catholic', 'Blk 19 Lot 9 Ilang-Ilang Street Masinag Heights', 'Navotas City', 'NCR / Metro Manila', '1440', 'carlo.samonte@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(279, 291, '000000000272', 'Alicia', NULL, 'Gonzales', 'female', '2012-04-11', 'Malabon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 11 Lot 27 Bougainvillea Drive Panorama Heights', 'Malabon City', 'None', '1430', 'alicia.gonzales@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(280, 292, '000000000273', 'Theodore', NULL, 'Austria', 'male', '2012-09-25', 'Malabon City', 'Filipino', 'Catholic', 'Blk 15 Lot 24 Lotus Street Masinag Heights', 'Malabon City', 'None', '1430', 'theodore.austria@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(281, 293, '000000000274', 'Leia', 'Gonzalez', 'Borja', 'female', '2010-08-02', 'Valenzuela City', 'Filipino', 'Born Again', 'Blk 44 Lot 13 Lotus Street Masinag Heights', 'Valenzuela City', 'NCR / Metro Manila', '1420', 'leia.borja@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(282, 294, '000000000275', 'Gilbert', NULL, 'Austria', 'male', '2011-07-19', 'Quezon City', 'Filipino', NULL, 'Blk 6 Lot 16 Waling-Waling Street Novaliches Proper', 'Quezon City', 'NCR / Metro Manila', '1405', 'gilbert.austria@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(283, 295, '000000000276', 'Miguel', 'Gonzalez', 'Macapagal', 'male', '2011-04-25', 'Malabon City', 'Filipino', 'Catholic', 'Blk 28 Lot 21 Ilang-Ilang Street Masinag Heights', 'Malabon City', 'NCR / Metro Manila', '1420', 'miguel.macapagal@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(284, 296, '000000000277', 'Patricia', 'Lopez', 'De Guzman', 'female', '2010-12-12', 'City of Caloocan', 'Filipino', 'Islam', 'Blk 44 Lot 1 Pansy Lane Bagumbong Residences', 'City of Caloocan', 'None', '1447', 'patricia.deguzman@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(285, 297, '000000000278', 'Jessica', 'Jimenez', 'Austria', 'female', '2012-05-06', 'City of Caloocan', 'Filipino', 'Iglesia ni Cristo', 'Blk 34 Lot 20 Waling-Waling Street Masinag Heights', 'City of Caloocan', 'NCR / Metro Manila', '1404', 'jessica.austria@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(286, 298, '000000000279', 'Oliver', 'Reyes', 'Tuason', 'male', '2010-03-26', 'Quezon City', 'Filipino', 'Born Again', 'Blk 9 Lot 7 Sampaguita Street Camarin North Subdivision', 'Quezon City', 'NCR / Metro Manila', '1403', 'oliver.tuason@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(287, 299, '000000000280', 'Felix', NULL, 'Danao', 'male', '2010-07-21', 'Navotas City', 'Filipino', 'Catholic', 'Blk 42 Lot 27 Sampaguita Street Crystal Valley Subdivision', 'Navotas City', 'NCR / Metro Manila', '1422', 'felix.danao@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(288, 300, '000000000281', 'Richard', 'Lopez', 'Doria', 'male', '2011-08-23', 'Malabon City', 'Filipino', NULL, 'Blk 20 Lot 14 Dahlia Drive Novaliches Proper', 'Malabon City', 'NCR / Metro Manila', '1440', 'richard.doria@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(289, 301, '000000000282', 'Claire', NULL, 'Delotavo', 'female', '2010-09-24', 'Valenzuela City', 'Filipino', 'Catholic', 'Blk 32 Lot 7 Calachuchi Lane Greenfield Residences', 'Valenzuela City', 'NCR / Metro Manila', '1404', 'claire.delotavo@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(290, 302, '000000000283', 'Sandra', 'Garcia', 'Barroga', 'female', '2011-03-02', 'Valenzuela City', 'Filipino', NULL, 'Blk 22 Lot 8 Sampaguita Street Crystal Valley Subdivision', 'Valenzuela City', 'None', '1403', 'sandra.barroga@gmail.com', 'returning', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(291, 303, '000000000284', 'Enrique', 'Iglesias', 'Soriano', 'male', '2010-02-25', 'Valenzuela City', 'Filipino', NULL, 'Blk 17 Lot 21 Pansy Lane Golden Villa Subdivision', 'Valenzuela City', 'NCR / Metro Manila', '1440', 'enrique.soriano@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(292, 304, '000000000285', 'Isabel', 'Santos', 'Dumlao', 'female', '2010-01-28', 'Navotas City', 'Filipino', NULL, 'Blk 48 Lot 4 Dahlia Drive Sta. Monica Hills', 'Navotas City', 'None', '1447', 'isabel.dumlao@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(293, 305, '000000000286', 'Adrian', 'Navarro', 'Tabios', 'male', '2010-06-12', 'Quezon City', 'Filipino', 'Catholic', 'Blk 22 Lot 6 Dahlia Drive Masinag Heights', 'Quezon City', 'None', '1440', 'adrian.tabios@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(294, 306, '000000000287', 'Monica', NULL, 'Borromeo', 'female', '2012-08-26', 'Quezon City', 'Filipino', 'Born Again', 'Blk 4 Lot 28 Bougainvillea Drive Heritage Park Subdivision', 'Quezon City', 'NCR / Metro Manila', '1401', 'monica.borromeo@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(295, 307, '000000000288', 'Victoria', NULL, 'Duran', 'female', '2012-08-06', 'Valenzuela City', 'Filipino', 'Iglesia ni Cristo', 'Blk 44 Lot 29 Rosal Avenue Golden Villa Subdivision', 'Valenzuela City', 'None', '1447', 'victoria.duran@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(296, 308, '000000000289', 'Cecilia', 'Andrade', 'Tolentino', 'female', '2010-05-21', 'Navotas City', 'Filipino', NULL, 'Blk 48 Lot 19 Pansy Lane Novaliches Proper', 'Navotas City', 'NCR / Metro Manila', '1440', 'cecilia.tolentino@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(297, 309, '000000000290', 'Sandra', NULL, 'Esteban', 'female', '2012-02-14', 'Malabon City', 'Filipino', NULL, 'Blk 25 Lot 5 Jasmine Lane Crystal Valley Subdivision', 'Malabon City', 'None', '1405', 'sandra.esteban@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(298, 310, '000000000291', 'Victor', 'Iglesias', 'Tabios', 'male', '2010-02-25', 'Quezon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 4 Lot 17 Pansy Lane Sunrise Village', 'Quezon City', 'None', '1403', 'victor.tabios@gmail.com', 'returning', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(299, 311, '000000000292', 'Lucia', 'Gonzalez', 'Santos', 'female', '2011-10-15', 'City of Caloocan', 'Filipino', 'Iglesia ni Cristo', 'Blk 32 Lot 24 Sampaguita Street Heritage Park Subdivision', 'City of Caloocan', 'None', '1420', 'lucia.santos@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0);
INSERT INTO `students` (`id`, `user_id`, `lrn`, `first_name`, `middle_name`, `last_name`, `sex`, `date_of_birth`, `place_of_birth`, `nationality`, `religion`, `address`, `city`, `province`, `zip_code`, `personal_email`, `enrollment_type`, `grade_level_id`, `registration_status`, `data_last_updated`, `created_at`, `updated_at`, `is_archived`) VALUES
(300, 312, '000000000293', 'Lydia', 'Aguilar', 'Aldana', 'female', '2010-10-20', 'Navotas City', 'Filipino', NULL, 'Blk 22 Lot 12 Jasmine Lane Sta. Monica Hills', 'Navotas City', 'NCR / Metro Manila', '1430', 'lydia.aldana@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(301, 313, '000000000294', 'Sean', 'Mendoza', 'Cervantes', 'male', '2012-08-23', 'Navotas City', 'Filipino', 'Catholic', 'Blk 15 Lot 1 Waling-Waling Street Lakeview Estates', 'Navotas City', 'None', '1401', 'sean.cervantes@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(302, 314, '000000000295', 'Stella', 'Bautista', 'Esteban', 'female', '2010-03-16', 'Malabon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 13 Lot 4 Marigold Avenue Bagumbong Residences', 'Malabon City', 'None', '1401', 'stella.esteban@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(303, 315, '000000000296', 'Eliza', 'Reyes', 'Orozco', 'female', '2011-01-21', 'Valenzuela City', 'Filipino', 'Christian', 'Blk 38 Lot 17 Rosal Avenue Golden Villa Subdivision', 'Valenzuela City', 'NCR / Metro Manila', '1447', 'eliza.orozco@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(304, 316, '000000000297', 'Xavier', 'Yap', 'Paglinawan', 'male', '2011-10-16', 'Valenzuela City', 'Filipino', 'Islam', 'Blk 9 Lot 4 Marigold Avenue Novaliches Proper', 'Valenzuela City', 'NCR / Metro Manila', '1440', 'xavier.paglinawan@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(305, 317, '000000000298', 'Reyna', 'Mendoza', 'Tolentino', 'female', '2012-04-09', 'Quezon City', 'Filipino', 'Christian', 'Blk 9 Lot 14 Lotus Street Sta. Monica Hills', 'Quezon City', 'None', '1404', 'reyna.tolentino@gmail.com', 'returning', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(306, 318, '000000000299', 'Stella', 'Cruz', 'Macapagal', 'female', '2012-12-10', 'Navotas City', 'Filipino', NULL, 'Blk 12 Lot 17 Waling-Waling Street Harmony Village', 'Navotas City', 'NCR / Metro Manila', '1440', 'stella.macapagal@gmail.com', 'returning', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(307, 319, '000000000300', 'Patrick', 'Magno', 'Flores', 'male', '2012-12-14', 'Valenzuela City', 'Filipino', 'Catholic', 'Blk 2 Lot 13 Rosal Avenue Crystal Valley Subdivision', 'Valenzuela City', 'None', '1410', 'patrick.flores@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(308, 320, '000000000301', 'John', NULL, 'Borromeo', 'male', '2010-05-22', 'Navotas City', 'Filipino', NULL, 'Blk 14 Lot 25 Jasmine Lane Lakeview Estates', 'Navotas City', 'NCR / Metro Manila', '1400', 'john.borromeo@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(309, 321, '000000000302', 'Caroline', NULL, 'Lim', 'female', '2012-09-28', 'Malabon City', 'Filipino', 'Islam', 'Blk 45 Lot 10 Jasmine Lane Masinag Heights', 'Malabon City', 'None', '1403', 'caroline.lim@gmail.com', 'transferee', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(310, 322, '000000000303', 'Mabel', NULL, 'Zamora', 'female', '2012-06-18', 'City of Caloocan', 'Filipino', 'Iglesia ni Cristo', 'Blk 50 Lot 28 Zinnia Street Sta. Monica Hills', 'City of Caloocan', 'NCR / Metro Manila', '1440', 'mabel.zamora@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(311, 323, '000000000304', 'Peter', 'Ramos', 'Reyes', 'male', '2012-04-25', 'Malabon City', 'Filipino', 'Born Again', 'Blk 5 Lot 6 Bougainvillea Drive Harmony Village', 'Malabon City', 'None', '1420', 'peter.reyes@gmail.com', 'returning', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(312, 324, '000000000305', 'Philip', 'Lopez', 'Aldana', 'male', '2011-03-06', 'Valenzuela City', 'Filipino', 'Iglesia ni Cristo', 'Blk 10 Lot 2 Rosal Avenue Lakeview Estates', 'Valenzuela City', 'None', '1400', 'philip.aldana@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(313, 325, '000000000306', 'Matthew', NULL, 'Enriquez', 'male', '2012-06-03', 'Navotas City', 'Filipino', 'Islam', 'Blk 33 Lot 6 Ilang-Ilang Street Sunrise Village', 'Navotas City', 'NCR / Metro Manila', '1402', 'matthew.enriquez@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(314, 326, '000000000307', 'Bianca', 'Cruz', 'Cipriano', 'female', '2012-06-11', 'Navotas City', 'Filipino', 'Islam', 'Blk 36 Lot 27 Sampaguita Street Heritage Park Subdivision', 'Navotas City', 'None', '1403', 'bianca.cipriano@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(315, 327, '000000000308', 'Michelle', NULL, 'Benedicto', 'female', '2012-10-08', 'City of Caloocan', 'Filipino', 'Catholic', 'Blk 35 Lot 24 Lotus Street Crystal Valley Subdivision', 'City of Caloocan', 'None', '1410', 'michelle.benedicto@gmail.com', 'new', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(316, 328, '000000000309', 'Rosa', 'Iglesias', 'Samonte', 'female', '2010-05-21', 'Malabon City', 'Filipino', 'Catholic', 'Blk 11 Lot 25 Sampaguita Street Novaliches Proper', 'Malabon City', 'None', '1421', 'rosa.samonte@gmail.com', 'returning', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(317, 329, '000000000310', 'Joseph', 'Cruz', 'Mercado', 'male', '2012-07-27', 'City of Caloocan', 'Filipino', NULL, 'Blk 48 Lot 25 Ilang-Ilang Street Novaliches Proper', 'City of Caloocan', 'NCR / Metro Manila', '1421', 'joseph.mercado@gmail.com', 'returning', 9, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(318, 330, '000000000311', 'Gilbert', 'Espinosa', 'Alcantara', 'male', '2009-02-03', 'City of Caloocan', 'Filipino', 'Iglesia ni Cristo', 'Blk 37 Lot 27 Pansy Lane Panorama Heights', 'City of Caloocan', 'NCR / Metro Manila', '1447', 'gilbert.alcantara@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(319, 331, '000000000312', 'Lorraine', 'Garcia', 'Doria', 'female', '2010-01-13', 'City of Caloocan', 'Filipino', NULL, 'Blk 49 Lot 24 Jasmine Lane Harmony Village', 'City of Caloocan', 'NCR / Metro Manila', '1430', 'lorraine.doria@gmail.com', 'transferee', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(320, 332, '000000000313', 'Patrick', 'Dela Cruz', 'Villanueva', 'male', '2011-05-20', 'City of Caloocan', 'Filipino', 'Christian', 'Blk 43 Lot 1 Makopa Drive Castlespring Heights Subdivision', 'City of Caloocan', 'None', '1447', 'patrick.villanueva@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(321, 333, '000000000314', 'Gabriel', 'Salazar', 'Paglinawan', 'male', '2011-05-21', 'Malabon City', 'Filipino', NULL, 'Blk 1 Lot 18 Rosal Avenue Heritage Park Subdivision', 'Malabon City', 'None', '1430', 'gabriel.paglinawan@gmail.com', 'transferee', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(322, 334, '000000000315', 'Aaron', 'Lopez', 'Fontanilla', 'male', '2011-02-10', 'Malabon City', 'Filipino', 'Christian', 'Blk 33 Lot 5 Bougainvillea Drive Castlespring Heights Subdivision', 'Malabon City', 'None', '1403', 'aaron.fontanilla@gmail.com', 'returning', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(323, 335, '000000000316', 'Leo', 'Ocampo', 'Barroga', 'male', '2011-01-28', 'Valenzuela City', 'Filipino', 'Islam', 'Blk 43 Lot 3 Champaca Road Heritage Park Subdivision', 'Valenzuela City', 'None', '1430', 'leo.barroga@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(324, 336, '000000000317', 'Timothy', 'Bernardo', 'Yap', 'male', '2011-11-08', 'City of Caloocan', 'Filipino', 'Catholic', 'Blk 21 Lot 16 Zinnia Street Lakeview Estates', 'City of Caloocan', 'None', '1422', 'timothy.yap@gmail.com', 'returning', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(325, 337, '000000000318', 'Veronica', 'Estrada', 'Ayala', 'female', '2010-07-06', 'City of Caloocan', 'Filipino', 'Born Again', 'Blk 42 Lot 14 Champaca Road Sta. Monica Hills', 'City of Caloocan', 'None', '1403', 'veronica.ayala@gmail.com', 'transferee', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(326, 338, '000000000319', 'Claire', NULL, 'Montoya', 'female', '2010-08-15', 'Navotas City', 'Filipino', 'Islam', 'Blk 42 Lot 20 Gumamela Road Sta. Monica Hills', 'Navotas City', 'None', '1420', 'claire.montoya@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(327, 339, '000000000320', 'Claire', 'De Leon', 'Tuason', 'female', '2011-11-03', 'City of Caloocan', 'Filipino', NULL, 'Blk 38 Lot 19 Marigold Avenue Greenfield Residences', 'City of Caloocan', 'NCR / Metro Manila', '1421', 'claire.tuason@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(328, 340, '000000000321', 'Angelo', 'Villanueva', 'Flores', 'male', '2011-08-21', 'Malabon City', 'Filipino', 'Born Again', 'Blk 38 Lot 24 Lotus Street Castlespring Heights Subdivision', 'Malabon City', 'None', '1410', 'angelo.flores@gmail.com', 'returning', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(329, 341, '000000000322', 'Reyna', 'Estrada', 'Esquivel', 'female', '2011-01-22', 'Malabon City', 'Filipino', 'Islam', 'Blk 11 Lot 6 Rosal Avenue Harmony Village', 'Malabon City', 'NCR / Metro Manila', '1447', 'reyna.esquivel@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(330, 342, '000000000323', 'Laura', 'Iglesias', 'Aldana', 'female', '2009-02-09', 'Navotas City', 'Filipino', NULL, 'Blk 24 Lot 13 Makopa Drive Golden Villa Subdivision', 'Navotas City', 'NCR / Metro Manila', '1400', 'laura.aldana@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(331, 343, '000000000324', 'Anthony', 'Padilla', 'Macaraeg', 'male', '2011-11-27', 'Navotas City', 'Filipino', 'Islam', 'Blk 25 Lot 21 Marigold Avenue Lakeview Estates', 'Navotas City', 'None', '1422', 'anthony.macaraeg@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(332, 344, '000000000325', 'William', 'Yap', 'Borja', 'male', '2009-09-13', 'Navotas City', 'Filipino', 'Christian', 'Blk 1 Lot 17 Rosal Avenue Golden Villa Subdivision', 'Navotas City', 'None', '1420', 'william.borja@gmail.com', 'returning', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(333, 345, '000000000326', 'Kevin', 'De Leon', 'Alfonso', 'male', '2009-03-06', 'Malabon City', 'Filipino', NULL, 'Blk 43 Lot 8 Ilang-Ilang Street Greenfield Residences', 'Malabon City', 'None', '1422', 'kevin.alfonso@gmail.com', 'returning', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(334, 346, '000000000327', 'Cecilia', NULL, 'Duran', 'female', '2010-04-19', 'Malabon City', 'Filipino', 'Born Again', 'Blk 37 Lot 19 Bougainvillea Drive Castlespring Heights Subdivision', 'Malabon City', 'None', '1400', 'cecilia.duran@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(335, 347, '000000000328', 'Gerald', 'Yap', 'Alejo', 'male', '2009-09-13', 'Valenzuela City', 'Filipino', NULL, 'Blk 19 Lot 3 Calachuchi Lane Golden Villa Subdivision', 'Valenzuela City', 'NCR / Metro Manila', '1440', 'gerald.alejo@gmail.com', 'transferee', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(336, 348, '000000000329', 'Patricia', 'Garcia', 'Balboa', 'female', '2011-03-26', 'Valenzuela City', 'Filipino', NULL, 'Blk 11 Lot 24 Waling-Waling Street Golden Villa Subdivision', 'Valenzuela City', 'NCR / Metro Manila', '1422', 'patricia.balboa@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(337, 349, '000000000330', 'Kevin', 'Bautista', 'De Guzman', 'male', '2009-04-17', 'Valenzuela City', 'Filipino', 'Islam', 'Blk 31 Lot 29 Jasmine Lane Greenfield Residences', 'Valenzuela City', 'None', '1402', 'kevin.deguzman@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(338, 350, '000000000331', 'Dominic', NULL, 'Duran', 'male', '2011-09-27', 'City of Caloocan', 'Filipino', 'Christian', 'Blk 3 Lot 23 Ilang-Ilang Street Bagumbong Residences', 'City of Caloocan', 'None', '1421', 'dominic.duran@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(339, 351, '000000000332', 'Lisa', 'Ramos', 'Cipriano', 'female', '2011-10-04', 'Quezon City', 'Filipino', 'Christian', 'Blk 6 Lot 10 Ilang-Ilang Street Panorama Heights', 'Quezon City', 'NCR / Metro Manila', '1404', 'lisa.cipriano@gmail.com', 'transferee', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(340, 352, '000000000333', 'Aaron', NULL, 'Orozco', 'male', '2009-10-17', 'City of Caloocan', 'Filipino', NULL, 'Blk 21 Lot 14 Adelfa Street Heritage Park Subdivision', 'City of Caloocan', 'NCR / Metro Manila', '1410', 'aaron.orozco@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(341, 353, '000000000334', 'Robert', 'De Leon', 'Macaraeg', 'male', '2011-07-19', 'Navotas City', 'Filipino', 'Christian', 'Blk 27 Lot 18 Makopa Drive Castlespring Heights Subdivision', 'Navotas City', 'None', '1430', 'robert.macaraeg@gmail.com', 'transferee', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(342, 354, '000000000335', 'Teresa', 'Dela Cruz', 'Flores', 'female', '2011-06-25', 'Quezon City', 'Filipino', 'Catholic', 'Blk 29 Lot 26 Bougainvillea Drive Heritage Park Subdivision', 'Quezon City', 'NCR / Metro Manila', '1430', 'teresa.flores@gmail.com', 'transferee', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(343, 355, '000000000336', 'Vincent', NULL, 'De Villa', 'male', '2011-10-23', 'City of Caloocan', 'Filipino', NULL, 'Blk 6 Lot 27 Rosal Avenue Golden Villa Subdivision', 'City of Caloocan', 'NCR / Metro Manila', '1410', 'vincent.devilla@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(344, 356, '000000000337', 'Bianca', 'Estrada', 'Alfonso', 'female', '2009-10-02', 'Quezon City', 'Filipino', NULL, 'Blk 46 Lot 20 Jasmine Lane Greenfield Residences', 'Quezon City', 'None', '1422', 'bianca.alfonso@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(345, 357, '000000000338', 'Tristan', 'Torres', 'Doria', 'male', '2011-09-10', 'Malabon City', 'Filipino', 'Islam', 'Blk 45 Lot 8 Bougainvillea Drive Novaliches Proper', 'Malabon City', 'NCR / Metro Manila', '1447', 'tristan.doria@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(346, 358, '000000000339', 'Paul', NULL, 'Benedicto', 'male', '2009-02-09', 'Quezon City', 'Filipino', 'Christian', 'Blk 13 Lot 17 Sampaguita Street Harmony Village', 'Quezon City', 'None', '1430', 'paul.benedicto@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(347, 359, '000000000340', 'Dominic', 'Santos', 'Flores', 'male', '2011-10-12', 'Navotas City', 'Filipino', 'Islam', 'Blk 30 Lot 30 Marigold Avenue Camarin North Subdivision', 'Navotas City', 'None', '1403', 'dominic.flores@gmail.com', 'returning', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(348, 360, '000000000341', 'Lorenzo', 'Bautista', 'Barrientos', 'male', '2011-02-17', 'Navotas City', 'Filipino', 'Islam', 'Blk 35 Lot 27 Champaca Road Harmony Village', 'Navotas City', 'None', '1401', 'lorenzo.barrientos360@gmail.com', 'returning', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(349, 361, '000000000342', 'Lisa', 'De Guzman', 'Fontanilla', 'female', '2010-08-22', 'Quezon City', 'Filipino', 'Catholic', 'Blk 25 Lot 21 Pansy Lane Novaliches Proper', 'Quezon City', 'NCR / Metro Manila', '1420', 'lisa.fontanilla@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(350, 362, '000000000343', 'Miguel', NULL, 'Delotavo', 'male', '2011-09-01', 'Navotas City', 'Filipino', 'Catholic', 'Blk 48 Lot 27 Waling-Waling Street Heritage Park Subdivision', 'Navotas City', 'NCR / Metro Manila', '1404', 'miguel.delotavo@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(351, 363, '000000000344', 'Theodore', 'Villanueva', 'Cayabyab', 'male', '2011-05-06', 'Malabon City', 'Filipino', 'Born Again', 'Blk 16 Lot 28 Champaca Road Bagumbong Residences', 'Malabon City', 'None', '1440', 'theodore.cayabyab@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(352, 364, '000000000345', 'John', 'Mendoza', 'Soriano', 'male', '2010-03-25', 'City of Caloocan', 'Filipino', NULL, 'Blk 32 Lot 20 Sampaguita Street Greenfield Residences', 'City of Caloocan', 'NCR / Metro Manila', '1401', 'john.soriano@gmail.com', 'returning', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(353, 365, '000000000346', 'Thomas', 'Iglesias', 'Danao', 'male', '2011-05-16', 'Malabon City', 'Filipino', 'Born Again', 'Blk 9 Lot 2 Ilang-Ilang Street Golden Villa Subdivision', 'Malabon City', 'None', '1410', 'thomas.danao@gmail.com', 'transferee', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(354, 366, '000000000347', 'Victor', 'Ocampo', 'Cipriano', 'male', '2009-08-04', 'Valenzuela City', 'Filipino', NULL, 'Blk 44 Lot 7 Marigold Avenue Camarin North Subdivision', 'Valenzuela City', 'None', '1405', 'victor.cipriano@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(355, 367, '000000000348', 'Nathan', 'De Leon', 'Danao', 'male', '2009-09-09', 'Malabon City', 'Filipino', 'Islam', 'Blk 12 Lot 16 Ilang-Ilang Street Bagumbong Residences', 'Malabon City', 'None', '1420', 'nathan.danao@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(356, 368, '000000000349', 'Leia', NULL, 'Danao', 'female', '2010-08-06', 'Valenzuela City', 'Filipino', NULL, 'Blk 7 Lot 24 Champaca Road Greenfield Residences', 'Valenzuela City', 'NCR / Metro Manila', '1422', 'leia.danao@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(357, 369, '000000000350', 'Ronald', 'Bernardo', 'Tabios', 'male', '2011-03-16', 'City of Caloocan', 'Filipino', 'Christian', 'Blk 41 Lot 17 Waling-Waling Street Greenfield Residences', 'City of Caloocan', 'NCR / Metro Manila', '1410', 'ronald.tabios@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(358, 370, '000000000351', 'Jennifer', 'Magno', 'Borja', 'female', '2009-07-04', 'Malabon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 41 Lot 4 Zinnia Street Harmony Village', 'Malabon City', 'NCR / Metro Manila', '1403', 'jennifer.borja@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(359, 371, '000000000352', 'Isabel', 'Lopez', 'Danao', 'female', '2010-06-01', 'Quezon City', 'Filipino', NULL, 'Blk 13 Lot 19 Bougainvillea Drive Greenfield Residences', 'Quezon City', 'NCR / Metro Manila', '1405', 'isabel.danao@gmail.com', 'returning', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(360, 372, '000000000353', 'Laura', NULL, 'Cayabyab', 'female', '2010-12-15', 'City of Caloocan', 'Filipino', 'Iglesia ni Cristo', 'Blk 10 Lot 28 Bougainvillea Drive Novaliches Proper', 'City of Caloocan', 'None', '1422', 'laura.cayabyab@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(361, 373, '000000000354', 'Mabel', 'Fernandez', 'Macapagal', 'female', '2009-02-06', 'Navotas City', 'Filipino', 'Iglesia ni Cristo', 'Blk 46 Lot 9 Marigold Avenue Panorama Heights', 'Navotas City', 'NCR / Metro Manila', '1405', 'mabel.macapagal@gmail.com', 'transferee', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(362, 374, '000000000355', 'Leah', 'Gonzalez', 'Paglinawan', 'female', '2010-03-06', 'City of Caloocan', 'Filipino', 'Born Again', 'Blk 48 Lot 23 Gumamela Road Bagumbong Residences', 'City of Caloocan', 'NCR / Metro Manila', '1440', 'leah.paglinawan@gmail.com', 'transferee', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(363, 375, '000000000356', 'Ramon', 'Yap', 'Andres', 'male', '2010-09-02', 'City of Caloocan', 'Filipino', 'Catholic', 'Blk 40 Lot 5 Gumamela Road Novaliches Proper', 'City of Caloocan', 'None', '1421', 'ramon.andres@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(364, 376, '000000000357', 'Jessica', 'Dela Cruz', 'Beltran', 'female', '2010-11-05', 'Malabon City', 'Filipino', 'Catholic', 'Blk 21 Lot 28 Makopa Drive Golden Villa Subdivision', 'Malabon City', 'NCR / Metro Manila', '1400', 'jessica.beltran@gmail.com', 'transferee', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(365, 377, '000000000358', 'Stella', 'Padilla', 'Doria', 'female', '2011-03-19', 'Valenzuela City', 'Filipino', NULL, 'Blk 37 Lot 14 Lotus Street Lakeview Estates', 'Valenzuela City', 'None', '1430', 'stella.doria@gmail.com', 'transferee', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(366, 378, '000000000359', 'Sofia', NULL, 'Beltran', 'female', '2010-05-12', 'Quezon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 34 Lot 27 Rosal Avenue Lakeview Estates', 'Quezon City', 'None', '1402', 'sofia.beltran@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(367, 379, '000000000360', 'Nicole', 'Yap', 'Ferrer', 'female', '2010-08-10', 'City of Caloocan', 'Filipino', 'Iglesia ni Cristo', 'Blk 1 Lot 18 Adelfa Street Bagumbong Residences', 'City of Caloocan', 'None', '1447', 'nicole.ferrer@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(368, 380, '000000000361', 'Teresa', 'Castillo', 'Dionisio', 'female', '2011-12-21', 'Quezon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 41 Lot 8 Champaca Road Panorama Heights', 'Quezon City', 'None', '1403', 'teresa.dionisio@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(369, 381, '000000000362', 'Lydia', NULL, 'Barroga', 'female', '2009-03-10', 'City of Caloocan', 'Filipino', 'Christian', 'Blk 40 Lot 16 Calachuchi Lane Lakeview Estates', 'City of Caloocan', 'None', '1422', 'lydia.barroga381@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(370, 382, '000000000363', 'Gilbert', NULL, 'Alejo', 'male', '2009-03-04', 'Navotas City', 'Filipino', NULL, 'Blk 1 Lot 8 Gumamela Road Castlespring Heights Subdivision', 'Navotas City', 'None', '1402', 'gilbert.alejo@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(371, 383, '000000000364', 'Tristan', 'Dela Cruz', 'Bautista', 'male', '2010-06-15', 'City of Caloocan', 'Filipino', 'Born Again', 'Blk 50 Lot 13 Gumamela Road Sunrise Village', 'City of Caloocan', 'None', '1401', 'tristan.bautista@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(372, 384, '000000000365', 'Elisa', NULL, 'Barroga', 'female', '2010-07-27', 'City of Caloocan', 'Filipino', NULL, 'Blk 50 Lot 15 Pansy Lane Harmony Village', 'City of Caloocan', 'NCR / Metro Manila', '1447', 'elisa.barroga@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(373, 385, '000000000366', 'John', NULL, 'Dumlao', 'male', '2009-09-22', 'Malabon City', 'Filipino', NULL, 'Blk 21 Lot 6 Jasmine Lane Harmony Village', 'Malabon City', 'None', '1410', 'john.dumlao@gmail.com', 'returning', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(374, 386, '000000000367', 'Leo', 'Cruz', 'Duran', 'male', '2010-01-28', 'Malabon City', 'Filipino', NULL, 'Blk 1 Lot 6 Champaca Road Camarin North Subdivision', 'Malabon City', 'NCR / Metro Manila', '1403', 'leo.duran@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(375, 387, '000000000368', 'Ramon', 'Andrade', 'Salas', 'male', '2011-12-16', 'Valenzuela City', 'Filipino', 'Catholic', 'Blk 32 Lot 3 Waling-Waling Street Greenfield Residences', 'Valenzuela City', 'NCR / Metro Manila', '1405', 'ramon.salas@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(376, 388, '000000000369', 'Carlo', 'Padilla', 'Cipriano', 'male', '2011-02-05', 'Quezon City', 'Filipino', 'Islam', 'Blk 49 Lot 12 Zinnia Street Harmony Village', 'Quezon City', 'NCR / Metro Manila', '1405', 'carlo.cipriano@gmail.com', 'transferee', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(377, 389, '000000000370', 'Alexander', 'Ramos', 'Navarro', 'male', '2009-05-02', 'Quezon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 32 Lot 7 Bougainvillea Drive Sunrise Village', 'Quezon City', 'None', '1421', 'alexander.navarro@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(378, 390, '000000000371', 'Julia', 'Torres', 'Padilla', 'female', '2011-09-06', 'City of Caloocan', 'Filipino', 'Iglesia ni Cristo', 'Blk 35 Lot 12 Zinnia Street Crystal Valley Subdivision', 'City of Caloocan', 'NCR / Metro Manila', '1420', 'julia.padilla@gmail.com', 'returning', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(379, 391, '000000000372', 'Elisa', 'Torres', 'Tolentino', 'female', '2010-10-08', 'Navotas City', 'Filipino', 'Islam', 'Blk 13 Lot 17 Makopa Drive Greenfield Residences', 'Navotas City', 'NCR / Metro Manila', '1430', 'elisa.tolentino@gmail.com', 'returning', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(380, 392, '000000000373', 'Marcus', 'Espinosa', 'Cayabyab', 'male', '2009-02-17', 'City of Caloocan', 'Filipino', 'Born Again', 'Blk 13 Lot 4 Makopa Drive Bagumbong Residences', 'City of Caloocan', 'NCR / Metro Manila', '1402', 'marcus.cayabyab@gmail.com', 'returning', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(381, 393, '000000000374', 'Angelo', 'Fernandez', 'Fontanilla', 'male', '2011-08-17', 'Valenzuela City', 'Filipino', 'Iglesia ni Cristo', 'Blk 46 Lot 3 Sampaguita Street Bagumbong Residences', 'Valenzuela City', 'None', '1400', 'angelo.fontanilla393@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(382, 394, '000000000375', 'Beatrice', NULL, 'Dumlao', 'female', '2009-06-18', 'Quezon City', 'Filipino', NULL, 'Blk 40 Lot 9 Jasmine Lane Harmony Village', 'Quezon City', 'None', '1447', 'beatrice.dumlao@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(383, 395, '000000000376', 'Matthew', NULL, 'Alfonso', 'male', '2011-02-04', 'Malabon City', 'Filipino', 'Born Again', 'Blk 16 Lot 19 Bougainvillea Drive Sunrise Village', 'Malabon City', 'None', '1403', 'matthew.alfonso@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(384, 396, '000000000377', 'Caroline', 'Estrada', 'Robles', 'female', '2011-08-23', 'Quezon City', 'Filipino', 'Born Again', 'Blk 33 Lot 11 Bougainvillea Drive Sunrise Village', 'Quezon City', 'NCR / Metro Manila', '1402', 'caroline.robles@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(385, 397, '000000000378', 'Laura', 'Espinosa', 'Tuason', 'female', '2010-07-25', 'Quezon City', 'Filipino', 'Born Again', 'Blk 14 Lot 13 Champaca Road Lakeview Estates', 'Quezon City', 'None', '1422', 'laura.tuason@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(386, 398, '000000000379', 'Michelle', 'Ramos', 'Zamora', 'female', '2009-05-20', 'City of Caloocan', 'Filipino', 'Catholic', 'Blk 15 Lot 7 Waling-Waling Street Crystal Valley Subdivision', 'City of Caloocan', 'NCR / Metro Manila', '1404', 'michelle.zamora@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(387, 399, '000000000380', 'Stella', 'Yap', 'Esquivel', 'female', '2011-03-04', 'City of Caloocan', 'Filipino', 'Born Again', 'Blk 24 Lot 29 Pansy Lane Bagumbong Residences', 'City of Caloocan', 'None', '1405', 'stella.esquivel@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(388, 400, '000000000381', 'Jennifer', 'Magno', 'Almeda', 'female', '2009-12-03', 'Navotas City', 'Filipino', 'Christian', 'Blk 45 Lot 23 Dahlia Drive Camarin North Subdivision', 'Navotas City', 'None', '1402', 'jennifer.almeda@gmail.com', 'returning', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(389, 401, '000000000382', 'Alicia', NULL, 'Padilla', 'female', '2010-02-25', 'City of Caloocan', 'Filipino', 'Christian', 'Blk 8 Lot 28 Pansy Lane Harmony Village', 'City of Caloocan', 'None', '1405', 'alicia.padilla@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(390, 402, '000000000383', 'Philip', 'Andrade', 'Alejo', 'male', '2010-09-19', 'Malabon City', 'Filipino', NULL, 'Blk 4 Lot 22 Marigold Avenue Golden Villa Subdivision', 'Malabon City', 'None', '1421', 'philip.alejo@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(391, 403, '000000000384', 'Julian', 'Fernandez', 'Dionisio', 'male', '2009-03-11', 'City of Caloocan', 'Filipino', NULL, 'Blk 26 Lot 9 Gumamela Road Masinag Heights', 'City of Caloocan', 'None', '1422', 'julian.dionisio@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(392, 404, '000000000385', 'Christina', 'Lopez', 'Reyes', 'female', '2009-08-13', 'Valenzuela City', 'Filipino', 'Islam', 'Blk 34 Lot 8 Pansy Lane Heritage Park Subdivision', 'Valenzuela City', 'NCR / Metro Manila', '1421', 'christina.reyes@gmail.com', 'returning', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(393, 405, '000000000386', 'Maricel', NULL, 'Cayabyab', 'female', '2011-02-04', 'Quezon City', 'Filipino', 'Iglesia ni Cristo', 'Blk 23 Lot 20 Sampaguita Street Greenfield Residences', 'Quezon City', 'None', '1405', 'maricel.cayabyab@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(394, 406, '000000000387', 'Donna', 'Salazar', 'Cipriano', 'female', '2010-10-05', 'Quezon City', 'Filipino', 'Born Again', 'Blk 10 Lot 25 Gumamela Road Heritage Park Subdivision', 'Quezon City', 'NCR / Metro Manila', '1403', 'donna.cipriano@gmail.com', 'transferee', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(395, 407, '000000000388', 'Lance', 'Bernardo', 'Yap', 'male', '2010-01-11', 'City of Caloocan', 'Filipino', 'Christian', 'Blk 14 Lot 24 Calachuchi Lane Bagumbong Residences', 'City of Caloocan', 'None', '1420', 'lance.yap@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(396, 408, '000000000389', 'Stella', 'Bernardo', 'Duran', 'female', '2011-12-22', 'City of Caloocan', 'Filipino', NULL, 'Blk 17 Lot 6 Jasmine Lane Panorama Heights', 'City of Caloocan', 'None', '1422', 'stella.duran408@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(397, 409, '000000000390', 'Luis', 'Aguilar', 'Alejo', 'male', '2009-07-22', 'Navotas City', 'Filipino', 'Catholic', 'Blk 42 Lot 13 Pansy Lane Masinag Heights', 'Navotas City', 'None', '1401', 'luis.alejo@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(398, 410, '000000000391', 'Miguel', NULL, 'Enriquez', 'male', '2011-02-06', 'Malabon City', 'Filipino', NULL, 'Blk 16 Lot 30 Lotus Street Lakeview Estates', 'Malabon City', 'None', '1421', 'miguel.enriquez@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(399, 411, '000000000392', 'Lourdes', 'Estrada', 'Paglinawan', 'female', '2011-06-12', 'Navotas City', 'Filipino', 'Iglesia ni Cristo', 'Blk 41 Lot 9 Marigold Avenue Sta. Monica Hills', 'Navotas City', 'NCR / Metro Manila', '1421', 'lourdes.paglinawan@gmail.com', 'returning', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(400, 412, '000000000393', 'Marco', 'Villanueva', 'Beltran', 'male', '2010-11-05', 'City of Caloocan', 'Filipino', NULL, 'Blk 41 Lot 22 Pansy Lane Masinag Heights', 'City of Caloocan', 'None', '1421', 'marco.beltran@gmail.com', 'transferee', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(401, 413, '000000000394', 'Gilbert', NULL, 'Dionisio', 'male', '2011-06-15', 'Valenzuela City', 'Filipino', NULL, 'Blk 35 Lot 22 Calachuchi Lane Sta. Monica Hills', 'Valenzuela City', 'NCR / Metro Manila', '1403', 'gilbert.dionisio@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(402, 414, '000000000395', 'Michael', NULL, 'Navarro', 'male', '2011-03-14', 'Malabon City', 'Filipino', 'Catholic', 'Blk 47 Lot 4 Bougainvillea Drive Lakeview Estates', 'Malabon City', 'NCR / Metro Manila', '1405', 'michael.navarro@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(403, 415, '000000000396', 'Andrei', 'Garcia', 'Reyes', 'male', '2010-05-15', 'Navotas City', 'Filipino', 'Born Again', 'Blk 12 Lot 1 Champaca Road Camarin North Subdivision', 'Navotas City', 'NCR / Metro Manila', '1447', 'andrei.reyes@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(404, 416, '000000000397', 'Kevin', NULL, 'Beltran', 'male', '2010-02-23', 'Quezon City', 'Filipino', 'Islam', 'Blk 42 Lot 12 Bougainvillea Drive Sta. Monica Hills', 'Quezon City', 'NCR / Metro Manila', '1421', 'kevin.beltran@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(405, 417, '000000000398', 'Paula', 'Cruz', 'Duran', 'female', '2009-01-14', 'City of Caloocan', 'Filipino', 'Born Again', 'Blk 13 Lot 25 Calachuchi Lane Heritage Park Subdivision', 'City of Caloocan', 'None', '1410', 'paula.duran@gmail.com', 'transferee', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(406, 418, '000000000399', 'Ryan', 'Padilla', 'Tan', 'male', '2010-08-08', 'Quezon City', 'Filipino', 'Catholic', 'Blk 25 Lot 24 Waling-Waling Street Masinag Heights', 'Quezon City', 'None', '1447', 'ryan.tan@gmail.com', 'transferee', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(407, 419, '000000000400', 'William', 'Santos', 'Andres', 'male', '2009-04-17', 'Valenzuela City', 'Filipino', 'Catholic', 'Blk 34 Lot 25 Jasmine Lane Bagumbong Residences', 'Valenzuela City', 'None', '1440', 'william.andres@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(408, 420, '000000000401', 'Melissa', NULL, 'De Villa', 'female', '2010-08-06', 'Quezon City', 'Filipino', 'Catholic', 'Blk 10 Lot 15 Zinnia Street Heritage Park Subdivision', 'Quezon City', 'None', '1422', 'melissa.devilla@gmail.com', 'transferee', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(409, 421, '000000000402', 'James', 'Villanueva', 'Robles', 'male', '2011-09-05', 'Quezon City', 'Filipino', 'Christian', 'Blk 30 Lot 19 Calachuchi Lane Golden Villa Subdivision', 'Quezon City', 'None', '1405', 'james.robles@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(410, 422, '000000000403', 'Leo', NULL, 'Cayabyab', 'male', '2011-03-23', 'City of Caloocan', 'Filipino', NULL, 'Blk 24 Lot 3 Marigold Avenue Harmony Village', 'City of Caloocan', 'NCR / Metro Manila', '1401', 'leo.cayabyab@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(411, 423, '000000000404', 'Philip', 'Reyes', 'Flores', 'male', '2009-06-19', 'Malabon City', 'Filipino', 'Born Again', 'Blk 4 Lot 14 Lotus Street Panorama Heights', 'Malabon City', 'NCR / Metro Manila', '1402', 'philip.flores@gmail.com', 'transferee', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(412, 424, '000000000405', 'Jane', 'Villanueva', 'Macapagal', 'female', '2009-04-01', 'Valenzuela City', 'Filipino', 'Christian', 'Blk 32 Lot 18 Sampaguita Street Camarin North Subdivision', 'Valenzuela City', 'None', '1400', 'jane.macapagal@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(413, 425, '000000000406', 'Grace', 'Iglesias', 'Bautista', 'female', '2010-07-15', 'City of Caloocan', 'Filipino', 'Islam', 'Blk 41 Lot 18 Calachuchi Lane Crystal Valley Subdivision', 'City of Caloocan', 'NCR / Metro Manila', '1403', 'grace.bautista@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(414, 426, '000000000407', 'Gerald', NULL, 'Alejo', 'male', '2009-03-28', 'City of Caloocan', 'Filipino', 'Catholic', 'Blk 27 Lot 6 Bougainvillea Drive Novaliches Proper', 'City of Caloocan', 'None', '1405', 'gerald.alejo426@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(415, 427, '000000000408', 'Vanessa', 'Gonzalez', 'Salas', 'female', '2011-10-12', 'City of Caloocan', 'Filipino', 'Iglesia ni Cristo', 'Blk 25 Lot 27 Gumamela Road Greenfield Residences', 'City of Caloocan', 'NCR / Metro Manila', '1447', 'vanessa.salas@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(416, 428, '000000000409', 'Stella', 'Bernardo', 'Alfonso', 'female', '2009-12-28', 'Navotas City', 'Filipino', 'Christian', 'Blk 45 Lot 7 Jasmine Lane Heritage Park Subdivision', 'Navotas City', 'None', '1421', 'stella.alfonso@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(417, 429, '000000000410', 'Thomas', NULL, 'Padilla', 'male', '2011-05-14', 'Valenzuela City', 'Filipino', 'Islam', 'Blk 40 Lot 12 Rosal Avenue Camarin North Subdivision', 'Valenzuela City', 'None', '1404', 'thomas.padilla@gmail.com', 'new', 10, 'enrolled', '2026-05-25 00:00:00', '2026-05-24 23:00:00', '2026-05-25 00:00:00', 0),
(418, 472, '000000008125', 'Aki', NULL, 'Rosenthal', 'female', '2008-01-05', 'Caloocan City', 'Filipino', 'Catholic', 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '2566', 'c.olumbin.a234@gmail.com', 'new', 7, 'enrolled', '2026-05-30 05:17:27', '2026-05-25 16:36:03', '2026-05-30 05:17:27', 0),
(419, 473, '000000000435', 'Saikken', 'Miyatono', 'Sakami', 'male', '2001-07-04', 'Caloocan City', 'Chinese', 'Catholic', 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '2566', 'phillippe.joshua27.9@gmail.com', 'new', 8, 'enrolled', '2026-05-29 12:08:13', '2026-05-28 18:40:52', '2026-05-29 12:08:13', 0),
(421, 475, '000000002348', 'Keith', 'Samantha', 'Canilang', 'female', '2001-12-01', 'Caloocan City', 'Filipino', 'Catholic', 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '2566', 'colu.mbina2.34@gmail.com', 'new', 8, 'enrolled', '2026-05-31 10:25:26', '2026-05-31 09:59:23', '2026-05-31 10:25:26', 0),
(423, 477, '000000234574', 'QueerBalasin', NULL, 'Saichou', 'male', '2011-11-05', 'Caloocan City', 'Filipino', 'Catholic', 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '2566', 'ph.illippejoshua27.9@gmail.com', 'new', 7, 'enrolled', '2026-05-31 20:38:02', '2026-05-31 20:06:08', '2026-05-31 20:38:02', 0),
(424, 478, '000006745674', 'Quarbloy', NULL, 'Quarbloy', 'male', '2012-12-02', 'Las Piñas City', 'Filipino', 'Catholic', 'Blk 30 Lot 15 Shamrock Street Castlespring Heights Subdivision', 'City of Caloocan', 'None', '2566', 'phillippejoshu.a27.9@gmail.com', 'new', 8, 'enrolled', '2026-06-01 00:04:08', '2026-05-31 23:54:50', '2026-06-01 00:04:08', 0);

-- --------------------------------------------------------

--
-- Table structure for table `student_grades`
--

CREATE TABLE `student_grades` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL COMMENT 'FK → students.id',
  `ssy_id` int(11) NOT NULL COMMENT 'FK → section_school_years.id',
  `subject_id` int(11) NOT NULL COMMENT 'FK → subjects.id',
  `grade_q1` decimal(5,2) DEFAULT NULL COMMENT '1st Term grade',
  `grade_q2` decimal(5,2) DEFAULT NULL COMMENT '2nd Term grade',
  `grade_q3` decimal(5,2) DEFAULT NULL COMMENT '3rd Term grade',
  `status` enum('encoded','submitted','approved','revision_requested','approved_by_principal','revision_by_principal','approved_by_head','published_by_registrar') NOT NULL DEFAULT 'encoded',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Stores per-term grades for each student per class assignment';

--
-- Dumping data for table `student_grades`
--

INSERT INTO `student_grades` (`id`, `student_id`, `ssy_id`, `subject_id`, `grade_q1`, `grade_q2`, `grade_q3`, `status`, `created_at`, `updated_at`) VALUES
(1, 87, 5, 5, 95.00, NULL, NULL, 'approved_by_head', '2026-05-25 13:55:13', '2026-05-31 21:08:33'),
(3, 47, 5, 5, 95.00, NULL, NULL, 'approved_by_head', '2026-05-25 13:56:42', '2026-05-31 21:08:33'),
(4, 52, 5, 5, 95.00, NULL, NULL, 'approved_by_head', '2026-05-25 13:56:42', '2026-05-31 21:08:33'),
(5, 27, 5, 5, 95.00, NULL, NULL, 'approved_by_head', '2026-05-25 13:56:42', '2026-05-31 21:08:33'),
(6, 112, 5, 5, 95.00, NULL, NULL, 'approved_by_head', '2026-05-25 13:56:42', '2026-05-31 21:08:33'),
(7, 32, 5, 5, 95.00, NULL, NULL, 'approved_by_head', '2026-05-25 13:56:42', '2026-05-31 21:08:33'),
(8, 92, 5, 5, 95.00, NULL, NULL, 'approved_by_head', '2026-05-25 13:56:42', '2026-05-31 21:08:33'),
(9, 67, 5, 5, 95.00, NULL, NULL, 'approved_by_head', '2026-05-25 13:56:42', '2026-05-31 21:08:33'),
(10, 77, 5, 5, 95.00, NULL, NULL, 'approved_by_head', '2026-05-25 13:56:42', '2026-05-31 21:08:33'),
(11, 22, 5, 5, 95.00, NULL, NULL, 'approved_by_head', '2026-05-25 13:56:42', '2026-05-31 21:08:33'),
(12, 117, 5, 5, 95.00, NULL, NULL, 'submitted', '2026-05-25 13:56:42', '2026-05-31 21:07:33'),
(13, 42, 5, 5, 95.00, NULL, NULL, 'submitted', '2026-05-25 13:56:42', '2026-05-31 21:07:33'),
(14, 57, 5, 5, 95.00, NULL, NULL, 'submitted', '2026-05-25 13:56:42', '2026-05-31 21:07:33'),
(15, 62, 5, 5, 95.00, NULL, NULL, 'submitted', '2026-05-25 13:56:42', '2026-05-31 21:07:33'),
(16, 37, 5, 5, 95.00, NULL, NULL, 'submitted', '2026-05-25 13:56:42', '2026-05-31 21:07:33'),
(17, 82, 5, 5, 95.00, NULL, NULL, 'submitted', '2026-05-25 13:56:42', '2026-05-31 21:07:33'),
(18, 97, 5, 5, 95.00, NULL, NULL, 'approved_by_head', '2026-05-25 13:56:42', '2026-05-31 21:08:33'),
(19, 102, 5, 5, 95.00, NULL, NULL, 'submitted', '2026-05-25 13:56:42', '2026-05-31 21:07:33'),
(20, 107, 5, 5, 95.00, NULL, NULL, 'submitted', '2026-05-25 13:56:42', '2026-05-31 21:07:33'),
(21, 72, 5, 5, 95.00, NULL, NULL, 'submitted', '2026-05-25 13:56:42', '2026-05-31 21:07:33'),
(62, 99, 2, 5, 65.00, NULL, NULL, 'revision_by_principal', '2026-05-25 14:02:49', '2026-05-25 17:45:44'),
(63, 79, 2, 5, 85.00, NULL, NULL, 'revision_by_principal', '2026-05-25 14:02:49', '2026-05-25 17:45:44'),
(64, 24, 2, 5, 77.00, NULL, NULL, 'revision_by_principal', '2026-05-25 14:02:49', '2026-05-25 17:45:44'),
(65, 59, 2, 5, 77.00, NULL, NULL, 'revision_by_principal', '2026-05-25 14:02:49', '2026-05-25 17:45:44'),
(66, 69, 2, 5, 77.00, NULL, NULL, 'revision_by_principal', '2026-05-25 14:02:49', '2026-05-25 17:45:44'),
(67, 44, 2, 5, 77.00, NULL, NULL, 'revision_by_principal', '2026-05-25 14:02:49', '2026-05-25 17:45:44'),
(68, 39, 2, 5, 77.00, NULL, NULL, 'revision_by_principal', '2026-05-25 14:02:49', '2026-05-25 17:45:44'),
(69, 109, 2, 5, 77.00, NULL, NULL, 'revision_by_principal', '2026-05-25 14:02:49', '2026-05-25 17:45:44'),
(70, 114, 2, 5, 77.00, NULL, NULL, 'revision_by_principal', '2026-05-25 14:02:49', '2026-05-25 17:45:44'),
(71, 104, 2, 5, 77.00, NULL, NULL, 'revision_by_principal', '2026-05-25 14:02:49', '2026-05-25 17:45:44'),
(72, 64, 2, 5, 77.00, NULL, NULL, 'revision_by_principal', '2026-05-25 14:02:49', '2026-05-25 17:45:44'),
(73, 49, 2, 5, 77.00, NULL, NULL, 'revision_by_principal', '2026-05-25 14:02:49', '2026-05-25 17:45:44'),
(74, 74, 2, 5, 77.00, NULL, NULL, 'revision_by_principal', '2026-05-25 14:02:49', '2026-05-25 17:45:44'),
(75, 89, 2, 5, 88.00, NULL, NULL, 'revision_by_principal', '2026-05-25 14:02:49', '2026-05-25 17:45:44'),
(76, 19, 2, 5, 95.00, NULL, NULL, 'revision_by_principal', '2026-05-25 14:02:49', '2026-05-25 17:45:44'),
(77, 29, 2, 5, 85.00, NULL, NULL, 'revision_by_principal', '2026-05-25 14:02:49', '2026-05-25 17:45:44'),
(78, 54, 2, 5, 85.00, NULL, NULL, 'revision_by_principal', '2026-05-25 14:02:49', '2026-05-25 17:45:44'),
(79, 34, 2, 5, 85.00, NULL, NULL, 'revision_by_principal', '2026-05-25 14:02:49', '2026-05-25 17:45:44'),
(80, 94, 2, 5, 85.00, NULL, NULL, 'revision_by_principal', '2026-05-25 14:02:49', '2026-05-25 17:45:44'),
(81, 84, 2, 5, 85.00, NULL, NULL, 'revision_by_principal', '2026-05-25 14:02:49', '2026-05-25 17:45:44'),
(102, 45, 1, 5, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-25 18:33:34', '2026-05-29 13:34:48'),
(103, 87, 1, 5, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-25 18:33:34', '2026-05-29 13:34:54'),
(104, 418, 1, 5, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-25 18:33:34', '2026-05-25 20:52:18'),
(126, 207, 8, 13, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-31 09:12:16', '2026-05-31 11:34:18'),
(127, 130, 8, 13, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-31 09:12:16', '2026-05-31 11:34:24'),
(128, 152, 8, 13, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-31 09:12:16', '2026-05-31 11:34:33'),
(129, 138, 8, 13, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-31 09:12:16', '2026-05-31 11:34:37'),
(130, 203, 8, 13, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-31 09:12:16', '2026-05-31 11:34:44'),
(131, 146, 8, 13, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-31 09:12:16', '2026-05-31 11:34:50'),
(132, 186, 8, 13, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-31 09:12:16', '2026-05-31 11:34:54'),
(133, 178, 8, 13, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-31 09:12:16', '2026-05-31 11:34:59'),
(134, 187, 8, 13, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-31 09:12:16', '2026-05-31 11:35:13'),
(135, 153, 8, 13, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-31 09:12:16', '2026-05-31 11:35:18'),
(136, 174, 8, 13, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-31 09:12:16', '2026-05-31 11:35:22'),
(137, 196, 8, 13, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-31 09:12:16', '2026-05-31 11:35:28'),
(138, 179, 8, 13, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-31 09:12:16', '2026-05-31 11:35:33'),
(139, 169, 8, 13, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-31 09:12:16', '2026-05-31 11:35:37'),
(140, 198, 8, 13, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-31 09:12:16', '2026-05-31 11:35:41'),
(141, 181, 8, 13, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-31 09:12:16', '2026-05-31 11:35:45'),
(142, 159, 8, 13, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-31 09:12:16', '2026-05-31 11:35:51'),
(143, 191, 8, 13, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-31 09:12:16', '2026-05-31 11:35:56'),
(144, 419, 8, 13, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-31 09:12:16', '2026-05-31 10:38:06'),
(183, 48, 5, 5, 85.00, NULL, NULL, 'approved_by_head', '2026-05-31 20:49:00', '2026-05-31 21:08:33'),
(184, 60, 5, 5, 65.00, NULL, NULL, 'approved_by_head', '2026-05-31 20:49:00', '2026-05-31 21:08:33'),
(185, 423, 5, 5, 95.00, NULL, NULL, 'published_by_registrar', '2026-05-31 20:49:00', '2026-05-31 21:09:54'),
(186, 75, 5, 5, 67.00, NULL, NULL, 'approved_by_head', '2026-05-31 20:49:00', '2026-05-31 21:08:33'),
(187, 94, 5, 5, 88.00, NULL, NULL, 'approved_by_head', '2026-05-31 20:49:00', '2026-05-31 21:08:33'),
(188, 84, 5, 5, 95.00, NULL, NULL, 'approved_by_head', '2026-05-31 20:49:00', '2026-05-31 21:08:33'),
(190, 40, 5, 5, 75.00, NULL, NULL, 'approved_by_head', '2026-05-31 20:49:11', '2026-05-31 21:08:33'),
(221, 424, 8, 13, 95.00, NULL, NULL, 'published_by_registrar', '2026-06-01 00:05:56', '2026-06-01 00:09:08');

-- --------------------------------------------------------

--
-- Table structure for table `student_guardians`
--

CREATE TABLE `student_guardians` (
  `id` int(11) NOT NULL COMMENT 'PK',
  `student_id` int(11) NOT NULL COMMENT 'FK → students.id',
  `guardian_id` int(11) NOT NULL COMMENT 'FK → guardians.id',
  `relationship_label` varchar(100) DEFAULT NULL COMMENT 'e.g. Mother, Father, Uncle',
  `custody_type` enum('sole_custody','joint_custody','split_custody','restricted_custody','none') NOT NULL DEFAULT 'none',
  `is_primary` tinyint(1) NOT NULL DEFAULT 0 COMMENT '1 = primary guardian',
  `emergency_priority` tinyint(3) NOT NULL DEFAULT 99 COMMENT '1 = first to call in emergency',
  `pickup_authorized` tinyint(1) NOT NULL DEFAULT 0 COMMENT '1 = authorized to pick up student',
  `permissions` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL COMMENT 'e.g. {"view_grades":true,"view_disciplinary":false,...}' CHECK (json_valid(`permissions`)),
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `effective_date` date DEFAULT NULL COMMENT 'Date custody/relationship became effective',
  `expiry_date` date DEFAULT NULL COMMENT 'Court order expiry, etc.',
  `notes` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Student ↔ Guardian junction with custody, permissions & priority';

--
-- Dumping data for table `student_guardians`
--

INSERT INTO `student_guardians` (`id`, `student_id`, `guardian_id`, `relationship_label`, `custody_type`, `is_primary`, `emergency_priority`, `pickup_authorized`, `permissions`, `is_active`, `effective_date`, `expiry_date`, `notes`, `created_at`, `updated_at`) VALUES
(2, 7, 2, 'Father', 'none', 0, 1, 0, NULL, 1, NULL, NULL, NULL, '2026-05-17 15:39:22', '2026-05-17 15:39:22'),
(3, 7, 3, 'Mother', 'none', 0, 2, 0, NULL, 1, NULL, NULL, NULL, '2026-05-17 15:39:22', '2026-05-17 15:39:22'),
(5, 9, 5, 'Mother', 'none', 0, 1, 0, NULL, 1, NULL, NULL, NULL, '2026-05-18 18:54:33', '2026-05-18 18:54:33'),
(6, 9, 6, 'Father', 'none', 0, 2, 0, NULL, 1, NULL, NULL, NULL, '2026-05-18 18:54:33', '2026-05-18 18:54:33'),
(7, 10, 7, 'Mother', 'none', 0, 1, 0, NULL, 1, NULL, NULL, NULL, '2026-05-18 19:04:41', '2026-05-18 19:04:41'),
(8, 14, 8, 'Father', 'none', 0, 1, 0, NULL, 1, NULL, NULL, NULL, '2026-05-20 18:10:49', '2026-05-20 18:10:49'),
(9, 14, 9, 'Mother', 'none', 0, 2, 0, NULL, 1, NULL, NULL, NULL, '2026-05-20 18:10:49', '2026-05-20 18:10:49'),
(10, 15, 10, 'Father', 'none', 0, 1, 0, NULL, 1, NULL, NULL, NULL, '2026-05-22 11:19:04', '2026-05-22 11:19:04'),
(11, 16, 11, 'Mother', 'none', 0, 1, 0, NULL, 1, NULL, NULL, NULL, '2026-05-22 12:49:10', '2026-05-22 12:49:10'),
(12, 17, 12, 'Father', 'none', 0, 1, 0, NULL, 1, NULL, NULL, NULL, '2026-05-24 07:50:04', '2026-05-24 07:50:04'),
(13, 418, 13, 'Mother', 'none', 0, 1, 0, NULL, 1, NULL, NULL, NULL, '2026-05-25 16:36:25', '2026-05-25 16:36:25'),
(14, 419, 14, 'Mother', 'none', 0, 1, 0, NULL, 1, NULL, NULL, NULL, '2026-05-28 18:57:53', '2026-05-28 18:57:53'),
(15, 419, 15, 'Father', 'none', 0, 2, 0, NULL, 1, NULL, NULL, NULL, '2026-05-28 18:57:53', '2026-05-28 18:57:53'),
(16, 419, 16, 'Legal Guardian', 'none', 0, 3, 0, NULL, 1, NULL, NULL, NULL, '2026-05-28 18:57:53', '2026-05-28 18:57:53'),
(18, 421, 18, 'Father', 'none', 0, 1, 0, NULL, 1, NULL, NULL, NULL, '2026-05-31 09:59:53', '2026-05-31 09:59:53'),
(20, 423, 20, 'Father', 'none', 0, 1, 0, NULL, 1, NULL, NULL, NULL, '2026-05-31 20:06:30', '2026-05-31 20:06:30'),
(21, 424, 21, 'Father', 'none', 0, 1, 0, NULL, 1, NULL, NULL, NULL, '2026-05-31 23:55:24', '2026-05-31 23:55:24');

-- --------------------------------------------------------

--
-- Table structure for table `student_profiles`
--

CREATE TABLE `student_profiles` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL COMMENT 'FK → students.id (1-to-1)',
  `verified_at` datetime DEFAULT NULL COMMENT 'Timestamp of successful OTP verification',
  `verified_by_ip` varchar(45) DEFAULT NULL,
  `school_year_id` int(11) DEFAULT NULL COMMENT 'FK → school_years.id',
  `section_sy_id` int(11) DEFAULT NULL COMMENT 'FK → section_school_years.id',
  `previous_school` varchar(255) DEFAULT NULL,
  `previous_school_address` varchar(500) DEFAULT NULL,
  `previous_sy` varchar(20) DEFAULT NULL COMMENT 'e.g. 2024-2025',
  `notes` text DEFAULT NULL COMMENT 'Registrar notes',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Extended profile & enrollment assignment for each student';

--
-- Dumping data for table `student_profiles`
--

INSERT INTO `student_profiles` (`id`, `student_id`, `verified_at`, `verified_by_ip`, `school_year_id`, `section_sy_id`, `previous_school`, `previous_school_address`, `previous_sy`, `notes`, `created_at`, `updated_at`) VALUES
(7, 7, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-17 15:38:15', '2026-05-17 15:38:15'),
(9, 9, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-18 18:53:52', '2026-05-18 18:53:52'),
(10, 10, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-18 19:04:10', '2026-05-18 19:04:10'),
(11, 11, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-19 15:13:08', '2026-05-19 15:13:08'),
(12, 12, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-19 16:01:12', '2026-05-19 16:01:12'),
(13, 13, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-19 16:11:44', '2026-05-19 16:11:44'),
(14, 14, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-20 18:07:03', '2026-05-20 18:07:03'),
(15, 15, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-22 11:18:39', '2026-05-22 11:18:39'),
(16, 16, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-22 12:48:25', '2026-05-22 12:48:25'),
(17, 17, NULL, NULL, 1, 17, NULL, NULL, NULL, NULL, '2026-05-24 07:48:42', '2026-05-31 15:18:20'),
(18, 45, NULL, NULL, 1, 1, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-25 18:32:29'),
(19, 87, NULL, NULL, 1, 1, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-25 18:32:29'),
(20, 73, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-31 20:28:10'),
(21, 47, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-31 20:28:10'),
(22, 36, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-31 20:28:10'),
(23, 105, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-31 20:28:10'),
(24, 71, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-31 20:28:10'),
(25, 21, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-31 20:28:10'),
(26, 80, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-31 20:28:10'),
(27, 95, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-31 20:28:10'),
(28, 96, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-31 20:28:10'),
(29, 99, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-31 20:28:10'),
(30, 53, NULL, NULL, 1, 3, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-31 15:15:57'),
(31, 52, NULL, NULL, 1, 2, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-31 15:16:06'),
(32, 23, NULL, NULL, 1, 2, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-31 15:16:06'),
(33, 61, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-25 18:30:59'),
(34, 27, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-25 18:30:59'),
(35, 101, NULL, NULL, 1, 3, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-31 15:15:57'),
(36, 46, NULL, NULL, 1, 3, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-31 15:15:57'),
(37, 112, NULL, NULL, 1, 3, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-31 15:15:57'),
(38, 32, NULL, NULL, 1, 3, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-31 15:15:57'),
(39, 79, NULL, NULL, 1, 3, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-31 15:15:57'),
(40, 24, NULL, NULL, 1, 3, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-31 15:15:57'),
(41, 20, NULL, NULL, 1, 3, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-31 15:15:57'),
(42, 59, NULL, NULL, 1, 3, NULL, NULL, NULL, NULL, '2026-05-24 16:59:06', '2026-05-31 15:15:57'),
(43, 111, NULL, NULL, 1, 3, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:15:57'),
(44, 31, NULL, NULL, 1, 3, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:15:57'),
(45, 68, NULL, NULL, 1, 3, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:15:57'),
(46, 69, NULL, NULL, 1, 3, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:15:57'),
(47, 90, NULL, NULL, 1, 3, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:15:57'),
(48, 33, NULL, NULL, 1, 3, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:15:57'),
(49, 66, NULL, NULL, 1, 3, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:15:57'),
(50, 55, NULL, NULL, 1, 3, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:15:57'),
(51, 44, NULL, NULL, 1, 3, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:15:57'),
(52, 35, NULL, NULL, 1, 3, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:15:57'),
(53, 39, NULL, NULL, 1, 3, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:15:57'),
(54, 92, NULL, NULL, 1, 3, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:15:57'),
(55, 67, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-25 18:17:17'),
(56, 78, NULL, NULL, 1, 2, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:16:06'),
(57, 77, NULL, NULL, 1, 2, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:16:06'),
(58, 109, NULL, NULL, 1, 2, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:16:06'),
(59, 43, NULL, NULL, 1, 2, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:16:06'),
(60, 108, NULL, NULL, 1, 1, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:16:22'),
(61, 106, NULL, NULL, 1, 1, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:16:22'),
(62, 26, NULL, NULL, 1, 2, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:16:06'),
(63, 22, NULL, NULL, 1, 2, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:16:06'),
(64, 114, NULL, NULL, 1, 2, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:16:06'),
(65, 104, NULL, NULL, 1, 2, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:16:06'),
(66, 64, NULL, NULL, 1, 2, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:16:06'),
(67, 25, NULL, NULL, 1, 2, NULL, NULL, NULL, NULL, '2026-05-24 16:59:16', '2026-05-31 15:16:06'),
(68, 38, NULL, NULL, 1, 2, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:06'),
(69, 56, NULL, NULL, 1, 2, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:06'),
(70, 117, NULL, NULL, 1, 2, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:06'),
(71, 70, NULL, NULL, 1, 2, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:06'),
(72, 50, NULL, NULL, 1, 2, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:06'),
(73, 110, NULL, NULL, 1, 2, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:06'),
(74, 63, NULL, NULL, 1, 2, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:06'),
(75, 93, NULL, NULL, 1, 2, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:06'),
(76, 115, NULL, NULL, 1, 1, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:22'),
(77, 28, NULL, NULL, 1, 1, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:22'),
(78, 42, NULL, NULL, 1, 1, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:22'),
(79, 57, NULL, NULL, 1, 1, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:22'),
(80, 81, NULL, NULL, 1, 1, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:22'),
(81, 83, NULL, NULL, 1, 1, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:22'),
(82, 76, NULL, NULL, 1, 1, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:22'),
(83, 113, NULL, NULL, 1, 1, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:22'),
(84, 62, NULL, NULL, 1, 1, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:22'),
(85, 37, NULL, NULL, 1, 1, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:22'),
(86, 82, NULL, NULL, 1, 1, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:22'),
(87, 88, NULL, NULL, 1, 1, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:22'),
(88, 49, NULL, NULL, 1, 1, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:22'),
(89, 85, NULL, NULL, 1, 1, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:22'),
(90, 41, NULL, NULL, 1, 1, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:22'),
(91, 86, NULL, NULL, 1, 1, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:22'),
(92, 74, NULL, NULL, 1, 1, NULL, NULL, NULL, NULL, '2026-05-24 16:59:23', '2026-05-31 15:16:22'),
(93, 97, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-24 17:02:45'),
(94, 30, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-24 17:02:45'),
(95, 89, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-24 17:02:45'),
(96, 19, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-24 17:02:45'),
(97, 102, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-31 20:37:20'),
(98, 48, NULL, NULL, 1, 5, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-31 20:31:30'),
(99, 29, NULL, NULL, 1, 4, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-31 15:16:33'),
(100, 18, NULL, NULL, 1, 4, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-31 15:16:33'),
(101, 54, NULL, NULL, 1, 4, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-31 15:16:33'),
(102, 40, NULL, NULL, 1, 5, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-31 20:31:30'),
(103, 60, NULL, NULL, 1, 5, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-31 20:31:30'),
(104, 91, NULL, NULL, 1, 4, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-31 15:16:33'),
(105, 51, NULL, NULL, 1, 4, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-31 15:16:33'),
(106, 100, NULL, NULL, 1, 4, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-31 15:16:33'),
(107, 107, NULL, NULL, 1, 4, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-31 15:16:33'),
(108, 65, NULL, NULL, 1, 4, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-31 15:16:33'),
(109, 103, NULL, NULL, 1, 4, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-31 15:16:33'),
(110, 98, NULL, NULL, 1, 4, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-31 15:16:33'),
(111, 58, NULL, NULL, 1, 4, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-31 15:16:33'),
(112, 34, NULL, NULL, 1, 4, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-31 15:16:33'),
(113, 72, NULL, NULL, 1, 4, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-31 15:16:33'),
(114, 116, NULL, NULL, 1, 4, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-31 15:16:33'),
(115, 75, NULL, NULL, 1, 5, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-31 20:31:30'),
(116, 94, NULL, NULL, 1, 5, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-31 20:31:30'),
(117, 84, NULL, NULL, 1, 5, NULL, NULL, NULL, NULL, '2026-05-24 16:59:29', '2026-05-31 20:31:30'),
(118, 207, NULL, NULL, 1, 8, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 08:49:53'),
(119, 130, NULL, NULL, 1, 8, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 08:49:53'),
(120, 152, NULL, NULL, 1, 8, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 08:49:53'),
(121, 138, NULL, NULL, 1, 8, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 08:49:53'),
(122, 203, NULL, NULL, 1, 8, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 08:49:53'),
(123, 146, NULL, NULL, 1, 8, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 08:49:53'),
(124, 186, NULL, NULL, 1, 8, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 08:49:53'),
(125, 178, NULL, NULL, 1, 8, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 08:49:53'),
(126, 187, NULL, NULL, 1, 8, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 08:49:53'),
(127, 120, NULL, NULL, 1, 6, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 15:17:01'),
(128, 171, NULL, NULL, 1, 6, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 15:17:01'),
(129, 176, NULL, NULL, 1, 6, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 15:17:01'),
(130, 153, NULL, NULL, 1, 8, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 08:49:53'),
(131, 174, NULL, NULL, 1, 8, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 08:49:53'),
(132, 196, NULL, NULL, 1, 8, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 08:49:53'),
(133, 179, NULL, NULL, 1, 8, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 08:49:53'),
(134, 169, NULL, NULL, 1, 8, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 08:49:53'),
(135, 198, NULL, NULL, 1, 8, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 08:49:53'),
(136, 181, NULL, NULL, 1, 8, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 08:49:53'),
(137, 159, NULL, NULL, 1, 8, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 08:49:53'),
(138, 191, NULL, NULL, 1, 8, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 08:49:53'),
(139, 140, NULL, NULL, 1, 6, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 15:17:01'),
(140, 215, NULL, NULL, 1, 6, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 15:17:01'),
(141, 162, NULL, NULL, 1, 9, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 15:16:45'),
(142, 175, NULL, NULL, 1, 9, NULL, NULL, NULL, NULL, '2026-05-24 16:59:38', '2026-05-31 15:16:45'),
(143, 180, NULL, NULL, 1, 9, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:45'),
(144, 184, NULL, NULL, 1, 9, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:45'),
(145, 145, NULL, NULL, 1, 9, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:45'),
(146, 183, NULL, NULL, 1, 9, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:45'),
(147, 172, NULL, NULL, 1, 9, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:45'),
(148, 156, NULL, NULL, 1, 9, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:45'),
(149, 197, NULL, NULL, 1, 9, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:45'),
(150, 212, NULL, NULL, 1, 9, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:45'),
(151, 199, NULL, NULL, 1, 9, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:45'),
(152, 206, NULL, NULL, 1, 9, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:45'),
(153, 148, NULL, NULL, 1, 9, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:45'),
(154, 142, NULL, NULL, 1, 9, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:45'),
(155, 122, NULL, NULL, 1, 9, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:45'),
(156, 131, NULL, NULL, 1, 9, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:45'),
(157, 190, NULL, NULL, 1, 9, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:45'),
(158, 118, NULL, NULL, 1, 9, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:45'),
(159, 134, NULL, NULL, 1, 9, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:45'),
(160, 173, NULL, NULL, 1, 7, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:53'),
(161, 136, NULL, NULL, 1, 7, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:53'),
(162, 135, NULL, NULL, 1, 7, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:53'),
(163, 129, NULL, NULL, 1, 7, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:53'),
(164, 137, NULL, NULL, 1, 7, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:53'),
(165, 149, NULL, NULL, 1, 7, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:53'),
(166, 170, NULL, NULL, 1, 7, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:53'),
(167, 205, NULL, NULL, 1, 7, NULL, NULL, NULL, NULL, '2026-05-24 16:59:43', '2026-05-31 15:16:53'),
(168, 200, NULL, NULL, 1, 7, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-31 15:16:53'),
(169, 147, NULL, NULL, 1, 7, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-31 15:16:53'),
(170, 151, NULL, NULL, 1, 7, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-31 15:16:53'),
(171, 188, NULL, NULL, 1, 7, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-31 15:16:53'),
(172, 119, NULL, NULL, 1, 7, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-31 15:16:53'),
(173, 211, NULL, NULL, 1, 7, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-31 15:16:53'),
(174, 193, NULL, NULL, 1, 7, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-31 15:16:53'),
(175, 177, NULL, NULL, 1, 7, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-31 15:16:53'),
(176, 144, NULL, NULL, 1, 7, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-31 15:16:53'),
(177, 150, NULL, NULL, 1, 7, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-31 15:16:53'),
(178, 139, NULL, NULL, 1, 7, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-31 15:16:53'),
(179, 158, NULL, NULL, 1, 7, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-31 15:16:53'),
(180, 154, NULL, NULL, 1, 6, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-31 15:17:01'),
(181, 165, NULL, NULL, 1, 6, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-31 15:17:01'),
(182, 217, NULL, NULL, 1, 6, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-31 15:17:01'),
(183, 160, NULL, NULL, 1, 6, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-31 15:17:01'),
(184, 209, NULL, NULL, 1, 6, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-31 15:17:01'),
(185, 157, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-24 17:45:29'),
(186, 166, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-24 17:45:29'),
(187, 210, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-24 17:45:29'),
(188, 121, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-24 17:45:29'),
(189, 194, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-24 17:45:29'),
(190, 202, NULL, NULL, 1, 6, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-31 15:17:01'),
(191, 133, NULL, NULL, 1, 6, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-31 15:17:01'),
(192, 208, NULL, NULL, 1, 6, NULL, NULL, NULL, NULL, '2026-05-24 16:59:47', '2026-05-31 15:17:01'),
(193, 163, NULL, NULL, 1, 6, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-31 15:17:01'),
(194, 168, NULL, NULL, 1, 6, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-31 15:17:01'),
(195, 201, NULL, NULL, 1, 6, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-31 15:17:01'),
(196, 124, NULL, NULL, 1, 6, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-31 15:17:01'),
(197, 195, NULL, NULL, 1, 6, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-31 15:17:01'),
(198, 141, NULL, NULL, 1, 6, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-31 15:17:01'),
(199, 213, NULL, NULL, 1, 6, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-31 15:17:01'),
(200, 182, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-24 17:01:35'),
(201, 214, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-24 17:01:35'),
(202, 185, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-24 17:01:35'),
(203, 125, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-24 17:45:32'),
(204, 189, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-24 17:45:32'),
(205, 128, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-24 17:45:32'),
(206, 132, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-24 17:45:32'),
(207, 216, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-24 17:45:32'),
(208, 143, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-24 17:45:32'),
(209, 155, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-24 17:45:32'),
(210, 123, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-24 17:45:32'),
(211, 127, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-24 17:45:32'),
(212, 164, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-24 17:45:32'),
(213, 167, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-24 17:45:32'),
(214, 161, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-24 17:45:32'),
(215, 126, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-24 17:45:32'),
(216, 192, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-24 17:45:32'),
(217, 204, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 16:59:52', '2026-05-24 17:45:32'),
(218, 224, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:22'),
(219, 262, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:22'),
(220, 274, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:22'),
(221, 300, NULL, NULL, 1, 13, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:08'),
(222, 312, NULL, NULL, 1, 13, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:08'),
(223, 237, NULL, NULL, 1, 13, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:08'),
(224, 231, NULL, NULL, 1, 13, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:08'),
(225, 282, NULL, NULL, 1, 13, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:08'),
(226, 285, NULL, NULL, 1, 13, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:08'),
(227, 280, NULL, NULL, 1, 13, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:08'),
(228, 268, NULL, NULL, 1, 13, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:08'),
(229, 269, NULL, NULL, 1, 13, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:08'),
(230, 255, NULL, NULL, 1, 13, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:08'),
(231, 247, NULL, NULL, 1, 13, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:08'),
(232, 271, NULL, NULL, 1, 13, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:08'),
(233, 245, NULL, NULL, 1, 13, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:08'),
(234, 272, NULL, NULL, 1, 13, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:08'),
(235, 290, NULL, NULL, 1, 13, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:08'),
(236, 315, NULL, NULL, 1, 13, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:08'),
(237, 230, NULL, NULL, 1, 13, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:08'),
(238, 281, NULL, NULL, 1, 13, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:08'),
(239, 244, NULL, NULL, 1, 13, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:08'),
(240, 276, NULL, NULL, 1, 13, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:08'),
(241, 243, NULL, NULL, 1, 13, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:08'),
(242, 218, NULL, NULL, 1, 13, NULL, NULL, NULL, NULL, '2026-05-24 17:00:03', '2026-05-31 15:17:08'),
(243, 308, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:22'),
(244, 227, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:22'),
(245, 294, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:22'),
(246, 228, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:22'),
(247, 253, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:22'),
(248, 270, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:22'),
(249, 301, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:22'),
(250, 314, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:22'),
(251, 250, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:22'),
(252, 233, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:22'),
(253, 287, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:22'),
(254, 234, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:22'),
(255, 238, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:22'),
(256, 229, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:22'),
(257, 267, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:22'),
(258, 284, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:22'),
(259, 223, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:22'),
(260, 289, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:22'),
(261, 236, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:22'),
(262, 222, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:22'),
(263, 259, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:22'),
(264, 288, NULL, NULL, 1, 11, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:22'),
(265, 232, NULL, NULL, 1, 12, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:32'),
(266, 292, NULL, NULL, 1, 12, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:32'),
(267, 264, NULL, NULL, 1, 12, NULL, NULL, NULL, NULL, '2026-05-24 17:00:08', '2026-05-31 15:17:32'),
(268, 248, NULL, NULL, 1, 12, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-31 15:17:32'),
(269, 295, NULL, NULL, 1, 12, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-31 15:17:32'),
(270, 313, NULL, NULL, 1, 12, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-31 15:17:32'),
(271, 297, NULL, NULL, 1, 12, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-31 15:17:32'),
(272, 302, NULL, NULL, 1, 12, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-31 15:17:32'),
(273, 307, NULL, NULL, 1, 12, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-31 15:17:32'),
(274, 279, NULL, NULL, 1, 10, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-31 15:17:45'),
(275, 260, NULL, NULL, 1, 10, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-31 15:17:45'),
(276, 309, NULL, NULL, 1, 10, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-31 15:17:45'),
(277, 219, NULL, NULL, 1, 10, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-31 15:17:45'),
(278, 283, NULL, NULL, 1, 10, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-31 15:17:45'),
(279, 306, NULL, NULL, 1, 10, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-31 15:17:45'),
(280, 317, NULL, NULL, 1, 10, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-31 15:17:45'),
(281, 241, NULL, NULL, 1, 10, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-31 15:17:45'),
(282, 273, NULL, NULL, 1, 10, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-31 15:17:45'),
(283, 277, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-25 18:17:46'),
(284, 303, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-25 18:17:46'),
(285, 258, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-25 18:17:46'),
(286, 220, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-25 18:17:46'),
(287, 261, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-25 18:17:46'),
(288, 257, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-25 18:17:46'),
(289, 304, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-25 18:17:46'),
(290, 311, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-24 17:45:57'),
(291, 242, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-24 17:45:57'),
(292, 263, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:13', '2026-05-24 17:45:57'),
(293, 278, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:01:58'),
(294, 316, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:01:58'),
(295, 299, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:01:58'),
(296, 265, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:01:58'),
(297, 291, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:01:58'),
(298, 252, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:01:58'),
(299, 221, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:01:58'),
(300, 293, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:01:58'),
(301, 235, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:01:58'),
(302, 239, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:46:01'),
(303, 298, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:46:01'),
(304, 254, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:46:01'),
(305, 296, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:46:01'),
(306, 225, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:46:01'),
(307, 305, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:46:01'),
(308, 246, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:46:01'),
(309, 240, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:46:01'),
(310, 286, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:46:01'),
(311, 226, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:46:01'),
(312, 249, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:46:01'),
(313, 275, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:46:01'),
(314, 251, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:46:01'),
(315, 256, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:46:01'),
(316, 266, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:46:01'),
(317, 310, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:18', '2026-05-24 17:46:01'),
(318, 318, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-25 18:18:02'),
(319, 330, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-25 18:18:02'),
(320, 335, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-25 18:18:05'),
(321, 414, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-25 18:18:02'),
(322, 370, NULL, NULL, 1, 14, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-31 15:18:04'),
(323, 397, NULL, NULL, 1, 15, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-31 15:17:53'),
(324, 390, NULL, NULL, 1, 15, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-31 15:17:53'),
(325, 344, NULL, NULL, 1, 15, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-31 15:17:53'),
(326, 333, NULL, NULL, 1, 15, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-31 15:17:53'),
(327, 383, NULL, NULL, 1, 15, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-31 15:17:53'),
(328, 416, NULL, NULL, 1, 15, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-31 15:17:53'),
(329, 388, NULL, NULL, 1, 15, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-31 15:17:53'),
(330, 363, NULL, NULL, 1, 15, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-31 15:17:53'),
(331, 407, NULL, NULL, 1, 15, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-31 15:17:53'),
(332, 325, NULL, NULL, 1, 15, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-31 15:17:53'),
(333, 336, NULL, NULL, 1, 15, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-31 15:17:53'),
(334, 348, NULL, NULL, 1, 15, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-31 15:17:53'),
(335, 372, NULL, NULL, 1, 15, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-31 15:17:53'),
(336, 323, NULL, NULL, 1, 15, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-31 15:17:53'),
(337, 369, NULL, NULL, 1, 15, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-31 15:17:53'),
(338, 413, NULL, NULL, 1, 15, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-31 15:17:53'),
(339, 371, NULL, NULL, 1, 15, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-31 15:17:53'),
(340, 364, NULL, NULL, 1, 15, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-31 15:17:53'),
(341, 404, NULL, NULL, 1, 15, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-31 15:17:53'),
(342, 400, NULL, NULL, 1, 15, NULL, NULL, NULL, NULL, '2026-05-24 17:00:25', '2026-05-31 15:17:53'),
(343, 366, NULL, NULL, 1, 14, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:04'),
(344, 346, NULL, NULL, 1, 14, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:04'),
(345, 358, NULL, NULL, 1, 14, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:04'),
(346, 332, NULL, NULL, 1, 14, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:04'),
(347, 360, NULL, NULL, 1, 14, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:04'),
(348, 410, NULL, NULL, 1, 16, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:14'),
(349, 380, NULL, NULL, 1, 16, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:14'),
(350, 393, NULL, NULL, 1, 16, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:14'),
(351, 351, NULL, NULL, 1, 16, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:14'),
(352, 376, NULL, NULL, 1, 16, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:14'),
(353, 394, NULL, NULL, 1, 14, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:04'),
(354, 339, NULL, NULL, 1, 14, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:04'),
(355, 354, NULL, NULL, 1, 14, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:04'),
(356, 359, NULL, NULL, 1, 14, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:04'),
(357, 356, NULL, NULL, 1, 14, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:04'),
(358, 355, NULL, NULL, 1, 14, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:04'),
(359, 353, NULL, NULL, 1, 14, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:04'),
(360, 337, NULL, NULL, 1, 14, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:04'),
(361, 408, NULL, NULL, 1, 14, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:04'),
(362, 343, NULL, NULL, 1, 14, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:04'),
(363, 350, NULL, NULL, 1, 16, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:14'),
(364, 401, NULL, NULL, 1, 17, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:20'),
(365, 391, NULL, NULL, 1, 17, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:20'),
(366, 368, NULL, NULL, 1, 17, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:20'),
(367, 319, NULL, NULL, 1, 17, NULL, NULL, NULL, NULL, '2026-05-24 17:00:30', '2026-05-31 15:18:20'),
(368, 365, NULL, NULL, 1, 17, NULL, NULL, NULL, NULL, '2026-05-24 17:00:40', '2026-05-31 15:18:20'),
(369, 345, NULL, NULL, 1, 17, NULL, NULL, NULL, NULL, '2026-05-24 17:00:40', '2026-05-31 15:18:20'),
(370, 382, NULL, NULL, 1, 16, NULL, NULL, NULL, NULL, '2026-05-24 17:00:40', '2026-05-31 15:18:14'),
(371, 373, NULL, NULL, 1, 16, NULL, NULL, NULL, NULL, '2026-05-24 17:00:40', '2026-05-31 15:18:14'),
(372, 334, NULL, NULL, 1, 16, NULL, NULL, NULL, NULL, '2026-05-24 17:00:40', '2026-05-31 15:18:14'),
(373, 338, NULL, NULL, 1, 16, NULL, NULL, NULL, NULL, '2026-05-24 17:00:40', '2026-05-31 15:18:14'),
(374, 374, NULL, NULL, 1, 16, NULL, NULL, NULL, NULL, '2026-05-24 17:00:40', '2026-05-31 15:18:14'),
(375, 405, NULL, NULL, 1, 16, NULL, NULL, NULL, NULL, '2026-05-24 17:00:40', '2026-05-31 15:18:14'),
(376, 396, NULL, NULL, 1, 16, NULL, NULL, NULL, NULL, '2026-05-24 17:00:40', '2026-05-31 15:18:14'),
(377, 398, NULL, NULL, 1, 16, NULL, NULL, NULL, NULL, '2026-05-24 17:00:40', '2026-05-31 15:18:14'),
(378, 329, NULL, NULL, 1, 16, NULL, NULL, NULL, NULL, '2026-05-24 17:00:40', '2026-05-31 15:18:14'),
(379, 387, NULL, NULL, 1, 17, NULL, NULL, NULL, NULL, '2026-05-24 17:00:40', '2026-05-31 15:18:20'),
(380, 367, NULL, NULL, 1, 17, NULL, NULL, NULL, NULL, '2026-05-24 17:00:40', '2026-05-31 15:18:20'),
(381, 328, NULL, NULL, 1, 17, NULL, NULL, NULL, NULL, '2026-05-24 17:00:40', '2026-05-31 15:18:20'),
(382, 347, NULL, NULL, 1, 17, NULL, NULL, NULL, NULL, '2026-05-24 17:00:40', '2026-05-31 15:18:20'),
(383, 411, NULL, NULL, 1, 17, NULL, NULL, NULL, NULL, '2026-05-24 17:00:40', '2026-05-31 15:18:20'),
(384, 342, NULL, NULL, 1, 17, NULL, NULL, NULL, NULL, '2026-05-24 17:00:40', '2026-05-31 15:18:20'),
(385, 361, NULL, NULL, 1, 17, NULL, NULL, NULL, NULL, '2026-05-24 17:00:40', '2026-05-31 15:18:20'),
(386, 331, NULL, NULL, 1, 17, NULL, NULL, NULL, NULL, '2026-05-24 17:00:40', '2026-05-31 15:18:20'),
(387, 341, NULL, NULL, 1, 17, NULL, NULL, NULL, NULL, '2026-05-24 17:00:40', '2026-05-31 15:18:20'),
(388, 322, NULL, NULL, 1, 17, NULL, NULL, NULL, NULL, '2026-05-24 17:00:53', '2026-05-31 15:18:20'),
(389, 381, NULL, NULL, 1, 17, NULL, NULL, NULL, NULL, '2026-05-24 17:00:53', '2026-05-31 15:18:20'),
(390, 349, NULL, NULL, 1, 17, NULL, NULL, NULL, NULL, '2026-05-24 17:00:53', '2026-05-31 15:18:20'),
(391, 412, NULL, NULL, 1, 17, NULL, NULL, NULL, NULL, '2026-05-24 17:00:53', '2026-05-31 15:18:20'),
(392, 326, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:53', '2026-05-24 17:46:29'),
(393, 377, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:53', '2026-05-24 17:46:29'),
(394, 402, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:53', '2026-05-24 17:46:29'),
(395, 340, NULL, NULL, 1, NULL, NULL, NULL, NULL, NULL, '2026-05-24 17:00:53', '2026-05-24 17:46:29'),
(396, 418, NULL, NULL, 1, 1, NULL, NULL, NULL, NULL, '2026-05-25 16:36:03', '2026-05-25 18:32:29'),
(397, 419, NULL, NULL, 1, 8, NULL, NULL, NULL, NULL, '2026-05-28 18:40:52', '2026-05-29 12:25:42'),
(399, 421, NULL, NULL, 1, 9, NULL, NULL, NULL, NULL, '2026-05-31 09:59:23', '2026-05-31 10:25:03'),
(401, 423, NULL, NULL, 1, 5, NULL, NULL, NULL, NULL, '2026-05-31 20:06:08', '2026-05-31 20:28:18'),
(402, 424, NULL, NULL, 1, 8, NULL, NULL, NULL, NULL, '2026-05-31 23:54:50', '2026-06-01 00:03:43');

-- --------------------------------------------------------

--
-- Table structure for table `student_submissions`
--

CREATE TABLE `student_submissions` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL COMMENT 'FK → students.id',
  `school_year_id` int(11) DEFAULT NULL COMMENT 'FK → school_years.id',
  `form137_status` enum('missing','uploaded','onsite') NOT NULL DEFAULT 'missing',
  `form137_file_path` varchar(1000) DEFAULT NULL,
  `form137_file_name` varchar(500) DEFAULT NULL,
  `form137_mime_type` varchar(100) DEFAULT NULL,
  `form137_size_kb` int(11) DEFAULT NULL,
  `birth_cert_status` enum('missing','uploaded','onsite') NOT NULL DEFAULT 'missing',
  `birth_cert_file_path` varchar(1000) DEFAULT NULL,
  `birth_cert_file_name` varchar(500) DEFAULT NULL,
  `birth_cert_mime_type` varchar(100) DEFAULT NULL,
  `birth_cert_size_kb` int(11) DEFAULT NULL,
  `reference_number` varchar(30) NOT NULL COMMENT 'e.g. SJC-2026-XXXX-0001',
  `privacy_accepted` tinyint(1) NOT NULL DEFAULT 0,
  `privacy_accepted_at` datetime DEFAULT NULL,
  `info_accuracy_accepted` tinyint(1) NOT NULL DEFAULT 0 COMMENT 'I confirm information is accurate checkbox',
  `info_accuracy_at` datetime DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `submitted_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `reviewed_by` int(11) DEFAULT NULL COMMENT 'FK → admins.id',
  `reviewed_at` datetime DEFAULT NULL,
  `registrar_notes` text DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Document submission record per student per school year';

--
-- Dumping data for table `student_submissions`
--

INSERT INTO `student_submissions` (`id`, `student_id`, `school_year_id`, `form137_status`, `form137_file_path`, `form137_file_name`, `form137_mime_type`, `form137_size_kb`, `birth_cert_status`, `birth_cert_file_path`, `birth_cert_file_name`, `birth_cert_mime_type`, `birth_cert_size_kb`, `reference_number`, `privacy_accepted`, `privacy_accepted_at`, `info_accuracy_accepted`, `info_accuracy_at`, `ip_address`, `submitted_at`, `updated_at`, `reviewed_by`, `reviewed_at`, `registrar_notes`) VALUES
(2, 7, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-E238-5048', 1, '2026-05-17 17:39:31', 1, '2026-05-17 17:39:31', '::1', '2026-05-17 15:39:31', '2026-05-17 15:39:31', NULL, NULL, NULL),
(4, 9, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-5CD4-0088', 1, '2026-05-18 20:54:42', 1, '2026-05-18 20:54:42', '::1', '2026-05-18 18:54:42', '2026-05-18 18:54:42', NULL, NULL, NULL),
(5, 10, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-DB6A-0281', 1, '2026-05-18 21:04:57', 1, '2026-05-18 21:04:57', '::1', '2026-05-18 19:04:57', '2026-05-18 19:04:57', NULL, NULL, NULL),
(6, 14, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-4EA0-9494', 1, '2026-05-20 20:11:05', 1, '2026-05-20 20:11:05', '192.168.68.157', '2026-05-20 18:11:05', '2026-05-20 18:11:05', NULL, NULL, NULL),
(7, 15, 1, 'uploaded', 'uploads/student_15/form137_15.jpg', 'image_2026-05-22_192008924.png', 'image/png', 103, 'uploaded', 'uploads/student_15/birth_cert_15.jpg', 'image_2026-05-22_192043422.png', 'image/png', 99, 'SJC-2026-3DF9-6716', 1, '2026-05-22 13:20:51', 1, '2026-05-22 13:20:51', '::1', '2026-05-22 11:20:51', '2026-05-23 19:53:46', NULL, NULL, NULL),
(8, 16, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-FAAC-0375', 1, '2026-05-22 14:49:19', 1, '2026-05-22 14:49:19', '::1', '2026-05-22 12:49:19', '2026-05-22 12:49:19', NULL, NULL, NULL),
(9, 17, 1, 'uploaded', 'uploads/student_17/doc_6a12adf65b74f6.06537695.jpg', 'form137-100630230353-phpapp01-thumbnail.jpg', 'image/jpeg', 57, 'uploaded', 'uploads/student_17/doc_6a12adf65baec2.34594530.jpg', '543916392604de744f9cad775ac5a9b1.jpg', 'image/jpeg', 206, 'SJC-2026-F72D-0314', 1, '2026-05-24 09:51:18', 1, '2026-05-24 09:51:18', '::1', '2026-05-24 07:51:18', '2026-05-24 07:51:18', NULL, NULL, NULL),
(10, 18, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-94AA-36A1', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(11, 19, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-E76F-251C', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(12, 20, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-FA1E-F791', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(13, 21, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-69EF-10C6', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(14, 22, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-C32C-91AA', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(15, 23, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-BE0B-A12C', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(16, 24, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-316C-60B8', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(17, 25, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-9336-9346', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(18, 26, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-CED1-28CC', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(19, 27, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-6AD8-A981', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(20, 28, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-F3A5-E5CA', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(21, 29, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-3EE9-87BD', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(22, 30, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-8314-A6B3', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(23, 31, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-B7D0-3154', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(24, 32, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-C5AA-6261', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(25, 33, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A0A9-7DAB', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(26, 34, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-4632-9288', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(27, 35, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-FB5F-40F9', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(28, 36, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-57D2-A1E6', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(29, 37, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-33A4-7E18', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(30, 38, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-3271-FE44', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(31, 39, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-ABD0-0E33', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(32, 40, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-57EE-D2CC', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(33, 41, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-205C-AB56', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(34, 42, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-FE74-75F7', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(35, 43, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-5125-9217', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(36, 44, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-DF39-D082', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(37, 45, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-3DD6-3112', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(38, 46, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-F3E9-F72E', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(39, 47, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-44BD-F1CE', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(40, 48, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-0F44-7142', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(41, 49, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A422-B019', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(42, 50, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-568B-E709', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(43, 51, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-78FF-5E7F', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(44, 52, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-2C12-D7BA', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(45, 53, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-F91A-AE4B', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(46, 54, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-0D7C-1FB0', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(47, 55, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-587B-9F11', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(48, 56, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-54A7-27BC', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(49, 57, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-45C6-2D42', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(50, 58, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-FD2F-6195', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(51, 59, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-2F16-4121', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(52, 60, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A514-2F90', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(53, 61, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-DEBA-4833', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(54, 62, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-445D-F70B', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(55, 63, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A99D-49D8', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(56, 64, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-F64C-8CDE', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(57, 65, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-616C-D20B', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(58, 66, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-D0F1-340B', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(59, 67, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-BB81-E16A', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(60, 68, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-E2F4-3C57', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(61, 69, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-DEF6-79E1', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(62, 70, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-2589-2A43', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(63, 71, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A39F-8332', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(64, 72, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-C0AF-F2F0', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(65, 73, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-671D-2AF5', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(66, 74, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-E5D4-257B', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(67, 75, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-1884-D62A', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(68, 76, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-8681-AA07', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(69, 77, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-93D1-7AC2', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(70, 78, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-4E29-58F5', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(71, 79, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-EDF9-75A9', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(72, 80, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A1B6-060E', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(73, 81, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-64BF-73F6', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(74, 82, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-5306-BD16', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(75, 83, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-0891-64F9', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(76, 84, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-FC21-E0B7', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(77, 85, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-2A23-F377', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(78, 86, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-7811-9091', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(79, 87, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-F47A-524A', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(80, 88, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-2FE0-8820', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(81, 89, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-5178-D2AA', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(82, 90, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-E170-D7B5', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(83, 91, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-2903-A658', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(84, 92, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-B29B-8AEA', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(85, 93, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-73EF-24CC', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(86, 94, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-816A-F0F6', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(87, 95, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-DFDD-3B7A', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(88, 96, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-5D42-77C9', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(89, 97, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-2A79-F529', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(90, 98, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-2F27-8E75', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(91, 99, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-F4F7-4070', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(92, 100, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-CC61-2C32', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(93, 101, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-E57B-5EDA', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(94, 102, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-4319-299B', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(95, 103, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-E344-95E6', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(96, 104, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-813E-DB59', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(97, 105, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-2B4E-C329', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(98, 106, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-B864-4A40', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(99, 107, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-1AC4-313D', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(100, 108, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-FF20-C2CA', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(101, 109, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-98F1-CC58', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(102, 110, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-506D-E2B1', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(103, 111, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-CAF1-7402', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(104, 112, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-ABE7-C1C3', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(105, 113, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-C9BD-A97D', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(106, 114, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-CC54-0D84', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(107, 115, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-51D4-7478', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(108, 116, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-99EF-F6BD', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(109, 117, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-86FA-4755', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(110, 118, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-9DF7-F99B', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(111, 119, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-5E16-00C3', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(112, 120, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-02C1-403D', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(113, 121, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-8E7C-9187', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(114, 122, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-7960-BDA1', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(115, 123, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-F57A-9103', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(116, 124, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-3B42-BB36', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(117, 125, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-2132-11E7', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(118, 126, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-67BA-F5AD', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(119, 127, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-B96F-CF0F', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(120, 128, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-9091-758A', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(121, 129, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-F9A2-CFEA', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(122, 130, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-6690-7776', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(123, 131, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-2884-6E31', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(124, 132, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-11B8-8F87', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(125, 133, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-8720-F1FA', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(126, 134, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-8E67-8B93', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(127, 135, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-7816-22AF', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(128, 136, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-FE7C-C59E', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(129, 137, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-00D7-CE1A', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(130, 138, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-6F50-3237', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(131, 139, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-B0B9-CCCA', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(132, 140, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-E769-35E6', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(133, 141, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-71FC-81C5', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(134, 142, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-9F70-34DE', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(135, 143, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-D89A-3271', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(136, 144, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-B19A-44D3', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(137, 145, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-616A-2B1F', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(138, 146, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-B8E2-AAB0', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(139, 147, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-064E-F768', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(140, 148, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-2210-291F', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(141, 149, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-79A2-838C', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(142, 150, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-4ACE-E945', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(143, 151, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-1E72-9558', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(144, 152, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-6B73-B0E2', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(145, 153, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-BF6F-4352', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(146, 154, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-EA58-2A4A', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(147, 155, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-BA4F-A391', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(148, 156, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-03B8-BCFB', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(149, 157, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-86C1-9EF7', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(150, 158, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-0C7C-68D0', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(151, 159, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-3B25-B9C7', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(152, 160, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A439-96DA', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(153, 161, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-24B8-4F07', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(154, 162, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-ED12-3CBF', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(155, 163, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A663-99F8', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(156, 164, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-CB3C-A437', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(157, 165, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-C831-C02E', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(158, 166, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-B6DF-28C4', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(159, 167, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-7D46-5DC7', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(160, 168, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A5A7-021F', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(161, 169, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-B394-BE90', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(162, 170, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-3767-E8EB', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(163, 171, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-885A-3A58', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(164, 172, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-FD74-88B0', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(165, 173, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-1802-1136', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(166, 174, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-756A-7714', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(167, 175, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-6DDC-4240', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(168, 176, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A03E-CEC3', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(169, 177, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A65A-EADE', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(170, 178, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-10FA-F5A2', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(171, 179, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-3732-3ED9', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(172, 180, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-74C1-5819', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(173, 181, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-78C6-5EDF', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(174, 182, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-3EA5-78F7', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(175, 183, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-3AA8-D6FD', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(176, 184, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A84A-8A4A', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(177, 185, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A7E3-C985', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(178, 186, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-B281-A054', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(179, 187, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-2585-4701', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(180, 188, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-1477-0514', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(181, 189, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-7EA5-306E', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(182, 190, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-7595-00AD', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(183, 191, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-8401-CFD9', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(184, 192, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-4616-DD87', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(185, 193, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-164A-0D0E', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(186, 194, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-DE67-D266', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(187, 195, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-370D-7F58', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(188, 196, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-7578-5D1A', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(189, 197, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-E665-AE3C', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(190, 198, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-7FFD-C970', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(191, 199, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-83B1-08CF', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(192, 200, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-ED32-D8AD', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(193, 201, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-BFAC-C382', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(194, 202, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-1D37-EFDA', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(195, 203, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-98C8-F3D2', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(196, 204, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-3D40-76E4', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(197, 205, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-89AA-C8BB', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(198, 206, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-E6BB-2046', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(199, 207, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-D720-F014', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(200, 208, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-8F96-BBF4', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(201, 209, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-C916-B5C1', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(202, 210, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-D3B7-1C9F', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(203, 211, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-0A7F-A810', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(204, 212, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-3089-B874', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(205, 213, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-4266-680E', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(206, 214, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-D848-8817', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(207, 215, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-0DFC-80BA', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(208, 216, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-EF3F-1168', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(209, 217, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-98D8-2ECC', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(210, 218, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-700B-230B', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(211, 219, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-1BF6-FBEE', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(212, 220, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-B610-E510', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(213, 221, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-4D6A-8358', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(214, 222, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-27E8-CA57', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL);
INSERT INTO `student_submissions` (`id`, `student_id`, `school_year_id`, `form137_status`, `form137_file_path`, `form137_file_name`, `form137_mime_type`, `form137_size_kb`, `birth_cert_status`, `birth_cert_file_path`, `birth_cert_file_name`, `birth_cert_mime_type`, `birth_cert_size_kb`, `reference_number`, `privacy_accepted`, `privacy_accepted_at`, `info_accuracy_accepted`, `info_accuracy_at`, `ip_address`, `submitted_at`, `updated_at`, `reviewed_by`, `reviewed_at`, `registrar_notes`) VALUES
(215, 223, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-68CA-55BD', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(216, 224, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-30C7-A2EA', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(217, 225, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-CDBB-DC30', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(218, 226, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-6594-132B', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(219, 227, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A507-61DD', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(220, 228, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-684C-4D54', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(221, 229, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-702A-7A8C', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(222, 230, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-6F01-6DF7', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(223, 231, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-7D83-3E85', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(224, 232, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-9ECC-3B36', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(225, 233, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-4729-FF5B', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(226, 234, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-3E41-7A5A', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(227, 235, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-C946-DCDC', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(228, 236, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-9C22-BD82', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(229, 237, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-3235-C03F', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(230, 238, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-3884-93B7', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(231, 239, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-4C43-21EE', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(232, 240, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-9B9C-3BCD', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(233, 241, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-9E53-475C', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(234, 242, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-F53F-8858', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(235, 243, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-D90B-887A', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(236, 244, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-E8B2-2E9D', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(237, 245, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-7F2C-F27D', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(238, 246, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-5EE3-5AB3', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(239, 247, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-FAAE-CA3E', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(240, 248, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-93C2-29CC', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(241, 249, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-FBC6-B4D8', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(242, 250, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A588-AB63', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(243, 251, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-CA72-A22E', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(244, 252, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A5BF-611C', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(245, 253, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-CEFE-24B6', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(246, 254, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-7870-8E92', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(247, 255, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-C899-7454', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(248, 256, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-02BB-DC22', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(249, 257, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-D35D-42C8', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(250, 258, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-BC1F-4CEF', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(251, 259, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-118A-5AFC', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(252, 260, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-577B-9302', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(253, 261, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-C983-76D2', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(254, 262, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-3034-D32E', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(255, 263, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-DABC-4257', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(256, 264, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-3FAD-62F9', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(257, 265, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-C050-080E', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(258, 266, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-F02E-F6C2', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(259, 267, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-ACF0-307A', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(260, 268, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-BD38-578E', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(261, 269, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-21B9-C9CE', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(262, 270, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-3E79-3072', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(263, 271, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-34DF-8D0E', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(264, 272, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-9BDE-80B9', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(265, 273, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-CC85-B3AF', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(266, 274, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-E131-B430', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(267, 275, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-0CC1-3FF3', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(268, 276, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-CD64-131C', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(269, 277, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-B442-4BB0', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(270, 278, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-38B3-C784', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(271, 279, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-0FBC-45FD', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(272, 280, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-AC26-F4A5', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(273, 281, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-E2CF-108A', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(274, 282, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-7AFE-966C', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(275, 283, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-51D5-F6EE', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(276, 284, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-F4C5-F328', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(277, 285, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-9CC7-4925', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(278, 286, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-7F90-0D93', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(279, 287, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A789-038B', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(280, 288, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-7FDF-0CD1', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(281, 289, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A05C-10DA', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(282, 290, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-42CB-1B32', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(283, 291, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-340B-7861', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(284, 292, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-79B4-AC9A', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(285, 293, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-9156-9753', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(286, 294, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-B89C-4802', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(287, 295, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-0507-E5F2', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(288, 296, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A6BF-69A0', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(289, 297, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-63BD-CFE6', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(290, 298, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-C654-31C1', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(291, 299, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-ECC0-5F27', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(292, 300, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-FAF3-0BE3', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(293, 301, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-586D-456B', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(294, 302, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-EA99-F54B', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(295, 303, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-48C9-A46B', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(296, 304, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-AA74-735B', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(297, 305, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-EBF1-C510', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(298, 306, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-674F-3D4B', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(299, 307, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-C29B-4BF0', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(300, 308, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-FEFC-00A3', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(301, 309, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-634F-83D9', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(302, 310, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-C63A-62FC', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(303, 311, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-4801-01B2', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(304, 312, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-7853-C09D', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(305, 313, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-FC0B-763E', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(306, 314, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-8BFF-9838', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(307, 315, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-37C3-0986', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(308, 316, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-DE2B-2BA9', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(309, 317, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-1DD6-B928', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(310, 318, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-5941-A107', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(311, 319, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-ED2C-6433', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(312, 320, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-8758-8309', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(313, 321, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-7CD3-1BB3', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(314, 322, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-B60A-7A78', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(315, 323, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-6004-71AA', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(316, 324, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-BABF-EA0D', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(317, 325, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-9E43-A3FB', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(318, 326, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-CB7E-E023', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(319, 327, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-4F90-70B2', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(320, 328, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-8861-38DC', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(321, 329, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-3982-2EDD', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(322, 330, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-C997-5995', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(323, 331, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-D16A-57CC', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(324, 332, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-6DA6-6AC7', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(325, 333, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-6C38-9C41', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(326, 334, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-80FE-C986', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(327, 335, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-6CF9-40A4', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(328, 336, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-C631-3CDF', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(329, 337, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-F317-BE10', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(330, 338, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-043D-7D64', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(331, 339, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A5C6-90ED', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(332, 340, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-26A7-679B', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(333, 341, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-F4BD-4642', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(334, 342, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-EC3E-6A2D', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(335, 343, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-97E0-10F8', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(336, 344, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-97BE-A7E9', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(337, 345, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-97DB-1A19', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(338, 346, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-6CE6-23EF', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(339, 347, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-6CAB-EA0C', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(340, 348, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-6BD8-3B8D', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(341, 349, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-B0AC-0FF0', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(342, 350, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-2D61-C0CC', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(343, 351, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A3FC-A355', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(344, 352, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-59C3-48CA', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(345, 353, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-43F0-5BFE', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(346, 354, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-23CB-32A1', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(347, 355, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-E9E2-C803', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(348, 356, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-9DA8-51B2', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(349, 357, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-5160-9EEB', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(350, 358, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-B574-C7D4', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(351, 359, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-DB98-B4C3', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(352, 360, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-184A-7374', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(353, 361, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-FF17-C6D9', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(354, 362, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-297A-0582', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(355, 363, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-05D1-0228', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(356, 364, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-14AA-D1D1', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(357, 365, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-B3A8-34C4', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(358, 366, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-286B-2CF0', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(359, 367, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-7EDB-5C8E', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(360, 368, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-166D-8461', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(361, 369, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-53AF-C656', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(362, 370, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-3CC7-2546', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(363, 371, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-D406-4E3C', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(364, 372, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-4C56-9418', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(365, 373, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-4EA5-F595', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(366, 374, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-5FFD-4BFD', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(367, 375, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-74E8-935F', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(368, 376, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-80E3-36FE', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(369, 377, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-9327-A323', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(370, 378, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-91BB-C926', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(371, 379, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-27CE-6C81', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(372, 380, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-C3F9-E255', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(373, 381, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-5579-B185', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(374, 382, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-9400-BB0E', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(375, 383, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-701F-967F', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(376, 384, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-4543-E7FF', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(377, 385, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-1C38-6F4B', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(378, 386, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-51C8-045D', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(379, 387, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-58D5-DDDA', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(380, 388, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-4864-58E1', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(381, 389, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-B5F0-612A', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(382, 390, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-B426-87BB', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(383, 391, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-9B49-279B', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(384, 392, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-80C4-46CD', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(385, 393, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-19F8-9634', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(386, 394, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-4D78-3883', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(387, 395, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-D2BE-D3CC', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(388, 396, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-8FA4-2E97', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(389, 397, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A589-5A37', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(390, 398, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-0B5C-92C7', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(391, 399, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-79A0-9855', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(392, 400, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-CC62-A533', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(393, 401, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-B6E4-6DA3', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(394, 402, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-689A-8AD7', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(395, 403, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-2BA3-218C', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(396, 404, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-91E2-DE32', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(397, 405, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-FC09-818B', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(398, 406, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-33EA-E138', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(399, 407, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-5C8F-E43D', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(400, 408, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-60D5-4733', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(401, 409, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-DF31-5A41', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(402, 410, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-2966-89E5', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(403, 411, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A0A0-DAA1', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(404, 412, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-A5F3-649B', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(405, 413, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-2134-3C0A', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(406, 414, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-163C-0651', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(407, 415, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-AFFB-7608', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(408, 416, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-CFB6-D5C4', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(409, 417, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-5F3C-EDDC', 1, '2026-05-25 08:00:00', 1, '2026-05-25 08:00:00', '127.0.0.1', '2026-05-24 23:00:00', '2026-05-24 23:00:00', NULL, NULL, NULL),
(410, 418, 1, 'uploaded', 'uploads/student_418/form137_418.png', NULL, NULL, NULL, 'uploaded', 'uploads/student_418/birth_cert_418.png', NULL, NULL, NULL, 'SJC-2026-9AA1-6322', 1, '2026-05-25 18:36:47', 1, '2026-05-25 18:36:47', '::1', '2026-05-25 16:36:47', '2026-05-25 17:17:35', NULL, NULL, NULL),
(411, 419, 1, 'uploaded', 'uploads/student_419/form137_419.png', NULL, NULL, NULL, 'uploaded', 'uploads/student_419/birth_cert_419.png', NULL, NULL, NULL, 'SJC-2026-B68F-4681', 1, '2026-05-28 20:58:08', 1, '2026-05-28 20:58:08', '::1', '2026-05-28 18:58:08', '2026-05-28 19:57:01', NULL, NULL, NULL),
(413, 421, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-5F13-7556', 1, '2026-05-31 12:00:02', 1, '2026-05-31 12:00:02', '::1', '2026-05-31 10:00:02', '2026-05-31 10:00:02', NULL, NULL, NULL),
(415, 423, 1, 'onsite', NULL, NULL, NULL, NULL, 'onsite', NULL, NULL, NULL, NULL, 'SJC-2026-39FA-5655', 1, '2026-05-31 22:06:38', 1, '2026-05-31 22:06:38', '::1', '2026-05-31 20:06:38', '2026-05-31 20:06:38', NULL, NULL, NULL),
(416, 424, 1, 'uploaded', 'uploads/student_424/form137_424.png', 'Form 137 Mock.png', 'image/png', 80, 'uploaded', 'uploads/student_424/birth_cert_424.jpg', 'BSA Certificate mock.jpg', 'image/jpeg', 136, 'SJC-2026-688E-2677', 1, '2026-06-01 01:55:46', 1, '2026-06-01 01:55:46', '::1', '2026-05-31 23:55:46', '2026-05-31 23:58:26', NULL, NULL, NULL);

-- --------------------------------------------------------

--
-- Table structure for table `student_wallets`
--

CREATE TABLE `student_wallets` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL COMMENT 'FK -> students.id',
  `balance` decimal(10,2) NOT NULL DEFAULT 0.00,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='One row per student cafeteria wallet';

--
-- Dumping data for table `student_wallets`
--

INSERT INTO `student_wallets` (`id`, `student_id`, `balance`, `updated_at`) VALUES
(1, 73, 0.00, '2026-07-23 17:30:37');

-- --------------------------------------------------------

--
-- Table structure for table `subjects`
--

CREATE TABLE `subjects` (
  `id` int(11) NOT NULL,
  `name` varchar(200) NOT NULL,
  `code` varchar(20) NOT NULL COMMENT 'e.g. SCI8, MATH7',
  `grade_level_id` int(11) NOT NULL DEFAULT 7 COMMENT 'FK → grade_levels.id',
  `units` decimal(4,2) NOT NULL DEFAULT 1.00,
  `hours_per_week` tinyint(4) NOT NULL DEFAULT 1,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `is_archived` tinyint(1) NOT NULL DEFAULT 0 COMMENT '1 = soft-deleted, hidden from curriculum; use archive_subject / restore_subject',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `subjects`
--

INSERT INTO `subjects` (`id`, `name`, `code`, `grade_level_id`, `units`, `hours_per_week`, `is_active`, `is_archived`, `created_at`, `updated_at`) VALUES
(1, 'ENGLISH', 'ENGLISH-07', 7, 1.00, 1, 1, 0, '2026-05-16 19:30:08', '2026-05-16 19:34:43'),
(2, 'MATH', 'MATH-07', 7, 1.00, 1, 1, 0, '2026-05-16 19:30:30', '2026-05-16 19:31:37'),
(3, 'SCIENCE', 'SCIENCE-07', 7, 1.00, 1, 1, 0, '2026-05-16 19:30:52', '2026-05-16 19:34:53'),
(4, 'FILIPINO', 'FILIPINO-07', 7, 1.00, 1, 1, 0, '2026-05-16 19:31:29', '2026-05-16 19:34:36'),
(5, 'VALUES EDUCATION', 'ESP-07', 7, 1.00, 1, 1, 0, '2026-05-16 19:32:08', '2026-05-16 19:32:08'),
(6, 'ARALING PANLIPUNAN', 'AP-07', 7, 1.00, 1, 1, 0, '2026-05-16 19:32:23', '2026-05-30 20:59:59'),
(7, 'MAPEH', 'MAPEH-07', 7, 1.00, 1, 1, 0, '2026-05-16 19:32:39', '2026-05-16 19:32:39'),
(8, 'TLE', 'TLE-07', 7, 1.00, 1, 1, 0, '2026-05-16 19:32:52', '2026-05-16 19:32:52'),
(9, 'ENGLISH', 'ENGLISH-08', 8, 1.00, 1, 1, 0, '2026-05-16 19:46:46', '2026-05-16 19:55:42'),
(10, 'MATH', 'MATH-08', 8, 1.00, 1, 1, 0, '2026-05-16 19:47:11', '2026-05-16 19:55:52'),
(11, 'SCIENCE', 'SCIENCE-08', 8, 1.00, 1, 1, 0, '2026-05-16 19:47:24', '2026-05-16 19:55:55'),
(12, 'FILIPINO', 'FILIPINO-08', 8, 1.00, 1, 1, 0, '2026-05-16 19:47:34', '2026-05-16 19:55:46'),
(13, 'VALUES EDUCATION', 'ESP-08', 8, 1.00, 1, 1, 0, '2026-05-16 19:47:47', '2026-05-16 19:56:05'),
(14, 'ARALING PANLIPUNAN', 'AP-08', 8, 1.00, 1, 1, 0, '2026-05-16 19:47:57', '2026-05-16 19:55:37'),
(15, 'MAPEH', 'MAPEH-08', 8, 1.00, 1, 1, 0, '2026-05-16 19:48:09', '2026-05-16 19:55:49'),
(16, 'TLE', 'TLE-08', 8, 1.00, 1, 1, 0, '2026-05-16 19:48:26', '2026-05-16 19:56:02'),
(17, 'ENGLISH', 'ENGLISH-09', 9, 1.00, 1, 1, 0, '2026-05-16 19:55:28', '2026-05-16 19:59:52'),
(18, 'MATH', 'MATH-09', 9, 1.00, 1, 1, 0, '2026-05-16 19:56:22', '2026-05-16 19:56:22'),
(19, 'SCIENCE', 'SCIENCE-09', 9, 1.00, 1, 1, 0, '2026-05-16 19:56:33', '2026-05-16 19:56:33'),
(20, 'FILIPINO', 'FILIPINO-09', 9, 1.00, 1, 1, 0, '2026-05-16 19:56:45', '2026-05-16 19:56:45'),
(21, 'VALUES EDUCATION', 'ESP-09', 9, 1.00, 1, 1, 0, '2026-05-16 19:56:55', '2026-05-16 19:56:55'),
(22, 'ARALING PANLIPUNAN', 'AP-09', 9, 1.00, 1, 1, 0, '2026-05-16 19:57:10', '2026-05-16 19:57:10'),
(23, 'MAPEH', 'MAPEH-09', 9, 1.00, 1, 1, 0, '2026-05-16 19:57:21', '2026-05-16 19:57:21'),
(24, 'TLE', 'TLE-09', 9, 1.00, 1, 1, 0, '2026-05-16 19:57:29', '2026-05-16 19:57:29'),
(25, 'ENGLISH', 'ENGLISH-10', 10, 1.00, 1, 1, 0, '2026-05-16 19:57:43', '2026-05-16 19:57:43'),
(26, 'MATH', 'MATH-10', 10, 1.00, 1, 1, 0, '2026-05-16 19:57:53', '2026-05-16 19:57:53'),
(27, 'SCIENCE', 'SCIENCE-10', 10, 1.00, 1, 1, 0, '2026-05-16 19:58:01', '2026-05-16 19:58:01'),
(28, 'FILIPINO', 'FILIPINO-10', 10, 1.00, 1, 1, 0, '2026-05-16 19:59:28', '2026-05-16 19:59:28'),
(32, 'VALUES EDUCATION', 'ESP-10', 10, 1.00, 1, 1, 0, '2026-05-16 20:01:17', '2026-05-16 20:01:17'),
(33, 'ARALING PANLIPUNAN', 'AP-10', 10, 1.00, 1, 1, 0, '2026-05-16 20:01:32', '2026-05-16 20:01:32'),
(34, 'MAPEH', 'MAPEH-10', 10, 1.00, 1, 1, 0, '2026-05-16 20:01:42', '2026-05-16 20:01:42'),
(35, 'TLE', 'TLE-10', 10, 1.00, 1, 1, 0, '2026-05-16 20:01:49', '2026-05-16 20:01:49');

-- --------------------------------------------------------

--
-- Table structure for table `system_deadlines`
--

CREATE TABLE `system_deadlines` (
  `id` int(11) NOT NULL,
  `school_year_id` int(11) NOT NULL,
  `type` enum('enrollment','grade_encoding_term1','grade_encoding_term2','grade_encoding_term3','payments') NOT NULL,
  `start_date` date NOT NULL,
  `end_date` date NOT NULL,
  `start_datetime` datetime DEFAULT NULL COMMENT 'Replaces start_date; includes time (e.g. 2026-06-01 08:00:00)',
  `end_datetime` datetime DEFAULT NULL COMMENT 'Replaces end_date; includes time (e.g. 2026-06-30 23:59:59)',
  `notes` text DEFAULT NULL,
  `created_by` int(11) NOT NULL COMMENT 'FK → admins.id',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `system_deadlines`
--

INSERT INTO `system_deadlines` (`id`, `school_year_id`, `type`, `start_date`, `end_date`, `start_datetime`, `end_datetime`, `notes`, `created_by`, `created_at`, `updated_at`) VALUES
(1, 1, 'enrollment', '2026-05-19', '2026-07-30', '2026-05-19 03:29:00', '2026-07-30 03:29:00', '', 1, '2026-05-18 19:30:13', '2026-05-31 06:49:35'),
(2, 1, 'grade_encoding_term1', '2026-05-25', '2026-07-25', '2026-05-25 20:51:00', '2026-07-25 20:51:00', '', 1, '2026-05-25 12:50:33', '2026-05-25 13:54:34'),
(3, 1, 'payments', '2026-05-31', '2026-06-10', '2026-05-31 14:50:00', '2026-06-10 15:00:00', '', 1, '2026-05-31 06:49:23', '2026-05-31 06:49:23');

-- --------------------------------------------------------

--
-- Table structure for table `teachers`
--

CREATE TABLE `teachers` (
  `id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL COMMENT 'FK → users.id',
  `first_name` varchar(100) NOT NULL,
  `middle_name` varchar(100) DEFAULT NULL,
  `last_name` varchar(100) NOT NULL,
  `subject_id` int(11) DEFAULT NULL COMMENT 'FK → subjects.id — teacher primary subject specialty (set by admin)',
  `full_name` varchar(200) DEFAULT NULL COMMENT 'Kept for display convenience',
  `employee_id` varchar(50) DEFAULT NULL COMMENT 'School employee number',
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `assigned_subjects` text DEFAULT NULL COMMENT 'Comma-separated assigned subject names',
  `is_archived` tinyint(1) NOT NULL DEFAULT 0 COMMENT '1 = archived / inactive account'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='One row per teacher staff member';

--
-- Dumping data for table `teachers`
--

INSERT INTO `teachers` (`id`, `user_id`, `first_name`, `middle_name`, `last_name`, `subject_id`, `full_name`, `employee_id`, `is_active`, `created_at`, `updated_at`, `assigned_subjects`, `is_archived`) VALUES
(1, 14, 'Denver', NULL, 'SandCheese', NULL, 'Denver SandCheese', NULL, 1, '2026-05-19 07:59:57', '2026-05-21 17:53:58', 'ENGLISH', 1),
(2, 17, 'Perlica', NULL, 'Clara', 5, 'Perlica Clara', NULL, 1, '2026-05-21 17:55:32', '2026-05-21 18:43:45', 'VALUES EDUCATION', 1),
(3, 20, 'Filomenileia', NULL, 'Querina', 5, 'Filomenileia Querina', NULL, 1, '2026-05-21 18:04:45', '2026-05-21 18:43:43', 'VALUES EDUCATION', 1),
(4, 22, 'Perlica', NULL, 'Nalaya', 5, 'Perlica Nalaya', NULL, 1, '2026-05-21 18:45:31', '2026-05-21 18:45:31', 'VALUES EDUCATION', 0),
(5, 23, 'Joshua', NULL, 'Lupisan', 5, 'Joshua Lupisan', NULL, 1, '2026-05-21 18:46:02', '2026-05-21 18:54:27', 'VALUES EDUCATION', 0),
(6, 430, 'Maria', NULL, 'Santos', 7, 'Maria Santos', 'EMP-A10001', 1, '2026-05-25 00:00:00', '2026-05-25 09:22:46', 'MAPEH', 0),
(7, 431, 'Jose', NULL, 'Reyes', 7, 'Jose Reyes', 'EMP-A10002', 1, '2026-05-25 00:00:00', '2026-05-25 09:22:32', 'MAPEH', 0),
(8, 432, 'Ana', NULL, 'Cruz', 5, 'Ana Cruz', 'EMP-A10003', 1, '2026-05-25 00:00:00', '2026-05-25 09:03:20', 'VALUES EDUCATION', 0),
(9, 433, 'Roberto', NULL, 'Mendoza', 4, 'Roberto Mendoza', 'EMP-A10004', 1, '2026-05-25 00:00:00', '2026-05-25 09:23:09', 'FILIPINO', 0),
(10, 434, 'Linda', NULL, 'Flores', 3, 'Linda Flores', 'EMP-A10005', 1, '2026-05-25 00:00:00', '2026-05-25 09:22:35', 'SCIENCE', 0),
(11, 435, 'Carlos', NULL, 'Torres', 8, 'Carlos Torres', 'EMP-A10006', 1, '2026-05-25 00:00:00', '2026-05-25 09:03:31', 'TLE', 0),
(12, 436, 'Rosalie', NULL, 'Bautista', 1, 'Rosalie Bautista', 'EMP-A10007', 1, '2026-05-25 00:00:00', '2026-05-25 09:23:14', 'ENGLISH', 0),
(13, 437, 'Miguel', NULL, 'Villanueva', 4, 'Miguel Villanueva', 'EMP-A10008', 1, '2026-05-25 00:00:00', '2026-05-25 09:22:54', 'FILIPINO', 0),
(14, 438, 'Teresa', NULL, 'Lim', 6, 'Teresa Lim', 'EMP-A10009', 1, '2026-05-25 00:00:00', '2026-05-25 09:23:18', 'ARALING PANLIPUNAN', 0),
(15, 439, 'Antonio', NULL, 'Garcia', 4, 'Antonio Garcia', 'EMP-A10010', 1, '2026-05-25 00:00:00', '2026-05-25 09:03:22', 'FILIPINO', 0),
(16, 440, 'Carmeni', NULL, 'Dela Rosa', 3, 'Carmeni Dela Rosa', 'EMP-A10011', 1, '2026-05-25 00:00:00', '2026-05-25 09:03:34', 'SCIENCE', 0),
(17, 441, 'Bernardo', NULL, 'Aquino', 7, 'Bernardo Aquino', 'EMP-A10012', 1, '2026-05-25 00:00:00', '2026-05-25 09:03:28', 'MAPEH', 0),
(18, 442, 'Evelyn', NULL, 'Pascual', 7, 'Evelyn Pascual', 'EMP-A10013', 1, '2026-05-25 00:00:00', '2026-05-25 09:21:17', 'MAPEH', 0),
(19, 443, 'Ramon', NULL, 'Navarro', 6, 'Ramon Navarro', 'EMP-A10014', 1, '2026-05-25 00:00:00', '2026-05-25 09:23:02', 'ARALING PANLIPUNAN', 0),
(20, 444, 'Clarita', NULL, 'Ocampo', 2, 'Clarita Ocampo', 'EMP-A10015', 1, '2026-05-25 00:00:00', '2026-05-25 09:04:54', 'MATH', 0),
(21, 445, 'Fernando', NULL, 'Diaz', 4, 'Fernando Diaz', 'EMP-A10016', 1, '2026-05-25 00:00:00', '2026-05-25 09:21:20', 'FILIPINO', 0),
(22, 446, 'Lourdes', NULL, 'Castillo', 6, 'Lourdes Castillo', 'EMP-A10017', 1, '2026-05-25 00:00:00', '2026-05-25 09:22:40', 'ARALING PANLIPUNAN', 0),
(23, 447, 'Eduardo', NULL, 'Ramos', 4, 'Eduardo Ramos', 'EMP-A10018', 1, '2026-05-25 00:00:00', '2026-05-25 09:05:09', 'FILIPINO', 0),
(24, 448, 'Marisol', NULL, 'Espinosa', 3, 'Marisol Espinosa', 'EMP-A10019', 1, '2026-05-25 00:00:00', '2026-05-25 09:22:49', 'SCIENCE', 0),
(25, 449, 'Rodolfo', NULL, 'Medina', 7, 'Rodolfo Medina', 'EMP-A10020', 1, '2026-05-25 00:00:00', '2026-05-25 09:23:12', 'MAPEH', 0),
(26, 450, 'Gloria', NULL, 'Hernandez', 3, 'Gloria Hernandez', 'EMP-A10021', 1, '2026-05-25 00:00:00', '2026-05-25 09:21:25', 'SCIENCE', 0),
(27, 451, 'Arthur', NULL, 'Salvador', 1, 'Arthur Salvador', 'EMP-A10022', 1, '2026-05-25 00:00:00', '2026-05-25 09:03:24', 'ENGLISH', 0),
(28, 452, 'Norma', NULL, 'Velasquez', 5, 'Norma Velasquez', 'EMP-A10023', 1, '2026-05-25 00:00:00', '2026-05-25 09:22:57', 'VALUES EDUCATION', 0),
(29, 453, 'Daniel', NULL, 'Buenaventura', 5, 'Daniel Buenaventura', 'EMP-A10024', 1, '2026-05-25 00:00:00', '2026-05-25 09:05:01', 'VALUES EDUCATION', 0),
(30, 454, 'Stella', NULL, 'Miranda', 8, 'Stella Miranda', 'EMP-A10025', 1, '2026-05-25 00:00:00', '2026-05-25 09:23:16', 'TLE', 0),
(31, 455, 'Ricardo', NULL, 'Perez', 1, 'Ricardo Perez', 'EMP-A10026', 1, '2026-05-25 00:00:00', '2026-05-25 09:23:07', 'ENGLISH', 0),
(32, 456, 'Cecilia', NULL, 'Aguilar', 3, 'Cecilia Aguilar', 'EMP-A10027', 1, '2026-05-25 00:00:00', '2026-05-25 09:03:37', 'SCIENCE', 0),
(33, 457, 'Manuel', NULL, 'Cabrera', 3, 'Manuel Cabrera', 'EMP-A10028', 1, '2026-05-25 00:00:00', '2026-05-25 09:22:42', 'SCIENCE', 0),
(34, 458, 'Imelda', NULL, 'Dela Cruz', 4, 'Imelda Dela Cruz', 'EMP-A10029', 1, '2026-05-25 00:00:00', '2026-05-25 09:22:29', 'FILIPINO', 0),
(35, 459, 'Victor', NULL, 'Enriquez', 8, 'Victor Enriquez', 'EMP-A10030', 1, '2026-05-25 00:00:00', '2026-05-25 09:23:20', 'TLE', 0),
(36, 460, 'Paulina', NULL, 'Robles', 5, 'Paulina Robles', 'EMP-A10031', 1, '2026-05-25 00:00:00', '2026-05-25 09:23:00', 'VALUES EDUCATION', 0),
(37, 461, 'Hector', NULL, 'Soriano', 5, 'Hector Soriano', 'EMP-A10032', 1, '2026-05-25 00:00:00', '2026-05-25 09:22:26', 'VALUES EDUCATION', 0),
(38, 462, 'Mercedes', NULL, 'Tan', 3, 'Mercedes Tan', 'EMP-A10033', 1, '2026-05-25 00:00:00', '2026-05-25 09:22:51', 'SCIENCE', 0),
(39, 463, 'Alfonso', NULL, 'Quizon', 6, 'Alfonso Quizon', 'EMP-A10034', 1, '2026-05-25 00:00:00', '2026-05-25 09:03:17', 'ARALING PANLIPUNAN', 0),
(40, 464, 'Conchita', NULL, 'Ureta', 8, 'Conchita Ureta', 'EMP-A10035', 1, '2026-05-25 00:00:00', '2026-05-25 09:04:57', 'TLE', 0);

-- --------------------------------------------------------

--
-- Table structure for table `teacher_notifications`
--

CREATE TABLE `teacher_notifications` (
  `id` int(11) NOT NULL,
  `teacher_id` int(11) NOT NULL,
  `type` varchar(60) NOT NULL,
  `grade_id` int(11) NOT NULL,
  `student_name` varchar(200) DEFAULT NULL,
  `subject_name` varchar(200) DEFAULT NULL,
  `section_name` varchar(100) DEFAULT NULL,
  `comment` text DEFAULT NULL,
  `is_read` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `teacher_notifications`
--

INSERT INTO `teacher_notifications` (`id`, `teacher_id`, `type`, `grade_id`, `student_name`, `subject_name`, `section_name`, `comment`, `is_read`, `created_at`) VALUES
(1, 5, 'approved_by_head', 142, 'Barroga, Patricia', 'VALUES EDUCATION', 'COMPETENCE', NULL, 0, '2026-05-31 11:30:37'),
(2, 5, 'approved_by_head', 141, 'Barroga, Daniel', 'VALUES EDUCATION', 'COMPETENCE', NULL, 0, '2026-05-31 11:30:37'),
(3, 5, 'approved_by_head', 140, 'Balboa, Christian', 'VALUES EDUCATION', 'COMPETENCE', NULL, 0, '2026-05-31 11:30:37'),
(4, 5, 'approved_by_head', 139, 'Ayala, Thomas', 'VALUES EDUCATION', 'COMPETENCE', NULL, 0, '2026-05-31 11:30:37'),
(5, 5, 'approved_by_head', 138, 'Ayala, Lydia', 'VALUES EDUCATION', 'COMPETENCE', NULL, 0, '2026-05-31 11:30:37'),
(6, 5, 'approved_by_head', 137, 'Austria, Caroline', 'VALUES EDUCATION', 'COMPETENCE', NULL, 0, '2026-05-31 11:30:37'),
(7, 5, 'approved_by_head', 136, 'Aquino, Paolo', 'VALUES EDUCATION', 'COMPETENCE', NULL, 0, '2026-05-31 11:30:37'),
(8, 5, 'approved_by_head', 135, 'Andres, Francis', 'VALUES EDUCATION', 'COMPETENCE', NULL, 0, '2026-05-31 11:30:37'),
(9, 5, 'approved_by_head', 134, 'Alejo, Leia', 'VALUES EDUCATION', 'COMPETENCE', NULL, 0, '2026-05-31 11:30:37'),
(10, 5, 'approved_by_head', 133, 'Alejo, Jade', 'VALUES EDUCATION', 'COMPETENCE', NULL, 0, '2026-05-31 11:30:37'),
(11, 5, 'approved_by_head', 132, 'Aldana, Xavier', 'VALUES EDUCATION', 'COMPETENCE', NULL, 0, '2026-05-31 11:30:37'),
(12, 5, 'approved_by_head', 131, 'Aldana, Tiffany', 'VALUES EDUCATION', 'COMPETENCE', NULL, 0, '2026-05-31 11:30:37'),
(13, 5, 'approved_by_head', 130, 'Aldana, Sofia', 'VALUES EDUCATION', 'COMPETENCE', NULL, 0, '2026-05-31 11:30:37'),
(14, 5, 'approved_by_head', 129, 'Aldana, Ryan', 'VALUES EDUCATION', 'COMPETENCE', NULL, 0, '2026-05-31 11:30:37'),
(15, 5, 'approved_by_head', 128, 'Aldana, Leah', 'VALUES EDUCATION', 'COMPETENCE', NULL, 0, '2026-05-31 11:30:37'),
(16, 5, 'approved_by_head', 127, 'Alcantara, Sheila', 'VALUES EDUCATION', 'COMPETENCE', NULL, 0, '2026-05-31 11:30:37'),
(17, 5, 'approved_by_head', 143, 'Bautista, Kevin', 'VALUES EDUCATION', 'COMPETENCE', NULL, 0, '2026-05-31 11:30:37'),
(18, 5, 'approved_by_head', 190, 'Paglinawan, Emmanuel', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-31 21:08:33'),
(19, 5, 'approved_by_head', 188, 'Zamora, Victor', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-31 21:08:33'),
(20, 5, 'approved_by_head', 187, 'Zamora, Ramon', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-31 21:08:33'),
(21, 5, 'approved_by_head', 186, 'Yap, Lucia', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-31 21:08:33'),
(22, 5, 'approved_by_head', 185, 'Saichou, QueerBalasin', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-31 21:08:33'),
(23, 5, 'approved_by_head', 184, 'Reyes, Anthony', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-31 21:08:33'),
(24, 5, 'approved_by_head', 183, 'Padilla, Charlene', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-31 21:08:33'),
(25, 5, 'approved_by_head', 18, 'Macaraeg, Richard', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-31 21:08:33'),
(26, 5, 'approved_by_head', 11, 'De Guzman, Eduardo', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-31 21:08:33'),
(27, 5, 'approved_by_head', 10, 'Cayabyab, Karen', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-31 21:08:33'),
(28, 5, 'approved_by_head', 9, 'Cabrido, Hannah', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-31 21:08:33'),
(29, 5, 'approved_by_head', 8, 'Cabrido, Anthony', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-31 21:08:33'),
(30, 5, 'approved_by_head', 7, 'Barroga, Lydia', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-31 21:08:33'),
(31, 5, 'approved_by_head', 6, 'Barrientos, Maricel', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-31 21:08:33'),
(32, 5, 'approved_by_head', 5, 'Balboa, Maricel', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-31 21:08:33'),
(33, 5, 'approved_by_head', 4, 'Ayala, Hannah', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-31 21:08:33'),
(34, 5, 'approved_by_head', 3, 'Aldana, Leo', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-31 21:08:33'),
(35, 5, 'approved_by_head', 1, 'Aldana, Alice', 'VALUES EDUCATION', 'CERTITUDE', NULL, 0, '2026-05-31 21:08:33'),
(36, 5, 'approved_by_head', 221, 'Quarbloy, Quarbloy', 'VALUES EDUCATION', 'COMPETENCE', NULL, 0, '2026-06-01 00:07:32');

-- --------------------------------------------------------

--
-- Table structure for table `trusted_devices`
--

CREATE TABLE `trusted_devices` (
  `id` int(10) UNSIGNED NOT NULL,
  `user_id` int(10) UNSIGNED NOT NULL,
  `token_hash` char(64) NOT NULL,
  `device_label` varchar(255) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `expires_at` datetime NOT NULL,
  `last_seen_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `confirmed_ip` varchar(45) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Stores trusted browser/device records. Expires after 7 days.';

--
-- Dumping data for table `trusted_devices`
--

INSERT INTO `trusted_devices` (`id`, `user_id`, `token_hash`, `device_label`, `created_at`, `expires_at`, `last_seen_at`, `confirmed_ip`) VALUES
(10, 3, '93b205874e1887696d580cd70ecd80b5cc1793977f342bb4e05f7405900d9ce7', 'Opera on Windows', '2026-05-18 03:49:45', '2026-05-24 21:49:45', '2026-05-18 03:49:45', '::1'),
(16, 2, '8f3ca1ad72509feb44230446cf1ecb8d673d7943516853dd8d9e00d4e8a02aa8', 'Opera on Windows', '2026-05-19 03:01:14', '2026-05-25 21:01:14', '2026-05-19 03:01:14', '::1'),
(17, 7, '697a310950a9e595128503f48427c26fb63babb062cfaa0d7f328cf8804dde06', 'Opera on Windows', '2026-05-19 03:07:29', '2026-05-25 21:07:29', '2026-05-19 03:07:29', '::1'),
(19, 8, '96128edcb4dee590048411208d3b8a4680ec3ac6b5e4092bc2c5c7f040990b10', 'Opera on Windows', '2026-05-19 03:11:46', '2026-05-25 21:11:46', '2026-05-19 03:11:46', '::1'),
(30, 11, 'd0e088e5f83d7c63eb2c528182dc46ed1848e3a1727b2c48b6305e57ffa0193d', 'Opera on Windows', '2026-05-19 15:56:58', '2026-05-26 15:56:58', '2026-05-19 15:56:58', '::1'),
(32, 14, 'd73efee72eb69b8853fac4e719175eba0081944c5e67a7dd0d0a56914f6f1437', 'Opera on Windows', '2026-05-19 16:06:59', '2026-05-26 16:06:59', '2026-05-19 16:06:59', '::1'),
(33, 13, '9871e06a3985b03a25ebe42ba164ccfc2cb5344d1f2d8eedd4a1bc72cb19a6e9', 'Opera on Windows', '2026-05-19 16:09:16', '2026-05-26 16:09:16', '2026-05-19 16:09:16', '::1'),
(38, 9, 'd87fe63a9b29ee9a17bcfc048e4b5094d6bce6e8351413b0b593a2e8a94aed75', 'Opera on Windows', '2026-05-20 00:24:11', '2026-05-27 00:24:11', '2026-05-20 00:24:11', '::1'),
(50, 6, 'edbf80c925fe0222b979ba42970f783614326722772ddcd3ffac9257d467cbc0', 'Opera on Windows', '2026-05-21 22:48:18', '2026-05-28 22:48:18', '2026-05-21 22:48:18', '::1'),
(54, 16, 'fd054455d386473a341962054b5ff0ae274b8938d077f8e140aa3335e27bd060', 'Opera on Windows', '2026-05-21 23:00:25', '2026-05-28 23:00:25', '2026-05-21 23:08:41', '::1'),
(61, 19, '9062e7d19b062eeb5c1c52ea2e34b04ac1d3fed42ac0ac9386f76a6179bff3b8', 'Opera on Windows', '2026-05-22 02:03:10', '2026-05-29 02:03:10', '2026-05-22 02:03:10', '::1'),
(62, 18, '20f39a2da76f47378c4d573cb2c669b837b102ab87e433e35d1c50da3770b35d', 'Opera on Windows', '2026-05-22 02:05:32', '2026-05-29 02:05:32', '2026-05-22 02:05:32', '::1'),
(76, 28, '89c004f20528129ac55593b3e9d040471fc365cacf6bca9fbc38698894f53e35', 'Opera on Windows', '2026-05-22 20:51:09', '2026-05-29 20:51:09', '2026-05-22 20:51:09', '::1'),
(95, 27, '932749c130a0284b1fd2659a7fc1ba7d8c6351393bc91cee7e5d1119e3563e94', 'Opera on Windows', '2026-05-24 15:18:09', '2026-05-31 15:18:09', '2026-05-24 15:19:17', '::1'),
(112, 29, 'f6c815809ac1885d2bf00a996e0887f0f2e03a0c9f9bbd1de1cd8ef04b8ed452', 'Opera on Windows', '2026-05-25 20:44:25', '2026-06-01 20:44:25', '2026-05-25 20:44:25', '::1'),
(119, 22, '011773a4964c38e2967032215333b1cc4fb8c73886c2b99dbf44c020fb86f79a', 'Opera on Windows', '2026-05-26 00:24:05', '2026-06-02 00:24:05', '2026-05-26 00:24:05', '::1'),
(144, 15, 'de5f5af06c94e4cfee563ccfa19e23225e8b37f59c59f0bc91e0e767c940757b', 'Safari on iPhone', '2026-05-26 04:04:32', '2026-06-02 04:04:32', '2026-06-01 05:09:39', '::1'),
(146, 23, '992e5b9e4ecb0baa70e6fc4ec4b2eda69921c8ff7d69805861978771551efee2', 'Opera on Windows', '2026-05-26 04:15:43', '2026-06-02 04:15:43', '2026-05-26 04:15:43', '::1'),
(147, 21, 'd8bc50c2e41ef6b208df3beed8180d1cee08a82ef3b1365462292c07b4827aba', 'Opera on Windows', '2026-05-26 04:22:15', '2026-06-02 04:22:15', '2026-05-26 04:22:15', '::1'),
(148, 25, '63a0127a2bbabc120bc7e42d2d6acc2862b5da38a85a1875065e05fee85d3d03', 'Chrome on Windows', '2026-05-26 04:25:23', '2026-06-02 04:25:23', '2026-05-26 04:25:23', '::1'),
(151, 472, '833b507b89505aabeab0e8617091864b31a8cdaa88518a6ebd00434d5f4a9d72', 'Opera on Windows', '2026-05-27 16:38:08', '2026-06-03 16:38:08', '2026-05-27 16:38:08', '::1'),
(152, 1, '0b38c44972601a513dc60f136362a8a580fa7a5a766d16abb097af1ab6e1573b', 'Opera on Windows', '2026-05-28 00:33:05', '2026-06-11 00:33:05', '2026-05-28 00:33:30', '::1'),
(153, 4, 'c07f173e432901e8c5960f6254d5cdba3c4f493fafdb6f14211829e81e41190f', 'Opera on Windows', '2026-05-28 00:34:06', '2026-06-11 00:34:06', '2026-05-31 18:22:48', '::1');

-- --------------------------------------------------------

--
-- Table structure for table `users`
--

CREATE TABLE `users` (
  `id` int(11) NOT NULL,
  `username` varchar(100) NOT NULL,
  `school_email` varchar(255) DEFAULT NULL COMMENT 'Auto-generated: firstname+lastname@sjc+role.edu.ph',
  `email` varchar(200) NOT NULL,
  `password_hash` varchar(255) NOT NULL,
  `role` enum('super_admin','teacher','cashier','registrar','principal','coordinator','admin','student','parent') NOT NULL DEFAULT 'student',
  `personal_email` varchar(255) DEFAULT NULL COMMENT 'Personal Gmail — OTP is sent here',
  `is_active` tinyint(1) NOT NULL DEFAULT 1 COMMENT '0 = deactivated by admin',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `is_first_login` tinyint(1) NOT NULL DEFAULT 1 COMMENT '1 = student must change password on first login',
  `account_status` enum('registered','enrolled','suspended','archived') NOT NULL DEFAULT 'registered' COMMENT 'registered = docs submitted, awaiting Registrar; enrolled = confirmed',
  `session_token` varchar(64) DEFAULT NULL COMMENT 'Active session token — replaced on every login to enforce single active session',
  `session_token_created_at` datetime DEFAULT NULL COMMENT 'When the current session token was issued',
  `employee_id` varchar(12) DEFAULT NULL COMMENT 'Auto-generated staff identifier for searching (e.g. EMP-4A9F2C)'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `users`
--

INSERT INTO `users` (`id`, `username`, `school_email`, `email`, `password_hash`, `role`, `personal_email`, `is_active`, `created_at`, `updated_at`, `is_first_login`, `account_status`, `session_token`, `session_token_created_at`, `employee_id`) VALUES
(1, 'Joshua Phillippe', 'admin@sjcadmin.edu.ph', 'admin@sjcadmin.edu.ph', '$2y$10$1ypuA92/8oF2n.Ako2ebJO8uR15CMio/ECs81.KGzDM.Pq/hLtUFi', 'admin', 'phillippejoshua275@gmail.com', 1, '2026-05-16 15:25:44', '2026-07-23 06:36:32', 0, 'registered', 'b16b3c3b6df53b6a6e8c3de18a11f5061c790b79b7e236943a43a7d21df7ba9a', '2026-07-23 14:36:32', 'EMP-7DCD85'),
(2, 'joshua.aguilar', 'joshua.aguilar@sjc.students.edu.ph', 'joshua.aguilar@sjc.students.edu.ph', '$2y$10$YWK2J1I9FTjJ82mIr56Xs.36Ml45pXaLSX5.nl.z85zcfWYYRbWpu', 'student', 'phillippejoshua27.5@gmail.com', 1, '2026-05-17 13:07:26', '2026-05-31 20:04:57', 1, '', 'b9e8bf39798c99e0fd873c8598b5f37e1ac852cb1571ba0ea4696f6d7775ab34', '2026-06-01 04:04:57', NULL),
(3, 'perlica.aguilar', 'perlica.aguilar@sjc.students.edu.ph', 'perlica.aguilar@sjc.students.edu.ph', '$2y$10$7Ph/sHfZ2apqPRksDBRb8.yLpcAD0hthW8tk.pbNQflbpGC7gxHVW', 'student', 'phillippejoshua27.5@gmail.com', 1, '2026-05-17 15:39:31', '2026-05-17 19:49:45', 1, 'registered', '15e6a5192d8439e7c79aae8e0f21022c774d1f73669116036be670bcde62dfc4', '2026-05-18 03:49:45', NULL),
(4, 'CarlosMendez', 'carlosmenendez@sjccashier.edu.ph', 'carlosmenendez@sjccashier.edu.ph', '$2y$10$NIo2i8dUb5t91DrIkhxL9eYKDUxuk2BrKh6cieXdyw1WS3ZFtFhWi', 'cashier', 'phillippejoshua275@gmail.com', 1, '2026-05-17 17:52:54', '2026-06-01 00:00:39', 1, 'registered', '49e3a8dd82150ae8c1154cea677d79c21add4ada26ece05d2f004cbbab66c401', '2026-06-01 08:00:39', 'EMP-FD855F'),
(5, 'artemis.wise', 'artemis.wise@sjc.students.edu.ph', 'artemis.wise@sjc.students.edu.ph', '$2y$10$83KJgfpoEWrL8N1WYhBsYe351pDtDlyvEAYfxeES//3ytEdgHoff6', 'student', 'phillippejoshua279@gmail.com', 1, '2026-05-18 18:15:32', '2026-05-18 18:15:32', 1, 'registered', NULL, NULL, NULL),
(6, 'wise.ramuela', 'wise.ramuela@sjc.students.edu.ph', 'wise.ramuela@sjc.students.edu.ph', '$2y$10$5vhC.x3R6eLRk/8olX3HyO1eIU4eJ2DIaJu6yIbc9AWquaGCp8YPy', 'student', 'phillippejoshua279@gmail.com', 1, '2026-05-18 18:54:42', '2026-05-21 14:48:18', 0, 'enrolled', '0eaf4483d115e651ac12d610173a153e36995cc0296143d10888eb2c42a7e042', '2026-05-21 22:48:18', NULL),
(7, 'sumalanka.cruz', 'sumalanka.cruz@sjc.students.edu.ph', 'sumalanka.cruz@sjc.students.edu.ph', '$2y$10$8.inZiKvnU7zpCCayshBbuL8SBX4oYvi15dzrXgdDm7yClGaNoHhq', 'student', 'phillippejoshua27.4@gmail.com', 1, '2026-05-18 19:04:57', '2026-05-18 19:07:29', 1, 'registered', '9d507b6e4d32636929df52ebd32727159f9b64723e5c0ebf30d84a547f0654dc', '2026-05-19 03:07:29', NULL),
(8, 'KurtM', 'kurtmichael@sjcadmin.edu.ph', 'kurtmichael@sjcadmin.edu.ph', '$2y$10$eLDsgY5yQqHQzJJCX23Tcu22O2bL6lxQf5eOCVV7DnVsvFg5.cnQK', 'admin', 'phillippejoshua2.74@gmail.com', 1, '2026-05-18 19:10:53', '2026-05-21 18:39:54', 1, 'registered', '97ad8b5e75c724150099c578e7019f8efa116d260255f25174dac170be3fd06e', '2026-05-19 03:11:46', 'EMP-05C3BE'),
(9, 'KeithC.', 'keithnacel@sjcregistrar.edu.ph', 'keithnacel@sjcregistrar.edu.ph', '$2y$10$tbRotLh7MLLWluxE0plVq.eiAXjZlHR/bapisxGihXQqgIEgZbt4a', 'registrar', 'phillippejoshua27.9@gmail.com', 0, '2026-05-19 07:51:10', '2026-05-21 18:39:54', 1, 'registered', 'f593b45716c7d700fde346cf5453d340991e27727592e2a7b8d58a660ebe2b8c', '2026-05-20 00:24:11', 'EMP-F4EC55'),
(11, 'KurtR', 'kurtrada@sjcprincipal.edu.ph', 'kurtrada@sjcprincipal.edu.ph', '$2y$10$/bDbGRV3qax23xdCWbTZBuVrfVrWTJLr5DP4Q2D.B1BiX/gQ7wsxC', 'principal', 'phillippejoshua27.5@gmail.com', 0, '2026-05-19 07:56:02', '2026-05-21 18:39:54', 1, 'registered', '6f9ddfba4d266ddf5593e7c437b9485f9f9b5b2d60b65ccfb500f56e71ab84e8', '2026-05-19 15:56:58', 'EMP-9FA8ED'),
(12, 'SherwinG', 'sherwingalang@sjccoordinator.edu.ph', 'sherwingalang@sjccoordinator.edu.ph', '$2y$10$3SBdjdMbPkp/2s.l81oDiucNu.fTB.wInj.RgXqfaCWO67DBnzoQa', 'coordinator', 'keithcanilang32@gmail.com', 0, '2026-05-19 07:58:19', '2026-05-21 18:39:54', 1, 'registered', NULL, NULL, 'EMP-D3A7F6'),
(13, 'JerichoO', 'carlosmichelle@sjccoordinator.edu.ph', 'carlosmichelle@sjccoordinator.edu.ph', '$2y$10$gdQoil9i0BpeTDzzzLIpH.vku4zKXnJKtjHEY2uelggNDpSFKHpZK', 'coordinator', 'columbina234@gmail.com', 0, '2026-05-19 07:59:18', '2026-05-21 18:39:54', 1, 'registered', 'da4150af060d18b7079acdb79ceb15ef825ad7478aa1d9ac1b37b215664e7f2b', '2026-05-19 16:09:16', 'EMP-67AE32'),
(14, 'DenverS', 'denversandcheese@sjcteacher.edu.ph', 'denversandcheese@sjcteacher.edu.ph', '$2y$10$1LJvi4xWfVVls/wqSkeJSO2MOvDHdYn2Yhy8zvGtopZR2mkPOe0kK', 'teacher', 'columbina23.4@gmail.com', 0, '2026-05-19 07:59:57', '2026-05-21 18:39:55', 1, 'registered', '4daeadf7792caddbf420ff035eab1ff1404fff2be8e1cca48773b064403441c9', '2026-05-19 16:06:59', 'EMP-01B7DA'),
(15, 'ArtemisArk', 'artemisarklight@sjcregistrar.edu.ph', 'artemisarklight@sjcregistrar.edu.ph', '$2y$10$5GFMhC6h2hNnhlQet2ZbduHfVGvSM60.ncnQXOCTBBsyAAjdcLkRe', 'registrar', 'phillippejoshua27.9@gmail.com', 1, '2026-05-20 15:16:54', '2026-06-01 00:01:12', 1, 'registered', '67557a8cf91be6d892db89de2ec106ae851872c6250e93b374f855ac154b3ee1', '2026-06-01 08:01:12', 'EMP-40FF43'),
(16, 'mabel.samonteza', 'mabel.samonteza@sjc.students.edu.ph', 'mabel.samonteza@sjc.students.edu.ph', '$2y$10$eOKB1mkSAP1WMzw5BkYLx.XOZwOmTNfqqk3cTwVsGjp3LFwaefPZ.', 'student', 'phillippejoshua2.79@gmail.com', 1, '2026-05-20 18:11:06', '2026-05-21 15:08:41', 1, 'registered', '95005739e238bb541105fff65d17ed900bdcb6b2481de5aee25de0372d64271f', '2026-05-21 23:08:41', NULL),
(17, 'PerliC', 'perlicaclara@sjcteacher.edu.ph', 'perlicaclara@sjcteacher.edu.ph', '$2y$10$j146s5njyPiOolIQDuondO9Q5rOI9hc6GWRUtE1BogmZkhbaiM15K', 'teacher', 'columbina23.4@gmail.com', 0, '2026-05-21 17:55:32', '2026-05-21 18:43:45', 1, 'registered', NULL, NULL, NULL),
(18, 'FelicitasG', 'felicitasgamuella@sjccoordinator.edu.ph', 'felicitasgamuella@sjccoordinator.edu.ph', '$2y$10$jclsJWeBVhDNJgXcEbO0de4QtcZcz2pa87H0gjj05AIm8QCHHbnOq', 'coordinator', 'columbina2.34@gmail.com', 0, '2026-05-21 17:56:28', '2026-05-21 18:43:53', 1, 'registered', '770b71d53de92051445ef5790300dc260afdd27ec1a610f5958923f7f8f0c72d', '2026-05-22 02:05:32', NULL),
(19, 'JoshuaA', 'joshuaaguilar@sjcprincipal.edu.ph', 'joshuaaguilar@sjcprincipal.edu.ph', '$2y$10$W2Rq1mhqZ/RIelStgG4WLuDL80U9PZyf/76yztxj5gr0M5HbI7iWi', 'principal', 'phillippejoshua2.79@gmail.com', 0, '2026-05-21 17:58:42', '2026-05-21 18:43:49', 1, 'registered', '5bd460d79dc3ecdc31860b30a5fd4a0b436efb54a7ceb2e27974b7c027b28cab', '2026-05-22 02:03:10', NULL),
(20, 'FiloQ', 'filomenileiaquerina@sjcteacher.edu.ph', 'filomenileiaquerina@sjcteacher.edu.ph', '$2y$10$O.Vqgb8SmgzHW0XuROm6weLOaG8st.qlwQ1EGFhxgYFHYIB5eeDee', 'teacher', 'columbina23.4@gmail.com', 0, '2026-05-21 18:04:45', '2026-05-21 18:43:43', 1, 'registered', NULL, NULL, NULL),
(21, 'SamonArgoy', 'samontezaargoyle@sjccoordinator.edu.ph', 'samontezaargoyle@sjccoordinator.edu.ph', '$2y$10$7TcxVf.EcSxh/ObqiynXtuWirFDnZ16PFW1nGjrcNLuf9aj2lHJtG', 'coordinator', 'columbin.a23.4@gmail.com', 1, '2026-05-21 18:44:54', '2026-06-01 00:06:34', 0, 'registered', 'ae5372744f546461151da895cfb95299a6ce12d7c9ff88633c9fde20c2437587', '2026-06-01 08:06:34', 'EMP-90FD41'),
(22, 'PerlicaN', 'perlicanalaya@sjcteacher.edu.ph', 'perlicanalaya@sjcteacher.edu.ph', '$2y$10$LEgMObrDcNOHP1XX0/a.Duubm8VZx5DpsiYxG/I.RupsnjGERuyw.', 'teacher', 'phillippejoshu.a279@gmail.com', 1, '2026-05-21 18:45:31', '2026-05-25 16:24:05', 0, 'registered', 'e70e58f82cee312ca2c327d256bdcb72f80f57736f17292148b154b1dc2441df', '2026-05-26 00:24:05', 'EMP-2F13AF'),
(23, 'JoshuaL', 'joshualupisan@sjcteacher.edu.ph', 'joshualupisan@sjcteacher.edu.ph', '$2y$10$r7jljtegooLOVx4YVNAnyex6gQXYVRsHvpO99JQ53TjDAtgN5.hke', 'teacher', 'phillippejoshua2.79@gmail.com', 1, '2026-05-21 18:46:02', '2026-06-01 00:05:19', 1, 'registered', '4a192019bd1107bbd99808fa45b2105583936565709dd945ee4d0f71eb94c5f4', '2026-06-01 08:05:19', 'EMP-7C1146'),
(25, 'JoshuaP', 'joshuaaguilar2@sjcprincipal.edu.ph', 'joshuaaguilar2@sjcprincipal.edu.ph', '$2y$10$3Uqa3F2VRzjujWCSWQeKFOy9ikjVCIUwriHgoXfGu3Ir7/Yq9g66W', 'principal', 'phillipp.ejoshua279@gmail.com', 1, '2026-05-21 18:46:44', '2026-06-01 00:07:28', 1, 'registered', '39588408006ba946331a16c5d3ed443fafa0a1a39c0203124797129e14caf2d0', '2026-06-01 08:07:28', 'EMP-0D9064'),
(27, 'quaterlyn.requiem', 'quaterlyn.requiem@sjc.students.edu.ph', 'quaterlyn.requiem@sjc.students.edu.ph', '$2y$10$4fPAK9P3/679rAo9C7um5.q3EBA5YQdI56S0OtPCYD6cEmD8.cOVG', 'student', 'p.hillippejoshua27.5@gmail.com', 1, '2026-05-22 11:20:51', '2026-05-24 07:19:17', 1, 'registered', '74fe28e56bd1439bfee8864c2ec63780a86abb8e3fda47e34c243cc07968e4dd', '2026-05-24 15:19:17', NULL),
(28, 'frieren.samontella', 'frieren.samontella@sjc.students.edu.ph', 'frieren.samontella@sjc.students.edu.ph', '$2y$10$CQkNazuvQYkHuYf1qnQaFOZ1iZUZ2c0Otz2OpcL4MTIG6oCgxA9Au', 'student', 'phillippe.joshua275@gmail.com', 1, '2026-05-22 12:49:19', '2026-05-22 12:51:09', 1, '', '38e9cd650483011dca667ba2621f407737fcb5ba89cd45aa6bddee5a14734ac9', '2026-05-22 20:51:09', NULL),
(29, 'suisei.hoshimachi', 'suisei.hoshimachi@sjc.students.edu.ph', 'suisei.hoshimachi@sjc.students.edu.ph', '$2y$10$H1t64vry27ORncKNGAiWguKvsReE4RmmalBCde8YEi2a7nQq1x1eu', 'student', 'columbina23.4@gmail.com', 1, '2026-05-24 07:51:18', '2026-05-25 12:44:25', 0, 'enrolled', 'f24580a7e4c2327be5fcc39aade3c19352c33a7582d95d880dfe8050df7f4154', '2026-05-25 20:44:25', NULL),
(30, 'andrei.paglinawan', 'andrei.paglinawan@sjc.students.edu.ph', 'andrei.paglinawan@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'andrei.paglinawan@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(31, 'john.orozco', 'john.orozco@sjc.students.edu.ph', 'john.orozco@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'john.orozco@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(32, 'danielle.bautista', 'danielle.bautista@sjc.students.edu.ph', 'danielle.bautista@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'danielle.bautista@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(33, 'philip.almeda', 'philip.almeda@sjc.students.edu.ph', 'philip.almeda@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'philip.almeda@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(34, 'eduardo.deguzman', 'eduardo.deguzman@sjc.students.edu.ph', 'eduardo.deguzman@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'eduardo.deguzman@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(35, 'lance.balboa', 'lance.balboa@sjc.students.edu.ph', 'lance.balboa@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'lance.balboa@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(36, 'angelica.bautista', 'angelica.bautista@sjc.students.edu.ph', 'angelica.bautista@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'angelica.bautista@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(37, 'veronica.dionisio', 'veronica.dionisio@sjc.students.edu.ph', 'veronica.dionisio@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'veronica.dionisio@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(38, 'angelica.deguzman', 'angelica.deguzman@sjc.students.edu.ph', 'angelica.deguzman@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'angelica.deguzman@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(39, 'maricel.balboa', 'maricel.balboa@sjc.students.edu.ph', 'maricel.balboa@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'maricel.balboa@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(40, 'diana.ferrer', 'diana.ferrer@sjc.students.edu.ph', 'diana.ferrer@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'diana.ferrer@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(41, 'david.padilla', 'david.padilla@sjc.students.edu.ph', 'david.padilla@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'david.padilla@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(42, 'lucia.mercado', 'lucia.mercado@sjc.students.edu.ph', 'lucia.mercado@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'lucia.mercado@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(43, 'carlo.beltran', 'carlo.beltran@sjc.students.edu.ph', 'carlo.beltran@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'carlo.beltran@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(44, 'lydia.barroga', 'lydia.barroga@sjc.students.edu.ph', 'lydia.barroga@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'lydia.barroga@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(45, 'caroline.benedicto', 'caroline.benedicto@sjc.students.edu.ph', 'caroline.benedicto@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'caroline.benedicto@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(46, 'dominic.villanueva', 'dominic.villanueva@sjc.students.edu.ph', 'dominic.villanueva@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'dominic.villanueva@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(47, 'monica.cabral', 'monica.cabral@sjc.students.edu.ph', 'monica.cabral@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'monica.cabral@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(48, 'angela.alejo', 'angela.alejo@sjc.students.edu.ph', 'angela.alejo@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'angela.alejo@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(49, 'lance.gonzales', 'lance.gonzales@sjc.students.edu.ph', 'lance.gonzales@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'lance.gonzales@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(50, 'matthew.dumlao', 'matthew.dumlao@sjc.students.edu.ph', 'matthew.dumlao@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'matthew.dumlao@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(51, 'peter.cabral', 'peter.cabral@sjc.students.edu.ph', 'peter.cabral@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'peter.cabral@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(52, 'emmanuel.paglinawan', 'emmanuel.paglinawan@sjc.students.edu.ph', 'emmanuel.paglinawan@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'emmanuel.paglinawan@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(53, 'dominic.macapagal', 'dominic.macapagal@sjc.students.edu.ph', 'dominic.macapagal@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'dominic.macapagal@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(54, 'gilbert.ferrer', 'gilbert.ferrer@sjc.students.edu.ph', 'gilbert.ferrer@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'gilbert.ferrer@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(55, 'emmanuel.cipriano', 'emmanuel.cipriano@sjc.students.edu.ph', 'emmanuel.cipriano@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'emmanuel.cipriano@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(56, 'hannah.borromeo', 'hannah.borromeo@sjc.students.edu.ph', 'hannah.borromeo@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'hannah.borromeo@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(57, 'julian.alcantara', 'julian.alcantara@sjc.students.edu.ph', 'julian.alcantara@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'julian.alcantara@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(58, 'lorenzo.barrientos', 'lorenzo.barrientos@sjc.students.edu.ph', 'lorenzo.barrientos@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'lorenzo.barrientos@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(59, 'leo.aldana', 'leo.aldana@sjc.students.edu.ph', 'leo.aldana@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'leo.aldana@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(60, 'charlene.padilla', 'charlene.padilla@sjc.students.edu.ph', 'charlene.padilla@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'charlene.padilla@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(61, 'elena.lim', 'elena.lim@sjc.students.edu.ph', 'elena.lim@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'elena.lim@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(62, 'vincent.duran', 'vincent.duran@sjc.students.edu.ph', 'vincent.duran@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'vincent.duran@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(63, 'frances.samonte', 'frances.samonte@sjc.students.edu.ph', 'frances.samonte@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'frances.samonte@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(64, 'hannah.ayala', 'hannah.ayala@sjc.students.edu.ph', 'hannah.ayala@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'hannah.ayala@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(65, 'sean.austria', 'sean.austria@sjc.students.edu.ph', 'sean.austria@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'sean.austria@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(66, 'diana.paglinawan', 'diana.paglinawan@sjc.students.edu.ph', 'diana.paglinawan@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'diana.paglinawan@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(67, 'grace.borromeo', 'grace.borromeo@sjc.students.edu.ph', 'grace.borromeo@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'grace.borromeo@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(68, 'sofia.dumlao', 'sofia.dumlao@sjc.students.edu.ph', 'sofia.dumlao@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'sofia.dumlao@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(69, 'mabel.ferrer', 'mabel.ferrer@sjc.students.edu.ph', 'mabel.ferrer@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'mabel.ferrer@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(70, 'stephen.velasco', 'stephen.velasco@sjc.students.edu.ph', 'stephen.velasco@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'stephen.velasco@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(71, 'julia.bautista', 'julia.bautista@sjc.students.edu.ph', 'julia.bautista@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'julia.bautista@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(72, 'anthony.reyes', 'anthony.reyes@sjc.students.edu.ph', 'anthony.reyes@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'anthony.reyes@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(73, 'leia.balboa', 'leia.balboa@sjc.students.edu.ph', 'leia.balboa@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'leia.balboa@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(74, 'daniel.gonzales', 'daniel.gonzales@sjc.students.edu.ph', 'daniel.gonzales@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'daniel.gonzales@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(75, 'angelica.esquivel', 'angelica.esquivel@sjc.students.edu.ph', 'angelica.esquivel@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'angelica.esquivel@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(76, 'natalie.dionisio', 'natalie.dionisio@sjc.students.edu.ph', 'natalie.dionisio@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'natalie.dionisio@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(77, 'tristan.tabios', 'tristan.tabios@sjc.students.edu.ph', 'tristan.tabios@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'tristan.tabios@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(78, 'david.benedicto', 'david.benedicto@sjc.students.edu.ph', 'david.benedicto@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'david.benedicto@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(79, 'hannah.cabrido', 'hannah.cabrido@sjc.students.edu.ph', 'hannah.cabrido@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'hannah.cabrido@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(80, 'irene.beltran', 'irene.beltran@sjc.students.edu.ph', 'irene.beltran@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'irene.beltran@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(81, 'martin.beltran', 'martin.beltran@sjc.students.edu.ph', 'martin.beltran@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'martin.beltran@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(82, 'marcus.duran', 'marcus.duran@sjc.students.edu.ph', 'marcus.duran@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'marcus.duran@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(83, 'matthew.almeda', 'matthew.almeda@sjc.students.edu.ph', 'matthew.almeda@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'matthew.almeda@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(84, 'eduardo.yap', 'eduardo.yap@sjc.students.edu.ph', 'eduardo.yap@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'eduardo.yap@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(85, 'jasmine.aldana', 'jasmine.aldana@sjc.students.edu.ph', 'jasmine.aldana@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'jasmine.aldana@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(86, 'julian.macaraeg', 'julian.macaraeg@sjc.students.edu.ph', 'julian.macaraeg@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'julian.macaraeg@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(87, 'lucia.yap', 'lucia.yap@sjc.students.edu.ph', 'lucia.yap@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'lucia.yap@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(88, 'luis.fontanilla', 'luis.fontanilla@sjc.students.edu.ph', 'luis.fontanilla@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'luis.fontanilla@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(89, 'karen.cayabyab', 'karen.cayabyab@sjc.students.edu.ph', 'karen.cayabyab@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'karen.cayabyab@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(90, 'irene.cayabyab', 'irene.cayabyab@sjc.students.edu.ph', 'irene.cayabyab@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'irene.cayabyab@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(91, 'andrea.bautista', 'andrea.bautista@sjc.students.edu.ph', 'andrea.bautista@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'andrea.bautista@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(92, 'raymond.almeda', 'raymond.almeda@sjc.students.edu.ph', 'raymond.almeda@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'raymond.almeda@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(93, 'sean.flores', 'sean.flores@sjc.students.edu.ph', 'sean.flores@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'sean.flores@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(94, 'victoria.gonzales', 'victoria.gonzales@sjc.students.edu.ph', 'victoria.gonzales@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'victoria.gonzales@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(95, 'kyle.fontanilla', 'kyle.fontanilla@sjc.students.edu.ph', 'kyle.fontanilla@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'kyle.fontanilla@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(96, 'victor.zamora', 'victor.zamora@sjc.students.edu.ph', 'victor.zamora@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'victor.zamora@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(97, 'kate.lim', 'kate.lim@sjc.students.edu.ph', 'kate.lim@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'kate.lim@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(98, 'kyle.macapagal', 'kyle.macapagal@sjc.students.edu.ph', 'kyle.macapagal@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'kyle.macapagal@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(99, 'alice.aldana', 'alice.aldana@sjc.students.edu.ph', 'alice.aldana@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'alice.aldana@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(100, 'david.lim', 'david.lim@sjc.students.edu.ph', 'david.lim@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'david.lim@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(101, 'jane.montoya', 'jane.montoya@sjc.students.edu.ph', 'jane.montoya@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'jane.montoya@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(102, 'caroline.benedicto102', 'caroline.benedicto102@sjc.students.edu.ph', 'caroline.benedicto102@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'caroline.benedicto102@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(103, 'jane.robles', 'jane.robles@sjc.students.edu.ph', 'jane.robles@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'jane.robles@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(104, 'anthony.cabrido', 'anthony.cabrido@sjc.students.edu.ph', 'anthony.cabrido@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'anthony.cabrido@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(105, 'sara.esquivel', 'sara.esquivel@sjc.students.edu.ph', 'sara.esquivel@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'sara.esquivel@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(106, 'ramon.zamora', 'ramon.zamora@sjc.students.edu.ph', 'ramon.zamora@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'ramon.zamora@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(107, 'leia.andres', 'leia.andres@sjc.students.edu.ph', 'leia.andres@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'leia.andres@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(108, 'lydia.aquino', 'lydia.aquino@sjc.students.edu.ph', 'lydia.aquino@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'lydia.aquino@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(109, 'richard.macaraeg', 'richard.macaraeg@sjc.students.edu.ph', 'richard.macaraeg@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'richard.macaraeg@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(110, 'sofia.tuason', 'sofia.tuason@sjc.students.edu.ph', 'sofia.tuason@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'sofia.tuason@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(111, 'hannah.austria', 'hannah.austria@sjc.students.edu.ph', 'hannah.austria@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'hannah.austria@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(112, 'marco.tabios', 'marco.tabios@sjc.students.edu.ph', 'marco.tabios@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'marco.tabios@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(113, 'alexandra.barrientos', 'alexandra.barrientos@sjc.students.edu.ph', 'alexandra.barrientos@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'alexandra.barrientos@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(114, 'anthony.padilla', 'anthony.padilla@sjc.students.edu.ph', 'anthony.padilla@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'anthony.padilla@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(115, 'anna.tuason', 'anna.tuason@sjc.students.edu.ph', 'anna.tuason@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'anna.tuason@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(116, 'joshua.dionisio', 'joshua.dionisio@sjc.students.edu.ph', 'joshua.dionisio@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'joshua.dionisio@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(117, 'theodore.alfonso', 'theodore.alfonso@sjc.students.edu.ph', 'theodore.alfonso@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'theodore.alfonso@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(118, 'raymond.cipriano', 'raymond.cipriano@sjc.students.edu.ph', 'raymond.cipriano@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'raymond.cipriano@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(119, 'paolo.tabios', 'paolo.tabios@sjc.students.edu.ph', 'paolo.tabios@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'paolo.tabios@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(120, 'kate.cipriano', 'kate.cipriano@sjc.students.edu.ph', 'kate.cipriano@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'kate.cipriano@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(121, 'monica.cervantes', 'monica.cervantes@sjc.students.edu.ph', 'monica.cervantes@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'monica.cervantes@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(122, 'maria.enriquez', 'maria.enriquez@sjc.students.edu.ph', 'maria.enriquez@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'maria.enriquez@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(123, 'amanda.beltran', 'amanda.beltran@sjc.students.edu.ph', 'amanda.beltran@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'amanda.beltran@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(124, 'maricel.barrientos', 'maricel.barrientos@sjc.students.edu.ph', 'maricel.barrientos@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'maricel.barrientos@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(125, 'miguel.fontanilla', 'miguel.fontanilla@sjc.students.edu.ph', 'miguel.fontanilla@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'miguel.fontanilla@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(126, 'bianca.dionisio', 'bianca.dionisio@sjc.students.edu.ph', 'bianca.dionisio@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'bianca.dionisio@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(127, 'xavier.esquivel', 'xavier.esquivel@sjc.students.edu.ph', 'xavier.esquivel@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'xavier.esquivel@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(128, 'jacob.yap', 'jacob.yap@sjc.students.edu.ph', 'jacob.yap@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'jacob.yap@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(129, 'angelica.duran', 'angelica.duran@sjc.students.edu.ph', 'angelica.duran@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'angelica.duran@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(130, 'victor.deguzman', 'victor.deguzman@sjc.students.edu.ph', 'victor.deguzman@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'victor.deguzman@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(131, 'beatrice.esquivel', 'beatrice.esquivel@sjc.students.edu.ph', 'beatrice.esquivel@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'beatrice.esquivel@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(132, 'neil.alfonso', 'neil.alfonso@sjc.students.edu.ph', 'neil.alfonso@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'neil.alfonso@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(133, 'christina.hernandez', 'christina.hernandez@sjc.students.edu.ph', 'christina.hernandez@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'christina.hernandez@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(134, 'rosa.danao', 'rosa.danao@sjc.students.edu.ph', 'rosa.danao@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'rosa.danao@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(135, 'oliver.tolentino', 'oliver.tolentino@sjc.students.edu.ph', 'oliver.tolentino@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'oliver.tolentino@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(136, 'leah.montoya', 'leah.montoya@sjc.students.edu.ph', 'leah.montoya@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'leah.montoya@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(137, 'natalie.robles', 'natalie.robles@sjc.students.edu.ph', 'natalie.robles@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'natalie.robles@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(138, 'stella.villanueva', 'stella.villanueva@sjc.students.edu.ph', 'stella.villanueva@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'stella.villanueva@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(139, 'samuel.tolentino', 'samuel.tolentino@sjc.students.edu.ph', 'samuel.tolentino@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'samuel.tolentino@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(140, 'neil.salas', 'neil.salas@sjc.students.edu.ph', 'neil.salas@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'neil.salas@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(141, 'xavier.dionisio', 'xavier.dionisio@sjc.students.edu.ph', 'xavier.dionisio@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'xavier.dionisio@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(142, 'sheila.alcantara', 'sheila.alcantara@sjc.students.edu.ph', 'sheila.alcantara@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'sheila.alcantara@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(143, 'xavier.danao', 'xavier.danao@sjc.students.edu.ph', 'xavier.danao@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'xavier.danao@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(144, 'patrick.salas', 'patrick.salas@sjc.students.edu.ph', 'patrick.salas@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'patrick.salas@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(145, 'patricia.macapagal', 'patricia.macapagal@sjc.students.edu.ph', 'patricia.macapagal@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'patricia.macapagal@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(146, 'rosa.devilla', 'rosa.devilla@sjc.students.edu.ph', 'rosa.devilla@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'rosa.devilla@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(147, 'peter.dionisio', 'peter.dionisio@sjc.students.edu.ph', 'peter.dionisio@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'peter.dionisio@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(148, 'beatrice.dionisio', 'beatrice.dionisio@sjc.students.edu.ph', 'beatrice.dionisio@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'beatrice.dionisio@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(149, 'katrina.doria', 'katrina.doria@sjc.students.edu.ph', 'katrina.doria@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'katrina.doria@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(150, 'ryan.aldana', 'ryan.aldana@sjc.students.edu.ph', 'ryan.aldana@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'ryan.aldana@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(151, 'gabriel.esteban', 'gabriel.esteban@sjc.students.edu.ph', 'gabriel.esteban@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'gabriel.esteban@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(152, 'michelle.bautista', 'michelle.bautista@sjc.students.edu.ph', 'michelle.bautista@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'michelle.bautista@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(153, 'katrina.orozco', 'katrina.orozco@sjc.students.edu.ph', 'katrina.orozco@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'katrina.orozco@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(154, 'alice.danao', 'alice.danao@sjc.students.edu.ph', 'alice.danao@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'alice.danao@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(155, 'lydia.santos', 'lydia.santos@sjc.students.edu.ph', 'lydia.santos@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'lydia.santos@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(156, 'ronald.esquivel', 'ronald.esquivel@sjc.students.edu.ph', 'ronald.esquivel@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'ronald.esquivel@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(157, 'beatrice.borja', 'beatrice.borja@sjc.students.edu.ph', 'beatrice.borja@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'beatrice.borja@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(158, 'tiffany.aldana', 'tiffany.aldana@sjc.students.edu.ph', 'tiffany.aldana@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'tiffany.aldana@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(159, 'jennifer.duran', 'jennifer.duran@sjc.students.edu.ph', 'jennifer.duran@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'jennifer.duran@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(160, 'claudine.cayabyab', 'claudine.cayabyab@sjc.students.edu.ph', 'claudine.cayabyab@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'claudine.cayabyab@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(161, 'luis.doria', 'luis.doria@sjc.students.edu.ph', 'luis.doria@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'luis.doria@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(162, 'tristan.esquivel', 'tristan.esquivel@sjc.students.edu.ph', 'tristan.esquivel@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'tristan.esquivel@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(163, 'marcus.enriquez', 'marcus.enriquez@sjc.students.edu.ph', 'marcus.enriquez@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'marcus.enriquez@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(164, 'leah.aldana', 'leah.aldana@sjc.students.edu.ph', 'leah.aldana@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'leah.aldana@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(165, 'francis.andres', 'francis.andres@sjc.students.edu.ph', 'francis.andres@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'francis.andres@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(166, 'nicole.esteban', 'nicole.esteban@sjc.students.edu.ph', 'nicole.esteban@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'nicole.esteban@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(167, 'reyna.soriano', 'reyna.soriano@sjc.students.edu.ph', 'reyna.soriano@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'reyna.soriano@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(168, 'theodore.borja', 'theodore.borja@sjc.students.edu.ph', 'theodore.borja@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'theodore.borja@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(169, 'angelo.fontanilla', 'angelo.fontanilla@sjc.students.edu.ph', 'angelo.fontanilla@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'angelo.fontanilla@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(170, 'gabriel.esteban170', 'gabriel.esteban170@sjc.students.edu.ph', 'gabriel.esteban170@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'gabriel.esteban170@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(171, 'patricia.barroga', 'patricia.barroga@sjc.students.edu.ph', 'patricia.barroga@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'patricia.barroga@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL);
INSERT INTO `users` (`id`, `username`, `school_email`, `email`, `password_hash`, `role`, `personal_email`, `is_active`, `created_at`, `updated_at`, `is_first_login`, `account_status`, `session_token`, `session_token_created_at`, `employee_id`) VALUES
(172, 'katrina.flores', 'katrina.flores@sjc.students.edu.ph', 'katrina.flores@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'katrina.flores@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(173, 'paolo.villanueva', 'paolo.villanueva@sjc.students.edu.ph', 'paolo.villanueva@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'paolo.villanueva@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(174, 'xavier.beltran', 'xavier.beltran@sjc.students.edu.ph', 'xavier.beltran@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'xavier.beltran@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(175, 'patricia.macaraeg', 'patricia.macaraeg@sjc.students.edu.ph', 'patricia.macaraeg@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'patricia.macaraeg@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(176, 'elena.villanueva', 'elena.villanueva@sjc.students.edu.ph', 'elena.villanueva@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'elena.villanueva@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(177, 'sofia.esteban', 'sofia.esteban@sjc.students.edu.ph', 'sofia.esteban@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'sofia.esteban@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(178, 'jasmine.fontanilla', 'jasmine.fontanilla@sjc.students.edu.ph', 'jasmine.fontanilla@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'jasmine.fontanilla@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(179, 'julia.villanueva', 'julia.villanueva@sjc.students.edu.ph', 'julia.villanueva@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'julia.villanueva@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(180, 'carlo.mercado', 'carlo.mercado@sjc.students.edu.ph', 'carlo.mercado@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'carlo.mercado@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(181, 'thomas.ayala', 'thomas.ayala@sjc.students.edu.ph', 'thomas.ayala@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'thomas.ayala@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(182, 'xavier.doria', 'xavier.doria@sjc.students.edu.ph', 'xavier.doria@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'xavier.doria@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(183, 'timothy.almeda', 'timothy.almeda@sjc.students.edu.ph', 'timothy.almeda@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'timothy.almeda@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(184, 'ramon.borja', 'ramon.borja@sjc.students.edu.ph', 'ramon.borja@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'ramon.borja@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(185, 'marcus.delotavo', 'marcus.delotavo@sjc.students.edu.ph', 'marcus.delotavo@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'marcus.delotavo@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(186, 'paolo.aquino', 'paolo.aquino@sjc.students.edu.ph', 'paolo.aquino@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'paolo.aquino@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(187, 'gabrielle.benedicto', 'gabrielle.benedicto@sjc.students.edu.ph', 'gabrielle.benedicto@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'gabrielle.benedicto@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(188, 'christian.andres', 'christian.andres@sjc.students.edu.ph', 'christian.andres@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'christian.andres@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(189, 'gabriel.esquivel', 'gabriel.esquivel@sjc.students.edu.ph', 'gabriel.esquivel@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'gabriel.esquivel@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(190, 'jade.alejo', 'jade.alejo@sjc.students.edu.ph', 'jade.alejo@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'jade.alejo@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(191, 'lydia.ayala', 'lydia.ayala@sjc.students.edu.ph', 'lydia.ayala@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'lydia.ayala@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(192, 'rafael.benedicto', 'rafael.benedicto@sjc.students.edu.ph', 'rafael.benedicto@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'rafael.benedicto@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(193, 'daniel.barroga', 'daniel.barroga@sjc.students.edu.ph', 'daniel.barroga@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'daniel.barroga@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(194, 'felix.paglinawan', 'felix.paglinawan@sjc.students.edu.ph', 'felix.paglinawan@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'felix.paglinawan@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(195, 'jessica.borja', 'jessica.borja@sjc.students.edu.ph', 'jessica.borja@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'jessica.borja@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(196, 'alexander.borja', 'alexander.borja@sjc.students.edu.ph', 'alexander.borja@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'alexander.borja@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(197, 'irene.reyes', 'irene.reyes@sjc.students.edu.ph', 'irene.reyes@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'irene.reyes@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(198, 'xavier.aldana', 'xavier.aldana@sjc.students.edu.ph', 'xavier.aldana@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'xavier.aldana@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(199, 'leia.alejo', 'leia.alejo@sjc.students.edu.ph', 'leia.alejo@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'leia.alejo@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(200, 'alexandra.esquivel', 'alexandra.esquivel@sjc.students.edu.ph', 'alexandra.esquivel@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'alexandra.esquivel@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(201, 'isabelle.salas', 'isabelle.salas@sjc.students.edu.ph', 'isabelle.salas@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'isabelle.salas@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(202, 'lisa.deguzman', 'lisa.deguzman@sjc.students.edu.ph', 'lisa.deguzman@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'lisa.deguzman@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(203, 'kevin.bautista', 'kevin.bautista@sjc.students.edu.ph', 'kevin.bautista@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'kevin.bautista@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(204, 'alexandra.zamora', 'alexandra.zamora@sjc.students.edu.ph', 'alexandra.zamora@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'alexandra.zamora@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(205, 'david.esquivel', 'david.esquivel@sjc.students.edu.ph', 'david.esquivel@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'david.esquivel@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(206, 'alice.macapagal', 'alice.macapagal@sjc.students.edu.ph', 'alice.macapagal@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'alice.macapagal@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(207, 'hannah.orozco', 'hannah.orozco@sjc.students.edu.ph', 'hannah.orozco@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'hannah.orozco@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(208, 'caroline.austria', 'caroline.austria@sjc.students.edu.ph', 'caroline.austria@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'caroline.austria@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(209, 'adriana.cabral', 'adriana.cabral@sjc.students.edu.ph', 'adriana.cabral@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'adriana.cabral@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(210, 'christian.balboa', 'christian.balboa@sjc.students.edu.ph', 'christian.balboa@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'christian.balboa@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(211, 'gabriel.cabrido', 'gabriel.cabrido@sjc.students.edu.ph', 'gabriel.cabrido@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'gabriel.cabrido@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(212, 'emma.duran', 'emma.duran@sjc.students.edu.ph', 'emma.duran@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'emma.duran@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(213, 'james.montoya', 'james.montoya@sjc.students.edu.ph', 'james.montoya@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'james.montoya@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(214, 'claire.macapagal', 'claire.macapagal@sjc.students.edu.ph', 'claire.macapagal@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'claire.macapagal@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(215, 'sofia.aldana', 'sofia.aldana@sjc.students.edu.ph', 'sofia.aldana@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'sofia.aldana@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(216, 'karen.zamora', 'karen.zamora@sjc.students.edu.ph', 'karen.zamora@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'karen.zamora@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(217, 'lourdes.dumlao', 'lourdes.dumlao@sjc.students.edu.ph', 'lourdes.dumlao@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'lourdes.dumlao@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(218, 'paolo.cabrido', 'paolo.cabrido@sjc.students.edu.ph', 'paolo.cabrido@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'paolo.cabrido@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(219, 'enrique.alcantara', 'enrique.alcantara@sjc.students.edu.ph', 'enrique.alcantara@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'enrique.alcantara@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(220, 'raphael.macapagal', 'raphael.macapagal@sjc.students.edu.ph', 'raphael.macapagal@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'raphael.macapagal@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(221, 'angelica.fontanilla', 'angelica.fontanilla@sjc.students.edu.ph', 'angelica.fontanilla@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'angelica.fontanilla@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(222, 'lourdes.gonzales', 'lourdes.gonzales@sjc.students.edu.ph', 'lourdes.gonzales@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'lourdes.gonzales@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(223, 'claudine.esquivel', 'claudine.esquivel@sjc.students.edu.ph', 'claudine.esquivel@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'claudine.esquivel@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(224, 'timothy.cabral', 'timothy.cabral@sjc.students.edu.ph', 'timothy.cabral@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'timothy.cabral@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(225, 'mabel.orozco', 'mabel.orozco@sjc.students.edu.ph', 'mabel.orozco@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'mabel.orozco@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(226, 'tiffany.paglinawan', 'tiffany.paglinawan@sjc.students.edu.ph', 'tiffany.paglinawan@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'tiffany.paglinawan@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(227, 'sofia.bautista', 'sofia.bautista@sjc.students.edu.ph', 'sofia.bautista@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'sofia.bautista@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(228, 'joseph.samonte', 'joseph.samonte@sjc.students.edu.ph', 'joseph.samonte@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'joseph.samonte@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(229, 'paolo.ferrer', 'paolo.ferrer@sjc.students.edu.ph', 'paolo.ferrer@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'paolo.ferrer@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(230, 'angela.borromeo', 'angela.borromeo@sjc.students.edu.ph', 'angela.borromeo@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'angela.borromeo@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(231, 'luis.macapagal', 'luis.macapagal@sjc.students.edu.ph', 'luis.macapagal@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'luis.macapagal@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(232, 'dominic.padilla', 'dominic.padilla@sjc.students.edu.ph', 'dominic.padilla@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'dominic.padilla@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(233, 'julia.soriano', 'julia.soriano@sjc.students.edu.ph', 'julia.soriano@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'julia.soriano@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(234, 'hector.doria', 'hector.doria@sjc.students.edu.ph', 'hector.doria@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'hector.doria@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(235, 'benedict.devilla', 'benedict.devilla@sjc.students.edu.ph', 'benedict.devilla@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'benedict.devilla@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(236, 'adriana.abella', 'adriana.abella@sjc.students.edu.ph', 'adriana.abella@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'adriana.abella@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(237, 'leia.tolentino', 'leia.tolentino@sjc.students.edu.ph', 'leia.tolentino@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'leia.tolentino@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(238, 'gilbert.velasco', 'gilbert.velasco@sjc.students.edu.ph', 'gilbert.velasco@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'gilbert.velasco@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(239, 'lance.borromeo', 'lance.borromeo@sjc.students.edu.ph', 'lance.borromeo@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'lance.borromeo@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(240, 'ramon.cabral', 'ramon.cabral@sjc.students.edu.ph', 'ramon.cabral@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'ramon.cabral@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(241, 'christina.deguzman', 'christina.deguzman@sjc.students.edu.ph', 'christina.deguzman@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'christina.deguzman@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(242, 'adrian.borja', 'adrian.borja@sjc.students.edu.ph', 'adrian.borja@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'adrian.borja@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(243, 'michael.almeda', 'michael.almeda@sjc.students.edu.ph', 'michael.almeda@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'michael.almeda@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(244, 'cecilia.dumlao', 'cecilia.dumlao@sjc.students.edu.ph', 'cecilia.dumlao@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'cecilia.dumlao@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(245, 'donna.danao', 'donna.danao@sjc.students.edu.ph', 'donna.danao@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'donna.danao@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(246, 'rosa.danao246', 'rosa.danao246@sjc.students.edu.ph', 'rosa.danao246@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'rosa.danao246@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(247, 'anthony.tabios', 'anthony.tabios@sjc.students.edu.ph', 'anthony.tabios@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'anthony.tabios@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(248, 'hannah.delotavo', 'hannah.delotavo@sjc.students.edu.ph', 'hannah.delotavo@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'hannah.delotavo@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(249, 'raphael.alfonso', 'raphael.alfonso@sjc.students.edu.ph', 'raphael.alfonso@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'raphael.alfonso@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(250, 'stephen.danao', 'stephen.danao@sjc.students.edu.ph', 'stephen.danao@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'stephen.danao@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(251, 'philip.tabios', 'philip.tabios@sjc.students.edu.ph', 'philip.tabios@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'philip.tabios@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(252, 'kevin.tuason', 'kevin.tuason@sjc.students.edu.ph', 'kevin.tuason@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'kevin.tuason@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(253, 'ronald.mercado', 'ronald.mercado@sjc.students.edu.ph', 'ronald.mercado@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'ronald.mercado@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(254, 'gabriel.robles', 'gabriel.robles@sjc.students.edu.ph', 'gabriel.robles@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'gabriel.robles@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(255, 'natalie.borja', 'natalie.borja@sjc.students.edu.ph', 'natalie.borja@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'natalie.borja@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(256, 'matthew.borja', 'matthew.borja@sjc.students.edu.ph', 'matthew.borja@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'matthew.borja@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(257, 'francis.barroga', 'francis.barroga@sjc.students.edu.ph', 'francis.barroga@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'francis.barroga@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(258, 'dominic.tuason', 'dominic.tuason@sjc.students.edu.ph', 'dominic.tuason@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'dominic.tuason@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(259, 'maria.barrientos', 'maria.barrientos@sjc.students.edu.ph', 'maria.barrientos@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'maria.barrientos@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(260, 'stella.duran', 'stella.duran@sjc.students.edu.ph', 'stella.duran@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'stella.duran@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(261, 'katrina.velasco', 'katrina.velasco@sjc.students.edu.ph', 'katrina.velasco@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'katrina.velasco@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(262, 'sara.cipriano', 'sara.cipriano@sjc.students.edu.ph', 'sara.cipriano@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'sara.cipriano@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(263, 'laura.villanueva', 'laura.villanueva@sjc.students.edu.ph', 'laura.villanueva@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'laura.villanueva@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(264, 'jerome.soriano', 'jerome.soriano@sjc.students.edu.ph', 'jerome.soriano@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'jerome.soriano@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(265, 'abigail.cervantes', 'abigail.cervantes@sjc.students.edu.ph', 'abigail.cervantes@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'abigail.cervantes@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(266, 'xavier.tan', 'xavier.tan@sjc.students.edu.ph', 'xavier.tan@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'xavier.tan@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(267, 'joanna.barrientos', 'joanna.barrientos@sjc.students.edu.ph', 'joanna.barrientos@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'joanna.barrientos@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(268, 'aaron.yap', 'aaron.yap@sjc.students.edu.ph', 'aaron.yap@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'aaron.yap@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(269, 'neil.paglinawan', 'neil.paglinawan@sjc.students.edu.ph', 'neil.paglinawan@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'neil.paglinawan@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(270, 'caroline.padilla', 'caroline.padilla@sjc.students.edu.ph', 'caroline.padilla@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'caroline.padilla@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(271, 'hector.doria271', 'hector.doria271@sjc.students.edu.ph', 'hector.doria271@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'hector.doria271@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(272, 'oliver.hernandez', 'oliver.hernandez@sjc.students.edu.ph', 'oliver.hernandez@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'oliver.hernandez@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(273, 'stella.padilla', 'stella.padilla@sjc.students.edu.ph', 'stella.padilla@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'stella.padilla@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(274, 'paul.abella', 'paul.abella@sjc.students.edu.ph', 'paul.abella@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'paul.abella@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(275, 'michael.salas', 'michael.salas@sjc.students.edu.ph', 'michael.salas@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'michael.salas@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(276, 'melissa.dumlao', 'melissa.dumlao@sjc.students.edu.ph', 'melissa.dumlao@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'melissa.dumlao@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(277, 'rafael.santos', 'rafael.santos@sjc.students.edu.ph', 'rafael.santos@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'rafael.santos@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(278, 'elena.yap', 'elena.yap@sjc.students.edu.ph', 'elena.yap@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'elena.yap@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(279, 'dominic.deguzman', 'dominic.deguzman@sjc.students.edu.ph', 'dominic.deguzman@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'dominic.deguzman@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(280, 'danielle.ayala', 'danielle.ayala@sjc.students.edu.ph', 'danielle.ayala@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'danielle.ayala@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(281, 'alicia.barrientos', 'alicia.barrientos@sjc.students.edu.ph', 'alicia.barrientos@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'alicia.barrientos@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(282, 'alexandra.cervantes', 'alexandra.cervantes@sjc.students.edu.ph', 'alexandra.cervantes@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'alexandra.cervantes@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(283, 'bianca.barroga', 'bianca.barroga@sjc.students.edu.ph', 'bianca.barroga@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'bianca.barroga@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(284, 'jacob.barroga', 'jacob.barroga@sjc.students.edu.ph', 'jacob.barroga@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'jacob.barroga@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(285, 'charlene.montoya', 'charlene.montoya@sjc.students.edu.ph', 'charlene.montoya@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'charlene.montoya@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(286, 'marcus.alcantara', 'marcus.alcantara@sjc.students.edu.ph', 'marcus.alcantara@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'marcus.alcantara@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(287, 'theodore.velasco', 'theodore.velasco@sjc.students.edu.ph', 'theodore.velasco@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'theodore.velasco@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(288, 'monica.borja', 'monica.borja@sjc.students.edu.ph', 'monica.borja@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'monica.borja@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(289, 'jennifer.montoya', 'jennifer.montoya@sjc.students.edu.ph', 'jennifer.montoya@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'jennifer.montoya@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(290, 'carlo.samonte', 'carlo.samonte@sjc.students.edu.ph', 'carlo.samonte@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'carlo.samonte@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(291, 'alicia.gonzales', 'alicia.gonzales@sjc.students.edu.ph', 'alicia.gonzales@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'alicia.gonzales@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(292, 'theodore.austria', 'theodore.austria@sjc.students.edu.ph', 'theodore.austria@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'theodore.austria@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(293, 'leia.borja', 'leia.borja@sjc.students.edu.ph', 'leia.borja@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'leia.borja@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(294, 'gilbert.austria', 'gilbert.austria@sjc.students.edu.ph', 'gilbert.austria@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'gilbert.austria@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(295, 'miguel.macapagal', 'miguel.macapagal@sjc.students.edu.ph', 'miguel.macapagal@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'miguel.macapagal@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(296, 'patricia.deguzman', 'patricia.deguzman@sjc.students.edu.ph', 'patricia.deguzman@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'patricia.deguzman@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(297, 'jessica.austria', 'jessica.austria@sjc.students.edu.ph', 'jessica.austria@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'jessica.austria@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(298, 'oliver.tuason', 'oliver.tuason@sjc.students.edu.ph', 'oliver.tuason@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'oliver.tuason@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(299, 'felix.danao', 'felix.danao@sjc.students.edu.ph', 'felix.danao@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'felix.danao@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(300, 'richard.doria', 'richard.doria@sjc.students.edu.ph', 'richard.doria@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'richard.doria@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(301, 'claire.delotavo', 'claire.delotavo@sjc.students.edu.ph', 'claire.delotavo@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'claire.delotavo@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(302, 'sandra.barroga', 'sandra.barroga@sjc.students.edu.ph', 'sandra.barroga@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'sandra.barroga@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(303, 'enrique.soriano', 'enrique.soriano@sjc.students.edu.ph', 'enrique.soriano@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'enrique.soriano@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(304, 'isabel.dumlao', 'isabel.dumlao@sjc.students.edu.ph', 'isabel.dumlao@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'isabel.dumlao@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(305, 'adrian.tabios', 'adrian.tabios@sjc.students.edu.ph', 'adrian.tabios@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'adrian.tabios@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(306, 'monica.borromeo', 'monica.borromeo@sjc.students.edu.ph', 'monica.borromeo@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'monica.borromeo@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(307, 'victoria.duran', 'victoria.duran@sjc.students.edu.ph', 'victoria.duran@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'victoria.duran@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(308, 'cecilia.tolentino', 'cecilia.tolentino@sjc.students.edu.ph', 'cecilia.tolentino@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'cecilia.tolentino@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(309, 'sandra.esteban', 'sandra.esteban@sjc.students.edu.ph', 'sandra.esteban@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'sandra.esteban@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(310, 'victor.tabios', 'victor.tabios@sjc.students.edu.ph', 'victor.tabios@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'victor.tabios@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(311, 'lucia.santos', 'lucia.santos@sjc.students.edu.ph', 'lucia.santos@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'lucia.santos@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(312, 'lydia.aldana', 'lydia.aldana@sjc.students.edu.ph', 'lydia.aldana@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'lydia.aldana@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(313, 'sean.cervantes', 'sean.cervantes@sjc.students.edu.ph', 'sean.cervantes@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'sean.cervantes@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(314, 'stella.esteban', 'stella.esteban@sjc.students.edu.ph', 'stella.esteban@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'stella.esteban@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(315, 'eliza.orozco', 'eliza.orozco@sjc.students.edu.ph', 'eliza.orozco@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'eliza.orozco@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(316, 'xavier.paglinawan', 'xavier.paglinawan@sjc.students.edu.ph', 'xavier.paglinawan@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'xavier.paglinawan@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(317, 'reyna.tolentino', 'reyna.tolentino@sjc.students.edu.ph', 'reyna.tolentino@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'reyna.tolentino@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(318, 'stella.macapagal', 'stella.macapagal@sjc.students.edu.ph', 'stella.macapagal@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'stella.macapagal@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(319, 'patrick.flores', 'patrick.flores@sjc.students.edu.ph', 'patrick.flores@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'patrick.flores@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(320, 'john.borromeo', 'john.borromeo@sjc.students.edu.ph', 'john.borromeo@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'john.borromeo@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(321, 'caroline.lim', 'caroline.lim@sjc.students.edu.ph', 'caroline.lim@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'caroline.lim@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(322, 'mabel.zamora', 'mabel.zamora@sjc.students.edu.ph', 'mabel.zamora@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'mabel.zamora@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(323, 'peter.reyes', 'peter.reyes@sjc.students.edu.ph', 'peter.reyes@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'peter.reyes@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(324, 'philip.aldana', 'philip.aldana@sjc.students.edu.ph', 'philip.aldana@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'philip.aldana@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(325, 'matthew.enriquez', 'matthew.enriquez@sjc.students.edu.ph', 'matthew.enriquez@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'matthew.enriquez@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(326, 'bianca.cipriano', 'bianca.cipriano@sjc.students.edu.ph', 'bianca.cipriano@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'bianca.cipriano@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(327, 'michelle.benedicto', 'michelle.benedicto@sjc.students.edu.ph', 'michelle.benedicto@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'michelle.benedicto@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(328, 'rosa.samonte', 'rosa.samonte@sjc.students.edu.ph', 'rosa.samonte@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'rosa.samonte@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(329, 'joseph.mercado', 'joseph.mercado@sjc.students.edu.ph', 'joseph.mercado@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'joseph.mercado@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(330, 'gilbert.alcantara', 'gilbert.alcantara@sjc.students.edu.ph', 'gilbert.alcantara@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'gilbert.alcantara@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(331, 'lorraine.doria', 'lorraine.doria@sjc.students.edu.ph', 'lorraine.doria@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'lorraine.doria@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(332, 'patrick.villanueva', 'patrick.villanueva@sjc.students.edu.ph', 'patrick.villanueva@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'patrick.villanueva@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(333, 'gabriel.paglinawan', 'gabriel.paglinawan@sjc.students.edu.ph', 'gabriel.paglinawan@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'gabriel.paglinawan@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(334, 'aaron.fontanilla', 'aaron.fontanilla@sjc.students.edu.ph', 'aaron.fontanilla@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'aaron.fontanilla@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(335, 'leo.barroga', 'leo.barroga@sjc.students.edu.ph', 'leo.barroga@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'leo.barroga@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(336, 'timothy.yap', 'timothy.yap@sjc.students.edu.ph', 'timothy.yap@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'timothy.yap@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(337, 'veronica.ayala', 'veronica.ayala@sjc.students.edu.ph', 'veronica.ayala@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'veronica.ayala@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(338, 'claire.montoya', 'claire.montoya@sjc.students.edu.ph', 'claire.montoya@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'claire.montoya@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(339, 'claire.tuason', 'claire.tuason@sjc.students.edu.ph', 'claire.tuason@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'claire.tuason@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(340, 'angelo.flores', 'angelo.flores@sjc.students.edu.ph', 'angelo.flores@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'angelo.flores@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(341, 'reyna.esquivel', 'reyna.esquivel@sjc.students.edu.ph', 'reyna.esquivel@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'reyna.esquivel@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(342, 'laura.aldana', 'laura.aldana@sjc.students.edu.ph', 'laura.aldana@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'laura.aldana@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(343, 'anthony.macaraeg', 'anthony.macaraeg@sjc.students.edu.ph', 'anthony.macaraeg@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'anthony.macaraeg@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(344, 'william.borja', 'william.borja@sjc.students.edu.ph', 'william.borja@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'william.borja@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(345, 'kevin.alfonso', 'kevin.alfonso@sjc.students.edu.ph', 'kevin.alfonso@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'kevin.alfonso@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL);
INSERT INTO `users` (`id`, `username`, `school_email`, `email`, `password_hash`, `role`, `personal_email`, `is_active`, `created_at`, `updated_at`, `is_first_login`, `account_status`, `session_token`, `session_token_created_at`, `employee_id`) VALUES
(346, 'cecilia.duran', 'cecilia.duran@sjc.students.edu.ph', 'cecilia.duran@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'cecilia.duran@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(347, 'gerald.alejo', 'gerald.alejo@sjc.students.edu.ph', 'gerald.alejo@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'gerald.alejo@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(348, 'patricia.balboa', 'patricia.balboa@sjc.students.edu.ph', 'patricia.balboa@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'patricia.balboa@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(349, 'kevin.deguzman', 'kevin.deguzman@sjc.students.edu.ph', 'kevin.deguzman@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'kevin.deguzman@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(350, 'dominic.duran', 'dominic.duran@sjc.students.edu.ph', 'dominic.duran@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'dominic.duran@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(351, 'lisa.cipriano', 'lisa.cipriano@sjc.students.edu.ph', 'lisa.cipriano@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'lisa.cipriano@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(352, 'aaron.orozco', 'aaron.orozco@sjc.students.edu.ph', 'aaron.orozco@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'aaron.orozco@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(353, 'robert.macaraeg', 'robert.macaraeg@sjc.students.edu.ph', 'robert.macaraeg@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'robert.macaraeg@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(354, 'teresa.flores', 'teresa.flores@sjc.students.edu.ph', 'teresa.flores@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'teresa.flores@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(355, 'vincent.devilla', 'vincent.devilla@sjc.students.edu.ph', 'vincent.devilla@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'vincent.devilla@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(356, 'bianca.alfonso', 'bianca.alfonso@sjc.students.edu.ph', 'bianca.alfonso@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'bianca.alfonso@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(357, 'tristan.doria', 'tristan.doria@sjc.students.edu.ph', 'tristan.doria@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'tristan.doria@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(358, 'paul.benedicto', 'paul.benedicto@sjc.students.edu.ph', 'paul.benedicto@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'paul.benedicto@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(359, 'dominic.flores', 'dominic.flores@sjc.students.edu.ph', 'dominic.flores@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'dominic.flores@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(360, 'lorenzo.barrientos360', 'lorenzo.barrientos360@sjc.students.edu.ph', 'lorenzo.barrientos360@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'lorenzo.barrientos360@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(361, 'lisa.fontanilla', 'lisa.fontanilla@sjc.students.edu.ph', 'lisa.fontanilla@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'lisa.fontanilla@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(362, 'miguel.delotavo', 'miguel.delotavo@sjc.students.edu.ph', 'miguel.delotavo@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'miguel.delotavo@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(363, 'theodore.cayabyab', 'theodore.cayabyab@sjc.students.edu.ph', 'theodore.cayabyab@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'theodore.cayabyab@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(364, 'john.soriano', 'john.soriano@sjc.students.edu.ph', 'john.soriano@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'john.soriano@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(365, 'thomas.danao', 'thomas.danao@sjc.students.edu.ph', 'thomas.danao@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'thomas.danao@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(366, 'victor.cipriano', 'victor.cipriano@sjc.students.edu.ph', 'victor.cipriano@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'victor.cipriano@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(367, 'nathan.danao', 'nathan.danao@sjc.students.edu.ph', 'nathan.danao@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'nathan.danao@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(368, 'leia.danao', 'leia.danao@sjc.students.edu.ph', 'leia.danao@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'leia.danao@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(369, 'ronald.tabios', 'ronald.tabios@sjc.students.edu.ph', 'ronald.tabios@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'ronald.tabios@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(370, 'jennifer.borja', 'jennifer.borja@sjc.students.edu.ph', 'jennifer.borja@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'jennifer.borja@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(371, 'isabel.danao', 'isabel.danao@sjc.students.edu.ph', 'isabel.danao@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'isabel.danao@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(372, 'laura.cayabyab', 'laura.cayabyab@sjc.students.edu.ph', 'laura.cayabyab@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'laura.cayabyab@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(373, 'mabel.macapagal', 'mabel.macapagal@sjc.students.edu.ph', 'mabel.macapagal@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'mabel.macapagal@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(374, 'leah.paglinawan', 'leah.paglinawan@sjc.students.edu.ph', 'leah.paglinawan@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'leah.paglinawan@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(375, 'ramon.andres', 'ramon.andres@sjc.students.edu.ph', 'ramon.andres@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'ramon.andres@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(376, 'jessica.beltran', 'jessica.beltran@sjc.students.edu.ph', 'jessica.beltran@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'jessica.beltran@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(377, 'stella.doria', 'stella.doria@sjc.students.edu.ph', 'stella.doria@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'stella.doria@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(378, 'sofia.beltran', 'sofia.beltran@sjc.students.edu.ph', 'sofia.beltran@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'sofia.beltran@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(379, 'nicole.ferrer', 'nicole.ferrer@sjc.students.edu.ph', 'nicole.ferrer@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'nicole.ferrer@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(380, 'teresa.dionisio', 'teresa.dionisio@sjc.students.edu.ph', 'teresa.dionisio@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'teresa.dionisio@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(381, 'lydia.barroga381', 'lydia.barroga381@sjc.students.edu.ph', 'lydia.barroga381@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'lydia.barroga381@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(382, 'gilbert.alejo', 'gilbert.alejo@sjc.students.edu.ph', 'gilbert.alejo@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'gilbert.alejo@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(383, 'tristan.bautista', 'tristan.bautista@sjc.students.edu.ph', 'tristan.bautista@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'tristan.bautista@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(384, 'elisa.barroga', 'elisa.barroga@sjc.students.edu.ph', 'elisa.barroga@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'elisa.barroga@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(385, 'john.dumlao', 'john.dumlao@sjc.students.edu.ph', 'john.dumlao@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'john.dumlao@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(386, 'leo.duran', 'leo.duran@sjc.students.edu.ph', 'leo.duran@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'leo.duran@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(387, 'ramon.salas', 'ramon.salas@sjc.students.edu.ph', 'ramon.salas@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'ramon.salas@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(388, 'carlo.cipriano', 'carlo.cipriano@sjc.students.edu.ph', 'carlo.cipriano@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'carlo.cipriano@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(389, 'alexander.navarro', 'alexander.navarro@sjc.students.edu.ph', 'alexander.navarro@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'alexander.navarro@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(390, 'julia.padilla', 'julia.padilla@sjc.students.edu.ph', 'julia.padilla@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'julia.padilla@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(391, 'elisa.tolentino', 'elisa.tolentino@sjc.students.edu.ph', 'elisa.tolentino@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'elisa.tolentino@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(392, 'marcus.cayabyab', 'marcus.cayabyab@sjc.students.edu.ph', 'marcus.cayabyab@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'marcus.cayabyab@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(393, 'angelo.fontanilla393', 'angelo.fontanilla393@sjc.students.edu.ph', 'angelo.fontanilla393@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'angelo.fontanilla393@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(394, 'beatrice.dumlao', 'beatrice.dumlao@sjc.students.edu.ph', 'beatrice.dumlao@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'beatrice.dumlao@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(395, 'matthew.alfonso', 'matthew.alfonso@sjc.students.edu.ph', 'matthew.alfonso@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'matthew.alfonso@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(396, 'caroline.robles', 'caroline.robles@sjc.students.edu.ph', 'caroline.robles@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'caroline.robles@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(397, 'laura.tuason', 'laura.tuason@sjc.students.edu.ph', 'laura.tuason@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'laura.tuason@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(398, 'michelle.zamora', 'michelle.zamora@sjc.students.edu.ph', 'michelle.zamora@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'michelle.zamora@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(399, 'stella.esquivel', 'stella.esquivel@sjc.students.edu.ph', 'stella.esquivel@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'stella.esquivel@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(400, 'jennifer.almeda', 'jennifer.almeda@sjc.students.edu.ph', 'jennifer.almeda@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'jennifer.almeda@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(401, 'alicia.padilla', 'alicia.padilla@sjc.students.edu.ph', 'alicia.padilla@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'alicia.padilla@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(402, 'philip.alejo', 'philip.alejo@sjc.students.edu.ph', 'philip.alejo@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'philip.alejo@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(403, 'julian.dionisio', 'julian.dionisio@sjc.students.edu.ph', 'julian.dionisio@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'julian.dionisio@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(404, 'christina.reyes', 'christina.reyes@sjc.students.edu.ph', 'christina.reyes@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'christina.reyes@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(405, 'maricel.cayabyab', 'maricel.cayabyab@sjc.students.edu.ph', 'maricel.cayabyab@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'maricel.cayabyab@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(406, 'donna.cipriano', 'donna.cipriano@sjc.students.edu.ph', 'donna.cipriano@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'donna.cipriano@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(407, 'lance.yap', 'lance.yap@sjc.students.edu.ph', 'lance.yap@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'lance.yap@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(408, 'stella.duran408', 'stella.duran408@sjc.students.edu.ph', 'stella.duran408@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'stella.duran408@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(409, 'luis.alejo', 'luis.alejo@sjc.students.edu.ph', 'luis.alejo@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'luis.alejo@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(410, 'miguel.enriquez', 'miguel.enriquez@sjc.students.edu.ph', 'miguel.enriquez@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'miguel.enriquez@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(411, 'lourdes.paglinawan', 'lourdes.paglinawan@sjc.students.edu.ph', 'lourdes.paglinawan@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'lourdes.paglinawan@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(412, 'marco.beltran', 'marco.beltran@sjc.students.edu.ph', 'marco.beltran@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'marco.beltran@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(413, 'gilbert.dionisio', 'gilbert.dionisio@sjc.students.edu.ph', 'gilbert.dionisio@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'gilbert.dionisio@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(414, 'michael.navarro', 'michael.navarro@sjc.students.edu.ph', 'michael.navarro@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'michael.navarro@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(415, 'andrei.reyes', 'andrei.reyes@sjc.students.edu.ph', 'andrei.reyes@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'andrei.reyes@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(416, 'kevin.beltran', 'kevin.beltran@sjc.students.edu.ph', 'kevin.beltran@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'kevin.beltran@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(417, 'paula.duran', 'paula.duran@sjc.students.edu.ph', 'paula.duran@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'paula.duran@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(418, 'ryan.tan', 'ryan.tan@sjc.students.edu.ph', 'ryan.tan@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'ryan.tan@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(419, 'william.andres', 'william.andres@sjc.students.edu.ph', 'william.andres@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'william.andres@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(420, 'melissa.devilla', 'melissa.devilla@sjc.students.edu.ph', 'melissa.devilla@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'melissa.devilla@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(421, 'james.robles', 'james.robles@sjc.students.edu.ph', 'james.robles@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'james.robles@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(422, 'leo.cayabyab', 'leo.cayabyab@sjc.students.edu.ph', 'leo.cayabyab@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'leo.cayabyab@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(423, 'philip.flores', 'philip.flores@sjc.students.edu.ph', 'philip.flores@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'philip.flores@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(424, 'jane.macapagal', 'jane.macapagal@sjc.students.edu.ph', 'jane.macapagal@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'jane.macapagal@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(425, 'grace.bautista', 'grace.bautista@sjc.students.edu.ph', 'grace.bautista@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'grace.bautista@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(426, 'gerald.alejo426', 'gerald.alejo426@sjc.students.edu.ph', 'gerald.alejo426@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'gerald.alejo426@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(427, 'vanessa.salas', 'vanessa.salas@sjc.students.edu.ph', 'vanessa.salas@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'vanessa.salas@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(428, 'stella.alfonso', 'stella.alfonso@sjc.students.edu.ph', 'stella.alfonso@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'stella.alfonso@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(429, 'thomas.padilla', 'thomas.padilla@sjc.students.edu.ph', 'thomas.padilla@sjc.students.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'student', 'thomas.padilla@gmail.com', 1, '2026-05-24 23:00:00', '2026-05-24 23:00:00', 1, 'enrolled', NULL, NULL, NULL),
(430, 'MariaS', 'mariasantos@sjcteacher.edu.ph', 'mariasantos@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'maria.santos@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:22:46', 1, 'registered', NULL, NULL, 'EMP-A10001'),
(431, 'JoseR', 'josereyes@sjcteacher.edu.ph', 'josereyes@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'jose.reyes@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:22:32', 1, 'registered', NULL, NULL, 'EMP-A10002'),
(432, 'AnaC', 'anacruz@sjcteacher.edu.ph', 'anacruz@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'ana.cruz@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:03:20', 1, 'registered', NULL, NULL, 'EMP-A10003'),
(433, 'RobertoM', 'robertomendoza@sjcteacher.edu.ph', 'robertomendoza@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'roberto.mendoza@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:23:09', 1, 'registered', NULL, NULL, 'EMP-A10004'),
(434, 'LindaF', 'lindaflores@sjcteacher.edu.ph', 'lindaflores@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'linda.flores@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:22:35', 1, 'registered', NULL, NULL, 'EMP-A10005'),
(435, 'CarlosT', 'carlostorres@sjcteacher.edu.ph', 'carlostorres@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'carlos.torres@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:03:31', 1, 'registered', NULL, NULL, 'EMP-A10006'),
(436, 'RosalieB', 'rosaliebautista@sjcteacher.edu.ph', 'rosaliebautista@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'rosalie.bautista@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:23:14', 1, 'registered', NULL, NULL, 'EMP-A10007'),
(437, 'MiguelV', 'miguelvillanueva@sjcteacher.edu.ph', 'miguelvillanueva@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'miguel.villanueva@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:22:54', 1, 'registered', NULL, NULL, 'EMP-A10008'),
(438, 'TeresaL', 'teresalim@sjcteacher.edu.ph', 'teresalim@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'teresa.lim@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:23:18', 1, 'registered', NULL, NULL, 'EMP-A10009'),
(439, 'AntonioG', 'antoniogarcia@sjcteacher.edu.ph', 'antoniogarcia@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'antonio.garcia@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:03:22', 1, 'registered', NULL, NULL, 'EMP-A10010'),
(440, 'CarmeniD', 'carmenidelarosa@sjcteacher.edu.ph', 'carmenidelarosa@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'carmeni.delarosa@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:03:34', 1, 'registered', NULL, NULL, 'EMP-A10011'),
(441, 'BernardoA', 'bernardoaquino@sjcteacher.edu.ph', 'bernardoaquino@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'bernardo.aquino@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:03:28', 1, 'registered', NULL, NULL, 'EMP-A10012'),
(442, 'EvelynP', 'evelynpascual@sjcteacher.edu.ph', 'evelynpascual@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'evelyn.pascual@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:21:17', 1, 'registered', NULL, NULL, 'EMP-A10013'),
(443, 'RamonN', 'ramonnavarro@sjcteacher.edu.ph', 'ramonnavarro@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'ramon.navarro@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:23:02', 1, 'registered', NULL, NULL, 'EMP-A10014'),
(444, 'ClaritaO', 'claritaocampo@sjcteacher.edu.ph', 'claritaocampo@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'clarita.ocampo@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:04:54', 1, 'registered', NULL, NULL, 'EMP-A10015'),
(445, 'FernandoD', 'fernandodiaz@sjcteacher.edu.ph', 'fernandodiaz@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'fernando.diaz@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:21:20', 1, 'registered', NULL, NULL, 'EMP-A10016'),
(446, 'LourdesC', 'lourdescastillo@sjcteacher.edu.ph', 'lourdescastillo@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'lourdes.castillo@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:22:40', 1, 'registered', NULL, NULL, 'EMP-A10017'),
(447, 'EduardoR', 'eduardoramos@sjcteacher.edu.ph', 'eduardoramos@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'eduardo.ramos@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:05:09', 1, 'registered', NULL, NULL, 'EMP-A10018'),
(448, 'MarisolE', 'marisolespinosa@sjcteacher.edu.ph', 'marisolespinosa@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'marisol.espinosa@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:22:49', 1, 'registered', NULL, NULL, 'EMP-A10019'),
(449, 'RodolfoM', 'rodolfomedina@sjcteacher.edu.ph', 'rodolfomedina@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'rodolfo.medina@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:23:12', 1, 'registered', NULL, NULL, 'EMP-A10020'),
(450, 'GloriaH', 'gloriahernandez@sjcteacher.edu.ph', 'gloriahernandez@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'gloria.hernandez@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:21:25', 1, 'registered', NULL, NULL, 'EMP-A10021'),
(451, 'ArthurSal', 'arthursalvador@sjcteacher.edu.ph', 'arthursalvador@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'arthur.salvador@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:03:24', 1, 'registered', NULL, NULL, 'EMP-A10022'),
(452, 'NormaV', 'normavelasquez@sjcteacher.edu.ph', 'normavelasquez@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'norma.velasquez@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:22:57', 1, 'registered', NULL, NULL, 'EMP-A10023'),
(453, 'DanielB', 'danielbuenaventura@sjcteacher.edu.ph', 'danielbuenaventura@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'daniel.buenaventura@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:05:01', 1, 'registered', NULL, NULL, 'EMP-A10024'),
(454, 'StellaM', 'stellamiranda@sjcteacher.edu.ph', 'stellamiranda@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'stella.miranda@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:23:16', 1, 'registered', NULL, NULL, 'EMP-A10025'),
(455, 'RicardoP', 'ricardoperez@sjcteacher.edu.ph', 'ricardoperez@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'ricardo.perez@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:23:07', 1, 'registered', NULL, NULL, 'EMP-A10026'),
(456, 'CeciliaA', 'ceciliaaguilar@sjcteacher.edu.ph', 'ceciliaaguilar@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'cecilia.aguilar@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:03:37', 1, 'registered', NULL, NULL, 'EMP-A10027'),
(457, 'ManuelC', 'manuelcabrera@sjcteacher.edu.ph', 'manuelcabrera@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'manuel.cabrera@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:22:42', 1, 'registered', NULL, NULL, 'EMP-A10028'),
(458, 'ImeldalD', 'imeldadelacruz@sjcteacher.edu.ph', 'imeldadelacruz@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'imelda.delacruz@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:22:29', 1, 'registered', NULL, NULL, 'EMP-A10029'),
(459, 'VictorE', 'victorenriquez@sjcteacher.edu.ph', 'victorenriquez@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'victor.enriquez@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:23:21', 1, 'registered', NULL, NULL, 'EMP-A10030'),
(460, 'PaulinaR', 'paulinarobles@sjcteacher.edu.ph', 'paulinarobles@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'paulina.robles@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:23:00', 1, 'registered', NULL, NULL, 'EMP-A10031'),
(461, 'HectorS', 'hectorsoriano@sjcteacher.edu.ph', 'hectorsoriano@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'hector.soriano@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:22:27', 1, 'registered', NULL, NULL, 'EMP-A10032'),
(462, 'MercedesT', 'mercedestan@sjcteacher.edu.ph', 'mercedestan@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'mercedes.tan@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:22:51', 1, 'registered', NULL, NULL, 'EMP-A10033'),
(463, 'AlfonsoQ', 'alfonsoquizon@sjcteacher.edu.ph', 'alfonsoquizon@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'alfonso.quizon@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:03:17', 1, 'registered', NULL, NULL, 'EMP-A10034'),
(464, 'ConchitaU', 'conchitaureta@sjcteacher.edu.ph', 'conchitaureta@sjcteacher.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'teacher', 'conchita.ureta@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-25 09:04:57', 1, 'registered', NULL, NULL, 'EMP-A10035'),
(465, 'ElenaZ', 'elenazabala@sjccoordinator.edu.ph', 'elenazabala@sjccoordinator.edu.ph', '$2y$10$ytP6lGj/FXwKsl1yCTcDhOKlWm4ZVsWwFgpjNzhGbvPhqnp7E5sv2', 'coordinator', 'co.lumbina234@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-31 19:20:16', 0, 'registered', 'afd686ccbd71337eca6788664cd41809ceb9e231a439570ac1abcf3ac457e169', '2026-06-01 03:20:16', 'EMP-B10001'),
(466, 'RonaldoI', 'ronaldoilagan@sjccoordinator.edu.ph', 'ronaldoilagan@sjccoordinator.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'coordinator', 'columbin.a23.4@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-31 15:13:31', 1, 'registered', NULL, NULL, 'EMP-B10002'),
(467, 'MaricelJ', 'mariceljimenez@sjccoordinator.edu.ph', 'mariceljimenez@sjccoordinator.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'coordinator', 'colu.m.bina23.4@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-31 15:10:32', 1, 'registered', NULL, NULL, 'EMP-B10003'),
(468, 'BenedictO', 'benedictong@sjccoordinator.edu.ph', 'benedictong@sjccoordinator.edu.ph', '$2y$10$Y6ddIlFm4s2Nstxld5G85.bBjdnPmF8oKDadqUzZ5csdc1L8QmIje', 'coordinator', 'columbi.na23.4@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-31 19:20:52', 0, 'registered', '1cfdcb9015eeb1997f079431171d7c6dfcecc2244f4874519697849a3b5ecaec', '2026-06-01 03:20:52', 'EMP-B10004'),
(469, 'JessicaB', 'jessicabulan@sjccoordinator.edu.ph', 'jessicabulan@sjccoordinator.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'coordinator', 'c.olumbina23.4@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-31 15:09:58', 1, 'registered', NULL, NULL, 'EMP-B10005'),
(470, 'RenatoSeg', 'renatosegovia@sjccoordinator.edu.ph', 'renatosegovia@sjccoordinator.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'coordinator', 'c.olum.bin.a23.4@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-31 15:10:43', 1, 'registered', NULL, NULL, 'EMP-B10006'),
(471, 'LorenaY', 'lorenayap@sjccoordinator.edu.ph', 'lorenayap@sjccoordinator.edu.ph', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'coordinator', 'c.olum.bin.a234@gmail.com', 1, '2026-05-25 00:00:00', '2026-05-31 15:10:12', 1, 'registered', NULL, NULL, 'EMP-B10007'),
(472, 'aki.rosenthal', 'aki.rosenthal@sjc.students.edu.ph', 'aki.rosenthal@sjc.students.edu.ph', '$2y$10$AefNKHZO3//HA4GB4WCvneABX4k.YptlJtmk5GgrAMd/GQafIY7Ae', 'student', 'columbin.a234@gmail.com', 1, '2026-05-25 16:36:47', '2026-05-31 06:51:13', 1, 'enrolled', 'd88fa05252bc08854af105bd516ccf00393c0d545e1cb0c7540e513a5440034e', '2026-05-31 14:51:13', NULL),
(473, 'saikken.sakami', 'saikken.sakami@sjc.students.edu.ph', 'saikken.sakami@sjc.students.edu.ph', '$2y$10$04PewKbiS/G1G/cHYW0Y9eXclgAvWbFQpXwUguL4XFqIE8SLlMhv2', 'student', 'phillippe.joshua27.9@gmail.com', 1, '2026-05-28 18:58:08', '2026-05-31 10:43:22', 0, 'enrolled', '91d8d6b4e379c31d4143b2f6eb9a4c86995cbbc43a66b2bce2b24383e6eca7d6', '2026-05-31 18:43:22', NULL),
(475, 'keith.canilang', 'keith.canilang@sjc.students.edu.ph', 'keith.canilang@sjc.students.edu.ph', '$2y$10$dw3SqdACv5eQZ9X/CZk74..G/rl.j4MhiCf94KsGd8s8EAhyqGYbG', 'student', 'colu.mbina2.34@gmail.com', 1, '2026-05-31 10:00:02', '2026-05-31 10:26:51', 1, 'enrolled', '2b9f0c22530696df6077f5a5fb8184825e978cebb607f02b4d4adc213f349449', '2026-05-31 18:26:51', NULL),
(477, 'queerbalasin.saichou', 'queerbalasin.saichou@sjc.students.edu.ph', 'queerbalasin.saichou@sjc.students.edu.ph', '$2y$10$NAivYbYdVRF2Fdw8/ZGhrujDJc8sFcpvl6uwUiscbpgH2wRzp2rSm', 'student', 'ph.illippejoshua27.9@gmail.com', 1, '2026-05-31 20:06:38', '2026-05-31 20:22:00', 1, 'enrolled', '4ad89873ac1b8cdd9237568fabb0f7db8eb2e1d1d826d151deacccdd4a988204', '2026-06-01 04:07:28', NULL),
(478, 'quarbloy.quarbloy', 'quarbloy.quarbloy@sjc.students.edu.ph', 'quarbloy.quarbloy@sjc.students.edu.ph', '$2y$10$KPcQoKMfoY6uDhhq4Zo/xuQRIkYlOH3dBwnKCuZ2vrhe1C3BZjG06', 'student', 'phillippejoshu.a27.9@gmail.com', 1, '2026-05-31 23:55:46', '2026-06-01 00:01:53', 1, 'enrolled', 'f492132a9da0987122b74ccb9e0a55a97daf6dd30218a3229b63a4efee2eefa2', '2026-06-01 07:56:53', NULL);

-- --------------------------------------------------------

--
-- Stand-in structure for view `v_curriculum_assignments`
-- (See below for the actual view)
--
CREATE TABLE `v_curriculum_assignments` (
`curriculum_id` int(11)
,`school_year_id` int(11)
,`school_year` varchar(20)
,`grade_level_id` int(11)
,`grade_level` varchar(50)
,`grade_num` tinyint(4)
,`subject_id` int(11)
,`subject_name` varchar(200)
,`subject_code` varchar(20)
,`units` decimal(4,2)
,`hours_per_week` tinyint(4)
,`is_active` tinyint(1)
,`coordinator_id` int(11)
,`coordinator_name` varchar(201)
,`coordinator_employee_id` varchar(50)
,`coordinator_email` varchar(255)
,`assigned_by_principal_id` int(11)
,`assigned_by_name` varchar(201)
,`assigned_at` datetime
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `v_enrollment_counts`
-- (See below for the actual view)
--
CREATE TABLE `v_enrollment_counts` (
`school_year_id` int(11)
,`school_year` varchar(20)
,`total` bigint(21)
,`registered_count` decimal(23,0)
,`enrolled_count` decimal(23,0)
,`unregistered_count` decimal(23,0)
,`archived_count` decimal(23,0)
,`new_students` decimal(23,0)
,`transferees` decimal(23,0)
,`returning_students` decimal(23,0)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `v_registrar_students`
-- (See below for the actual view)
--
CREATE TABLE `v_registrar_students` (
`student_id` int(11)
,`lrn` varchar(12)
,`first_name` varchar(100)
,`middle_name` varchar(100)
,`last_name` varchar(100)
,`full_name` varchar(302)
,`sex` enum('male','female')
,`date_of_birth` date
,`place_of_birth` varchar(255)
,`nationality` varchar(100)
,`religion` varchar(100)
,`address` varchar(500)
,`city` varchar(150)
,`province` varchar(150)
,`zip_code` char(4)
,`personal_email` varchar(255)
,`enrollment_type` enum('new','transferee','returning')
,`grade_level` varchar(50)
,`grade_level_id` int(11)
,`enrollment_id` int(11)
,`enrollment_status` enum('pending','registered','enrolled','unregistered','archived')
,`school_year_id` int(11)
,`school_year` varchar(20)
,`section_sy_id` int(11)
,`section_name` varchar(100)
,`enrollment_notes` text
,`unregistered_reason` varchar(500)
,`processed_by` int(11)
,`processed_at` datetime
,`reference_number` varchar(30)
,`form137_status` enum('missing','uploaded','onsite')
,`form137_file_path` varchar(1000)
,`birth_cert_status` enum('missing','uploaded','onsite')
,`birth_cert_file_path` varchar(1000)
,`registration_status` enum('pending','registered','verified','enrolled','archived','rejected')
,`created_at` timestamp
,`updated_at` timestamp
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `v_section_slots`
-- (See below for the actual view)
--
CREATE TABLE `v_section_slots` (
`section_sy_id` int(11)
,`school_year` varchar(20)
,`grade_level` varchar(50)
,`section_name` varchar(100)
,`capacity` int(11)
,`enrolled_count` int(11)
,`available_slots` bigint(12)
,`status` enum('open','closed','archived')
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `v_student_guardian_overview`
-- (See below for the actual view)
--
CREATE TABLE `v_student_guardian_overview` (
`sg_id` int(11)
,`student_id` int(11)
,`student_name` varchar(201)
,`guardian_id` int(11)
,`guardian_name` varchar(255)
,`guardian_type` enum('biological_parent','adoptive_parent','foster_guardian','court_appointed_guardian','step_parent','grandparent','uncle_aunt','sibling','other')
,`relationship_label` varchar(100)
,`custody_type` enum('sole_custody','joint_custody','split_custody','restricted_custody','none')
,`is_primary` tinyint(1)
,`emergency_priority` tinyint(3)
,`pickup_authorized` tinyint(1)
,`mobile_number` varchar(15)
,`email_address` varchar(255)
,`is_deceased` tinyint(1)
,`is_restricted` tinyint(1)
,`is_active` tinyint(1)
,`notes` text
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `v_student_registration_summary`
-- (See below for the actual view)
--
CREATE TABLE `v_student_registration_summary` (
`student_id` int(11)
,`lrn` varchar(12)
,`full_name` varchar(302)
,`sex` enum('male','female')
,`date_of_birth` date
,`grade_level` varchar(50)
,`enrollment_type` enum('new','transferee','returning')
,`registration_status` enum('pending','registered','verified','enrolled','archived','rejected')
,`personal_email` varchar(255)
,`school_year` varchar(20)
,`applied_at` timestamp
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `v_submission_overview`
-- (See below for the actual view)
--
CREATE TABLE `v_submission_overview` (
`submission_id` int(11)
,`reference_number` varchar(30)
,`student_id` int(11)
,`lrn` varchar(12)
,`full_name` varchar(201)
,`personal_email` varchar(255)
,`enrollment_type` enum('new','transferee','returning')
,`grade_level` varchar(50)
,`school_year` varchar(20)
,`form137_status` enum('missing','uploaded','onsite')
,`birth_cert_status` enum('missing','uploaded','onsite')
,`registration_status` enum('pending','registered','verified','enrolled','archived','rejected')
,`account_status` enum('registered','enrolled','suspended','archived')
,`privacy_accepted` tinyint(1)
,`info_accuracy_accepted` tinyint(1)
,`submitted_at` timestamp
);

-- --------------------------------------------------------

--
-- Table structure for table `wallet_transactions`
--

CREATE TABLE `wallet_transactions` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `admin_id` int(11) DEFAULT NULL COMMENT 'admin who performed the adjustment',
  `type` enum('credit','debit') NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `balance_after` decimal(10,2) NOT NULL,
  `note` varchar(255) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Ledger of wallet balance adjustments';

--
-- Dumping data for table `wallet_transactions`
--

INSERT INTO `wallet_transactions` (`id`, `student_id`, `admin_id`, `type`, `amount`, `balance_after`, `note`, `created_at`) VALUES
(1, 73, 1, 'credit', 250.00, 250.00, NULL, '2026-07-23 17:30:32'),
(2, 73, 1, 'debit', 250.00, 0.00, NULL, '2026-07-23 17:30:37');

-- --------------------------------------------------------

--
-- Structure for view `v_curriculum_assignments`
--
DROP TABLE IF EXISTS `v_curriculum_assignments`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_curriculum_assignments`  AS SELECT `cur`.`id` AS `curriculum_id`, `sy`.`id` AS `school_year_id`, `sy`.`label` AS `school_year`, `gl`.`id` AS `grade_level_id`, `gl`.`display_name` AS `grade_level`, `gl`.`level` AS `grade_num`, `subj`.`id` AS `subject_id`, `subj`.`name` AS `subject_name`, `subj`.`code` AS `subject_code`, `subj`.`units` AS `units`, `subj`.`hours_per_week` AS `hours_per_week`, `cur`.`is_active` AS `is_active`, `cur`.`coordinator_id` AS `coordinator_id`, concat(`coord`.`first_name`,' ',`coord`.`last_name`) AS `coordinator_name`, `coord`.`employee_id` AS `coordinator_employee_id`, `u`.`school_email` AS `coordinator_email`, `cur`.`assigned_by` AS `assigned_by_principal_id`, concat(`pr`.`first_name`,' ',`pr`.`last_name`) AS `assigned_by_name`, `cur`.`assigned_at` AS `assigned_at` FROM ((((((`curriculum` `cur` join `school_years` `sy` on(`sy`.`id` = `cur`.`school_year_id`)) join `grade_levels` `gl` on(`gl`.`id` = `cur`.`grade_level_id`)) join `subjects` `subj` on(`subj`.`id` = `cur`.`subject_id`)) left join `coordinators` `coord` on(`coord`.`id` = `cur`.`coordinator_id`)) left join `users` `u` on(`u`.`id` = `coord`.`user_id`)) left join `principals` `pr` on(`pr`.`id` = `cur`.`assigned_by`)) WHERE `cur`.`is_active` = 1 AND `subj`.`is_archived` = 0 ;

-- --------------------------------------------------------

--
-- Structure for view `v_enrollment_counts`
--
DROP TABLE IF EXISTS `v_enrollment_counts`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_enrollment_counts`  AS SELECT `e`.`school_year_id` AS `school_year_id`, `sy`.`label` AS `school_year`, count(0) AS `total`, sum(`e`.`status` = 'pending') AS `registered_count`, sum(`e`.`status` = 'enrolled') AS `enrolled_count`, sum(`e`.`status` = 'unregistered') AS `unregistered_count`, sum(`e`.`status` = 'archived') AS `archived_count`, sum(`e`.`enrollment_type` = 'new') AS `new_students`, sum(`e`.`enrollment_type` = 'transferee') AS `transferees`, sum(`e`.`enrollment_type` = 'returning') AS `returning_students` FROM (`enrollments` `e` join `school_years` `sy` on(`sy`.`id` = `e`.`school_year_id`)) GROUP BY `e`.`school_year_id`, `sy`.`label` ;

-- --------------------------------------------------------

--
-- Structure for view `v_registrar_students`
--
DROP TABLE IF EXISTS `v_registrar_students`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_registrar_students`  AS SELECT `s`.`id` AS `student_id`, `s`.`lrn` AS `lrn`, `s`.`first_name` AS `first_name`, `s`.`middle_name` AS `middle_name`, `s`.`last_name` AS `last_name`, concat(`s`.`first_name`,' ',coalesce(concat(`s`.`middle_name`,' '),''),`s`.`last_name`) AS `full_name`, `s`.`sex` AS `sex`, `s`.`date_of_birth` AS `date_of_birth`, `s`.`place_of_birth` AS `place_of_birth`, `s`.`nationality` AS `nationality`, `s`.`religion` AS `religion`, `s`.`address` AS `address`, `s`.`city` AS `city`, `s`.`province` AS `province`, `s`.`zip_code` AS `zip_code`, `s`.`personal_email` AS `personal_email`, `s`.`enrollment_type` AS `enrollment_type`, `gl`.`display_name` AS `grade_level`, `gl`.`id` AS `grade_level_id`, `e`.`id` AS `enrollment_id`, `e`.`status` AS `enrollment_status`, `e`.`school_year_id` AS `school_year_id`, `sy`.`label` AS `school_year`, `e`.`section_sy_id` AS `section_sy_id`, `sec`.`name` AS `section_name`, `e`.`notes` AS `enrollment_notes`, `e`.`unregistered_reason` AS `unregistered_reason`, `e`.`processed_by` AS `processed_by`, `e`.`processed_at` AS `processed_at`, `ss`.`reference_number` AS `reference_number`, `ss`.`form137_status` AS `form137_status`, `ss`.`form137_file_path` AS `form137_file_path`, `ss`.`birth_cert_status` AS `birth_cert_status`, `ss`.`birth_cert_file_path` AS `birth_cert_file_path`, `s`.`registration_status` AS `registration_status`, `s`.`created_at` AS `created_at`, `s`.`updated_at` AS `updated_at` FROM ((((((`students` `s` left join `grade_levels` `gl` on(`gl`.`id` = `s`.`grade_level_id`)) left join `enrollments` `e` on(`e`.`student_id` = `s`.`id`)) left join `school_years` `sy` on(`sy`.`id` = `e`.`school_year_id`)) left join `section_school_years` `ssy` on(`ssy`.`id` = `e`.`section_sy_id`)) left join `sections` `sec` on(`sec`.`id` = `ssy`.`section_id`)) left join `student_submissions` `ss` on(`ss`.`student_id` = `s`.`id` and `ss`.`school_year_id` = `e`.`school_year_id`)) ;

-- --------------------------------------------------------

--
-- Structure for view `v_section_slots`
--
DROP TABLE IF EXISTS `v_section_slots`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_section_slots`  AS SELECT `ssy`.`id` AS `section_sy_id`, `sy`.`label` AS `school_year`, `gl`.`display_name` AS `grade_level`, `s`.`name` AS `section_name`, `ssy`.`capacity` AS `capacity`, `ssy`.`enrolled_count` AS `enrolled_count`, `ssy`.`capacity`- `ssy`.`enrolled_count` AS `available_slots`, `ssy`.`status` AS `status` FROM (((`section_school_years` `ssy` join `sections` `s` on(`s`.`id` = `ssy`.`section_id`)) join `school_years` `sy` on(`sy`.`id` = `ssy`.`school_year_id`)) join `grade_levels` `gl` on(`gl`.`id` = `s`.`grade_level_id`)) ;

-- --------------------------------------------------------

--
-- Structure for view `v_student_guardian_overview`
--
DROP TABLE IF EXISTS `v_student_guardian_overview`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_student_guardian_overview`  AS SELECT `sg`.`id` AS `sg_id`, `sg`.`student_id` AS `student_id`, concat(`s`.`first_name`,' ',`s`.`last_name`) AS `student_name`, `sg`.`guardian_id` AS `guardian_id`, `g`.`full_name` AS `guardian_name`, `g`.`guardian_type` AS `guardian_type`, `sg`.`relationship_label` AS `relationship_label`, `sg`.`custody_type` AS `custody_type`, `sg`.`is_primary` AS `is_primary`, `sg`.`emergency_priority` AS `emergency_priority`, `sg`.`pickup_authorized` AS `pickup_authorized`, `g`.`mobile_number` AS `mobile_number`, `g`.`email_address` AS `email_address`, `g`.`is_deceased` AS `is_deceased`, `g`.`is_restricted` AS `is_restricted`, `sg`.`is_active` AS `is_active`, `sg`.`notes` AS `notes` FROM ((`student_guardians` `sg` join `students` `s` on(`s`.`id` = `sg`.`student_id`)) join `guardians` `g` on(`g`.`id` = `sg`.`guardian_id`)) ORDER BY `sg`.`student_id` ASC, `sg`.`emergency_priority` ASC ;

-- --------------------------------------------------------

--
-- Structure for view `v_student_registration_summary`
--
DROP TABLE IF EXISTS `v_student_registration_summary`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_student_registration_summary`  AS SELECT `s`.`id` AS `student_id`, `s`.`lrn` AS `lrn`, concat(`s`.`first_name`,' ',ifnull(concat(`s`.`middle_name`,' '),''),`s`.`last_name`) AS `full_name`, `s`.`sex` AS `sex`, `s`.`date_of_birth` AS `date_of_birth`, `gl`.`display_name` AS `grade_level`, `s`.`enrollment_type` AS `enrollment_type`, `s`.`registration_status` AS `registration_status`, `s`.`personal_email` AS `personal_email`, `sy`.`label` AS `school_year`, `s`.`created_at` AS `applied_at` FROM (((`students` `s` join `grade_levels` `gl` on(`gl`.`id` = `s`.`grade_level_id`)) left join `student_profiles` `sp` on(`sp`.`student_id` = `s`.`id`)) left join `school_years` `sy` on(`sy`.`id` = `sp`.`school_year_id`)) ORDER BY `s`.`created_at` DESC ;

-- --------------------------------------------------------

--
-- Structure for view `v_submission_overview`
--
DROP TABLE IF EXISTS `v_submission_overview`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_submission_overview`  AS SELECT `ss`.`id` AS `submission_id`, `ss`.`reference_number` AS `reference_number`, `s`.`id` AS `student_id`, `s`.`lrn` AS `lrn`, concat(`s`.`first_name`,' ',`s`.`last_name`) AS `full_name`, `s`.`personal_email` AS `personal_email`, `s`.`enrollment_type` AS `enrollment_type`, `gl`.`display_name` AS `grade_level`, `sy`.`label` AS `school_year`, `ss`.`form137_status` AS `form137_status`, `ss`.`birth_cert_status` AS `birth_cert_status`, `s`.`registration_status` AS `registration_status`, `u`.`account_status` AS `account_status`, `ss`.`privacy_accepted` AS `privacy_accepted`, `ss`.`info_accuracy_accepted` AS `info_accuracy_accepted`, `ss`.`submitted_at` AS `submitted_at` FROM ((((`student_submissions` `ss` join `students` `s` on(`s`.`id` = `ss`.`student_id`)) join `grade_levels` `gl` on(`gl`.`id` = `s`.`grade_level_id`)) left join `school_years` `sy` on(`sy`.`id` = `ss`.`school_year_id`)) left join `users` `u` on(`u`.`id` = `s`.`user_id`)) ORDER BY `ss`.`submitted_at` DESC ;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `admins`
--
ALTER TABLE `admins`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_user_id` (`user_id`),
  ADD UNIQUE KEY `uq_admins_user_id` (`user_id`);

--
-- Indexes for table `audit_logs`
--
ALTER TABLE `audit_logs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_admin` (`admin_id`),
  ADD KEY `idx_table_rec` (`table_name`,`record_id`),
  ADD KEY `idx_created_at` (`created_at`);

--
-- Indexes for table `cafeteria_inventory`
--
ALTER TABLE `cafeteria_inventory`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_cafinv_product` (`product_id`),
  ADD KEY `fk_cafinv_admin` (`updated_by`);

--
-- Indexes for table `cafeteria_products`
--
ALTER TABLE `cafeteria_products`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_cafprod_admin` (`created_by`);

--
-- Indexes for table `cafeteria_settings`
--
ALTER TABLE `cafeteria_settings`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_cafset_admin` (`updated_by`);

--
-- Indexes for table `cashiers`
--
ALTER TABLE `cashiers`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_cashier_user` (`user_id`);

--
-- Indexes for table `class_schedules`
--
ALTER TABLE `class_schedules`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_cs_ssy` (`ssy_id`),
  ADD KEY `idx_cs_subject` (`subject_id`),
  ADD KEY `idx_cs_teacher` (`teacher_id`),
  ADD KEY `fk_cs_creator` (`created_by`);

--
-- Indexes for table `coordinators`
--
ALTER TABLE `coordinators`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_coordinator_user` (`user_id`);

--
-- Indexes for table `coordinator_actions`
--
ALTER TABLE `coordinator_actions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `grade_id` (`grade_id`),
  ADD KEY `coordinator_id` (`coordinator_id`);

--
-- Indexes for table `coordinator_assignment_logs`
--
ALTER TABLE `coordinator_assignment_logs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_cal_curriculum` (`curriculum_id`),
  ADD KEY `idx_cal_new_coord` (`new_coordinator`);

--
-- Indexes for table `curriculum`
--
ALTER TABLE `curriculum`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_curriculum` (`school_year_id`,`grade_level_id`,`subject_id`),
  ADD UNIQUE KEY `uq_curriculum_coordinator` (`id`,`coordinator_id`),
  ADD UNIQUE KEY `uq_coordinator_per_curriculum` (`coordinator_id`,`school_year_id`,`grade_level_id`,`subject_id`),
  ADD KEY `fk_cur_sy` (`school_year_id`),
  ADD KEY `fk_cur_grade` (`grade_level_id`),
  ADD KEY `fk_cur_subject` (`subject_id`),
  ADD KEY `fk_cur_admin` (`created_by`),
  ADD KEY `fk_cur_assigned_by` (`assigned_by`);

--
-- Indexes for table `enrollments`
--
ALTER TABLE `enrollments`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_enrollment_sy` (`student_id`,`school_year_id`),
  ADD KEY `fk_enroll_sy` (`school_year_id`),
  ADD KEY `fk_enroll_grade` (`grade_level_id`),
  ADD KEY `fk_enroll_sec_sy` (`section_sy_id`),
  ADD KEY `fk_enroll_registrar` (`processed_by`),
  ADD KEY `idx_status_sy` (`status`,`school_year_id`),
  ADD KEY `idx_student_sy` (`student_id`,`school_year_id`);

--
-- Indexes for table `enrollment_logs`
--
ALTER TABLE `enrollment_logs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_el_enrollment` (`enrollment_id`),
  ADD KEY `fk_el_student` (`student_id`),
  ADD KEY `fk_el_registrar` (`changed_by`);

--
-- Indexes for table `grade_levels`
--
ALTER TABLE `grade_levels`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_level` (`level`);

--
-- Indexes for table `guardians`
--
ALTER TABLE `guardians`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_full_name` (`full_name`),
  ADD KEY `idx_guardian_type` (`guardian_type`),
  ADD KEY `idx_is_active` (`is_active`);

--
-- Indexes for table `guardian_audit_log`
--
ALTER TABLE `guardian_audit_log`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_gal_student` (`student_id`),
  ADD KEY `idx_gal_guardian` (`guardian_id`),
  ADD KEY `idx_gal_action` (`action`),
  ADD KEY `idx_gal_created` (`created_at`),
  ADD KEY `fk_gal_admin` (`changed_by`);

--
-- Indexes for table `otp_attempts`
--
ALTER TABLE `otp_attempts`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_user_attempt` (`user_id`,`attempt_at`);

--
-- Indexes for table `otp_verifications`
--
ALTER TABLE `otp_verifications`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_student_otp` (`student_id`),
  ADD KEY `idx_expires_at` (`expires_at`);

--
-- Indexes for table `password_reset_tokens`
--
ALTER TABLE `password_reset_tokens`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_token_hash` (`token_hash`),
  ADD KEY `idx_user_id` (`user_id`),
  ADD KEY `idx_expires_at` (`expires_at`);

--
-- Indexes for table `payment_due_notices`
--
ALTER TABLE `payment_due_notices`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_pdn_student_id` (`student_id`),
  ADD KEY `idx_pdn_school_year_id` (`school_year_id`),
  ADD KEY `idx_pdn_assigned_by` (`assigned_by`);

--
-- Indexes for table `payment_submissions`
--
ALTER TABLE `payment_submissions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_ps_student` (`student_id`),
  ADD KEY `idx_ps_school_year` (`school_year_id`),
  ADD KEY `idx_ps_status` (`status`),
  ADD KEY `idx_ps_submitted_at` (`submitted_at`),
  ADD KEY `fk_ps_cashier` (`cashier_id`);

--
-- Indexes for table `principals`
--
ALTER TABLE `principals`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_principal_user` (`user_id`);

--
-- Indexes for table `principal_notifications`
--
ALTER TABLE `principal_notifications`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_notif_recipient` (`recipient_type`,`recipient_id`,`is_read`);

--
-- Indexes for table `privacy_consents`
--
ALTER TABLE `privacy_consents`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_pc_student` (`student_id`),
  ADD KEY `idx_pc_type` (`consent_type`);

--
-- Indexes for table `registrars`
--
ALTER TABLE `registrars`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_reg_user` (`user_id`);

--
-- Indexes for table `registration_documents`
--
ALTER TABLE `registration_documents`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_student_docs` (`student_id`),
  ADD KEY `idx_school_year` (`school_year_id`),
  ADD KEY `idx_doc_status` (`status`),
  ADD KEY `fk_docs_reviewer` (`reviewed_by`);

--
-- Indexes for table `remember_me_tokens`
--
ALTER TABLE `remember_me_tokens`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_token_hash` (`token_hash`),
  ADD KEY `idx_user_id` (`user_id`),
  ADD KEY `idx_expires_at` (`expires_at`);

--
-- Indexes for table `role_redirects`
--
ALTER TABLE `role_redirects`
  ADD PRIMARY KEY (`role`);

--
-- Indexes for table `rooms`
--
ALTER TABLE `rooms`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_room_number_active` (`number`,`status`),
  ADD KEY `fk_rooms_admin` (`created_by`);

--
-- Indexes for table `school_years`
--
ALTER TABLE `school_years`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_label` (`label`),
  ADD KEY `fk_sy_admin` (`created_by`);

--
-- Indexes for table `sections`
--
ALTER TABLE `sections`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_grade_section` (`grade_level_id`,`name`),
  ADD KEY `fk_sec_grade` (`grade_level_id`);

--
-- Indexes for table `section_school_years`
--
ALTER TABLE `section_school_years`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_section_sy` (`section_id`,`school_year_id`),
  ADD KEY `fk_ssy_section` (`section_id`),
  ADD KEY `fk_ssy_sy` (`school_year_id`),
  ADD KEY `fk_ssy_adviser` (`adviser_id`);

--
-- Indexes for table `students`
--
ALTER TABLE `students`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_personal_email` (`personal_email`),
  ADD UNIQUE KEY `uq_lrn` (`lrn`),
  ADD KEY `idx_user_id` (`user_id`),
  ADD KEY `idx_grade_level` (`grade_level_id`),
  ADD KEY `idx_enrollment_type` (`enrollment_type`),
  ADD KEY `idx_registration_status` (`registration_status`);

--
-- Indexes for table `student_grades`
--
ALTER TABLE `student_grades`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_student_grade` (`student_id`,`ssy_id`,`subject_id`),
  ADD KEY `idx_ssy_subject` (`ssy_id`,`subject_id`),
  ADD KEY `idx_student` (`student_id`),
  ADD KEY `fk_sgrades_subject` (`subject_id`);

--
-- Indexes for table `student_guardians`
--
ALTER TABLE `student_guardians`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_student_guardian` (`student_id`,`guardian_id`),
  ADD KEY `idx_sg_student` (`student_id`),
  ADD KEY `idx_sg_guardian` (`guardian_id`),
  ADD KEY `idx_emergency_priority` (`student_id`,`emergency_priority`),
  ADD KEY `idx_sg_student_active` (`student_id`,`is_active`);

--
-- Indexes for table `student_profiles`
--
ALTER TABLE `student_profiles`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_student_profile` (`student_id`),
  ADD KEY `idx_school_year` (`school_year_id`),
  ADD KEY `idx_section_sy` (`section_sy_id`);

--
-- Indexes for table `student_submissions`
--
ALTER TABLE `student_submissions`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_student_submission` (`student_id`,`school_year_id`),
  ADD KEY `idx_sub_student` (`student_id`),
  ADD KEY `idx_sub_sy` (`school_year_id`),
  ADD KEY `idx_sub_ref` (`reference_number`),
  ADD KEY `fk_sub_reviewer` (`reviewed_by`),
  ADD KEY `idx_ss_student_sy` (`student_id`,`school_year_id`);

--
-- Indexes for table `student_wallets`
--
ALTER TABLE `student_wallets`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_wallet_student` (`student_id`);

--
-- Indexes for table `subjects`
--
ALTER TABLE `subjects`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_code` (`code`),
  ADD KEY `idx_is_archived` (`is_archived`),
  ADD KEY `fk_sub_grade_level` (`grade_level_id`);

--
-- Indexes for table `system_deadlines`
--
ALTER TABLE `system_deadlines`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_sy_type` (`school_year_id`,`type`) COMMENT 'One deadline window per type per school year',
  ADD KEY `fk_dl_sy` (`school_year_id`),
  ADD KEY `fk_dl_admin` (`created_by`);

--
-- Indexes for table `teachers`
--
ALTER TABLE `teachers`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_teacher_user` (`user_id`),
  ADD KEY `fk_teacher_subject` (`subject_id`);

--
-- Indexes for table `teacher_notifications`
--
ALTER TABLE `teacher_notifications`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `trusted_devices`
--
ALTER TABLE `trusted_devices`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_token_hash` (`token_hash`),
  ADD KEY `idx_user_expires` (`user_id`,`expires_at`);

--
-- Indexes for table `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_username` (`username`),
  ADD UNIQUE KEY `uq_school_email` (`school_email`),
  ADD UNIQUE KEY `employee_id` (`employee_id`),
  ADD KEY `idx_users_role` (`role`),
  ADD KEY `idx_session_token` (`session_token`);

--
-- Indexes for table `wallet_transactions`
--
ALTER TABLE `wallet_transactions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `fk_wtx_student` (`student_id`),
  ADD KEY `fk_wtx_admin` (`admin_id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `admins`
--
ALTER TABLE `admins`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=57;

--
-- AUTO_INCREMENT for table `audit_logs`
--
ALTER TABLE `audit_logs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=514;

--
-- AUTO_INCREMENT for table `cafeteria_inventory`
--
ALTER TABLE `cafeteria_inventory`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `cafeteria_products`
--
ALTER TABLE `cafeteria_products`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `cafeteria_settings`
--
ALTER TABLE `cafeteria_settings`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `cashiers`
--
ALTER TABLE `cashiers`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `class_schedules`
--
ALTER TABLE `class_schedules`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=676;

--
-- AUTO_INCREMENT for table `coordinators`
--
ALTER TABLE `coordinators`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=12;

--
-- AUTO_INCREMENT for table `coordinator_actions`
--
ALTER TABLE `coordinator_actions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=110;

--
-- AUTO_INCREMENT for table `coordinator_assignment_logs`
--
ALTER TABLE `coordinator_assignment_logs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=61;

--
-- AUTO_INCREMENT for table `curriculum`
--
ALTER TABLE `curriculum`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=41;

--
-- AUTO_INCREMENT for table `enrollments`
--
ALTER TABLE `enrollments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=414;

--
-- AUTO_INCREMENT for table `enrollment_logs`
--
ALTER TABLE `enrollment_logs`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=13;

--
-- AUTO_INCREMENT for table `grade_levels`
--
ALTER TABLE `grade_levels`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT for table `guardians`
--
ALTER TABLE `guardians`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT COMMENT 'PK', AUTO_INCREMENT=22;

--
-- AUTO_INCREMENT for table `guardian_audit_log`
--
ALTER TABLE `guardian_audit_log`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=22;

--
-- AUTO_INCREMENT for table `otp_attempts`
--
ALTER TABLE `otp_attempts`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `otp_verifications`
--
ALTER TABLE `otp_verifications`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `password_reset_tokens`
--
ALTER TABLE `password_reset_tokens`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT for table `payment_due_notices`
--
ALTER TABLE `payment_due_notices`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `payment_submissions`
--
ALTER TABLE `payment_submissions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=28;

--
-- AUTO_INCREMENT for table `principals`
--
ALTER TABLE `principals`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `principal_notifications`
--
ALTER TABLE `principal_notifications`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=87;

--
-- AUTO_INCREMENT for table `privacy_consents`
--
ALTER TABLE `privacy_consents`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=33;

--
-- AUTO_INCREMENT for table `registrars`
--
ALTER TABLE `registrars`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- AUTO_INCREMENT for table `registration_documents`
--
ALTER TABLE `registration_documents`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `remember_me_tokens`
--
ALTER TABLE `remember_me_tokens`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `rooms`
--
ALTER TABLE `rooms`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=25;

--
-- AUTO_INCREMENT for table `school_years`
--
ALTER TABLE `school_years`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `sections`
--
ALTER TABLE `sections`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=24;

--
-- AUTO_INCREMENT for table `section_school_years`
--
ALTER TABLE `section_school_years`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=24;

--
-- AUTO_INCREMENT for table `students`
--
ALTER TABLE `students`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=425;

--
-- AUTO_INCREMENT for table `student_grades`
--
ALTER TABLE `student_grades`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=223;

--
-- AUTO_INCREMENT for table `student_guardians`
--
ALTER TABLE `student_guardians`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT COMMENT 'PK', AUTO_INCREMENT=22;

--
-- AUTO_INCREMENT for table `student_profiles`
--
ALTER TABLE `student_profiles`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=403;

--
-- AUTO_INCREMENT for table `student_submissions`
--
ALTER TABLE `student_submissions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=417;

--
-- AUTO_INCREMENT for table `student_wallets`
--
ALTER TABLE `student_wallets`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `subjects`
--
ALTER TABLE `subjects`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=36;

--
-- AUTO_INCREMENT for table `system_deadlines`
--
ALTER TABLE `system_deadlines`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `teachers`
--
ALTER TABLE `teachers`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=41;

--
-- AUTO_INCREMENT for table `teacher_notifications`
--
ALTER TABLE `teacher_notifications`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=37;

--
-- AUTO_INCREMENT for table `trusted_devices`
--
ALTER TABLE `trusted_devices`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=154;

--
-- AUTO_INCREMENT for table `users`
--
ALTER TABLE `users`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=479;

--
-- AUTO_INCREMENT for table `wallet_transactions`
--
ALTER TABLE `wallet_transactions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=3;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `audit_logs`
--
ALTER TABLE `audit_logs`
  ADD CONSTRAINT `fk_log_admin` FOREIGN KEY (`admin_id`) REFERENCES `admins` (`id`);

--
-- Constraints for table `cafeteria_inventory`
--
ALTER TABLE `cafeteria_inventory`
  ADD CONSTRAINT `fk_cafinv_admin` FOREIGN KEY (`updated_by`) REFERENCES `admins` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_cafinv_product` FOREIGN KEY (`product_id`) REFERENCES `cafeteria_products` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `cafeteria_products`
--
ALTER TABLE `cafeteria_products`
  ADD CONSTRAINT `fk_cafprod_admin` FOREIGN KEY (`created_by`) REFERENCES `admins` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `cafeteria_settings`
--
ALTER TABLE `cafeteria_settings`
  ADD CONSTRAINT `fk_cafset_admin` FOREIGN KEY (`updated_by`) REFERENCES `admins` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `cashiers`
--
ALTER TABLE `cashiers`
  ADD CONSTRAINT `fk_cashier_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `class_schedules`
--
ALTER TABLE `class_schedules`
  ADD CONSTRAINT `fk_cs_creator` FOREIGN KEY (`created_by`) REFERENCES `registrars` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_cs_ssy` FOREIGN KEY (`ssy_id`) REFERENCES `section_school_years` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_cs_subject` FOREIGN KEY (`subject_id`) REFERENCES `subjects` (`id`),
  ADD CONSTRAINT `fk_cs_teacher` FOREIGN KEY (`teacher_id`) REFERENCES `teachers` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `coordinators`
--
ALTER TABLE `coordinators`
  ADD CONSTRAINT `fk_coordinator_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `curriculum`
--
ALTER TABLE `curriculum`
  ADD CONSTRAINT `fk_cur_admin` FOREIGN KEY (`created_by`) REFERENCES `admins` (`id`),
  ADD CONSTRAINT `fk_cur_assigned_by` FOREIGN KEY (`assigned_by`) REFERENCES `principals` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_cur_coordinator` FOREIGN KEY (`coordinator_id`) REFERENCES `coordinators` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_cur_grade` FOREIGN KEY (`grade_level_id`) REFERENCES `grade_levels` (`id`),
  ADD CONSTRAINT `fk_cur_subject` FOREIGN KEY (`subject_id`) REFERENCES `subjects` (`id`),
  ADD CONSTRAINT `fk_cur_sy` FOREIGN KEY (`school_year_id`) REFERENCES `school_years` (`id`);

--
-- Constraints for table `enrollments`
--
ALTER TABLE `enrollments`
  ADD CONSTRAINT `fk_enroll_grade` FOREIGN KEY (`grade_level_id`) REFERENCES `grade_levels` (`id`),
  ADD CONSTRAINT `fk_enroll_registrar` FOREIGN KEY (`processed_by`) REFERENCES `registrars` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_enroll_sec_sy` FOREIGN KEY (`section_sy_id`) REFERENCES `section_school_years` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_enroll_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_enroll_sy` FOREIGN KEY (`school_year_id`) REFERENCES `school_years` (`id`);

--
-- Constraints for table `enrollment_logs`
--
ALTER TABLE `enrollment_logs`
  ADD CONSTRAINT `fk_el_enrollment` FOREIGN KEY (`enrollment_id`) REFERENCES `enrollments` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_el_registrar` FOREIGN KEY (`changed_by`) REFERENCES `registrars` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_el_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `guardian_audit_log`
--
ALTER TABLE `guardian_audit_log`
  ADD CONSTRAINT `fk_gal_admin` FOREIGN KEY (`changed_by`) REFERENCES `admins` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_gal_guardian` FOREIGN KEY (`guardian_id`) REFERENCES `guardians` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_gal_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `otp_verifications`
--
ALTER TABLE `otp_verifications`
  ADD CONSTRAINT `fk_otp_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `password_reset_tokens`
--
ALTER TABLE `password_reset_tokens`
  ADD CONSTRAINT `fk_prt_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `payment_due_notices`
--
ALTER TABLE `payment_due_notices`
  ADD CONSTRAINT `fk_pdn_cashier` FOREIGN KEY (`assigned_by`) REFERENCES `cashiers` (`id`),
  ADD CONSTRAINT `fk_pdn_school_year` FOREIGN KEY (`school_year_id`) REFERENCES `school_years` (`id`),
  ADD CONSTRAINT `fk_pdn_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `payment_submissions`
--
ALTER TABLE `payment_submissions`
  ADD CONSTRAINT `fk_ps_cashier` FOREIGN KEY (`cashier_id`) REFERENCES `cashiers` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_ps_school_year` FOREIGN KEY (`school_year_id`) REFERENCES `school_years` (`id`),
  ADD CONSTRAINT `fk_ps_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `principals`
--
ALTER TABLE `principals`
  ADD CONSTRAINT `fk_principal_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `privacy_consents`
--
ALTER TABLE `privacy_consents`
  ADD CONSTRAINT `fk_pc_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `registrars`
--
ALTER TABLE `registrars`
  ADD CONSTRAINT `fk_reg_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `registration_documents`
--
ALTER TABLE `registration_documents`
  ADD CONSTRAINT `fk_docs_reviewer` FOREIGN KEY (`reviewed_by`) REFERENCES `admins` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_docs_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_docs_sy` FOREIGN KEY (`school_year_id`) REFERENCES `school_years` (`id`) ON UPDATE CASCADE;

--
-- Constraints for table `remember_me_tokens`
--
ALTER TABLE `remember_me_tokens`
  ADD CONSTRAINT `fk_rmt_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `rooms`
--
ALTER TABLE `rooms`
  ADD CONSTRAINT `fk_rooms_admin` FOREIGN KEY (`created_by`) REFERENCES `admins` (`id`) ON DELETE SET NULL;

--
-- Constraints for table `school_years`
--
ALTER TABLE `school_years`
  ADD CONSTRAINT `fk_sy_admin` FOREIGN KEY (`created_by`) REFERENCES `admins` (`id`);

--
-- Constraints for table `sections`
--
ALTER TABLE `sections`
  ADD CONSTRAINT `fk_sec_grade` FOREIGN KEY (`grade_level_id`) REFERENCES `grade_levels` (`id`);

--
-- Constraints for table `section_school_years`
--
ALTER TABLE `section_school_years`
  ADD CONSTRAINT `fk_ssy_adviser` FOREIGN KEY (`adviser_id`) REFERENCES `teachers` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_ssy_section` FOREIGN KEY (`section_id`) REFERENCES `sections` (`id`),
  ADD CONSTRAINT `fk_ssy_sy` FOREIGN KEY (`school_year_id`) REFERENCES `school_years` (`id`);

--
-- Constraints for table `students`
--
ALTER TABLE `students`
  ADD CONSTRAINT `fk_student_grade` FOREIGN KEY (`grade_level_id`) REFERENCES `grade_levels` (`id`) ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_student_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL ON UPDATE CASCADE;

--
-- Constraints for table `student_grades`
--
ALTER TABLE `student_grades`
  ADD CONSTRAINT `fk_sgrades_ssy` FOREIGN KEY (`ssy_id`) REFERENCES `section_school_years` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_sgrades_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_sgrades_subject` FOREIGN KEY (`subject_id`) REFERENCES `subjects` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `student_guardians`
--
ALTER TABLE `student_guardians`
  ADD CONSTRAINT `fk_sg_guardian` FOREIGN KEY (`guardian_id`) REFERENCES `guardians` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_sg_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `student_profiles`
--
ALTER TABLE `student_profiles`
  ADD CONSTRAINT `fk_profile_section_sy` FOREIGN KEY (`section_sy_id`) REFERENCES `section_school_years` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_profile_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_profile_sy` FOREIGN KEY (`school_year_id`) REFERENCES `school_years` (`id`) ON DELETE SET NULL ON UPDATE CASCADE;

--
-- Constraints for table `student_submissions`
--
ALTER TABLE `student_submissions`
  ADD CONSTRAINT `fk_sub_reviewer` FOREIGN KEY (`reviewed_by`) REFERENCES `admins` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_sub_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_sub_sy` FOREIGN KEY (`school_year_id`) REFERENCES `school_years` (`id`) ON DELETE SET NULL ON UPDATE CASCADE;

--
-- Constraints for table `student_wallets`
--
ALTER TABLE `student_wallets`
  ADD CONSTRAINT `fk_wallet_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `system_deadlines`
--
ALTER TABLE `system_deadlines`
  ADD CONSTRAINT `fk_dl_admin` FOREIGN KEY (`created_by`) REFERENCES `admins` (`id`),
  ADD CONSTRAINT `fk_dl_sy` FOREIGN KEY (`school_year_id`) REFERENCES `school_years` (`id`);

--
-- Constraints for table `teachers`
--
ALTER TABLE `teachers`
  ADD CONSTRAINT `fk_teacher_subject` FOREIGN KEY (`subject_id`) REFERENCES `subjects` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_teacher_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Constraints for table `wallet_transactions`
--
ALTER TABLE `wallet_transactions`
  ADD CONSTRAINT `fk_wtx_admin` FOREIGN KEY (`admin_id`) REFERENCES `admins` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_wtx_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE;

DELIMITER $$
--
-- Events
--
CREATE DEFINER=`root`@`localhost` EVENT `evt_purge_expired_drafts` ON SCHEDULE EVERY 1 DAY STARTS '2026-05-20 03:00:00' ON COMPLETION PRESERVE ENABLE COMMENT 'Purge expired registration drafts daily at 03:00.' DO DELETE FROM registration_drafts
    WHERE  expires_at < NOW()$$

DELIMITER ;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
