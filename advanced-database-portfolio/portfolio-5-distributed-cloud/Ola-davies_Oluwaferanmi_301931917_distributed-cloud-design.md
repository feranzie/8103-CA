
# Portfolio 5: Distributed and Cloud Database Design for the Hospital System (MongoDB)

This exercise distributes the MongoDB document model from Portfolio 4: replication and automatic failover with a replica set, consistency and availability trade-offs through write concern and read preference, sharding with a hashed shard key, and a discussion of cloud deployment. Everything is based on the same  Clinic case study.

## 1. Goals for the Clinic

| Goal | Why it matters for this case study |
|---|---|
| **Availability** | Reception and doctors must be able to book appointments and record diagnoses even if one database server fails |
| **Read scaling** | Patient-history reads and reports should not slow down booking |
| **Consistency where it is safe to be strict** | A prescription or a booking must never be silently lost |
| **Room to grow** | The design should still work if the clinic becomes a multi-branch hospital group |

## 2. What was designed

| Area | Approach | Evidence |
|---|---|---|
| Replication | Three-node MongoDB replica set (`rs1`, `rs2`, `rs3`) in Docker | E1, E2 |
| Consistency | Write concern (`w: "majority"`) and read preference, with replica lag simulated by a delayed secondary | E3, E5 |
| Availability | Automatic election of a new primary when the primary is stopped | E4 |
| Sharding | Config server, two shards and a `mongos` router, with a hashed patient `_id` as the shard key | E6, E7 |
| Deployment | Discussion of managed cloud options (section 8) | Architectural analysis |

The Docker Compose files are in the repository: `Ola-davies_Oluwaferanmi_301931917_05-mongo-replicaset-compose.yml`and `Ola-davies_Oluwaferanmi_301931917_05-mongo-sharded-compose.yml` 

## 3. The data being distributed

The `patients` collection holds one document per patient, with that patient's appointments embedded and each appointment embedding its prescriptions and lab records (Portfolio 4). The documents were exported from the relational database and validated before loading into the distributed clusters:

