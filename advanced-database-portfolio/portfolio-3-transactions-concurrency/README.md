# Portfolio 3, 
# 1
`Ola-davies_Oluwaferanmi_301931917_tx-00-setup.sql` Creates the test patient, doctor and two appointments, and resets them if you re-run it. It uses IDs from 900001 up, so it can’t clash with your seed data.

`Ola-davies_Oluwaferanmi_301931917_tx-01-commit-rollback.sql` covers four cases:
**1A, COMMIT:** completing a consultation (diagnosis, prescription and lab request) as one atomic unit.
**1B, ROLLBACK:** a booking that’s visible inside the transaction and gone after the rollback.
**1C, atomicity:** a bad prescription makes PostgreSQL refuse every further command (“current transaction is aborted”). After the rollback, nothing from the transaction survives.
**1D, SAVEPOINT:** undo only the failed prescription and keep the valid one.


results can be found: [Output](results/Ola-davies_Oluwaferanmi_301931917_tx-01-output.txt)








# Part 2: Isolation and Concurrency (two terminals)
This section simulates how postgres  works when people update the same rows at once.These scenarios need **two database sessions open at the same time**. For this test i opened seperate terminals and switched between them.

## 2A. READ COMMITTED (PostgreSQL's default isolation level)

in either terminal i ran `UPDATE appointment SET status='booked' WHERE appointment_id=900001;`

| Step | Terminal | SQL |
|---|---|---|
| 1 | A | `BEGIN;` |
| 2 | A | `SELECT status FROM appointment WHERE appointment_id = 900001;` |
| 3 | B | `UPDATE appointment SET status = 'cancelled' WHERE appointment_id = 900001;` |
| 4 | A | `SELECT status FROM appointment WHERE appointment_id = 900001;` |
| 5 | A | `COMMIT;` |


[terminal A](screenshots/Ola-davies_Oluwaferanmi_301931917_2A-terminal-A.png)
[terminal B](screenshots/Ola-davies_Oluwaferanmi_301931917_2A-terminal-B.png)

step 2 shows `booked`. Step 4 shows `cancelled`. Within a single transaction, A read from the same row twice and got different answers. This is a **non-repeatable read**, which READ COMMITTED allows: each statement see the latest committed data.

## 2B. REPEATABLE READ

Reset: `UPDATE appointment SET status='booked' WHERE appointment_id=900001;`

| Step | Terminal | SQL |
|---|---|---|
| 1 | A | `BEGIN ISOLATION LEVEL REPEATABLE READ;` |
| 2 | A | `SELECT status FROM appointment WHERE appointment_id = 900001;` |
| 3 | B | `UPDATE appointment SET status = 'cancelled' WHERE appointment_id = 900001;` |
| 4 | A | `SELECT status FROM appointment WHERE appointment_id = 900001;` |
| 5 | A | `COMMIT;` |
| 6 | A | `SELECT status FROM appointment WHERE appointment_id = 900001;` |

[terminal A](screenshots/Ola-davies_Oluwaferanmi_301931917_2B-terminal-A.png)
[terminal B](screenshots/Ola-davies_Oluwaferanmi_301931917_2B-terminal-B.png)


 steps 2 and 4 both show `booked`, because A works from a snapshot taken at its first query, so B's committed change is invisible to it. After the `COMMIT` (step 6), A sees `cancelled`. The cost of this stronger isolation is that A may be working with data that is already out of date.

---
## 3A. Concurrency issue: lost update

Scenario: Two doctors add to the same diagnosis. Each reads the current text, then writes back their own version.

Reset: `UPDATE appointment SET status='booked', diagnosis='Malaria' WHERE appointment_id=900001;`

| Step | Terminal | SQL |
|---|---|---|
| 1 | A | `BEGIN;` |
| 2 | A | `SELECT diagnosis FROM appointment WHERE appointment_id = 900001;` |
| 3 | B | `BEGIN;` |
| 4 | B | `SELECT diagnosis FROM appointment WHERE appointment_id = 900001;` |
| 5 | A | `UPDATE appointment SET diagnosis = 'Malaria; Typhoid fever' WHERE appointment_id = 900001;` |
| 6 | A | `COMMIT;` |
| 7 | B | `UPDATE appointment SET diagnosis = 'Malaria; Anaemia' WHERE appointment_id = 900001;` |
| 8 | B | `COMMIT;` |
| 9 | A | `SELECT diagnosis FROM appointment WHERE appointment_id = 900001;` |

