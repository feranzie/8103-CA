# MIT 8103 Advanced Database Systems: Individual Practical Database Portfolio

**Student:** Oluwaferanmi Ola-davies | **Student ID:** 301931917 | **Session:** 2026/2027, First Semester

## Case study

**the Clinic**, a simulated outpatient clinic.

| | |
|---|---|
| Nature of the system | Outpatient consultations: booking, diagnosis, prescriptions, laboratory tests |
| Users | Receptionists, doctors, laboratory staff |
| Major data | Patients, doctors, appointments, prescriptions, laboratory records |
| Key operations | Book an appointment, store a diagnosis, retrieve patient history |

All five portfolio activities use this one case study. PostgreSQL is used for Portfolios 1 to 3 and MongoDB for Portfolios 4 and 5. Everything runs in Docker.

## Repository structure


```
advanced-database-portfolio/
├── portfolio-1-database-design/
│   ├──  Ola-davies_Oluwaferanmi_301931917_schema.sql · Ola-davies_Oluwaferanmi_301931917_ERDiagram.md
│   ├── Ola-davies_Oluwaferanmi_301931917_KeysConstraints.md · Ola-davies_Oluwaferanmi_301931917_normalisation.md
│   ├── Ola-davies_Oluwaferanmi_301931917_constraint-tests.sql · 
│   └── results/Ola-davies_Oluwaferanmi_301931917_constraint-tests-output.txt
    
├── portfolio-2-query-optimisation/
│   ├── Ola-davies_Oluwaferanmi_301931917_seed.sql · Ola-davies_Oluwaferanmi_301931917_query.sql · 
│   ├── Ola-davies_Oluwaferanmi_301931917_explain-before.sql 
│   ├── Ola-davies_Oluwaferanmi_301931917_indexes.sql 
│   ├── Ola-davies_Oluwaferanmi_301931917_explain-after.sql 
│   ├── Ola-davies_Oluwaferanmi_301931917_performance-analysis.md
│   └── screenshots/
│   └── results/
├── portfolio-3-transactions-concurrency/
│   ├── Ola-davies_Oluwaferanmi_301931917_tx-00-setup.sql · Ola-davies_Oluwaferanmi_301931917_tx-01-commit-rollback.sql 
│   ├── tx-02-concurrency-runbook.md · Ola-davies_Oluwaferanmi_301931917_tx-99-cleanup.sql
│   ├── Ola-davies_Oluwaferanmi_301931917_README.md
│   └── screenshots/
│   └── results/
├── portfolio-4-nosql/
│   ├── Ola-davies_Oluwaferanmi_301931917_04-export-doctors.sql 
│   ├── Ola-davies_Oluwaferanmi_301931917_04-export-from-postgres.sql
│   ├── Ola-davies_Oluwaferanmi_301931917_README.md
│   ├── Ola-davies_Oluwaferanmi_301931917_04-mongo-operations.js
│   ├── Ola-davies_Oluwaferanmi_301931917_doctors.jsonl
│   ├── Ola-davies_Oluwaferanmi_301931917_patients.jsonl
│   └── screenshots/
│   └── results/
├── portfolio-5-distributed-cloud/
│   ├── Ola-davies_Oluwaferanmi_301931917_05-mongo-replicaset-compose.yml ·
Ola-davies_Oluwaferanmi_301931917_05-mongo-sharded-compose.yml
│   ├── Ola-davies_Oluwaferanmi_301931917_distributed-cloud-design.md
│   ├── Ola-davies_Oluwaferanmi_301931917_README.md
│   └── screenshots/
└── README.md
```

Large generated files (`Ola-davies_Oluwaferanmi_301931917_patients.jsonl`, `Ola-davies_Oluwaferanmi_301931917_doctors.jsonl`) are not committed. They are produced by the Portfolio 4 export scripts.

## Requirements

- Docker
- A PostgreSQL container named `my-postgres` with a database called `hospital`
- A MongoDB 7 image (`mongo:7`) for Portfolios 4 and 5

## Portfolio 1: Database design and modelling

**What it contains:** a five-table relational design (`patient`, `doctor`, `appointment`, `prescription`, `lab_record`) in the `hospital` schema, with primary keys, foreign keys, CHECK and NOT NULL constraints, and an exclusion constraint (`no_doctor_double_booking`) that prevents overlapping appointments for one doctor. The normalisation document walks from an unnormalised visit record to 3NF with example tables.
![diagram](advanced-database-portfolio/portfolio-1-database-design/Ola-davies_Oluwaferanmi_301931917_ERDiagram.md)

**How to run it:**

```bash
docker exec -i my-postgres psql -U postgres -c "CREATE DATABASE hospital;"
docker exec -i my-postgres psql -U postgres -d hospital < Ola-davies_Oluwaferanmi_301931917_schema.sql
```

**How it was tested:** `Ola-davies_Oluwaferanmi_301931917_constraint-tests.sql` runs 13 tests that deliberately break each rule (double booking, bad status, future birth date, foreign key violation and others) plus positive controls that should succeed. The output is in `results/Ola-davies_Oluwaferanmi_301931917_constraints-test-output` .

## Portfolio 2: Query processing and optimisation