| Check | Result |
|---|---|
| Patient documents exported | 20,000, with no malformed lines |
| Appointments embedded inside them | 100,000, equal to the appointment rows in the relational database |
| Most appointments in one patient document | 16 |
| Largest single document | ~8 KB (average ~1 KiB on shard; well below MongoDB's 16 MB BSON limit) |

Small, self-contained documents matter for distribution: each patient fits easily on one shard, and one document is always read or written atomically as a single unit.

## 4. Replication

A replica set keeps the same data on several servers. One member is the **primary** and receives all writes. The **secondaries** copy the primary's operation log (oplog) and apply it. In this exercise `rs1` has a higher priority (`priority: 2`), so it is preferred as primary.

- **Writes** always go to the primary. A write sent directly to a secondary is rejected with `MongoServerError: not primary` (E2).
- **Reads** go to the primary by default. A client can choose a **read preference** such as `secondaryPreferred` to read from secondaries and take load off the primary.
- **Three members** is the smallest set that survives the loss of one node and still retains a voting majority (2 of 3).

**How the clinic would use it:** booking, diagnoses, prescriptions and lab entries go to the primary. Reports, such as monthly appointment counts, read from secondaries.

## 5. Consistency and availability

Replication forces a trade-off between how fresh and safe the data is and how available the system stays when something fails (the CAP theorem). MongoDB lets the application tune this **per operation**.

| Setting | Behaviour | Favours |
|---|---|---|
| Write concern `w: 1` | The primary confirms as soon as it has written locally. If it fails before secondaries copy the write, the write can be rolled back | Speed and availability |
| Write concern `w: "majority"` | The write is confirmed only after a majority of voting members have persisted it, so it survives a failover | Consistency and durability |
| Read preference `primary` (default) | Always reads current data from the primary | Strong consistency |
| Read preference `secondaryPreferred` | Spreads reads across secondaries, which may lag behind the primary and return **stale** data | Read scaling |

**Lag was simulated** with a delayed secondary (`secondaryDelaySecs: 20` on `rs3`): patient `_id: 900002` written on the primary returned `0` on `rs3` immediately after insertion (`rs.printSecondaryReplicationInfo()` reported `rs3:27017` at `30 secs behind the primary`), and returned `1` after waiting 25 seconds (E3). In production, the same effect occurs under heavy write load or network congestion, causing a "read your own writes" anomaly if a doctor saves a diagnosis and immediately reads from a lagging secondary.

**Choice for this clinic:**
- Bookings, diagnoses and prescriptions are safety-critical: use `w: "majority"` and read from the primary immediately after a write.
- Browsing historical analytics and administrative reports can tolerate a short delay: read from secondaries via `secondaryPreferred`.

**What happens when a majority is lost (CP behaviour).** When `rs2` and `rs3` were stopped, only `rs1` remained (1 of 3 members—no majority). Because Docker removes stopped container hostnames from internal DNS, the replica-set seed-list connection failed with `MongoServerSelectionError: getaddrinfo ENOTFOUND rs2`. Connecting directly to `rs1` confirmed that it stepped down to secondary (`is secondary: true`), continued serving reads (`reads still work: 20003`), and rejected writes with `MongoServerError: not primary` (E5). MongoDB therefore enforces **consistency over write availability** during a partition rather than risking split-brain divergence.

## 6. Availability and automatic failover

When `rs1` was stopped, the remaining members (`rs2` and `rs3`, holding 2 of 3 votes) detected the heartbeat loss and automatically elected `rs2:27017` as `PRIMARY` within the 15-second window, allowing write `_id: 900004` to succeed with `w: "majority"` without human intervention (E4). When `rs1` was restarted, it rejoined automatically, caught up via the oplog, and reclaimed `PRIMARY` due to its higher priority (`test patients present: 3`).

What this exercise does not cover, and production requires:
- **Rollback of unconfirmed writes:** Writes using `w: 1` that have not replicated prior to a primary crash are rolled back when the old primary rejoins. Using `w: "majority"` for clinical writes prevents this.
- **Retryable writes in the driver:** During the brief election window (~10–12 seconds), in-flight writes fail unless retried; modern MongoDB drivers enable `retryWrites=true` by default.
- **Odd number of voting members:** Maintaining 3 (or 5) voting members avoids tied elections.

## 7. Sharding

**Sharding** partitions a collection across multiple servers using a **shard key**. The cluster consists of a config server (`cfgrs`), two shards (`shard1rs`, `shard2rs`), and a `mongos` router that routes queries.

**Shard key chosen: hashed patient `_id`** (`sh.shardCollection("hospital.patients", { _id: "hashed" })`).

| Option | Patient history | Doctor's schedule | Verdict |
|---|---|---|---|
| Hashed patient `_id` | **One shard** (`SINGLE_SHARD`) | **All shards** (`SHARD_MERGE`) | **Chosen:** matches the primary clinical read and distributes data evenly (~49.3% vs ~50.7%) |
| Ranged patient `_id` | One shard | All shards | **Rejected:** monotonically increasing patient IDs route all new inserts to the highest chunk (write hotspot) |
| Doctor ID | Scattered | One shard | **Not possible in this model:** `doctor_id` is nested inside the embedded `appointments` array, and MongoDB prohibits sharding on array fields |

**Observed routing and storage behaviour:**
- The 20,000 documents (35.9 MiB across 4 chunks) distributed evenly: `shard1rs` held **9,859 documents (49.29%, 17.74 MiB)** and `shard2rs` held **10,141 documents (50.70%, 18.15 MiB)** (E6).
- Looking up a patient by `_id` (`{ _id: 1000 }`) executed a targeted **`SINGLE_SHARD`** plan hitting only `['shard2rs']` (E7).
- Querying by doctor (`{ "appointments.doctor.doctor_id": 7 }`) lacked the shard key, forcing `mongos` to perform a **`SHARD_MERGE`** scatter-gather across both `['shard2rs', 'shard1rs']` (E7).
- **Double-booking constraint trade-off:** Because a doctor's appointments are embedded inside many patient documents spread across shards, a unique compound index cannot prevent overlapping time slots globally. Enforcing strict slot uniqueness would require a separate `appointments` collection sharded by `doctor_id`, trading away single-document patient history reads.

**Suitability for the Clinic:** At 100,000 appointments (35.9 MiB), sharding is unnecessary operational overhead; a single 3-node replica set is sufficient. Sharding becomes justified if the clinic expands into a multi-branch hospital network storing tens of millions of records.

## 8. Cloud deployment (discussion)

All experiments ran locally in Docker containers, which map directly to managed cloud database services (such as **MongoDB Atlas**):

| Need | Local Docker Exercise | Managed Cloud Equivalent (e.g., MongoDB Atlas) |
|---|---|---|
| Replica set | Three local containers (`rs1`–`rs3`) | Multi-AZ replica set deployed across isolated availability zones |
| Automatic failover | Raft-based elections between containers | Built-in automated failover with managed DNS endpoints |
| Sharding | 1 config server, 2 single-node shards, 1 `mongos` | Managed sharded cluster with redundant config servers and routers |
| Backups & recovery | Not configured | Continuous cloud backups with Point-in-Time Recovery (PITR) |
| Security | Unauthenticated local bridge network | TLS in transit, encryption at rest, SCRAM/X.509 auth, VPC peering |

**Considerations specific to a clinic in Nigeria:**
- **Data protection and residency:** Patient records constitute sensitive personal health data under the **Nigeria Data Protection Act (NDPA) 2023**. Deploying to a cloud region outside Nigeria (e.g., `eu-west-1` or `af-south-1`) requires compliance with NDPA cross-border data transfer safeguards and Data Protection Impact Assessments.
- **Network latency:** Hosting in the nearest available cloud region (`af-south-1` Cape Town or `eu-west-1` Ireland) introduces WAN round-trip latency (~40–120 ms), making `secondaryPreferred` reads and connection pooling important for responsive clinic terminals.
- **Cost vs. operational overhead:** Managed clusters eliminate DBA maintenance (patching, failover orchestration, backups), whereas self-hosting on cloud VMs lowers licensing costs at the expense of requiring 24/7 internal database administration.

## 9. Verified Experimental Evidence
All experiments were executed against the local Docker Compose clusters and captured in `portfolio-5-distributed-cloud/screenshots/`.

| ID | Evidence |  step | Screenshot | Verified Result |
|---|---|---|---|---|
| E1 | Replica set members: one `PRIMARY`, two `SECONDARY` | `A2` | `screenshots/Ola-davies_Oluwaferanmi_301931917_A2.png` | 20,000 patients loaded; `rs1:27017` (`PRIMARY`, `health: 1`), `rs2:27017` (`SECONDARY`, `health: 1`), `rs3:27017` (`SECONDARY`, `health: 1`). |
| E2 | Write on primary visible on secondary; write to secondary refused | `A3` | `screenshots/Ola-davies_Oluwaferanmi_301931917_A3.png` | Write `_id: 900001` (`w: "majority"`) acknowledged and replicated to `rs3` (`count: 1`). Direct insert `_id: 900099` on `rs3` failed with `MongoServerError: not primary`. |
| E3 | Stale read: primary has new patient, delayed secondary returns `0`, then `1` | `A4` | `screenshots/Ola-davies_Oluwaferanmi_301931917_A4.png` | With `secondaryDelaySecs: 20` on `rs3`, immediate read of `_id: 900002` returned `0` (`replLag: '30 secs (0.01 hrs) behind the primary'`); after 25s, read returned `1`. |
| E4 | Automatic election after stopping `rs1`, write accepted, `rs1` rejoins | `A5` | `screenshots/Ola-davies_Oluwaferanmi_301931917_A5.png` | Stopping `rs1` caused `rs2:27017` to win election within 15s and accept write `_id: 900004`. Restarting `rs1` restored all 3 nodes (`test patients present: 3`) with `rs1` reclaiming `PRIMARY`. |
| E5 | Majority lost with two nodes down; lone node serves reads, refuses writes | `A6` | `screenshots/Ola-davies_Oluwaferanmi_301931917_A6.png` | Stopping `rs2` and `rs3` broke majority: seed-list write threw `MongoServerSelectionError: getaddrinfo ENOTFOUND rs2`; direct check on `rs1` confirmed `is secondary: true`, `reads still work: 20003`, and write failed with `MongoServerError: not primary`. |
| E6 | Shard distribution across the two shards | `B5` | `screenshots/Ola-davies_Oluwaferanmi_301931917_B5.png` | 20,000 docs (35.9 MiB, 4 chunks) balanced evenly: `shard1rs` = **9,859 docs (49.29%, 17.74 MiB)**; `shard2rs` = **10,141 docs (50.70%, 18.15 MiB)**. |
| E7 | Patient lookup is `SINGLE_SHARD`; doctor query is `SHARD_MERGE` | `B6` | `screenshots/Ola-davies_Oluwaferanmi_301931917_B6.png` | Patient lookup (`_id: 1000`) routed to **`SINGLE_SHARD` `['shard2rs']`**; doctor query (`appointments.doctor.doctor_id: 7`) executed **`SHARD_MERGE` `['shard2rs', 'shard1rs']`**. |

## 10. Limitations of this exercise

- All containers ran on a single local host , so network partitions were simulated by stopping containers rather than introducing real packet loss or WAN latency.
- The sharded cluster used single-member replica sets for `cfgrs`, `shard1rs`, and `shard2rs` to conserve local resources; production clusters require 3-member replica sets per shard and config server for fault tolerance.
- Authentication (`keyFile` / SCRAM), TLS encryption, and automated backups were omitted in the local sandbox.
- Cloud deployment was evaluated architecturally rather than provisioned on a live cloud account.

## 11. Conclusion

A three-node MongoDB replica set gives the clinic high availability and read scaling with zero manual failover intervention, as surviving members automatically elect a new primary within seconds. Tunable write concerns and read preferences make the CAP trade-off explicit: `w: "majority"` protects clinical writes at the cost of write availability when a majority is lost, whereas `secondaryPreferred` offloads read-heavy reporting with bounded eventual consistency. Sharding on `{ _id: "hashed" }` evenly distributes patient records (~49.3% / ~50.7%) and keeps single-patient lookups targeted (`SINGLE_SHARD`), while cross-patient doctor queries require scatter-gather (`SHARD_MERGE`). Given the clinic's current data footprint, a single multi-AZ replica set is the optimal production choice, reserving sharding for future multi-branch growth.