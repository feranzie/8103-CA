
\set ECHO queries
SET search_path TO hospital;

\echo
\echo '=== SETUP: one test patient, one test doctor, one valid appointment ==='
INSERT INTO patient (first_name, last_name, date_of_birth, sex)
VALUES ('Test', 'Patient', DATE '1990-05-10', 'F')
RETURNING patient_id AS test_patient \gset

INSERT INTO doctor (first_name, last_name, specialty)
VALUES ('Test', 'Doctor', 'General Practice')
RETURNING doctor_id AS test_doctor \gset

INSERT INTO appointment (patient_id, doctor_id, scheduled_start, scheduled_end)
VALUES (:test_patient, :test_doctor,
        TIMESTAMPTZ '2030-01-01 09:00:00+01', TIMESTAMPTZ '2030-01-01 09:30:00+01')
RETURNING appointment_id AS test_appt \gset

\echo
\echo '=== TEST 1 (EXPECT FAIL): overlapping appointment for the same doctor ==='
\echo '    Rule: no_doctor_double_booking (exclusion constraint)'
INSERT INTO appointment (patient_id, doctor_id, scheduled_start, scheduled_end)
VALUES (:test_patient, :test_doctor,
        TIMESTAMPTZ '2030-01-01 09:15:00+01', TIMESTAMPTZ '2030-01-01 09:45:00+01');

\echo
\echo '=== TEST 2 (EXPECT SUCCESS): back-to-back slot, 09:30 to 10:00 ==='
\echo '    Adjacent slots do not overlap, so this is allowed'
INSERT INTO appointment (patient_id, doctor_id, scheduled_start, scheduled_end)
VALUES (:test_patient, :test_doctor,
        TIMESTAMPTZ '2030-01-01 09:30:00+01', TIMESTAMPTZ '2030-01-01 10:00:00+01');

\echo
\echo '=== TEST 3 (EXPECT SUCCESS): a cancelled slot can be rebooked ==='
UPDATE appointment SET status = 'cancelled' WHERE appointment_id = :test_appt;
INSERT INTO appointment (patient_id, doctor_id, scheduled_start, scheduled_end)
VALUES (:test_patient, :test_doctor,
        TIMESTAMPTZ '2030-01-01 09:00:00+01', TIMESTAMPTZ '2030-01-01 09:30:00+01');

\echo
\echo '=== TEST 4 (EXPECT FAIL): appointment ends before it starts ==='
\echo '    Rule: CHECK scheduled_end > scheduled_start'
INSERT INTO appointment (patient_id, doctor_id, scheduled_start, scheduled_end)
VALUES (:test_patient, :test_doctor,
        TIMESTAMPTZ '2030-02-01 10:00:00+01', TIMESTAMPTZ '2030-02-01 09:00:00+01');

\echo
\echo '=== TEST 5 (EXPECT FAIL): invalid appointment status ==='
\echo '    Rule: CHECK status IN (booked, completed, cancelled)'
INSERT INTO appointment (patient_id, doctor_id, scheduled_start, scheduled_end, status)
VALUES (:test_patient, :test_doctor,
        TIMESTAMPTZ '2030-03-01 09:00:00+01', TIMESTAMPTZ '2030-03-01 09:30:00+01', 'pending');

\echo
\echo '=== TEST 6 (EXPECT FAIL): appointment for a patient that does not exist ==='
\echo '    Rule: FOREIGN KEY appointment.patient_id'
INSERT INTO appointment (patient_id, doctor_id, scheduled_start, scheduled_end)
VALUES (999999999, :test_doctor,
        TIMESTAMPTZ '2030-04-01 09:00:00+01', TIMESTAMPTZ '2030-04-01 09:30:00+01');

\echo
\echo '=== TEST 7 (EXPECT FAIL): patient born in the future ==='
\echo '    Rule: CHECK date_of_birth <= CURRENT_DATE'
INSERT INTO patient (first_name, last_name, date_of_birth, sex)
VALUES ('Future', 'Baby', CURRENT_DATE + 30, 'M');

\echo
\echo '=== TEST 8 (EXPECT FAIL): invalid sex code ==='
\echo '    Rule: CHECK sex IN (M, F)'
INSERT INTO patient (first_name, last_name, date_of_birth, sex)
VALUES ('Bad', 'Code', DATE '1985-01-01', 'X');

\echo
\echo '=== TEST 9 (EXPECT FAIL): patient with no first name ==='
\echo '    Rule: NOT NULL first_name'
INSERT INTO patient (first_name, last_name, date_of_birth, sex)
VALUES (NULL, 'Nameless', DATE '1985-01-01', 'M');

\echo
\echo '=== TEST 10 (EXPECT FAIL): prescription lasting 0 days ==='
\echo '    Rule: CHECK duration_days > 0'
INSERT INTO prescription (appointment_id, drug_name, dosage, frequency, duration_days)
VALUES (:test_appt, 'Paracetamol 500mg', '1 tablet', 'Twice daily', 0);

\echo
\echo '=== TEST 11 (EXPECT FAIL): lab result time before request time ==='
\echo '    Rule: CHECK resulted_at IS NULL OR resulted_at >= requested_at'
INSERT INTO lab_record (appointment_id, test_name, result_value, status, requested_at, resulted_at)
VALUES (:test_appt, 'Blood glucose', 'Normal', 'completed',
        TIMESTAMPTZ '2030-01-01 10:00:00+01', TIMESTAMPTZ '2030-01-01 09:00:00+01');

\echo
\echo '=== TEST 12 (EXPECT FAIL): delete a patient who has appointments ==='
\echo '    Rule: FOREIGN KEY with NO ACTION protects clinical history'
DELETE FROM patient WHERE patient_id = :test_patient;

\echo
\echo '=== TEST 13 (EXPECT SUCCESS): valid prescription and lab record ==='
INSERT INTO prescription (appointment_id, drug_name, dosage, frequency, duration_days)
VALUES (:test_appt, 'Paracetamol 500mg', '1 tablet', 'Twice daily', 5);
INSERT INTO lab_record (appointment_id, test_name) VALUES (:test_appt, 'Blood glucose');

\echo
\echo '=== CLEANUP: remove all test data ==='
DELETE FROM prescription WHERE appointment_id IN
    (SELECT appointment_id FROM appointment WHERE doctor_id = :test_doctor);
DELETE FROM lab_record WHERE appointment_id IN
    (SELECT appointment_id FROM appointment WHERE doctor_id = :test_doctor);
DELETE FROM appointment WHERE doctor_id = :test_doctor;
DELETE FROM patient WHERE patient_id = :test_patient;
DELETE FROM doctor WHERE doctor_id = :test_doctor;

\echo
\echo '=== Leftover test rows (should all be 0) ==='
SELECT (SELECT count(*) FROM patient WHERE last_name IN ('Patient','Baby','Code','Nameless') AND first_name IN ('Test','Future','Bad')) AS test_patients,
       (SELECT count(*) FROM doctor  WHERE first_name = 'Test' AND last_name = 'Doctor') AS test_doctors;