
\ir Ola-davies_Oluwaferanmi_301931917_tx-00-setup.sql
\set ECHO queries
SET search_path TO hospital;

\echo
\echo '=== 1A: COMMIT. Complete a consultation as ONE atomic unit ==='
\echo '    Diagnosis + prescription + lab request all succeed together.'
BEGIN;
UPDATE appointment
   SET status = 'completed', diagnosis = 'Hypertension'
 WHERE appointment_id = 900002;
INSERT INTO prescription (appointment_id, drug_name, dosage, frequency, duration_days)
VALUES (900002, 'Amlodipine 5mg', '1 tablet', 'Once daily', 30);
INSERT INTO lab_record (appointment_id, test_name)
VALUES (900002, 'Lipid profile');
COMMIT;

\echo '--- Result after COMMIT: all three changes are permanent ---'
SELECT a.status, a.diagnosis,
       (SELECT count(*) FROM prescription p WHERE p.appointment_id = a.appointment_id) AS prescriptions,
       (SELECT count(*) FROM lab_record   l WHERE l.appointment_id = a.appointment_id) AS lab_requests
FROM appointment a WHERE a.appointment_id = 900002;

\echo
\echo '=== 1B: ROLLBACK. Cancel a booking before it is committed ==='
BEGIN;
INSERT INTO appointment (appointment_id, patient_id, doctor_id, scheduled_start, scheduled_end)
VALUES (900003, 900001, 900001, TIMESTAMPTZ '2030-06-01 11:00+00', TIMESTAMPTZ '2030-06-01 11:30+00');
\echo '--- Inside the transaction the new appointment is visible (count = 1) ---'
SELECT count(*) AS visible_inside_transaction FROM appointment WHERE appointment_id = 900003;
ROLLBACK;
\echo '--- After ROLLBACK it is gone (count = 0) ---'
SELECT count(*) AS visible_after_rollback FROM appointment WHERE appointment_id = 900003;

\echo
\echo '=== 1C: ATOMICITY. One failing statement undoes the whole transaction ==='
\echo '    The second prescription breaks CHECK (duration_days > 0).'
BEGIN;
UPDATE appointment
   SET status = 'completed', diagnosis = 'Typhoid fever'
 WHERE appointment_id = 900001;
INSERT INTO prescription (appointment_id, drug_name, dosage, frequency, duration_days)
VALUES (900001, 'Ciprofloxacin 500mg', '1 tablet', 'Twice daily', 7);
INSERT INTO prescription (appointment_id, drug_name, dosage, frequency, duration_days)
VALUES (900001, 'Paracetamol 500mg', '1 tablet', 'Twice daily', 0);
\echo '--- The transaction is now in an aborted state: every further command is refused ---'
SELECT 1;
ROLLBACK;
\echo '--- After ROLLBACK: status and diagnosis are unchanged and no prescription was saved ---'
SELECT a.status, a.diagnosis,
       (SELECT count(*) FROM prescription p WHERE p.appointment_id = a.appointment_id) AS prescriptions
FROM appointment a WHERE a.appointment_id = 900001;

\echo
\echo '=== 1D: SAVEPOINT. Undo only the failed step, keep the rest ==='
BEGIN;
INSERT INTO prescription (appointment_id, drug_name, dosage, frequency, duration_days)
VALUES (900001, 'Paracetamol 500mg', '1 tablet', 'Three times daily', 5);
SAVEPOINT before_second_drug;
INSERT INTO prescription (appointment_id, drug_name, dosage, frequency, duration_days)
VALUES (900001, 'Ibuprofen 400mg', '1 tablet', 'Twice daily', -1);
ROLLBACK TO SAVEPOINT before_second_drug;
\echo '--- Retry the second drug with a valid duration ---'
INSERT INTO prescription (appointment_id, drug_name, dosage, frequency, duration_days)
VALUES (900001, 'Ibuprofen 400mg', '1 tablet', 'Twice daily', 3);
COMMIT;
\echo '--- Both valid prescriptions were saved; the bad attempt left no trace ---'
SELECT drug_name, duration_days FROM prescription WHERE appointment_id = 900001 ORDER BY prescription_id;