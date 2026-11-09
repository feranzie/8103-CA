# Hospital  — ER diagram

```mermaid
    erDiagram
        PATIENT ||--o{ APPOINTMENT : books
        DOCTOR ||--o{ APPOINTMENT : attends
        APPOINTMENT ||--o{ PRESCRIPTION : results_in
        APPOINTMENT ||--o{ LAB_RECORD : requests

        PATIENT {
            int patient_id PK
            varchar first_name
            varchar last_name
            date date_of_birth
            char sex
            varchar phone
            varchar address
        }

        DOCTOR {
            int doctor_id PK
            varchar first_name
            varchar last_name
            varchar specialty
            varchar phone
        }

        APPOINTMENT {
            int appointment_id PK
            int patient_id FK
            int doctor_id FK
            timestamptz scheduled_start
            timestamptz scheduled_end
            varchar status
            varchar reason
            text diagnosis
        }

        PRESCRIPTION {
            int prescription_id PK
            int appointment_id FK
            varchar drug_name
            varchar dosage
            varchar frequency
            int duration_days
            timestamptz issued_at
        }

        LAB_RECORD {
            int lab_record_id PK
            int appointment_id FK
            varchar test_name
            varchar result_value
            varchar status
            timestamptz requested_at
            timestamptz resulted_at
        }
    ```