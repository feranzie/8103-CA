# Normalisation: Hospital / Clinic System

Scope: patients, doctors, appointments, prescriptions, laboratory records.
The goal is to show how a flat record of a hospital visit is decomposed into the five tables in `schema.sql`, and why each decomposition step was needed.

## 1. Unnormalised form (UNF)

Imagine the hospital first recorded everything about a visit in one flat table:

`visit(appointment_id, appointment_time, status, reason, diagnosis, patient_id, patient_name, patient_dob, patient_phone, doctor_id, doctor_name, specialty, drugs, lab_tests)`

| appointment_id | patient_name | doctor_name | specialty | diagnosis | drugs | lab_tests |
|---|---|---|---|---|---|---|
| 101 | Ada Obi | Dr. Bello | Cardiology | Hypertension | Amlodipine 5mg; Aspirin 75mg | ECG; Lipid profile |
| 102 | Ada Obi | Dr. Eze | General | Malaria | Artemether | Malaria test |

**Problems (anomalies)**
- **Update anomaly:** if Ada Obi changes her phone number, every one of her visit rows must be edited. Missing one leaves contradictory data.
- **Insertion anomaly:** a new doctor or patient cannot be recorded until they have an appointment.
- **Deletion anomaly:** deleting the only appointment of a doctor also deletes everything known about that doctor.
- **Repeating groups:** `drugs` and `lab_tests` hold several values in one cell, so they cannot be searched or constrained properly.

## 2. First Normal Form (1NF)

Rule: every column holds a single atomic value, and there are no repeating groups.

Fix: split the multi-valued `drugs` and `lab_tests` cells into one row each. The table now needs a composite key to identify a row, for example `(appointment_id, drug_name, test_name)`.

**Table in 1NF** (key: `appointment_id, drug_name, test_name`)

| appointment_id | patient_name | doctor_name | diagnosis | drug_name | test_name |
|---|---|---|---|---|---|
| 101 | Ada Obi | Dr. Bello | Hypertension | Amlodipine 5mg | ECG |
| 101 | Ada Obi | Dr. Bello | Hypertension | Amlodipine 5mg | Lipid profile |
| 101 | Ada Obi | Dr. Bello | Hypertension | Aspirin 75mg | ECG |
| 101 | Ada Obi | Dr. Bello | Hypertension | Aspirin 75mg | Lipid profile |
| 102 | Ada Obi | Dr. Eze | Malaria | Artemether | Malaria test |

Every cell is now a single value. Because drugs and tests are independent of each other, appointment 101 (2 drugs, 2 tests) produces 2 × 2 = 4 rows.

This removes repeating groups, but it creates a new problem: appointment, patient and doctor details are now copied on every drug/test row.

## 3. Second Normal Form (2NF)

Rule: 1NF, and no non-key column depends on only part of a composite key.

Partial dependencies found:
- `appointment_id → appointment_time, status, reason, diagnosis, patient_*, doctor_*`
- `(appointment_id, drug_name) → dosage, frequency, duration_days`
- `(appointment_id, test_name) → result_value, status`

Fix: separate the facts by what they depend on.
- `appointment` for facts that depend only on `appointment_id`
- `prescription` for drug facts
- `lab_record` for test facts

Each prescription and lab row now links back to its appointment through `appointment_id`.

**Tables in 2NF**

`appointment` (key: `appointment_id`)

| appointment_id | patient_name | doctor_name | specialty | diagnosis |
|---|---|---|---|---|
| 101 | Ada Obi | Dr. Bello | Cardiology | Hypertension |
| 102 | Ada Obi | Dr. Eze | General | Malaria |

`prescription` (key: `appointment_id, drug_name`)

| appointment_id | drug_name | dosage | frequency |
|---|---|---|---|
| 101 | Amlodipine 5mg | 1 tablet | Once daily |
| 101 | Aspirin 75mg | 1 tablet | Once daily |
| 102 | Artemether | 4 tablets | Twice daily |

`lab_record` (key: `appointment_id, test_name`)

| appointment_id | test_name | result_value |
|---|---|---|
| 101 | ECG | Normal |
| 101 | Lipid profile | High LDL |
| 102 | Malaria test | Positive |

The cross-product rows are gone: each drug and each test is stored once. The `appointment` table still repeats Ada Obi's name for both of her appointments, and `specialty` depends on the doctor rather than on the appointment. That is the transitive dependency that 3NF removes.

## 4. Third Normal Form (3NF)

Rule: 2NF, and no non-key column depends on another non-key column (no transitive dependencies).

Transitive dependencies found in the appointment data:
- `appointment_id → patient_id → patient_name, patient_dob, patient_phone`
- `appointment_id → doctor_id → doctor_name, specialty`

Fix: move patient attributes into `patient` and doctor attributes into `doctor`. `appointment` keeps only `patient_id` and `doctor_id` as foreign keys.

## 5. Final schema and functional dependencies

| Table | Primary key | Determines |
|---|---|---|
| patient | patient_id | first_name, last_name, date_of_birth, sex, phone, address |
| doctor | doctor_id | first_name, last_name, specialty, phone |
| appointment | appointment_id | patient_id, doctor_id, scheduled_start, scheduled_end, status, reason, diagnosis |
| prescription | prescription_id | appointment_id, drug_name, dosage, frequency, duration_days, issued_at |
| lab_record | lab_record_id | appointment_id, test_name, result_value, status, requested_at, resulted_at |

In every table the only determinant is the primary key, so each table is also in **Boyce-Codd Normal Form (BCNF)**.

The anomalies from section 1 are resolved:
- A patient's phone number is stored once, in `patient`.
- Doctors and patients exist independently of appointments.
- Deleting an appointment does not delete the doctor or patient.
- Drugs and lab tests are one row each and can be queried and constrained.

## 6. Design decisions and trade-offs

- **`diagnosis` stored on `appointment`:** the scope asks to "store diagnosis". A single text field per appointment is the simplest design. The trade-off is that one appointment holds one free-text diagnosis, so it cannot be queried by diagnosis code.
- **`drug_name` as plain text in `prescription`:** this repeats drug names across rows and allows spelling variation. A separate `drug` table would remove that, but it was left out to stay within the stated scope. This is a known, accepted redundancy.
- **Surrogate keys (`SERIAL`):** chosen over natural keys such as names or phone numbers, which can change or repeat.
- **Constraints supporting integrity:** foreign keys, `NOT NULL`, `CHECK` constraints on status values and dates, and the `no_doctor_double_booking` exclusion constraint, which stops overlapping appointments for the same doctor.