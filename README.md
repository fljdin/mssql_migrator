# MSSQL Server to PostgreSQL migration tools

`mssql_migrator` is a plugin for [`db_migrator`][migrator] that uses
[`tds_fdw`][tds_fdw] to migrate an SQL Server database to PostgreSQL.

[migrator]: https://github.com/cybertec-postgresql/db_migrator
[tds_fdw]: https://github.com/tds-fdw/tds_fdw

# Prerequisites

- The `tds_fdw` and `db_migrator` extensions must be installed.

- A foreign server must be defined for the MSSQL database you want to access.

- A user mapping must exist for the user who calls the `db_migrate` function.

# Troubleshooting

## ERROR:  invalid input syntax for type time

The `tds_fdw` extension is built on FreeTDS project and the contribution team
does the best data and time conversion possible. For `time` data type, it may
happen that conversion fails with the following error:

```text
ERROR:  invalid input syntax for type time: "Jan  1 1900  3:00:00:0000000PM"
```

A well-known workaround is to translate binary time-based data to a supported
format by using `locales.conf` file.

```sh
cat <<EOF > /etc/freetds/locales.conf
[default]
    date format = %F %T.%z
EOF
```