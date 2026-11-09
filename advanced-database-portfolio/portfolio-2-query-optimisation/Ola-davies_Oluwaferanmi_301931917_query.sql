\if :{?explain}
\else
  \set explain ''
\endif
SET search_path TO hospital;

-- Q1 needs a patient who actually has appointments. The seed data is
-- random, so a hard-coded ID can have none. Pick the patient with the
-- most appointments (ties broken by lowest ID) and store it as :pid.
SELECT patient_id AS pid
FROM appointment
GROUP BY patient_id
ORDER BY count(*) DESC, patient_id
LIMIT 1 \gset

\echo
\echo --- Q1: Retrieve patient history, patient_id = :pid ---
:explain
SELECT a.appointment_id,
       a.scheduled_start,
       d.first_name || ' ' || d.last_name AS doctor,
       a.status,
       a.diagnosis,
       (SELECT string_agg(p.drug_name, ', ')
          FROM prescription p
         WHERE p.appointment_id = a.appointment_id) AS prescriptions,
       (SELECT string_agg(l.test_name || ': ' || COALESCE(l.result_value, 'pending'), ', ')
          FROM lab_record l
         WHERE l.appointment_id = a.appointment_id) AS lab_results
FROM appointment a
JOIN doctor d ON d.doctor_id = a.doctor_id
WHERE a.patient_id = :pid
ORDER BY a.scheduled_start;

\echo
\echo '--- Q2: One doctor''s schedule for one day (doctor_id = 7, 2026-10-06) ---'
:explain
SELECT a.appointment_id,
       a.scheduled_start,
       a.scheduled_end,
       p.first_name || ' ' || p.last_name AS patient,
       a.reason,
       a.status
FROM appointment a
JOIN patient p ON p.patient_id = a.patient_id
WHERE a.doctor_id = 7
  AND a.scheduled_start >= TIMESTAMPTZ '2026-10-06 00:00:00+01'
  AND a.scheduled_start <  TIMESTAMPTZ '2026-10-07 00:00:00+01'
  AND a.status <> 'cancelled'
ORDER BY a.scheduled_start;

\echo
\echo '--- Q3: Appointments per doctor, October 2026 ---'
:explain
SELECT d.doctor_id,
       d.first_name || ' ' || d.last_name AS doctor,
       d.specialty,
       count(*)                                        AS total_appointments,
       count(*) FILTER (WHERE a.status = 'completed')  AS completed,
       count(*) FILTER (WHERE a.status = 'cancelled')  AS cancelled
FROM appointment a
JOIN doctor d ON d.doctor_id = a.doctor_id
WHERE a.scheduled_start >= TIMESTAMPTZ '2026-10-01 00:00:00+01'
  AND a.scheduled_start <  TIMESTAMPTZ '2026-11-01 00:00:00+01'
GROUP BY d.doctor_id, d.first_name, d.last_name, d.specialty
ORDER BY completed DESC, d.doctor_id;

\echo
\echo '--- Q4: Pending lab requests, oldest first ---'
:explain
SELECT l.lab_record_id,
       l.test_name,
       l.requested_at,
       p.first_name || ' ' || p.last_name AS patient
FROM lab_record l
JOIN appointment a ON a.appointment_id = l.appointment_id
JOIN patient p     ON p.patient_id = a.patient_id
WHERE l.status = 'requested'
ORDER BY l.requested_at
LIMIT 50;