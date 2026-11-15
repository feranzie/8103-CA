# Portfolio 4: NoSQL Model for the Hospital / Clinic System
## 1. Model chosen

**Document database: MongoDB.** The same hospital data from Portfolios 1 to 3 (patients, doctors, appointments, prescriptions, laboratory records) is remodelled as documents. The data was exported from the PostgreSQL database with a SQL script, so both systems hold identical data: 20,000 patients, 100,000 appointments, 40680 prescriptions and 20329 lab records.

## 2. Why a document model fits this case study

The main operation in the scope is **retrieve patient history**. In the relational design that needs joins across four tables (patient, appointment, prescription, lab record). A clinician reading a history wants the whole record at once, so the document model stores it as one unit: a patient document contains that patient's appointments, and each appointment contains its prescriptions and lab records.

## 3. Collections and document structure

| Collection | Contents |
|---|---|
| `patients` | One document per patient, with embedded `appointments[]`, each holding `prescriptions[]` and `lab_records[]` |
| `doctors` | One document per doctor (the master copy of doctor data) |

Sample `patients` document (shortened to two appointments):

```json
{
  "_id": 5,
  "first_name": "Ibrahim",
  "last_name": "Okonkwo",
  "date_of_birth": { "$date": "1986-10-08T00:00:00.000Z" },
  "sex": "F",
  "phone": "08020000123",
  "address": "14 Sample Street, Ibadan",
  "appointments": [
    {
      "appointment_id": 74455,
      "doctor": { "doctor_id": 38, "name": "Doctor38 Surname38", "specialty": "Gynaecology" },
      "scheduled_start": { "$date": "2026-09-29T10:00:00.000Z" },
      "scheduled_end":   { "$date": "2026-09-29T10:30:00.000Z" },
      "status": "completed",
      "reason": "Headache",
      "diagnosis": "Typhoid fever",
      "prescriptions": [
        { "drug_name": "Omeprazole 20mg", "dosage": "10 ml", "frequency": "Three times daily",
          "duration_days": 30, "issued_at": { "$date": "2026-09-29T10:20:00.000Z" } }
      ],
      "lab_records": [
        { "test_name": "Liver function test", "result_value": "Abnormal - see notes", "status": "completed",
          "requested_at": { "$date": "2026-09-29T10:10:00.000Z" },
          "resulted_at":  { "$date": "2026-09-30T20:10:00.000Z" } }
      ]
    },
    {
      "appointment_id": 97325,
      "doctor": { "doctor_id": 49, "name": "Doctor49 Surname49", "specialty": "Cardiology" },
      "scheduled_start": { "$date": "2026-11-22T13:00:00.000Z" },
      "scheduled_end":   { "$date": "2026-11-22T13:30:00.000Z" },
      "status": "booked", "reason": "Fever", "diagnosis": null,
      "prescriptions": [], "lab_records": []
    }
  ]
}
```

## 4. Embed or reference: the design decisions

| Relationship | Decision | Reason |
|---|---|---|
| patient to appointments | **Embedded** | Always read together; one patient has a bounded number of appointments (the largest document here holds 16) |
| appointment to prescriptions, lab records | **Embedded** | They belong to exactly one appointment and are never read on their own |
| appointment to doctor | **Referenced by `doctor_id`, plus a copy of `name` and `specialty`** | Doctors are shared by thousands of appointments, so they keep their own collection. The copy avoids a lookup when displaying a history |

How the tables map: `patient`, `appointment`, `prescription` and `lab_record` collapse into one nested `patients` document. `doctor` stays separate.

## 5. The same operations in SQL and MongoDB

| Operation | PostgreSQL | MongoDB |
|---|---|---|
| Retrieve patient history | `appointment` joined to `doctor`, with subqueries on `prescription` and `lab_record` | `db.patients.findOne({_id: ...})`, one read, no joins |
| Book an appointment | `INSERT INTO appointment` | `$push` onto the patient's `appointments` array |
| Store a diagnosis | `UPDATE appointment` (and separate inserts for prescription and lab record) | One `updateOne` using `$set` and `$push` with the positional `$` operator |
| Pending lab requests | `WHERE status = 'requested'` plus joins | `$unwind` twice, then `$match` |
| Doctor's schedule | `WHERE doctor_id = ? AND scheduled_start ...` | `$elemMatch` to find patients, then `$unwind` and `$match` |

A diagnosis, a prescription and a lab request are changed with a single `updateOne` on a single document, and MongoDB guarantees that one-document update is atomic. In PostgreSQL the same work needed an explicit transaction across three tables (Portfolio 3, Part 1).

## 6. Strengths for this case study

- **Fast, simple history retrieval.** One lookup by `_id` examines one document (see section 8).
- **Natural fit for the data.** The record is hierarchical, and a patient's history is read far more often than it is restructured.
- **Atomic updates within a patient.** Everything in one patient document changes together or not at all.
- **Schema flexibility.** Different lab tests could carry different result fields without altering a table.

## 7. Weaknesses and trade-offs

- **Duplicated doctor data.** The doctor's name and specialty are copied into every appointment. If a doctor's name changes, every copy must be updated. This is exactly the kind of redundancy that normalisation removed in Portfolio 1, accepted here deliberately in exchange for faster reads.
- **No built-in integrity rules.** MongoDB does not enforce foreign keys, CHECK constraints, or the `no_doctor_double_booking` exclusion constraint. Preventing a doctor from being double-booked would need extra design, such as a separate slots collection with a unique index, or logic in the application. This is the biggest weakness for the "book appointment" operation.
- **Queries that cut across patients are awkward.** "Doctor 7's schedule" and "appointments per doctor" must `$unwind` appointment arrays out of many patient documents. The model is organised around the patient, so doctor-centred and report-style queries do not suit it.
- **Document growth.** A patient with a very long history makes a larger document. MongoDB limits one document to 16 MB. The largest here is about 8 KB, but a real hospital with decades of records would need a bucketing or referencing strategy.

## 8. Implementation evidence

- Import check: [patients: 20000, doctors: 50, appointments embedded inside patient documents: 100000]
- Patient history lookup: `_id` index, 1 documents examined, 0 ms
- Doctor schedule before the index: COLLSCAN, 20,000 documents examined, 9 ms
[proof](screenshots/Ola-davies_Oluwaferanmi_301931917_before-index.png)
- Doctor schedule after the `idx_doctor_start` index: IXSCAN, 16 documents examined, 0 ms
[proof](screenshots/Ola-davies_Oluwaferanmi_301931917_after-index.png)

[full result](results/Ola-davies_Oluwaferanmi_301931917_mongo-output.txt)

## 9. Conclusion

MongoDB suits the **read-heavy clinical record**: opening a patient's full history is a single document read. The relational design in PostgreSQL remains the better choice for **booking**, where correctness under concurrency matters and the database must guarantee that no doctor is double-booked. A realistic hospital system could combine both: relational for scheduling and billing integrity, and a document store for the clinical record view.