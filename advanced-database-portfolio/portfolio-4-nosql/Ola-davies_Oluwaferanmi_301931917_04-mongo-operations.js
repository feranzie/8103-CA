// =====================================================================
// MongoDB operations
// =====================================================================

// ---------- 0. Import check ------------------------------------------
print("=== 0. IMPORT CHECK ===");
// Remove any demo appointment left by an earlier run
db.patients.updateMany(
  { "appointments.appointment_id": 900001 },
  { $pull: { appointments: { appointment_id: 900001 } } }
);
print("patients:", db.patients.countDocuments(), "| doctors:", db.doctors.countDocuments());
const totals = db.patients.aggregate([
  { $project: { n: { $size: "$appointments" } } },
  { $group: { _id: null, appointments: { $sum: "$n" } } }
]).toArray()[0];
print("appointments embedded inside patient documents:", totals.appointments);

// A patient with at least 5 appointments, used for the demos below
const pid = db.patients
  .find({ "appointments.4": { $exists: true } }, { _id: 1 })
  .sort({ _id: 1 }).limit(1).next()._id;

// ---------- 1. Retrieve patient history -------------------------------
print("\n=== 1. RETRIEVE PATIENT HISTORY (one read, no joins), patient _id =", pid, "===");
printjson(db.patients.findOne({ _id: pid }));

// ---------- 2. Book an appointment ------------------------------------
print("\n=== 2. BOOK AN APPOINTMENT ($push into the patient's appointments array) ===");
const doc = db.doctors.findOne({ _id: 7 });
printjson(db.patients.updateOne(
  { _id: pid },
  { $push: { appointments: {
      appointment_id: 900001,
      doctor: { doctor_id: doc._id, name: doc.first_name + " " + doc.last_name, specialty: doc.specialty },
      scheduled_start: new Date("2030-06-01T09:00:00Z"),
      scheduled_end:   new Date("2030-06-01T09:30:00Z"),
      status: "booked",
      reason: "Routine check-up",
      diagnosis: null,
      prescriptions: [],
      lab_records: []
  } } }
));
print("--- the new appointment as stored ---");
printjson(db.patients.findOne({ _id: pid, "appointments.appointment_id": 900001 },
                              { "appointments.$": 1 }));

// ---------- 3. Store diagnosis ----------------------------------------
print("\n=== 3. STORE A DIAGNOSIS (status + diagnosis + prescription + lab request in ONE atomic update) ===");
printjson(db.patients.updateOne(
  { _id: pid, "appointments.appointment_id": 900001 },
  {
    $set:  { "appointments.$.status": "completed", "appointments.$.diagnosis": "Malaria" },
    $push: {
      "appointments.$.prescriptions": { drug_name: "Artemether-Lumefantrine", dosage: "4 tablets",
                                         frequency: "Twice daily", duration_days: 3, issued_at: new Date() },
      "appointments.$.lab_records":   { test_name: "Malaria parasite test", result_value: null,
                                         status: "requested", requested_at: new Date(), resulted_at: null }
    }
  }
));
printjson(db.patients.findOne({ _id: pid, "appointments.appointment_id": 900001 },
                              { "appointments.$": 1 }));

// ---------- 4. Pending lab requests (mirrors SQL Q4) ------------------
print("\n=== 4. PENDING LAB REQUESTS, oldest first (aggregation: $unwind, $match, $sort) ===");
db.patients.aggregate([
  { $unwind: "$appointments" },
  { $unwind: "$appointments.lab_records" },
  { $match: { "appointments.lab_records.status": "requested" } },
  { $sort:  { "appointments.lab_records.requested_at": 1 } },
  { $limit: 5 },
  { $project: { _id: 0,
                patient: { $concat: ["$first_name", " ", "$last_name"] },
                test_name: "$appointments.lab_records.test_name",
                requested_at: "$appointments.lab_records.requested_at" } }
]).forEach(printjson);

