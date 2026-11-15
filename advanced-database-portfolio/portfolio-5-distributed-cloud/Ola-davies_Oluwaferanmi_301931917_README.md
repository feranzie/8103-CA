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
    ├── Ola-davies_Oluwaferanmi_301931917_a6.png                                                       # E5: Majority loss step-down, read availability & write rejection
    ├── Ola-davies_Oluwaferanmi_301931917_B5.png                                    # E6: Hashed shard distribution across shard1rs & shard2rs
    └── Ola-davies_Oluwaferanmi_301931917_B6.png                                                       # E7: Explain plans (SINGLE_SHARD vs SHARD_MERGE)