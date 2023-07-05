-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION mssql_migrator" to load this file. \quit

CREATE FUNCTION mssql_create_catalog(
    server      name,
    schema      name    DEFAULT NAME 'fdw_stage',
    options     jsonb   DEFAULT NULL
) RETURNS void
    LANGUAGE plpgsql VOLATILE CALLED ON NULL INPUT SET search_path = pg_catalog AS
$mssql_create_catalog$
DECLARE
    old_msglevel text;

    /* schemas */
    schemas_sql text := $$
        CREATE FOREIGN TABLE %1$I.schemas (
            schema text NOT NULL
        ) SERVER %2$I OPTIONS (query
            E'SELECT s.name AS "schema" FROM sys.schemas s '
             'INNER JOIN sys.database_principals p ON p.principal_id = s.principal_id '
             'WHERE p.type <> ''R'' AND p.principal_id NOT IN (2, 3, 4)'
        );
       COMMENT ON FOREIGN TABLE %1$I.schemas IS 'MSSQL schemas on foreign server "%2$I"';
    $$;

    /* tables  */
    tables_sql text := $$
        CREATE FOREIGN TABLE %1$I.tables (
            schema     text NOT NULL,
            table_name text NOT NULL
        ) SERVER %2$I OPTIONS (query
            E'SELECT s.name AS "schema", t.name AS table_name '
             'FROM sys.tables t '
             'INNER JOIN sys.schemas s ON t.schema_id = s.schema_id'
        );
        COMMENT ON FOREIGN TABLE %1$I.tables IS 'MSSQL tables on foreign server "%2$I"';
    $$;

    /* columns */
    columns_sql text := $$
        CREATE FOREIGN TABLE %1$I.columns (
            schema        text    NOT NULL,
            table_name    text    NOT NULL,
            column_name   text    NOT NULL,
            position      integer NOT NULL,
            type_name     text    NOT NULL,
            length        integer NOT NULL,
            precision     integer,
            scale         integer,
            nullable      boolean NOT NULL,
            default_value text
        ) SERVER %2$I OPTIONS (query
            E'SELECT s.name AS "schema", t.name AS table_name, c.name AS column_name, '
                    'c.column_id AS position, ty.name AS type_name, c.max_length AS length, '
                    'c.precision, c.scale, c.is_nullable AS nullable, d.definition AS default_value '
             'FROM sys.columns c '
             'INNER JOIN sys.tables t ON c.object_id = t.object_id '
             'INNER JOIN sys.schemas s ON t.schema_id = s.schema_id '
             'INNER JOIN sys.types ty ON c.user_type_id = ty.user_type_id '
             'LEFT JOIN sys.default_constraints d ON c.object_id = d.parent_object_id AND c.column_id = d.parent_column_id'
        );
        COMMENT ON FOREIGN TABLE %1$I.columns IS 'columns of MSSQL tables on foreign server "%2$I"';
    $$;

    /* check constraints */
    check_sql text := $$
        CREATE FOREIGN TABLE %1$I.checks (
            schema          text    NOT NULL,
            table_name      text    NOT NULL,
            constraint_name text    NOT NULL,
            "deferrable"    boolean NOT NULL,
            deferred        boolean NOT NULL,
            condition       text    NOT NULL
        ) SERVER %2$I OPTIONS (query
            E'SELECT s.name AS "schema", t.name AS table_name, cc.name AS constraint_name, '
	                '0 AS deferrable, 0 AS deferred, cc.definition AS condition '
             'FROM sys.check_constraints cc '
             'INNER JOIN sys.tables t ON t.object_id = cc.parent_object_id '
             'INNER JOIN sys.schemas s ON s.schema_id = cc.schema_id'
        );
        COMMENT ON FOREIGN TABLE %1$I.checks IS 'MSSQL check constraints on foreign server "%2$I"';
    $$;

    /* keys */
    keys_sql text := $$
        CREATE FOREIGN TABLE %1$I.keys (
            schema          text    NOT NULL,
            table_name      text    NOT NULL,
            constraint_name text    NOT NULL,
            "deferrable"    boolean NOT NULL,
            deferred        boolean NOT NULL,
            column_name     text    NOT NULL,
            position        integer NOT NULL,
            is_primary      boolean NOT NULL
        ) SERVER %2$I OPTIONS (query
            E'SELECT s.name AS "schema", t.name AS table_name, i.name AS constraint_name, '
                    '0 AS deferrable, 0 AS deferred, c.name AS column_name, ic.key_ordinal AS position, '
		            'i.is_primary_key AS is_primary '
             'FROM sys.indexes i '
             'INNER JOIN sys.tables t ON t.object_id = i.object_id '
             'INNER JOIN sys.index_columns ic ON ic.index_id = i.index_id AND ic.object_id = i.object_id '
             'INNER JOIN sys.columns c ON c.object_id = t.object_id AND c.column_id = ic.column_id '
             'INNER JOIN sys.schemas s ON s.schema_id = t.schema_id '
             'WHERE i.is_unique = 1 OR i.is_primary_key = 1'
        );
        COMMENT ON FOREIGN TABLE %1$I.keys IS 'MSSQL primary and unique key columns on foreign server "%2$I"';
    $$;

    /* foreign keys */
    foreign_keys_sql text := $$
        CREATE FOREIGN TABLE %1$I.foreign_keys (
            schema          text    NOT NULL,
            table_name      text    NOT NULL,
            constraint_name text    NOT NULL,
            "deferrable"    boolean NOT NULL,
            deferred        boolean NOT NULL,
            delete_rule     text    NOT NULL,
            column_name     text    NOT NULL,
            position        integer NOT NULL,
            remote_schema   text    NOT NULL,
            remote_table    text    NOT NULL,
            remote_column   text    NOT NULL
        ) SERVER %2$I OPTIONS (query
            E'SELECT schema_name(fk.schema_id) AS "schema", object_name(fk.parent_object_id) AS table_name, '
                    'fk.name AS constraint_name, 0 AS deferrable, 0 AS deferred, '
                    'fk.delete_referential_action_desc AS delete_rule, '
                    'col_name(c.parent_object_id, c.parent_column_id) AS column_name, '
                    'c.constraint_column_id AS position, '
                    'schema_name(t.schema_id) AS remote_schema, '
                    'object_name(c.referenced_object_id) AS remote_table, '
                    'col_name(c.referenced_object_id, c.referenced_column_id) AS remote_column '
             'FROM sys.foreign_keys fk '
             'INNER JOIN sys.foreign_key_columns c ON fk.object_id = c.constraint_object_id '
             'INNER JOIN sys.tables t ON c.parent_object_id = t.object_id'
        );
        COMMENT ON FOREIGN TABLE %1$I.foreign_keys IS 'MSSQL foreign key columns on foreign server "%2$I"';
    $$;

