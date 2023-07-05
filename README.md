# MSSQL Server to PostgreSQL migration tools

`mssql_migrator` is a plugin for [`db_migrator`][migrator] that uses
[`tds_fdw`][tds_fdw] to migrate an SQL Server database to PostgreSQL.

[migrator]: https://github.com/cybertec-postgresql/db_migrator
[tds_fdw]: https://github.com/tds-fdw/tds_fdw

# Prerequisites

- The `tds_fdw` and `db_migrator` extensions must be installed.

- A foreign server must be defined for the MSSQL database you want to access.

- A user mapping must exist for the user who calls the `db_migrate` function.