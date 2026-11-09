# Keys and Constraints

All definitions below are implemented in `Ola-davies_Oluwaferanmi_301931917_schema.sql` (PostgreSQL, schema `hospital`).

## 1. Primary keys

| Table | Primary key | Type | Why |
|---|---|---|---|
| patient | patient_id | SERIAL (surrogate) | Names, phone numbers and dates of birth can change or repeat, so they are unsafe identifiers |
| doctor | doctor_id | SERIAL (surrogate) | Two doctors can share a name; specialty and phone can change |
| appointment | appointment_id | SERIAL (surrogate) | A patient can see the same doctor many times, so no natural combination is unique |
| prescription | prescription_id | SERIAL (surrogate) | One appointment can have several prescriptions, and the same drug can be prescribed again |
| lab_record | lab_record_id | SERIAL (surrogate) | One appointment can request several tests, including repeat tests |

Surrogate keys are used throughout because no stable natural key exists for these entities within the stated scope.

## 2. Foreign keys

| Child table.column | References | Meaning | On delete |
|---|---|---|---|
| appointment.patient_id | patient.patient_id | The patient who booked | NO ACTION |
| appointment.doctor_id | doctor.doctor_id | The doctor attending | NO ACTION |
| prescription.appointment_id | appointment.appointment_id | The appointment the drug was prescribed in | NO ACTION |
| lab_record.appointment_id | appointment.appointment_id | The appointment the test was requested in | NO ACTION |

**Referential integrity rule:** a foreign key may not point to a row that does not exist. `NO ACTION` (the default) means a patient, doctor or appointment that has dependent records cannot be deleted. This is deliberate, because medical history must not be lost by accident.

## 3. Relationships

| Relationship | Cardinality | Implemented by |
|---|---|---|
| patient to appointment | one to many | appointment.patient_id |
| doctor to appointment | one to many | appointment.doctor_id |
| appointment to prescription | one to many | prescription.appointment_id |
| appointment to lab_record | one to many | lab_record.appointment_id |

Patient to doctor is a many-to-many relationship, resolved through the `appointment` table.

## 4. NOT NULL constraints

| Table | Columns that must have a value |
|---|---|
| patient | first_name, last_name, date_of_birth, sex |
| doctor | first_name, last_name, specialty |
| appointment | patient_id, doctor_id, scheduled_start, scheduled_end, status |
| prescription | appointment_id, drug_name, dosage, frequency, duration_days, issued_at |
| lab_record | appointment_id, test_name, status, requested_at |

Optional columns: `phone` and `address` (patient), `phone` (doctor), `reason` and `diagnosis` (appointment), `result_value` and `resulted_at` (lab_record). The diagnosis and lab result are only known after the consultation or test, so they must allow NULL.

## 5. CHECK constraints

| Table | Rule | Purpose |
|---|---|---|
| patient | `date_of_birth <= CURRENT_DATE` | No birth dates in the future |
| patient | `sex IN ('M','F')` | Restricts values to the allowed codes |
| appointment | `status IN ('booked','completed','cancelled')` | Valid lifecycle states only |
| appointment | `scheduled_end > scheduled_start` | An appointment must end after it starts |
| prescription | `duration_days > 0` | A course must last at least one day |
| lab_record | `status IN ('requested','completed')` | Valid test states only |
| lab_record | `resulted_at IS NULL OR resulted_at >= requested_at` | A result cannot arrive before the request |

## 6. Default values

| Table.column | Default | Purpose |
|---|---|---|
| appointment.status | 'booked' | New appointments start as booked |
| prescription.issued_at | now() | Timestamp when issued |
| lab_record.status | 'requested' | New tests start as requested |
| lab_record.requested_at | now() | Timestamp when requested |

## 7. Exclusion constraint (advanced)

```sql
CONSTRAINT no_doctor_double_booking
    EXCLUDE USING gist (
        doctor_id WITH =,
        tstzrange(scheduled_start, scheduled_end) WITH &&
    ) WHERE (status <> 'cancelled')
```

**Rule:** the same doctor cannot have two non-cancelled appointments whose time ranges overlap.

**Why a constraint instead of application code:** the database enforces it for every session. Two receptionists booking the same slot at the same moment cannot both succeed, which is what a check in application code cannot guarantee. This requires the `btree_gist` extension. Cancelled appointments are excluded so that a cancelled slot can be rebooked. This constraint is demonstrated further in Portfolio 3.

## 8. Constraints not used, and why

- **UNIQUE on patient or doctor details (phone, name):** these are not guaranteed unique, for example family members sharing a phone number, so a UNIQUE constraint would reject valid data.
- **ON DELETE CASCADE:** rejected so that deleting a record can never silently remove clinical history.