BEGIN
    /* remember old setting */
    old_msglevel := current_setting('client_min_messages');

    /* make the output less verbose */
    SET LOCAL client_min_messages = warning;

    /* create foreign tables needed by db_migrator */
    EXECUTE format(schemas_sql, schema, server);
    EXECUTE format(tables_sql, schema, server);
    EXECUTE format(columns_sql, schema, server);
    EXECUTE format(check_sql, schema, server);
    EXECUTE format(keys_sql, schema, server);
    EXECUTE format(foreign_keys_sql, schema, server);
    -- EXECUTE format(partitions_sql, schema, sys_schemas, server);
    -- EXECUTE format(subpartitions_sql, schema, sys_schemas, server);
    -- EXECUTE format(views_sql, schema, sys_schemas, server);
    -- EXECUTE format(functions_sql, schema, sys_schemas, server);
    -- EXECUTE format(index_columns_sql, schema, sys_schemas, server);
    -- EXECUTE format(indexes_sql, schema, sys_schemas, server);
    -- EXECUTE format(sequences_sql, schema, sys_schemas, server);
    -- EXECUTE format(triggers_sql, schema, sys_schemas, server);
    -- EXECUTE format(table_privs_sql, schema, sys_schemas, server);
    -- EXECUTE format(column_privs_sql, schema, sys_schemas, server);

    /* reset client_min_messages */
    EXECUTE 'SET LOCAL client_min_messages = ' || old_msglevel;
END;
$mssql_create_catalog$;

COMMENT ON FUNCTION mssql_create_catalog(name, name, jsonb) IS
   'create mssql foreign tables for the metadata of a foreign server';

CREATE FUNCTION mssql_translate_datatype(
    v_type text,
    v_length integer,
    v_precision integer,
    v_scale integer
) RETURNS text
    LANGUAGE sql STABLE CALLED ON NULL INPUT SET search_path = pg_catalog AS
$mssql_translate_datatype$
    SELECT CASE data_type
        WHEN 'bit' THEN 'boolean'
        WHEN 'tinyint' THEN 'smallint'
        WHEN 'nchar' THEN format('char(%s)', data_length)
        WHEN 'varchar' THEN CASE
            WHEN data_length = -1 THEN 'text'
            ELSE format('varchar(%s)', data_length)
        END
        WHEN 'nvarchar' THEN CASE
            WHEN data_length = -1 THEN 'text'
            ELSE format('varchar(%s)', data_length)
        END
        WHEN 'datetime' THEN 'timestamp'
        WHEN 'datetime2' THEN 'timestamp'
        WHEN 'smallmoney' THEN 'money'
        WHEN 'smalldatetime' THEN 'timestamp'
        WHEN 'datetimeoffset' THEN 'timestamp with time zone'
        WHEN 'varbinary' THEN 'bytea'
        WHEN 'uniqueidentifier' THEN 'uuid'
        WHEN 'sysname' THEN 'varchar(128)'
        ELSE data_type
    END;