// ---------- 5. Appointments per doctor, October (mirrors SQL Q3) -----
// Boundaries are written in UTC; the SQL used +01:00, so they are shifted by 1 hour.
print("\n=== 5. APPOINTMENTS PER DOCTOR, OCTOBER 2026 (compare with SQL Q3) ===");
db.patients.aggregate([
  { $unwind: "$appointments" },
  { $match: { "appointments.scheduled_start": {
        $gte: new Date("2026-09-30T23:00:00Z"), $lt: new Date("2026-10-31T23:00:00Z") } } },
  { $group: {
      _id: "$appointments.doctor.doctor_id",
      doctor: { $first: "$appointments.doctor.name" },
      total_appointments: { $sum: 1 },
      completed: { $sum: { $cond: [{ $eq: ["$appointments.status", "completed"] }, 1, 0] } },
      cancelled: { $sum: { $cond: [{ $eq: ["$appointments.status", "cancelled"] }, 1, 0] } } } },
  { $sort: { completed: -1, _id: 1 } },
  { $limit: 5 }
]).forEach(printjson);

// ---------- 6. Doctor's schedule for one day (mirrors SQL Q2) ---------
const dayStart = new Date("2026-10-05T23:00:00Z");   // 2026-10-06 00:00 at +01:00
const dayEnd   = new Date("2026-10-06T23:00:00Z");
const slotFilter = { "doctor.doctor_id": 7, scheduled_start: { $gte: dayStart, $lt: dayEnd },
                     status: { $ne: "cancelled" } };

print("\n=== 6. DOCTOR 7'S SCHEDULE FOR 2026-10-06 ===");
db.patients.aggregate([
  { $match:  { appointments: { $elemMatch: slotFilter } } },   // narrows to candidate patients (can use an index)
  { $unwind: "$appointments" },
  { $match:  { "appointments.doctor.doctor_id": 7,
               "appointments.scheduled_start": { $gte: dayStart, $lt: dayEnd },
               "appointments.status": { $ne: "cancelled" } } },
  { $sort:   { "appointments.scheduled_start": 1 } },
  { $project: { _id: 0,
                patient: { $concat: ["$first_name", " ", "$last_name"] },
                start: "$appointments.scheduled_start",
                reason: "$appointments.reason" } }
]).forEach(printjson);

// ---------- 7. Indexing and execution evidence ------------------------
function planSummary(ex) {
  const plan = JSON.stringify(ex.queryPlanner.winningPlan);
  return { plan: plan.includes("IXSCAN") ? "IXSCAN" : "COLLSCAN",
           keysExamined: ex.executionStats.totalKeysExamined,
           docsExamined: ex.executionStats.totalDocsExamined,
           nReturned: ex.executionStats.nReturned,
           millis: ex.executionStats.executionTimeMillis };
}
const scheduleQuery = { appointments: { $elemMatch: slotFilter } };

print("\n=== 7a. PATIENT HISTORY LOOKUP uses the built-in _id index ===");
printjson(planSummary(db.patients.find({ _id: pid }).explain("executionStats")));

print("\n=== 7b. DOCTOR SCHEDULE: BEFORE adding an index ===");
db.patients.dropIndexes();     // drops every index except _id, so the script is re-runnable
printjson(planSummary(db.patients.find(scheduleQuery).explain("executionStats")));

print("\n=== 7c. DOCTOR SCHEDULE: AFTER adding a compound multikey index ===");
print("created index:", db.patients.createIndex(
  { "appointments.doctor.doctor_id": 1, "appointments.scheduled_start": 1 },
  { name: "idx_doctor_start" }));
printjson(planSummary(db.patients.find(scheduleQuery).explain("executionStats")));

print("\n=== 7d. INDEXES ON THE patients COLLECTION ===");
printjson(db.patients.getIndexes());

// ---------- Cleanup ----------------------------------------------------
db.patients.updateOne({ _id: pid }, { $pull: { appointments: { appointment_id: 900001 } } });
print("\n=== Demo booking removed. Done. ===");