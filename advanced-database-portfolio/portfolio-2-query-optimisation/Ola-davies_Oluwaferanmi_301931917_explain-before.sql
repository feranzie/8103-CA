
SET search_path TO hospital;

-- Make the script re-runnable: remove the optimisation indexes if present
DROP INDEX IF EXISTS idx_appointment_patient;
DROP INDEX IF EXISTS idx_appointment_doctor_start;
DROP INDEX IF EXISTS idx_appointment_start;
DROP INDEX IF EXISTS idx_prescription_appointment;
DROP INDEX IF EXISTS idx_lab_record_appointment;
DROP INDEX IF EXISTS idx_lab_record_pending;
ANALYZE;

\echo '=============== BEFORE INDEXING ==============='
\timing on
\set explain 'EXPLAIN (ANALYZE, BUFFERS)'
\ir Ola-davies_Oluwaferanmi_301931917_query.sql