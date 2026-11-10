SET search_path TO hospital;

-- Q1: find one patient's appointments quickly
CREATE INDEX idx_appointment_patient ON appointment (patient_id);

-- Q1: the per-appointment lookups of prescriptions and lab results
CREATE INDEX idx_prescription_appointment ON prescription (appointment_id);
CREATE INDEX idx_lab_record_appointment   ON lab_record (appointment_id);

-- Q2: equality on doctor, range on time, results already in time order
CREATE INDEX idx_appointment_doctor_start ON appointment (doctor_id, scheduled_start);

-- Q3: date-range scan across all doctors
CREATE INDEX idx_appointment_start ON appointment (scheduled_start);

-- Q4: partial index, only the small set of lab requests still pending
CREATE INDEX idx_lab_record_pending ON lab_record (requested_at)
    WHERE status = 'requested';

-- Refresh statistics, then list the indexes with their sizes
ANALYZE;
SELECT indexrelname AS index_name,
       relname      AS table_name,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE schemaname = 'hospital'
ORDER BY relname, indexrelname;