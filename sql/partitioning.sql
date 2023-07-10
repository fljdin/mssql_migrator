\connect - migrator
SET client_min_messages = WARNING;

/* set up staging schemas */
SELECT db_migrate_prepare(
   plugin => 'mssql_migrator',
   server => 'mssql',
   only_schemas => '{Partitions}'
);

/* perform the data migration */
SELECT db_migrate_mkforeign(
   plugin => 'mssql_migrator',
   server => 'mssql'
);

/* migrate the rest of the database */
SELECT db_migrate_tables(
   plugin => 'mssql_migrator'
);

SELECT db_migrate_constraints(
   plugin => 'mssql_migrator'
);

/* we have to check the log table before we drop the schema */
SELECT operation, schema_name, object_name, failed_sql, error_message
FROM pgsql_stage.migrate_log
ORDER BY log_time \gx

SELECT db_migrate_finish();

\d+ "Partitions"."PartByDateRange"
\d+ "Partitions"."PartByIntRange"

SELECT tableoid::regclass partname, * FROM "Partitions"."PartByDateRange";
SELECT tableoid::regclass partname, * FROM "Partitions"."PartByIntRange";