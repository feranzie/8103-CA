-- =====================================================================
-- export the relational data as MongoDB documents
-- Produces ONE JSON document per line (JSON Lines) that mongoimport reads.

-- Design: a patient document EMBEDS that patient's appointments, and each
-- appointment embeds its prescriptions and lab records. The doctor is
-- referenced by doctor_id plus a copy of name and specialty.
-- =====================================================================
SET search_path TO hospital;

-- Temporary helper (disappears when the session ends). Emits MongoDB
-- extended JSON so mongoimport stores real Date values, not strings.
CREATE FUNCTION pg_temp.mdate(ts timestamptz) RETURNS json LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN ts IS NULL THEN NULL
                ELSE json_build_object('$date',
                     to_char(ts AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')) END
$$;

SELECT json_build_object(
    '_id',           p.patient_id,
    'first_name',    p.first_name,
    'last_name',     p.last_name,
    'date_of_birth', pg_temp.mdate(p.date_of_birth::timestamptz),
    'sex',           p.sex,
    'phone',         p.phone,
    'address',       p.address,
    'appointments',  COALESCE((
        SELECT json_agg(json_build_object(
                   'appointment_id',  a.appointment_id,
                   'doctor',          json_build_object(
                                          'doctor_id', d.doctor_id,
                                          'name',      d.first_name || ' ' || d.last_name,
                                          'specialty', d.specialty),
                   'scheduled_start', pg_temp.mdate(a.scheduled_start),
                   'scheduled_end',   pg_temp.mdate(a.scheduled_end),
                   'status',          a.status,
                   'reason',          a.reason,
                   'diagnosis',       a.diagnosis,
                   'prescriptions',   COALESCE((
                        SELECT json_agg(json_build_object(
                                   'drug_name',     pr.drug_name,
                                   'dosage',        pr.dosage,
                                   'frequency',     pr.frequency,
                                   'duration_days', pr.duration_days,
                                   'issued_at',     pg_temp.mdate(pr.issued_at))
                               ORDER BY pr.prescription_id)
                        FROM prescription pr
                        WHERE pr.appointment_id = a.appointment_id), '[]'::json),
                   'lab_records',     COALESCE((
                        SELECT json_agg(json_build_object(
                                   'test_name',    l.test_name,
                                   'result_value', l.result_value,
                                   'status',       l.status,
                                   'requested_at', pg_temp.mdate(l.requested_at),
                                   'resulted_at',  pg_temp.mdate(l.resulted_at))
                               ORDER BY l.lab_record_id)
                        FROM lab_record l
                        WHERE l.appointment_id = a.appointment_id), '[]'::json)
               ) ORDER BY a.scheduled_start)
        FROM appointment a
        JOIN doctor d ON d.doctor_id = a.doctor_id
        WHERE a.patient_id = p.patient_id), '[]'::json)
)
FROM patient p
ORDER BY p.patient_id;