
SET search_path TO hospital;

DELETE FROM prescription WHERE appointment_id BETWEEN 900001 AND 900099;
DELETE FROM lab_record   WHERE appointment_id BETWEEN 900001 AND 900099;
DELETE FROM appointment  WHERE appointment_id BETWEEN 900001 AND 900099;
DELETE FROM patient      WHERE patient_id = 900001;
DELETE FROM doctor       WHERE doctor_id  = 900001;

INSERT INTO patient (patient_id, first_name, last_name, date_of_birth, sex)
VALUES (900001, 'Tx', 'Tester', DATE '1990-01-01', 'F');

INSERT INTO doctor (doctor_id, first_name, last_name, specialty)
VALUES (900001, 'Tx', 'Doctor', 'General Practice');

INSERT INTO appointment (appointment_id, patient_id, doctor_id,
                         scheduled_start, scheduled_end, status, reason, diagnosis)
VALUES (900001, 900001, 900001, TIMESTAMPTZ '2030-06-01 09:00+00', TIMESTAMPTZ '2030-06-01 09:30+00',
        'booked', 'Fever', 'Malaria'),
       (900002, 900001, 900001, TIMESTAMPTZ '2030-06-01 10:00+00', TIMESTAMPTZ '2030-06-01 10:30+00',
        'booked', 'Headache', NULL);