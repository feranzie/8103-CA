# Portfolio 5: Distributed and Cloud Database Exercise (MongoDB)

**Course:** MIT 8103 – Advanced Database Systems  
**Case Study:** the Clinic (Hospital & Outpatient Management System)  
**Database Engine:** MongoDB 7 (Docker Compose Multi-Node Clusters)  

---

## 1. Overview

This portfolio activity extends the **Clinic** MongoDB document model from Portfolio 4 (`hospital.patients` and `hospital.doctors`) into a distributed database architecture. Using Docker Compose, two distinct distributed topologies were implemented and tested locally:

1. **Part A – High-Availability Replica Set (`hospitalrs`):** A 3-node replica set (`rs1`, `rs2`, `rs3`) demonstrating primary-to-secondary oplog replication, read-only secondary enforcement, simulated replica lag (eventual consistency), automatic leader election during primary failure, and CP (Consistency/Partition-Tolerance) behavior when a voting majority is lost.
2. **Part B – Horizontally Sharded Cluster:** A sharded deployment comprising a config server (`cfgrs`), two shards (`shard1rs`, `shard2rs`), and a `mongos` query router, partitioned using a **hashed `_id` shard key** (`{ _id: "hashed" }`) to compare targeted single-shard routing against scatter-gather queries.

---

## 2. Repository Contents

```text
portfolio-5-distributed-cloud/
├── README.md                                                        architecture & test results
├── Ola-davies_Oluwaferanmi_301931917_distributed-cloud-design.md    # Full architectural design, CAP analysis & cloud strategy
├── Ola-davies_Oluwaferanmi_301931917_05-mongo-replicaset-compose.yml# 3-node replica set + client container definition
├── Ola-davies_Oluwaferanmi_301931917_05-mongo-sharded-compose.yml   # Config server, 2 shards, mongos router + client definition
└── screenshots/                                                     # Captured terminal outputs (E1–E7)
    ├── Ola-davies_Oluwaferanmi_301931917_A2.png                                                       # E1: Replica set health & initial 20,000 document load
    ├── Ola-davies_Oluwaferanmi_301931917_A3.png                                                       # E2: Primary write replication & secondary write rejection
    ├── Ola-davies_Oluwaferanmi_301931917_A4.png                                                       # E3: 20s delayed secondary stale read (0 -> 1) & replLag
    ├── Ola-davies_Oluwaferanmi_301931917_A5.png                                                       # E4: Automatic failover to rs2 & self-healing rejoin of rs1
    ├── Ola-davies_Oluwaferanmi_301931917_A6.png                                                       # E5: Majority loss step-down, read availability & write rejection
    ├── Ola-davies_Oluwaferanmi_301931917_B5.png                                    # E6: Hashed shard distribution across shard1rs & shard2rs
    └── Ola-davies_Oluwaferanmi_301931917_B6.png                                                       # E7: Explain plans (SINGLE_SHARD vs SHARD_MERGE)

```
---
## 3. Distributed Dataset Profile

The `patients` collection stores one self-contained document per patient, embedding that patient's appointments along with nested prescriptions and lab records from Portfolio 4. Before running the distributed experiments, the exported JSONL dataset was validated:

