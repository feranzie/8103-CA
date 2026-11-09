CREATE EXTENSION IF NOT EXISTS btree_gist;  -- for the double-booking constraint

DROP SCHEMA IF EXISTS hospital CASCADE;
CREATE SCHEMA hospital;
SET search_path TO hospital;

CREATE TABLE patient (
    patient_id     SERIAL PRIMARY KEY,
    first_name     VARCHAR(60) NOT NULL,
    last_name      VARCHAR(60) NOT NULL,
    date_of_birth  DATE NOT NULL CHECK (date_of_birth <= CURRENT_DATE),
    sex            CHAR(1) NOT NULL CHECK (sex IN ('M','F')),
    phone          VARCHAR(25),
    address        VARCHAR(200)
);

CREATE TABLE doctor (
    doctor_id      SERIAL PRIMARY KEY,
    first_name     VARCHAR(60) NOT NULL,
    last_name      VARCHAR(60) NOT NULL,
    specialty      VARCHAR(80) NOT NULL,
    phone          VARCHAR(25)
);

-- Book appointment + store diagnosis (diagnosis is filled in after the consultation)
CREATE TABLE appointment (
    appointment_id  SERIAL PRIMARY KEY,
    patient_id      INT NOT NULL REFERENCES patient(patient_id),
    doctor_id       INT NOT NULL REFERENCES doctor(doctor_id),
    scheduled_start TIMESTAMPTZ NOT NULL,
    scheduled_end   TIMESTAMPTZ NOT NULL,
    status          VARCHAR(12) NOT NULL DEFAULT 'booked'
                    CHECK (status IN ('booked','completed','cancelled')),
    reason          VARCHAR(200),
    diagnosis       TEXT,
    CHECK (scheduled_end > scheduled_start),
    -- a doctor cannot have two overlapping, non-cancelled appointments
    CONSTRAINT no_doctor_double_booking
        EXCLUDE USING gist (
            doctor_id WITH =,
            tstzrange(scheduled_start, scheduled_end) WITH &&
        ) WHERE (status <> 'cancelled')
);

-- One row per drug prescribed during an appointment
CREATE TABLE prescription (
    prescription_id SERIAL PRIMARY KEY,
    appointment_id  INT NOT NULL REFERENCES appointment(appointment_id),
    drug_name       VARCHAR(100) NOT NULL,
    dosage          VARCHAR(50) NOT NULL,
    frequency       VARCHAR(50) NOT NULL,
    duration_days   INT NOT NULL CHECK (duration_days > 0),
    issued_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Laboratory tests requested during an appointment, and their results
CREATE TABLE lab_record (
    lab_record_id   SERIAL PRIMARY KEY,
    appointment_id  INT NOT NULL REFERENCES appointment(appointment_id),
    test_name       VARCHAR(100) NOT NULL,
    result_value    VARCHAR(100),
    status          VARCHAR(12) NOT NULL DEFAULT 'requested'
                    CHECK (status IN ('requested','completed')),
    requested_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    resulted_at     TIMESTAMPTZ,
    CHECK (resulted_at IS NULL OR resulted_at >= requested_at)
);

