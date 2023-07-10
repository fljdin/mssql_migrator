SET client_min_messages = WARNING;

/* create a user to perform the migration */
DROP ROLE IF EXISTS migrator;
CREATE ROLE migrator LOGIN;

/* create all requisite extensions */
CREATE EXTENSION tds_fdw;
CREATE EXTENSION mssql_migrator CASCADE;

/* create a foreign server and a user mapping */
CREATE SERVER mssql FOREIGN DATA WRAPPER tds_fdw
   OPTIONS (servername 'mssql_db', port '1433', database 'AdventureWorks', tds_version '7.4');

CREATE USER MAPPING FOR PUBLIC SERVER mssql
   OPTIONS (username 'sa', password 'Passw0rd');

/* give the user the required permissions */
GRANT CREATE ON DATABASE contrib_regression TO migrator;
GRANT USAGE ON FOREIGN SERVER mssql TO migrator;