| Validation Metric | Result |
|---|---|
| Patient documents exported | 20,000 (zero malformed records) |
| Embedded appointments | 100,000 (matching the source relational database) |
| Maximum appointments in a single patient document | 16 |
| Maximum / average single document size | ~8 KB max (~1 KiB average on shard; well below MongoDB's 16 MB BSON limit) |

Compact, self-contained patient documents ensure each patient record resides cleanly on a single shard and can be read or updated atomically as one unit.

---

## 4. Reproducible Implementation & Execution Steps

* **Runtime:** Docker Desktop / Docker Engine with Docker Compose v2

* **Input Files:** `Ola-davies_Oluwaferanmi_301931917_patients.jsonl` and `Ola-davies_Oluwaferanmi_301931917_doctors.jsonl` exported from Portfolio 4

### Part A: 3-Node Replica Set (`hospitalrs`)

1. **Start containers and define shell helpers:**
   ```bash
   docker compose -f Ola-davies_Oluwaferanmi_301931917_05-mongo-replicaset-compose.yml up -d

   mrs() { docker exec -i mclient mongosh --quiet "mongodb://rs1:27017,rs2:27017,rs3:27017/hospital?replicaSet=hospitalrs" "$@"; }
   mnode() { local h="$1"; shift; docker exec -i mclient mongosh --quiet "mongodb://$h:27017/hospital?directConnection=true" "$@"; }
   ```

2. **Initiate `hospitalrs` (`rs1` configured with `priority: 2` as preferred primary) and import dataset:**
   ```bash
   mnode rs1 --eval 'rs.initiate({ _id: "hospitalrs", members: [ { _id: 0, host: "rs1:27017", priority: 2 }, { _id: 1, host: "rs2:27017", priority: 1 }, { _id: 2, host: "rs3:27017", priority: 1 } ] })'
   docker exec -i mclient mongoimport --uri "mongodb://rs1:27017,rs2:27017,rs3:27017/hospital?replicaSet=hospitalrs" --collection patients --drop <Ola-davies_Oluwaferanmi_301931917_patients.jsonl
   docker exec -i mclient mongoimport --uri "mongodb://rs1:27017,rs2:27017,rs3:27017/hospital?replicaSet=hospitalrs" --collection doctors --drop < Ola-davies_Oluwaferanmi_301931917_doctors.jsonl
   ```

3. **Verify replication, read-only secondaries, and simulated lag:**
   ```bash
   # Write with majority concern and verify secondary replication & write rejection
   mrs --eval 'db.patients.insertOne({ _id: 900001, first_name: "Repl", last_name: "One", appointments: [] }, { writeConcern: { w: "majority" } })'
   mnode rs3 --eval 'db.getMongo().setReadPref("secondaryPreferred"); print("is secondary:", db.hello().secondary); print("rs3 sees patient 900001:", db.patients.countDocuments({ _id: 900001 }))'
   mnode rs3 --eval 'db.patients.insertOne({ _id: 900099, first_name: "No", last_name: "Way" })'

   # Configure 20-second delayed secondary on rs3 to observe eventual consistency
   mrs --eval 'const c = rs.conf(); c.members[2].priority = 0; c.members[2].secondaryDelaySecs = 20; rs.reconfig(c)'
   mrs --eval 'db.patients.insertOne({ _id: 900002, first_name: "Repl", last_name: "Two", appointments: [] }, { writeConcern: { w: "majority" } })'
   mnode rs3 --eval 'db.getMongo().setReadPref("secondaryPreferred"); print("rs3 sees patient 900002:", db.patients.countDocuments({ _id: 900002 }))'
   mrs --eval 'rs.printSecondaryReplicationInfo()'
   sleep 25
   mnode rs3 --eval 'db.getMongo().setReadPref("secondaryPreferred"); print("rs3 sees patient 900002 later:", db.patients.countDocuments({ _id: 900002 }))'
   mrs --eval 'const c = rs.conf(); c.members[2].secondaryDelaySecs = 0; c.members[2].priority = 1; rs.reconfig(c)'
   ```

4. **Verify automatic failover and majority-loss behavior, then tear down:**
   ```bash
   # Stop primary (rs1) to trigger automatic election, then restart rs1
   docker stop rs1 && sleep 15
   mrs --eval 'rs.status().members.forEach(m => print(m.name, m.stateStr))'
   mrs --eval 'db.patients.insertOne({ _id: 900004, first_name: "After", last_name: "Failover", appointments: [] }, { writeConcern: { w: "majority" } })'
   docker start rs1 && sleep 30

   # Stop two nodes (rs2, rs3) to break voting majority and observe CP step-down
   docker stop rs2 rs3 && sleep 15
   mnode rs1 --eval 'db.getMongo().setReadPref("secondaryPreferred"); print("is secondary:", db.hello().secondary); print("reads still work:", db.patients.countDocuments())'
   mnode rs1 --eval 'db.patients.insertOne({ _id: 900006, first_name: "Blocked", last_name: "Write" })'

   # Cleanup Part A before starting Part B
   docker compose -f Ola-davies_Oluwaferanmi_301931917_05-mongo-replicaset-compose.yml down -v
   ```

### Part B: Horizontally Sharded Cluster

1. **Start config server and shard nodes, initiate replica sets, and start `mongos`:**
   ```bash
   docker compose -f Ola-davies_Oluwaferanmi_301931917_05-mongo-sharded-compose.yml up -d cfg1 shard1 shard2 sclient
   docker exec sclient mongosh --quiet "mongodb://cfg1:27017/?directConnection=true" --eval 'rs.initiate({ _id: "cfgrs", configsvr: true, members: [{ _id: 0, host: "cfg1:27017" }] })'
   docker exec sclient mongosh --quiet "mongodb://shard1:27017/?directConnection=true" --eval 'rs.initiate({ _id: "shard1rs", members: [{ _id: 0, host: "shard1:27017" }] })'
   docker exec sclient mongosh --quiet "mongodb://shard2:27017/?directConnection=true" --eval 'rs.initiate({ _id: "shard2rs", members: [{ _id: 0, host: "shard2:27017" }] })'
   sleep 10
   docker compose -f Ola-davies_Oluwaferanmi_301931917_05-mongo-sharded-compose.yml up -d mongos
   ```

2. **Shard `hospital.patients` using `{ _id: "hashed" }` and import data (without `--drop`):**
   ```bash
   msh() { docker exec -i sclient mongosh --quiet "mongodb://mongos:27017/hospital" "$@"; }
   msh --eval 'sh.addShard("shard1rs/shard1:27017"); sh.addShard("shard2rs/shard2:27017"); sh.shardCollection("hospital.patients", { _id: "hashed" });'
   docker exec -i sclient mongoimport --uri "mongodb://mongos:27017/hospital" --collection patients < Ola-davies_Oluwaferanmi_301931917_patients.jsonl
   docker exec -i sclient mongoimport --uri "mongodb://mongos:27017/hospital" --collection doctors --drop < Ola-davies_Oluwaferanmi_301931917_doctors.jsonl
   ```

3. **Inspect shard distribution and compare targeted vs. scatter-gather query plans, then clean up:**
   ```bash
   msh --eval 'db.patients.getShardDistribution()'
   msh --eval '
     const targeted = db.patients.find({ _id: 1000 }).explain();
     print("patient lookup by _id:", targeted.queryPlanner.winningPlan.stage, targeted.queryPlanner.winningPlan.shards.map(s => s.shardName));
     const scatter = db.patients.find({ "appointments.doctor.doctor_id": 7 }).explain();
     print("doctor query:", scatter.queryPlanner.winningPlan.stage, scatter.queryPlanner.winningPlan.shards.map(s => s.shardName));'

   docker compose -f Ola-davies_Oluwaferanmi_301931917_05-mongo-sharded-compose.yml down -v
   ```

---

## 5. Verified Experimental Evidence

All experiments were executed against the local Docker Compose clusters and captured in `portfolio-5-distributed-cloud/screenshots/`.

| ID | Scenario Tested | Step | Screenshot | Observed & Verified Outcome |
| :--- | :--- | :---: | :---: | :--- |
| **E1** | Cluster Initialization & Health | `A2` | `screenshots/Ola-davies_Oluwaferanmi_301931917_A2.png` | 20,000 patient documents imported; `rs1:27017` elected `PRIMARY` (`health: 1`), `rs2:27017` and `rs3:27017` online as `SECONDARY` (`health: 1`). |
| **E2** | Oplog Replication & Write Isolation | `A3` | `screenshots/Ola-davies_Oluwaferanmi_301931917_A3.png` | Document `_id: 900001` written with `w: "majority"` replicated immediately to `rs3` (`count: 1`). Direct write (`_id: 900099`) to `rs3` rejected with `MongoServerError: not primary`. |
| **E3** | Replica Lag & Stale Reads | `A4` | `screenshots/Ola-davies_Oluwaferanmi_301931917_A4.png` | Configuring `rs3` with `secondaryDelaySecs: 20` caused an immediate read of `_id: 900002` on `rs3` to return `0` (`replLag: '30 secs (0.01 hrs) behind the primary'`). After waiting 25s, the read returned `1`, demonstrating eventual consistency. |
| **E4** | Automatic Failover & Self-Healing | `A5` | `screenshots/Ola-davies_Oluwaferanmi_301931917_A5.png` | Stopping `rs1` triggered an automatic election within the 15s window; `rs2:27017` became `PRIMARY` and accepted write `_id: 900004`. Restarting `rs1` allowed it to rejoin automatically, sync via oplog, and reclaim `PRIMARY` (`test patients present: 3`). |
| **E5** | Majority Loss (CP Trade-Off) | `A6` | `screenshots/Ola-davies_Oluwaferanmi_301931917_A6.png` | Stopping `rs2` and `rs3` prevented a voting majority. Seed-list connection failed DNS lookup (`MongoServerSelectionError: getaddrinfo ENOTFOUND rs2`), while direct inspection of `rs1` confirmed it stepped down (`is secondary: true`), continued serving reads (`20003` documents), and rejected writes (`MongoServerError: not primary`). |
| **E6** | Hashed Shard Key Distribution | `B5` | `screenshots/Ola-davies_Oluwaferanmi_301931917_B5.png` | 20,000 documents (35.9 MiB across 4 chunks) split evenly: **`shard1rs`** received **9,859 docs (49.29%, 17.74 MiB)** and **`shard2rs`** received **10,141 docs (50.70%, 18.15 MiB)**, avoiding write hotspots. |
| **E7** | Targeted vs. Scatter-Gather Routing | `B6` | `screenshots/Ola-davies_Oluwaferanmi_301931917_B6.png` | Patient lookup by shard key (`{ _id: 1000 }`) executed a targeted **`SINGLE_SHARD`** plan on `['shard2rs']`. Doctor lookup (`{ "appointments.doctor.doctor_id": 7 }`) required a **`SHARD_MERGE`** scatter-gather across `['shard2rs', 'shard1rs']`. |

---

## 6. Architectural Analysis & Design Trade-Offs

### 6.1 Replication & Automatic Failover
A three-node replica set (`hospitalrs`) is the minimum topology capable of surviving a single node failure while preserving a strict voting majority (2 of 3 nodes). Giving `rs1` a higher election priority (`priority: 2`) ensures predictable primary placement under normal operation. When `rs1` was stopped in **E4**, `rs2` and `rs3` detected the heartbeat timeout and automatically elected `rs2:27017` without manual operator promotion. Once `rs1` returned, it re-synchronized via the oplog and reclaimed primary status cleanly. In production, drivers should use `retryWrites=true` so in-flight writes automatically retry across the brief (~10–12 second) election window.

### 6.2 Consistency vs. Availability (CAP Theorem Trade-Offs)
MongoDB allows tuning durability and freshness per operation:

| Configuration | Behavior | Favors | Clinical Use Case at the clinic |
|---|---|---|---|
| `writeConcern: { w: 1 }` | Acknowledged once written to primary memory/journal; vulnerable to rollback if primary crashes prior to replication. | Low latency / availability | Non-critical audit logs or telemetry |
| `writeConcern: { w: "majority" }` | Acknowledged only after a voting majority persists the write, surviving failover. | Strong durability & consistency | Appointment bookings, diagnoses, and prescriptions |
| `readPreference: "primary"` (default) | Reads strictly from the current primary. | Strong consistency ("read your own writes") | Immediate post-consultation chart review |
| `readPreference: "secondaryPreferred"` | Routes reads to secondaries, risking bounded staleness under replication lag (**E3**). | Read scaling | Monthly clinic statistics and administrative reports |

During a network partition where two of three nodes become unreachable (**E5**), the surviving node (`rs1`) cannot form a majority and steps down to secondary. It continues serving read queries (`20003` documents) while rejecting all writes (`MongoServerError: not primary`), enforcing **consistency over write availability (CP)** to prevent split-brain divergence.

### 6.3 Shard Key Selection & Query Routing
Choosing `{ _id: "hashed" }` as the shard key for `hospital.patients` directly aligns with the Clinic's dominant workload:

| Candidate Shard Key | Single-Patient Lookup | Doctor Schedule Query | Evaluation |
|---|---|---|---|
| **Hashed patient `_id`** | Targeted (`SINGLE_SHARD`) | Scatter-gather (`SHARD_MERGE`) | **Selected:** Avoids write hotspots on sequential IDs and balances data (~49.3% / ~50.7%). |
| **Ranged patient `_id`** | Targeted (`SINGLE_SHARD`) | Scatter-gather (`SHARD_MERGE`) | **Rejected:** Monotonically increasing IDs concentrate all new patient inserts onto the highest chunk. |
| **Doctor ID** | Scatter-gather | Targeted | **Infeasible:** `doctor_id` resides inside the embedded `appointments` array, and MongoDB prohibits sharding on array fields. |

**Trade-off on appointment conflict enforcement:** Because appointments are embedded inside patient documents distributed across shards, a unique index cannot prevent double-booking a doctor's time slot across different patients. Enforcing database-level slot uniqueness at scale would require decomposing appointments into a dedicated collection sharded by `doctor_id`, trading single-document patient history reads for transactional scheduling integrity.

---

## 7. Cloud Deployment Strategy & Limitations

### 7.1 Mapping to Managed Cloud Infrastructure (e.g., MongoDB Atlas)
While this exercise ran in local Docker containers, the architecture maps directly to a managed cloud database service:

| Capability | Local Docker Implementation | Production Cloud Equivalent (MongoDB Atlas) |
|---|---|---|
| High availability | 3 containers (`rs1`–`rs3`) on one host | Multi-AZ replica set across isolated availability zones |
| Automated failover | Raft elections across local containers | Built-in failover with managed DNS connection strings |
| Horizontal scaling | 1 config server, 2 single-node shards, 1 `mongos` | Managed sharded cluster with redundant config servers and routers |
| Backup & security | Unauthenticated local network; no backups | TLS in transit, encryption at rest, SCRAM/X.509 auth, VPC peering, and Point-in-Time Recovery (PITR) |

**Operational & Regulatory Considerations for the Clinic:**
* **Data Residency & Compliance:** Patient medical records constitute sensitive health data governed by the **Nigeria Data Protection Act (NDPA) 2023**. Hosting in an offshore cloud region (`af-south-1` Cape Town or `eu-west-1` Ireland) requires cross-border transfer compliance and encryption key governance.
* **Right-Sizing Infrastructure:** With 20,000 patients and 100,000 appointments (~35.9 MiB), sharding adds unnecessary operational cost and complexity today. A single 3-node Multi-AZ replica set is the recommended production deployment for the Clinic, reserving sharding for future multi-hospital expansion.

### 7.2 Exercise Limitations
* All nodes ran on a single local workstation, simulating failures via container stops rather than physical network partitions or cross-region WAN latency.
* Shard and config server replica sets used single members (`cfgrs`, `shard1rs`, `shard2rs`) to stay lightweight locally; production clusters require three voting members per shard.
* Transport encryption (TLS), role-based authentication, and automated backups were omitted in the local sandbox.