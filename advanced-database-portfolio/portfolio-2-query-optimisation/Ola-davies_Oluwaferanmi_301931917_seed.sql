-- populate the hospital database with sample data --
SET search_path TO hospital;

TRUNCATE prescription, lab_record, appointment, patient, doctor RESTART IDENTITY;
-- Doctors ------------------------------------------------------------
INSERT INTO doctor (first_name, last_name, specialty, phone)
SELECT 'Doctor' || g,
       'Surname' || g,
       (ARRAY['General Practice','Cardiology','Paediatrics','Neurology',
              'Orthopaedics','Dermatology','Gynaecology','Ophthalmology'])[1 + (g % 8)],
       '080' || lpad((10000000 + g)::text, 8, '0')
FROM generate_series(1, 50) AS g;

-- Patients -----------------------------------------------------------
INSERT INTO patient (first_name, last_name, date_of_birth, sex, phone, address)
SELECT (ARRAY['Ade','Chika','Tunde','Ngozi','Ibrahim','Funke','Emeka','Aisha',
              'Segun','Amaka','Yusuf','Bisi','Chidi','Halima','Kunle'])[1 + floor(random() * 15)::int],
       (ARRAY['Adeyemi','Okafor','Bello','Eze','Balogun','Ogunleye','Nwosu','Abdullahi',
              'Olawale','Obi','Musa','Ajayi','Okonkwo','Lawal','Adeleke'])[1 + floor(random() * 15)::int],
       DATE '1940-01-01' + floor(random() * 29000)::int,
       CASE WHEN random() < 0.5 THEN 'M' ELSE 'F' END,
       '080' || lpad((20000000 + g)::text, 8, '0'),
       (1 + floor(random() * 200))::int || ' Sample Street, Ibadan'
FROM generate_series(1, 20000) AS g;

-- Appointments -------------------------------------------------------
-- Every doctor gets 2,000 non-overlapping 30-minute slots (16 per day),
-- so the no_doctor_double_booking constraint is never violated.
WITH slots AS MATERIALIZED (
    SELECT d AS doctor_id,
           TIMESTAMPTZ '2026-09-01 08:00:00+01'
             + (s / 16) * INTERVAL '1 day'
             + (s % 16) * INTERVAL '30 minutes' AS st,
           random() AS r_status,
           random() AS r_reason
    FROM generate_series(1, 50) AS d
    CROSS JOIN generate_series(0, 1999) AS s
),
typed AS MATERIALIZED (
    SELECT doctor_id, st, r_reason,
           CASE WHEN r_status < 0.08 THEN 'cancelled'
                WHEN st < now()      THEN 'completed'
                ELSE 'booked' END AS status
    FROM slots
)
INSERT INTO appointment (patient_id, doctor_id, scheduled_start, scheduled_end,
                         status, reason, diagnosis)
SELECT 1 + floor(random() * 20000)::int,
       doctor_id,
       st,
       st + INTERVAL '30 minutes',
       status,
       (ARRAY['Routine check-up','Fever','Headache','Chest pain','Back pain',
              'Skin rash','Follow-up visit','Blood pressure review'])[1 + floor(r_reason * 8)::int],
       CASE WHEN status = 'completed'
            THEN (ARRAY['Malaria','Hypertension','Typhoid fever','Migraine','Type 2 diabetes',
                        'Upper respiratory infection','Gastritis','Dermatitis',
                        'Lower back strain','Healthy - no issue found'])[1 + floor(random() * 10)::int]
       END
FROM typed;

-- Prescriptions (about 60% of completed visits get one, 20% get a second) ----
INSERT INTO prescription (appointment_id, drug_name, dosage, frequency, duration_days, issued_at)
SELECT appointment_id,
       (ARRAY['Paracetamol 500mg','Amoxicillin 500mg','Artemether-Lumefantrine','Amlodipine 5mg',
              'Metformin 500mg','Ibuprofen 400mg','Omeprazole 20mg','Cetirizine 10mg',
              'Ciprofloxacin 500mg','Loratadine 10mg'])[1 + floor(random() * 10)::int],
       (ARRAY['1 tablet','2 tablets','5 ml','10 ml'])[1 + floor(random() * 4)::int],
       (ARRAY['Once daily','Twice daily','Three times daily'])[1 + floor(random() * 3)::int],
       (ARRAY[3, 5, 7, 14, 30])[1 + floor(random() * 5)::int],
       scheduled_start + INTERVAL '20 minutes'
FROM appointment
WHERE status = 'completed' AND random() < 0.6;

INSERT INTO prescription (appointment_id, drug_name, dosage, frequency, duration_days, issued_at)
SELECT appointment_id,
       (ARRAY['Vitamin C 500mg','Zinc 20mg','Folic acid 5mg','Aspirin 75mg','Salbutamol inhaler'])
           [1 + floor(random() * 5)::int],
       '1 tablet',
       'Once daily',
       (ARRAY[7, 14, 30])[1 + floor(random() * 3)::int],
       scheduled_start + INTERVAL '22 minutes'
FROM appointment
WHERE status = 'completed' AND random() < 0.2;

-- Lab records (about 40% of completed visits) ----------------------------
WITH picks AS MATERIALIZED (
    SELECT appointment_id, scheduled_start, random() AS r_done
    FROM appointment
    WHERE status = 'completed' AND random() < 0.4
)
INSERT INTO lab_record (appointment_id, test_name, result_value, status, requested_at, resulted_at)
SELECT appointment_id,
       (ARRAY['Full blood count','Malaria parasite test','Blood glucose','Lipid profile',
              'Urinalysis','Widal test','Liver function test','Kidney function test'])
           [1 + floor(random() * 8)::int],
       CASE WHEN r_done < 0.85
            THEN (ARRAY['Normal','Abnormal - see notes','Positive','Negative'])[1 + floor(random() * 4)::int]
       END,
       CASE WHEN r_done < 0.85 THEN 'completed' ELSE 'requested' END,
       scheduled_start + INTERVAL '10 minutes',
       CASE WHEN r_done < 0.85
            THEN scheduled_start + INTERVAL '10 minutes' + floor(random() * 48 + 1) * INTERVAL '1 hour'
       END
FROM picks;

-- Refresh planner statistics so execution plans reflect the new data
ANALYZE;

-- Row counts for your evidence screenshot
SELECT 'patient' AS table_name, count(*) FROM patient
UNION ALL SELECT 'doctor',       count(*) FROM doctor
UNION ALL SELECT 'appointment',  count(*) FROM appointment
UNION ALL SELECT 'prescription', count(*) FROM prescription
UNION ALL SELECT 'lab_record',   count(*) FROM lab_record;