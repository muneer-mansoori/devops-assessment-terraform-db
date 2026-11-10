# DevOps Assessment: Terraform + Database Reliability

AWS infrastructure for a hotel-booking service (**Internet → ALB → ECS Fargate → RDS PostgreSQL**) in Terraform with separate `dev` and `prod` environments, plus a local PostgreSQL setup with migrations, seed data, query optimisation, and verified backup/restore.

| Part | What | Where |
|---|---|---|
| 1 | VPC, 3 security groups, ALB, ECS cluster/task/service, private RDS | [`infra/modules/`](infra/modules) |
| 2 | `dev` / `prod` with their own variables, tfvars, backend, sizing, backups, deletion protection | [`infra/envs/`](infra/envs) |
| 3 | PR workflow: fmt → init → validate → plan, posted as **PR comment + artifact + job summary** | [`.github/workflows/terraform.yml`](.github/workflows/terraform.yml) |
| 4 | PostgreSQL 16 via Docker Compose, `hotel_bookings` + `booking_events` | [`docker-compose.yml`](docker-compose.yml), [`db/migrations/`](db/migrations) |
| 5 | Seed data + covering index for the report query (before/after `EXPLAIN`) | [`db/seed/seed.sql`](db/seed/seed.sql), [`003_add_city_report_index.sql`](db/migrations/003_add_city_report_index.sql) |
| 6 | Timestamped, checksummed backup; restore into a fresh DB with automatic verification | [`scripts/backup.sh`](scripts/backup.sh), [`scripts/restore.sh`](scripts/restore.sh) |
| CI | Database end-to-end test on every PR (compose up → backup → restore → index check) | [`.github/workflows/database.yml`](.github/workflows/database.yml) |

---

## Quick start

**Prerequisites:** Docker with Compose v2, Terraform ≥ 1.10, bash. No AWS account is needed.

```bash
git clone https://github.com/muneer-mansoori/devops-assessment-terraform-db.git
cd devops-assessment-terraform-db

# Database tasks
docker compose up -d --wait     # starts PostgreSQL, runs migrations + seed (first start only)
./scripts/backup.sh             # timestamped dump in backups/
./scripts/restore.sh            # restores it into a fresh database and verifies it
./scripts/explain.sh            # report query plan without vs with the index

# Terraform (no AWS credentials needed)
./scripts/tf-plan-offline.sh dev
./scripts/tf-plan-offline.sh prod
```

> **Reviewer note on `terraform init`:** each environment's `backend.tf` points at a real S3 state bucket, so a plain `terraform init` needs AWS credentials. Without credentials, use `./scripts/tf-plan-offline.sh <env>`. It runs the same `fmt → init → validate → plan -refresh=false` sequence against local state with mock credentials and leaves the committed files unchanged. `terraform init -backend=false && terraform validate` also works offline.

`make help` lists the same commands as shortcuts. `./scripts/e2e.sh` runs the whole database flow from a clean volume and fails loudly if any step is wrong (this is what CI runs).

---

## Part 1 – Architecture

```
                 Internet
                    │  80 (443 when certificate_arn is set)
        ┌───────────▼────────────┐   public subnets (one per AZ)
        │  ALB  [sg: alb]        │   + NAT gateway(s)
        └───────────┬────────────┘
                    │  container port, from sg:alb only
        ┌───────────▼────────────┐   private subnets (NAT egress, no public IPs)
        │  ECS Fargate service   │   nginx placeholder, autoscaling on CPU
        │  [sg: ecs-tasks]       │   DB credentials injected from Secrets Manager
        └───────────┬────────────┘
                    │  5432, from sg:ecs-tasks only
        ┌───────────▼────────────┐   database subnets (no route to the internet)
        │  RDS PostgreSQL 16     │   encrypted, TLS enforced, not publicly accessible
        │  [sg: rds]             │
        └────────────────────────┘
```

**Modules**

| Module | Contents |
|---|---|
| `network` | VPC; public, private and database subnets across the given AZs; IGW; NAT per AZ (or one shared in dev); separate route tables (database tier has **no** default route); default SG locked down; optional VPC flow logs |
| `ecs` | ALB + target group + listeners (HTTP, or HTTPS with HTTP→HTTPS redirect when a certificate is given); ALB and ECS security groups; ECS cluster; task definition; service with deployment circuit breaker + rollback; CPU target-tracking autoscaling; CloudWatch logs; least-privilege IAM execution/task roles |
| `rds` | DB subnet group; RDS security group; parameter group (`rds.force_ssl=1`, slow-query logging); `aws_db_instance` (gp3, encrypted, storage autoscaling, Multi-AZ option, backups, deletion protection, Performance Insights, log exports) |