**What it contains:** a seed script generating 50 doctors, 20,000 patients and 100,000 appointments (with prescriptions and lab records), four benchmark queries, six indexes (foreign key, composite and partial), and execution plans before and after.

**How to run it, in order:**

```bash
docker exec -i my-postgres psql -U postgres -d hospital < Ola-davies_Oluwaferanmi_301931917_seed.sql
docker exec -i my-postgres psql -U postgres -d hospital < Ola-davies_Oluwaferanmi_301931917_query.sql > query-results.txt
docker exec -i my-postgres psql -U postgres -d hospital < Ola-davies_Oluwaferanmi_301931917_explain-before.sql > explain-before.txt
docker exec -i my-postgres psql -U postgres -d hospital < Ola-davies_Oluwaferanmi_301931917_indexes.sql > index-creation-output.txt
docker exec -i my-postgres psql -U postgres -d hospital < Ola-davies_Oluwaferanmi_301931917_explain-after.sql > explain-after.txt
```

(The explain scripts include the query file with `\ir`, so run them from a location where the relative path resolves, or from inside the container's working folder.)

**How it was tested:** each query was run with `EXPLAIN (ANALYZE, BUFFERS)` before and after indexing, twice, and the warm-cache run was recorded. Results are summarised in `Ola-davies_Oluwaferanmi_301931917_performance-analysis.md`.

## Portfolio 3: Transactions and concurrency

**What it contains:** a single-session script (commit, rollback, atomicity, savepoint) and a two-terminal runbook covering isolation levels, a lost update and its prevention with `SELECT ... FOR UPDATE`, and concurrent double booking controlled by the exclusion constraint.

**How to run it:**

```bash
docker exec -i my-postgres psql -U postgres -d hospital < Ola-davies_Oluwaferanmi_301931917_tx-00-setup.sql
docker exec -i my-postgres psql -U postgres -d hospital < Ola-davies_Oluwaferanmi_301931917_tx-01-commit-rollback.sql > tx-01-output.txt 2>&1
```

Then follow instructions in `Ola-davies_Oluwaferanmi_301931917_README.md` in two terminals, and finish with `Ola-davies_Oluwaferanmi_301931917_tx-99-cleanup.sql`.

**How it was tested:** output files plus side-by-side terminal screenshots for each scenario in `screenshots/`.

## Portfolio 4: NoSQL and advanced data models

**What it contains:** a MongoDB `patients` collection with appointments embedded (and prescriptions and lab records embedded inside each appointment), plus a `doctors` collection. The data is exported from PostgreSQL as JSON Lines, so both databases hold the same data. The operations script covers patient history, booking, storing a diagnosis, aggregation queries, and indexing with `explain` output.
**How to run it:**

```bash
docker exec -i my-postgres psql -U postgres -d hospital -q -At < Ola-davies_Oluwaferanmi_301931917_04-export-from-postgres.sql > Ola-davies_Oluwaferanmi_301931917_patients.jsonl
docker exec -i my-postgres psql -U postgres -d hospital -q -At < Ola-davies_Oluwaferanmi_301931917_04-export-doctors.sql > Ola-davies_Oluwaferanmi_301931917_doctors.jsonl
docker run --name my-mongo -p 27017:27017 -d mongo:7
docker exec -i my-mongo mongoimport --db hospital --collection patients --drop < Ola-davies_Oluwaferanmi_301931917_patients.jsonl
docker exec -i my-mongo mongoimport --db hospital --collection doctors --drop < Ola-davies_Oluwaferanmi_301931917_doctors.jsonl
docker cp Ola-davies_Oluwaferanmi_301931917_04-mongo-operations.js my-mongo:/tmp/ops.js
docker exec my-mongo mongosh hospital --quiet --file /tmp/ops.js > results/Ola-davies_Oluwaferanmi_301931917_mongo-output.txt
```

**How it was tested:** the export was validated (20,000 documents, 100,000 embedded appointments, counts matching the relational tables), and the aggregation results were compared with the equivalent SQL queries.

## Portfolio 5: Distributed and cloud database

**What it contains:** a three-node MongoDB replica set and a sharded cluster (config server, two shards, `mongos` router) defined in Docker Compose, with a runbook, and a design document covering replication, consistency, availability, sharding and cloud deployment.

**How to run it:** follow steps in `Ola-davies_Oluwaferanmi_301931917_README.md`. Run Part A (replica set) and Part B (sharding) one at a time:

```bash
docker compose -f Ola-davies_Oluwaferanmi_301931917_05-mongo-replicaset-compose.yml up -d
docker compose -f Ola-davies_Oluwaferanmi_301931917_05-mongo-sharded-compose.yml up -d cfg1 shard1 shard2 sclient
```

**How it was tested:** the experiments (replica set status, replication, replica lag, automatic failover, majority loss, shard distribution and query routing) are recorded with screenshots in `screenshots/`, and their results are in section 9 of `Ola-davies_Oluwaferanmi_301931917_distributed-cloud-design.md`.

## Academic integrity and AI use

AI assistance (Claude, Anthropic) was used as a learning aid and for first drafts of some scripts . All scripts were run and checked by me, and the evidence in this repository comes from my own runs. The full AI Use Declaration is in the LMS submission document.