$mssql_translate_datatype$;

CREATE FUNCTION mssql_translate_identifier(text) RETURNS name
    LANGUAGE sql STABLE CALLED ON NULL INPUT SET search_path = pg_catalog AS
$mssql_translate_identifier$
SELECT $1
$mssql_translate_identifier$;

COMMENT ON FUNCTION mssql_translate_identifier(text) IS
    'helper function to truncate MSSQL names';

CREATE FUNCTION mssql_translate_expression(s text) RETURNS text
    LANGUAGE plpgsql IMMUTABLE STRICT SET search_path FROM CURRENT AS
$mssql_translate_expression$
BEGIN
    s := regexp_replace(s, '\[([a-zA-Z]+)\]', '"\1"', 'g');
    s := regexp_replace(s, 'getdate\s*\(\)', 'current_timestamp', 'i');
    s := regexp_replace(s, 'newid\s*\(\)', 'gen_random_uuid()', 'i');

    RETURN s;
END;
$mssql_translate_expression$;

COMMENT ON FUNCTION mssql_translate_expression(text) IS
    'helper function to translate MSSQL expressions to PostgreSQL';

CREATE FUNCTION mssql_mkforeign(
    server         name,
    schema         name,
    table_name     name,
    orig_schema    text,
    orig_table     text,
    column_names   name[],
    column_options jsonb[],
    orig_columns   text[],
    data_types     text[],
    nullable       boolean[],
    options        jsonb
) RETURNS text
    LANGUAGE plpgsql IMMUTABLE CALLED ON NULL INPUT AS
$mssql_mkforeign$

DECLARE
    stmt       text;
    i          integer;
    sep        text := '';
    colopt_str text;
BEGIN
    stmt := format(E'CREATE FOREIGN TABLE %I.%I (', schema, table_name);

    FOR i IN 1..cardinality(column_names) LOOP
        /* format the column options as string */
        SELECT ' OPTIONS (' ||
        string_agg(format('%I %L', j.key, j.value->>0), ', ') ||
        ')'
        INTO colopt_str
        FROM jsonb_each(column_options[i]) AS j;

        stmt := stmt || format(E'%s\n   %I %s%s%s',
        sep, column_names[i], data_types[i],
        coalesce(colopt_str, ''),
        CASE WHEN nullable[i] THEN '' ELSE ' NOT NULL' END
        );
        sep := ',';
    END LOOP;

    RETURN stmt || format(
        E') SERVER %I\n'
        '   OPTIONS (dbname ''%s'', table_name ''%s'')',
        server, orig_schema, orig_table
    );
END;
$mssql_mkforeign$;

COMMENT ON FUNCTION mssql_mkforeign(name,name,name,text,text,name[],jsonb[],text[],text[],boolean[],jsonb) IS
   'construct a CREATE FOREIGN TABLE statement based on the input data';

CREATE FUNCTION db_migrator_callback(
    OUT create_metadata_views_fun regprocedure,
    OUT translate_datatype_fun    regprocedure,
    OUT translate_identifier_fun  regprocedure,
    OUT translate_expression_fun  regprocedure,
    OUT create_foreign_table_fun  regprocedure
) RETURNS record
    LANGUAGE sql STABLE CALLED ON NULL INPUT SET search_path = pg_catalog AS
$db_migrator_callback$
WITH ext AS (
    SELECT extnamespace::regnamespace::text AS schema_name
    FROM pg_extension
    WHERE extname = 'mssql_migrator'
)
SELECT format('%s.%I(name,name,jsonb)', ext.schema_name, 'mssql_create_catalog')::regprocedure,
       format('%s.%I(text,integer,integer,integer)', ext.schema_name, 'mssql_translate_datatype')::regprocedure,
       format('%s.%I(text)', ext.schema_name, 'mssql_translate_identifier')::regprocedure,
       format('%s.%I(text)', ext.schema_name, 'mssql_translate_expression')::regprocedure,
       format('%s.%I(name,name,name,text,text,name[],jsonb[],text[],text[],boolean[],jsonb)', ext.schema_name, 'mssql_mkforeign')::regprocedure
FROM ext
$db_migrator_callback$;

COMMENT ON FUNCTION db_migrator_callback() IS
    'callback for db_migrator to get the appropriate conversion functions';