**How "RDS is private and only reachable from ECS" is enforced, in layers**

1. `publicly_accessible = false`, and the DB lives in *database* subnets whose route table only has the local VPC route.
2. The RDS security group has exactly one ingress rule: TCP 5432 from the **ECS task security group** (a security-group reference, not a CIDR). It has no egress rules.
3. ECS tasks may only send 5432 to the database subnet CIDRs; the ALB may only send to the ECS tasks.
4. `rds.force_ssl = 1` rejects unencrypted connections.

**Production details worth calling out**

- **No secrets in code or state:** `manage_master_user_password = true` makes RDS generate and store the master password in Secrets Manager. The task definition references it with `valueFrom`, and the execution role can read only that one secret.
- **Zero-downtime deploys:** `minimum_healthy_percent = 100`, circuit breaker with automatic rollback, `create_before_destroy` on security groups, target group and parameter group.
- **Autoscaling owns `desired_count`** after the first apply (`ignore_changes`), so a later `apply` never scales the service back down.
- **Deterministic plans:** AZs are listed in tfvars rather than read from a data source, so plans are reproducible and work offline.

## Part 2 – Environments

```
infra/
  modules/  network/  ecs/  rds/
  envs/
    dev/   backend.tf  providers.tf  variables.tf  terraform.tfvars  main.tf  outputs.tf
    prod/  backend.tf  providers.tf  variables.tf  terraform.tfvars  main.tf  outputs.tf
```

Each environment is its own Terraform root with its own state. The settings that differ:

| Setting | dev | prod |
|---|---|---|
| State backend | `s3://hotel-booking-tfstate-dev/envs/dev/…` | `s3://hotel-booking-tfstate-prod/envs/prod/…` |
| VPC / AZs | `10.10.0.0/16`, 2 AZs | `10.20.0.0/16`, 3 AZs |
| NAT gateways | 1 shared | 1 per AZ |
| VPC flow logs | off | on |
| RDS instance | `db.t4g.micro`, 20 → 50 GiB | `db.m6g.large`, 100 → 500 GiB |
| RDS Multi-AZ | no | yes |
| **RDS backup retention** | **3 days** | **30 days** |
| **RDS deletion protection** | **false** (no final snapshot) | **true** (+ final snapshot) |
| RDS changes applied | immediately | in the maintenance window |
| Performance Insights | off | on |
| ECS task | 0.25 vCPU / 512 MiB | 0.5 vCPU / 1 GiB |
| ECS tasks (min–max) | 1–2 | 3–10 |
| ALB deletion protection | off | on |
| Log retention | 7 days | 90 days |
| ECS Exec | on (debugging) | off |

### Remote state

`backend.tf` uses S3 with **native S3 state locking** (`use_lockfile = true`, Terraform ≥ 1.10), so no DynamoDB lock table is needed. Before the first real `terraform init`, create each bucket once with versioning, default encryption and public access blocked:

```bash
aws s3api create-bucket --bucket hotel-booking-tfstate-dev --region ap-south-1 \
  --create-bucket-configuration LocationConstraint=ap-south-1
aws s3api put-bucket-versioning --bucket hotel-booking-tfstate-dev --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket hotel-booking-tfstate-dev \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
```

In a real organisation, prod state would live in a separate AWS account.

## Part 3 – Reviewing the Terraform

### Without AWS credentials (recommended for review)

```bash
./scripts/tf-plan-offline.sh dev     # or prod
```

This runs `terraform fmt -check`, `init`, `validate` and `plan -refresh=false`. It writes a temporary, git-ignored `zz_offline_override.tf` that switches the backend to local state and gives the AWS provider mock credentials with all account lookups skipped. The committed `backend.tf` and `providers.tf` are never changed, and the override is deleted on exit. Plans are saved to `plans/<env>.plan.txt`.