[terminal A](screenshots/Ola-davies_Oluwaferanmi_301931917_3A-terminal-A.png)
[terminal B](screenshots/Ola-davies_Oluwaferanmi_301931917_3A-terminal-B.png)

both read `Malaria`. The final result is `Malaria; Anaemia`. **Doctor A's "Typhoid fever" has been silently lost**, and neither session received an error. B wrote its answer based on a value that was already stale.

## 3B. Control mechanism: row locking with `SELECT ... FOR UPDATE`

Reset: `UPDATE appointment SET status='booked', diagnosis='Malaria' WHERE appointment_id=900001;`

| Step | Terminal | SQL |
|---|---|---|
| 1 | A | `BEGIN;` |
| 2 | A | `SELECT diagnosis FROM appointment WHERE appointment_id = 900001 FOR UPDATE;` |
| 3 | B | `BEGIN;` |
| 4 | B | `SELECT diagnosis FROM appointment WHERE appointment_id = 900001 FOR UPDATE;` |
| 5 | C | `SELECT pid, state, wait_event_type, wait_event, left(query, 60) AS query FROM pg_stat_activity WHERE datname = 'hospital' AND wait_event_type = 'Lock';` |
| 6 | A | `UPDATE appointment SET diagnosis = 'Malaria; Typhoid fever' WHERE appointment_id = 900001;` |
| 7 | A | `COMMIT;` |
| 8 | B |  `UPDATE appointment SET diagnosis = 'Malaria; Typhoid fever; Anaemia' WHERE appointment_id = 900001;` |
| 9 | B | `COMMIT;` |
| 10 | A | `SELECT diagnosis FROM appointment WHERE appointment_id = 900001;` |

[terminal A](screenshots/Ola-davies_Oluwaferanmi_301931917_3B-terminal-A.png)
[terminal B](screenshots/Ola-davies_Oluwaferanmi_301931917_3B-terminal-B.png)
[terminal C](screenshots/Ola-davies_Oluwaferanmi_301931917_3B-terminal-C.png)


at step 4, **B appears to hang**: B is waiting for A. Step 5 shows B waiting with `wait_event_type = Lock`. When A commits (step 7), B's query returns **`Malaria; Typhoid fever`**, the up-to-date value, so B builds on it instead of overwriting it. Step 10 shows `Malaria; Typhoid fever; Anaemia`: which shows that both doctors work survives.


---

## 4A. Double booking: the first transaction commits

This is the "book appointment" operation under concurrency. The control mechanism is the `no_doctor_double_booking` exclusion constraint.

Reset: `DELETE FROM appointment WHERE appointment_id IN (900010, 900011);`

| Step | Terminal | SQL |
|---|---|---|
| 1 | A | `BEGIN;` |
| 2 | A | `INSERT INTO appointment (appointment_id, patient_id, doctor_id, scheduled_start, scheduled_end) VALUES (900010, 900001, 900001, TIMESTAMPTZ '2030-07-01 09:00+00', TIMESTAMPTZ '2030-07-01 09:30+00');` |
| 3 | B | `BEGIN;` |
| 4 | B | `INSERT INTO appointment (appointment_id, patient_id, doctor_id, scheduled_start, scheduled_end) VALUES (900011, 900001, 900001, TIMESTAMPTZ '2030-07-01 09:15+00', TIMESTAMPTZ '2030-07-01 09:45+00');` |
| 5 | C | `SELECT pid, state, wait_event_type, wait_event, left(query, 60) AS query FROM pg_stat_activity WHERE datname = 'hospital' AND wait_event_type = 'Lock';` |
| 6 | A | `COMMIT;` |
| 7 | B | *(step 4 now fails by itself)* then: `ROLLBACK;` |


[terminal A](screenshots/Ola-davies_Oluwaferanmi_301931917_4A-terminal-A.png)
[terminal B](screenshots/Ola-davies_Oluwaferanmi_301931917_4A-terminal-B.png)
[terminal C](screenshots/Ola-davies_Oluwaferanmi_301931917_4A-terminal-C.png)

at step 4, **B waits**, because A's booking is not committed yet, so the database cannot yet say whether the slots conflict. After A commits (step 6), B receives: `ERROR: conflicting key value violates exclusion constraint "no_doctor_double_booking"`
Two receptionists tried to book overlapping slots for one doctor at the same moment, and exactly one succeeded. No application code was needed.