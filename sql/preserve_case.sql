\connect - migrator
SET client_min_messages = WARNING;
SET mssql_migrator.preserve_case = off;

/* perform a data migration */
SELECT db_migrate(
   plugin => 'mssql_migrator',
   server => 'mssql',
   only_schemas => '{dbo}'
);

/* check identifiers */
\d dbo.*