Expected result: `dev` plans **51** resources and `prod` plans **68** (the difference is prod's third AZ with its subnets and routes, a NAT gateway per AZ, and VPC flow logs).

### With AWS credentials

```bash
cd infra/envs/dev
terraform fmt -check -recursive ../..
terraform init
terraform validate
terraform plan -refresh=false
```

Plain `terraform init` uses the S3 backend, so it needs credentials and the state bucket from the previous section.

### GitHub Actions

[`terraform.yml`](.github/workflows/terraform.yml) runs on every pull request that touches `infra/`:

1. `terraform fmt -check -recursive`
2. For `dev` and `prod` in parallel: `init` → `validate` → `plan -refresh=false`
3. The plan is published three ways: a **PR comment** (updated in place on new pushes, one per environment), a **workflow artifact** (`terraform-plan-<env>`, text + binary plan), and the **job summary**.

By default it plans offline. Setting the repository variable `AWS_PLAN_ROLE_ARN` to a read-only IAM role switches it to OIDC authentication with the real S3 backend; no long-lived AWS keys are stored in GitHub.

### Security scan

`trivy config infra/envs/prod --tf-vars infra/envs/prod/terraform.tfvars` reports **no MEDIUM, HIGH or CRITICAL findings** for prod. Three checks are suppressed inline, each with its reason next to the resource:

| Check | Why it is accepted |
|---|---|
| AWS-0053 public ALB | The brief's architecture is Internet → ALB. Only the ALB is public; tasks and DB are private |
| AWS-0054 HTTP listener | HTTP forwards only while no `certificate_arn` is set. With one, HTTP redirects to HTTPS |
| AWS-0104 egress `0.0.0.0/0` | TCP 443 only, through NAT. VPC endpoints would remove it (see trade-offs) |

The remaining LOW findings are about customer-managed KMS keys for logs and Performance Insights. The `rds` module already accepts `kms_key_arn` for storage.

## Part 4 – Local database

`docker compose up -d --wait` starts `postgres:16-alpine` (port bound to `127.0.0.1` only). On the first start with an empty volume, [`db/init/00-init.sh`](db/init/00-init.sh) runs:

1. [`db/migrate.sh`](db/migrate.sh): applies `db/migrations/*.sql` in order, each in its own transaction, recorded in `schema_migrations` (re-running is a no-op).
2. [`db/seed.sh`](db/seed.sh): loads the seed data, then `VACUUM (ANALYZE)`.

The container only reports **healthy** after init has finished, so `--wait` returns once the data is ready.

| Migration | |
|---|---|
| `001_create_hotel_bookings.sql` | table from the brief |
| `002_create_booking_events.sql` | table from the brief + FK index |
| `003_add_city_report_index.sql` | the report index (Part 5) |

**Deliberate changes to the suggested schema** (all additive):

- `created_at` is `TIMESTAMPTZ` instead of `TIMESTAMP`. `NOW() - INTERVAL '30 days'` then means the same instant whatever the client's time zone is.
- `CHECK` constraints: allowed statuses, `amount >= 0`, `checkout_date > checkin_date`, and `city = lower(city)`. The last one guarantees the report's `city = 'delhi'` cannot silently miss rows stored as `Delhi`.
- `booking_events.booking_id` is a **foreign key** (`ON DELETE CASCADE`) with an index on `(booking_id, created_at)`. PostgreSQL does not index foreign keys automatically.
- `DEFAULT gen_random_uuid()` / `DEFAULT now()` so the application does not have to supply them.

Useful commands: `make psql` (shell into the DB), `make reset` (wipe the volume and re-seed).

## Part 5 – Seed data and indexing

[`db/seed/seed.sql`](db/seed/seed.sql) generates **50,000 bookings** by default (the brief asks for at least 100; set `SEED_BOOKINGS` in `.env` to change it). They cover 10 cities, 8 organisations and 6 statuses, with `created_at` spread over the last year. About 70% of bookings get a status-consistent event history (`booking_created`, `payment_captured`, `checked_in`, …). The data is **deterministic** (`setseed` + md5-derived UUIDs): every run produces the same IDs, cities, organisations, statuses and amounts. Only the timestamps differ, because they are relative to the moment of seeding so that "last 30 days" always has data. With only 100 rows PostgreSQL would scan the table no matter what indexes exist, so a realistic volume is what makes the index's effect measurable.

### The query

```sql
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
```

### The index

```sql
CREATE INDEX idx_hotel_bookings_city_created_at
    ON hotel_bookings (city, created_at)
    INCLUDE (org_id, status, amount);
```

**Why this one:**

- **`city` first, `created_at` second.** Equality columns go before range columns. The B-tree seeks directly to `('delhi', now − 30 days)` and reads one contiguous slice of the index. In the opposite order, `(created_at, city)`, it would read the last 30 days for *every* city and filter out the rest.
- **`INCLUDE (org_id, status, amount)` makes it a covering index.** Every column the query reads is in the index, so PostgreSQL uses an **Index Only Scan** and never touches the table heap (the seed's `VACUUM` keeps the visibility map current, which is what makes index-only scans possible). `INCLUDE` columns are stored only in leaf pages, so they don't widen the search key.
- **`GROUP BY` stays cheap.** After the filter only around 1/10 × 30/365 of the table remains, which a `HashAggregate` handles easily. Putting `org_id, status` in the key to avoid that aggregation would push `created_at` behind them and lose the range seek.

**Alternatives considered:**

| Option | Why not |
|---|---|
| Separate indexes on `city` and `created_at` | Needs a BitmapAnd of two large bitmaps plus heap visits; slower and larger in total |
| `(city, created_at)` without `INCLUDE` | Good seek, but every matching row needs a heap visit for `org_id/status/amount` |
| Partial index `WHERE created_at >= now() - '30 days'` | Not allowed: index predicates must be immutable, and `now()` is not |
| BRIN on `created_at` | Very small and good for huge append-only tables, but it can't narrow by city; worth adding later alongside time-based partitioning |

### Measured result (50,000 rows, PostgreSQL 16)

Run `./scripts/explain.sh`. It drops the index inside a transaction that is rolled back, shows the plan, and then shows the plan with the index.

| | Without index | With index |
|---|---|---|
| Access path | `Seq Scan` + filter (49,622 rows read and discarded) | `Index Only Scan` on `idx_hotel_bookings_city_created_at` |
| Heap fetches | entire table | **0** |
| Buffers read | 768 | **8** (96× fewer) |
| Execution time | 2.87 ms | **0.11 ms** (~25× faster) |

```
HashAggregate (actual time=0.089..0.093 rows=45 loops=1)
  Group Key: org_id, status
  Buffers: shared hit=8
  ->  Index Only Scan using idx_hotel_bookings_city_created_at on hotel_bookings (actual time=0.025..0.047 rows=378 loops=1)
        Index Cond: ((city = 'delhi'::text) AND (created_at >= (now() - '30 days'::interval)))
        Heap Fetches: 0
```

The absolute times are small because 50k rows fit in memory. What matters is the shape of the plan. Without the index, cost grows with the **whole table**; with it, cost grows only with the rows that match (one city, 30 days). At 50M rows the sequential scan reads about 1,000× more pages, while the index scan still reads only the matching slice.

On a production table, the index would be created with `CREATE INDEX CONCURRENTLY` (outside a transaction) to avoid blocking writes. The migration uses a plain `CREATE INDEX` because the table is still empty when it runs.

## Part 6 – Backup and restore

### Backup

```bash
./scripts/backup.sh
```

1. Runs `pg_dump --format=custom --compress=6 --no-owner --no-privileges` inside the container. Custom format is compressed and supports selective and parallel restore. `pg_dump` reads from one consistent snapshot, so it is safe while the DB is in use.
2. Writes to `*.partial` first and renames only after `pg_restore --list` proves the archive is readable. A failed run never leaves something that looks like a valid backup.
3. Writes three files to `backups/`:
   - `hotel_db_<UTC timestamp>.dump`: the backup
   - `…dump.sha256`: a checksum
   - `…manifest`: a data fingerprint (row counts, content md5 per table, applied migrations, index list)
4. Keeps the newest `BACKUP_KEEP` backups (default 7) and deletes older ones.

### Restore

```bash
./scripts/restore.sh                                 # newest backup -> database hotel_db_restore
./scripts/restore.sh backups/hotel_db_<ts>.dump      # a specific backup
RESTORE_DB=my_copy ./scripts/restore.sh              # another target name
```

1. Checks the dump against its `.sha256`.
2. Drops and recreates the target database from `template0`, so the restore always starts from a **fresh, empty database**. It refuses to target the source database `hotel_db` or system databases.
3. Runs `pg_restore --exit-on-error --single-transaction`, so the restore either completes fully or changes nothing, then `VACUUM (ANALYZE)` (planner statistics are not part of a dump).
4. **Verifies automatically:** it recomputes the fingerprint on the restored database and compares it with the backup's manifest. The script exits non-zero on any difference.

### How to verify that the restore worked

`restore.sh` performs the check itself and ends with:

```
RESTORE VERIFIED: row counts, content checksums, migrations and indexes match the backup manifest
```

To check by hand, compare the source and the restored database:

```bash
for db in hotel_db hotel_db_restore; do
  echo "== $db"
  docker compose exec -T db psql -U hotel -d "$db" -tA -c "
    SELECT 'bookings=' || count(*) || ' sum=' || sum(amount) FROM hotel_bookings;
    SELECT 'events='   || count(*) FROM booking_events;
    SELECT 'migrations=' || string_agg(version, ',' ORDER BY version) FROM schema_migrations;"
done

# The report query returns the same rows on both, and the restored DB uses the same index:
docker compose exec -T db psql -U hotel -d hotel_db_restore -c "
  EXPLAIN SELECT org_id, status, COUNT(*), SUM(amount) FROM hotel_bookings
  WHERE city = 'delhi' AND created_at >= NOW() - INTERVAL '30 days' GROUP BY org_id, status;"
```

Also try a negative test: corrupt a dump (`printf x >> backups/<file>.dump`). `restore.sh` then refuses with a checksum mismatch.

### What this does not cover, and what production on AWS would add

These scripts are logical backups for the local database. On RDS, the main mechanisms are already in the Terraform: **automated backups with point-in-time restore** (3 days in dev, 30 in prod), a **final snapshot** on deletion in prod, and Multi-AZ. Next steps would be AWS Backup with cross-region/cross-account copies, a scheduled restore drill (restore the latest snapshot to a scratch instance and run the same fingerprint check), and alerts when a backup is missing.

---

## Repository layout

```
.
├── .github/workflows/
│   ├── terraform.yml         # PR: fmt, init, validate, plan -> PR comment / artifact / summary
│   └── database.yml          # PR: shellcheck + compose up -> backup -> restore -> index check
├── infra/
│   ├── modules/{network,ecs,rds}/
│   └── envs/{dev,prod}/
├── db/
│   ├── init/00-init.sh       # first-start hook for the postgres container
│   ├── migrate.sh            # ordered, tracked, transactional migrations
│   ├── seed.sh
│   ├── migrations/001..003_*.sql
│   └── seed/seed.sql
├── scripts/
│   ├── backup.sh  restore.sh  explain.sh  e2e.sh
│   ├── tf-plan-offline.sh
│   └── lib.sh
├── docker-compose.yml
├── .env.example
└── Makefile
```

## How this was tested

- **Terraform 1.17.1, AWS provider 6.72.0:** `fmt -check`, `validate` and `plan -refresh=false` pass for both environments (dev 51 resources, prod 68). `trivy config` was run as described above.
- **Database (PostgreSQL 16):** `./scripts/e2e.sh` passes: migrations, seeding 50,000 bookings and 93,466 events, backup, restore verified against the manifest, and an Index Only Scan on the report query. Negative cases also pass: a corrupted dump is refused, restoring over `hotel_db` is refused, retention keeps exactly `BACKUP_KEEP` dumps, and re-running migrations is a no-op.
- **CI:** both workflows run the same commands on every pull request; `shellcheck` covers all scripts.

## Assumptions and trade-offs

- **Region `ap-south-1` (Mumbai)**; AZs are pinned in tfvars.
- **Placeholder app:** `public.ecr.aws/nginx/nginx` (ECR Public avoids Docker Hub pull limits). It receives `DB_HOST/DB_PORT/DB_NAME` and `DB_USERNAME/DB_PASSWORD` from Secrets Manager, so the wiring is real even though nginx ignores it.
- **HTTP by default:** there is no domain or ACM certificate here. Setting `certificate_arn` turns on the HTTPS listener (TLS 1.3 policy) and an HTTP→HTTPS redirect.
- **The ECS tasks' security group allows HTTPS egress to `0.0.0.0/0`** through NAT for image pulls, Secrets Manager and CloudWatch. A stricter setup would add VPC interface endpoints and remove internet egress. That was left out to keep dev cheap.
- **`skip_final_snapshot` follows `deletion_protection`:** dev is disposable, prod always keeps a final snapshot.
- **Not deployed to AWS**, per the brief. The code is validated with `fmt`, `validate` and `plan`, both locally and in CI.
