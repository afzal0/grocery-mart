# Backup & Disaster Recovery Runbook (Story 9.10)

**Targets:** RPO ≤ 24h, RTO ≤ 4h. Database: AWS RDS PostgreSQL (PostGIS).

**Last successful restore drill:** _not yet run_ (update on each drill — staleness is visible here).

## Backup configuration

- **Automated backups + PITR** enabled on the production RDS instance with a backup retention
  window of **≥ 7 days** (satisfies RPO ≤ 24h; PITR allows recovery to any second in the window).
- Backups are encrypted; snapshots replicated to a second region for regional-failure resilience.
- Terraform: `aws_db_instance.backup_retention_period >= 7`, `backup_window`, `copy_tags_to_snapshot = true`.

## Restore drill (run quarterly)

1. Pick a target timestamp `T` (e.g. 1h ago). Record `T`.
2. `aws rds restore-db-instance-to-point-in-time --source-db-instance-identifier grocery-mart-prod \
   --target-db-instance-identifier grocery-mart-restore-drill --restore-time T`
3. Start a stopwatch; wait until the restored instance is `available`. Record elapsed time (must be ≤ 4h).
4. Point a read-only verifier at the restored instance and check **key invariants**:
   - `SELECT SUM(order_total) FROM settlement_ledger` matches the expected ledger total at `T`.
   - Recent orders around `T` are present and consistent (`SELECT count(*) FROM orders WHERE created_at <= T`).
   - Flyway `schema_history` last version matches production.
5. Record: target `T`, actual restored data position, elapsed time, invariant results.
6. Tear down the drill instance. Update **Last successful restore drill** above with today's date.

## Failover decision

- Data loss / corruption → PITR restore to just before the event.
- AZ failure → RDS Multi-AZ automatic failover (no manual action; verify health).
- Region failure → promote cross-region replica / restore from replicated snapshot.

## Escalation

On-call DBA → Eng lead → CTO. Pause writes (maintenance mode) before any restore-over-prod.
