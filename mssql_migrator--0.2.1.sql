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
             'WHERE i.is_unique_constraint = 1 OR i.is_primary_key = 1'
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
            E'SELECT s.name AS "schema", t.name AS table_name, '
                    'fk.name AS constraint_name, 0 AS deferrable, 0 AS deferred, '
                    'REPLACE(fk.delete_referential_action_desc, ''_'', '' '') AS delete_rule, '
                    'col_name(c.parent_object_id, c.parent_column_id) AS column_name, '
                    'c.constraint_column_id AS position, '
                    'rs.name AS remote_schema, rt.name AS remote_table, '
                    'col_name(c.referenced_object_id, c.referenced_column_id) AS remote_column '
             'FROM sys.foreign_keys fk '
             'INNER JOIN sys.foreign_key_columns c ON fk.object_id = c.constraint_object_id '
             'INNER JOIN sys.tables t ON c.parent_object_id = t.object_id '
             'INNER JOIN sys.schemas s ON t.schema_id = s.schema_id '
             'INNER JOIN sys.tables rt ON fk.referenced_object_id = rt.object_id '
             'INNER JOIN sys.schemas rs ON rt.schema_id = rs.schema_id '
        );
        COMMENT ON FOREIGN TABLE %1$I.foreign_keys IS 'MSSQL foreign key columns on foreign server "%2$I"';
    $$;

    /* views */
    views_sql text := $$
        CREATE FOREIGN TABLE %1$I.views (
            schema     text NOT NULL,
            view_name  text NOT NULL,
            definition text NOT NULL
        ) SERVER %2$I OPTIONS (query
            E'SELECT s.name AS "schema", v.name AS view_name, m.definition '
             'FROM sys.views v '
             'INNER JOIN sys.sql_modules m ON v.object_id = m.object_id '
             'INNER JOIN sys.schemas s ON v.schema_id = s.schema_id'
        );
        COMMENT ON FOREIGN TABLE %1$I.views IS 'MSSQL views on foreign server "%2$I"';
    $$;

    /* functions */
    functions_sql text := $$
        CREATE FOREIGN TABLE %1$I.functions (
            schema        text    NOT NULL,
            function_name text    NOT NULL,
            is_procedure  boolean NOT NULL,
            source        text    NOT NULL
        ) SERVER %2$I OPTIONS (query
            E'SELECT s.name AS "schema", o.name AS function_name, '
	         'CASE o.type WHEN ''P'' THEN 1 ELSE 0 END AS is_procedure, '
             'm.definition AS source '
             'FROM sys.sql_modules m '
             'INNER JOIN sys.objects o ON m.object_id = o.object_id '
             'INNER JOIN sys.schemas s ON o.schema_id = s.schema_id '
             'WHERE o.type IN (''FN'', ''P'', ''TF'')'
        );
        COMMENT ON FOREIGN TABLE %1$I.functions IS 'MSSQL functions and procedures on foreign server "%2$I"';
    $$;

    /* functions */
    triggers_sql text := $$
        CREATE FOREIGN TABLE %1$I.triggers_events (
            schema           text    NOT NULL,
            table_name       text    NOT NULL,
            trigger_name     text    NOT NULL,
            trigger_type     text    NOT NULL,
            trigger_event    text    NOT NULL,
            for_each_row     boolean NOT NULL,
            when_clause      text,
            trigger_body     text    NOT NULL
        ) SERVER %2$I OPTIONS (query
            E'SELECT s.name AS "schema", object_name(t.parent_id) AS table_name, t.name AS "trigger_name", '
	                'CASE t.is_instead_of_trigger WHEN 0 THEN ''AFTER'' WHEN 1 THEN ''INSTEAD OF'' END AS trigger_type, '
	                'e.type_desc AS trigger_event, 0 AS for_each_row, null AS when_clause, m.definition AS trigger_body '
             'FROM sys.triggers t '
             'INNER JOIN sys.objects o ON t.object_id = o.object_id '
             'INNER JOIN sys.sql_modules m ON t.object_id = m.object_id '
             'INNER JOIN sys.schemas s ON o.schema_id = s.schema_id '
             'INNER JOIN sys.trigger_events e ON t.object_id = e.object_id '
             'WHERE t.parent_class = 1 AND t.type = ''TR'' AND t.is_disabled = 0'
        );
        CREATE VIEW %1$I.triggers AS
            SELECT schema, table_name, trigger_name, trigger_type,
                   string_agg(trigger_event, ' OR ') triggering_event,
                   for_each_row, when_clause, trigger_body
            FROM %1$I.triggers_events
            GROUP BY schema, table_name, trigger_name, trigger_type,
                     for_each_row, when_clause, trigger_body;
        COMMENT ON FOREIGN TABLE %1$I.triggers_events IS 'MSSQL triggers on foreign server "%2$I"';
        COMMENT ON VIEW %1$I.triggers IS 'MSSQL triggers with triggering events on foreign server "%2$I"';
    $$;

    /* partitions and subpartitions */
    partitions_sql text := $$
        CREATE FOREIGN TABLE %1$I.partition_cols (
            schema         text    NOT NULL,
            table_name     text    NOT NULL,
            type           text    NOT NULL,
            key            text    NOT NULL,
            position       integer NOT NULL,
            boundary_value text    NOT NULL
        ) SERVER mssql OPTIONS (query
            E'SELECT s.name AS "schema", t.name AS table_name, '
                    '''RANGE'' AS "type", c.name AS "key", p.partition_number AS position, '
                    'ISNULL(CASE sql_variant_property(rv.value, ''BaseType'') '
                        'WHEN ''time'' THEN CONVERT(varchar(64), rv.value, 114) '
                        'WHEN ''date'' THEN CONVERT(varchar(64), rv.value, 23) '
                        'WHEN ''datetime1'' THEN CONVERT(varchar(64), rv.value, 126) '
                        'WHEN ''datetime2'' THEN CONVERT(varchar(64), rv.value, 126) '
                        'WHEN ''datetimeoffset'' THEN CONVERT(varchar(64), rv.value, 126) '
                        'ELSE CONVERT(varchar(64), rv.value) '
                    'END, ''MAXVALUE'') AS boundary_value '
             'FROM sys.tables AS t '
             'JOIN sys.schemas AS s ON t.schema_id = s.schema_id '
             'JOIN sys.indexes AS i ON t.object_id = i.object_id '
             'JOIN sys.index_columns AS ic '
                'ON ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.partition_ordinal >= 1 '
             'JOIN sys.columns AS c ON c.object_id = t.object_id AND c.column_id = ic.column_id '
             'JOIN sys.partitions AS p ON t.object_id = p.object_id AND i.index_id = p.index_id '
             'JOIN sys.partition_schemes AS ps ON i.data_space_id = ps.data_space_id '
             'JOIN sys.partition_functions AS f ON f.function_id = ps.function_id '
             'LEFT JOIN sys.partition_range_values AS rv '
                'ON f.function_id = rv.function_id AND p.partition_number = rv.boundary_id'
        );
        CREATE VIEW %1$I.partitions AS
            SELECT schema, table_name, concat_ws('_', table_name, position) AS partition_name, 
                   type, key, false AS is_default, ARRAY[
                      lag(boundary_value, 1, 'MINVALUE') OVER (PARTITION BY schema, table_name ORDER BY position),
                      boundary_value
                   ] AS values
            FROM %1$I.partition_cols;
        COMMENT ON FOREIGN TABLE %1$I.partition_cols IS 'MSSQL partition schemes on foreign server "%2$I"';
        COMMENT ON VIEW %1$I.partitions IS 'MSSQL partitions on foreign server "%2$I"';
    $$;

    subpartitions_sql text := $$
        CREATE TABLE %1$I.subpartitions (
            schema            name    NOT NULL,
            table_name        name    NOT NULL,
            partition_name    name    NOT NULL,
            subpartition_name name    NOT NULL,
            type              text    NOT NULL,
            key               text    NOT NULL,
            is_default        boolean NOT NULL,
            values            text[]
        )
    $$;

    /* indexes and index_columns */
    indexes_sql text := $$
        CREATE FOREIGN TABLE %1$I.indexes (
            schema        text    NOT NULL,
            table_name    text    NOT NULL,
            index_name    text    NOT NULL,
            uniqueness    boolean NOT NULL,
            where_clause  text
        ) SERVER %2$I OPTIONS (query
            E'SELECT s.name AS "schema", t.name AS table_name, '
                    'i.name AS index_name, i.is_unique AS uniqueness, '
                    'i.filter_definition AS where_clause '
             'FROM sys.indexes i '
             'INNER JOIN sys.tables t ON i.object_id = t.object_id '
             'INNER JOIN sys.schemas s ON t.schema_id = s.schema_id '
             'WHERE i.is_primary_key = 0 AND i.is_unique_constraint = 0 '
             'AND i.type IN (1, 2)'
        );
        COMMENT ON FOREIGN TABLE %1$I.indexes IS 'MSSQL indexes on foreign server "%2$I"';
    $$;

    index_columns_sql text := $$
        CREATE FOREIGN TABLE %1$I.index_columns (
            schema        text    NOT NULL,
            table_name    text    NOT NULL,
            index_name    text    NOT NULL,
            position      integer NOT NULL,
            descend       boolean NOT NULL,
            is_expression boolean NOT NULL,
            column_name   text    NOT NULL
        ) SERVER %2$I OPTIONS (query
            E'SELECT s.name AS "schema", t.name AS table_name, i.name AS index_name, '
                    'ic.index_column_id AS position, ic.is_descending_key AS descend, '
                    '0 AS is_expression, c.name AS column_name '
                    'FROM sys.indexes i '
                    'INNER JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id '
                    'INNER JOIN sys.tables t ON i.object_id = t.object_id '
                    'INNER JOIN sys.columns c ON t.object_id = c.object_id AND ic.column_id  = c.column_id '
                    'INNER JOIN sys.schemas s ON t.schema_id = s.schema_id '
                    'WHERE i.is_primary_key = 0 AND i.is_unique_constraint = 0 '
                    'AND i.type IN (1, 2)'
        );
        COMMENT ON FOREIGN TABLE %1$I.index_columns IS 'MSSQL index columns on foreign server "%2$I"';
    $$;

    /* sequences */
    sequences_sql text := $$
        CREATE FOREIGN TABLE %1$I.sequences (
            schema        text    NOT NULL,
            sequence_name text    NOT NULL,
            min_value     numeric,
            max_value     numeric,
            increment_by  numeric NOT NULL,
            cyclical      boolean NOT NULL,
            cache_size    integer NOT NULL,
            last_value    numeric NOT NULL
        ) SERVER %2$I OPTIONS (query
            E'SELECT s.name AS "schema", sq.name AS sequence_name, '
	                'convert(bigint, minimum_value) AS min_value, '
	                'convert(bigint, maximum_value) AS max_value, '
	                'convert(bigint, increment) AS increment_by, is_cycling AS cyclical, '
	                'CASE WHEN is_cached = 0 OR cache_size IS NULL THEN 0 ELSE cache_size END AS cache_size, '
	                'convert(bigint, current_value) AS last_value '
             'FROM sys.sequences sq '
             'INNER JOIN sys.schemas s ON sq.schema_id = s.schema_id'
        );
        COMMENT ON FOREIGN TABLE %1$I.sequences IS 'MSSQL sequences on foreign server "%2$I"';
    $$;

    /* permissions */
    table_privs_sql text := $$
        CREATE TABLE %1$I.table_privs (
            schema     text    NOT NULL,
            table_name text    NOT NULL,
            privilege  text    NOT NULL,
            grantor    text    NOT NULL,
            grantee    text    NOT NULL,
            grantable  boolean NOT NULL
        )
    $$;

    column_privs_sql text := $$
        CREATE TABLE %1$I.column_privs (
            schema      text    NOT NULL,
            table_name  text    NOT NULL,
            column_name text    NOT NULL,
            privilege   text    NOT NULL,
            grantor     text    NOT NULL,
            grantee     text    NOT NULL,
            grantable   boolean NOT NULL
        )
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
    EXECUTE format(partitions_sql, schema, server);
    EXECUTE format(subpartitions_sql, schema);
    EXECUTE format(views_sql, schema, server);
    EXECUTE format(functions_sql, schema, server);
    EXECUTE format(triggers_sql, schema, server);
    EXECUTE format(index_columns_sql, schema, server);
    EXECUTE format(indexes_sql, schema, server);
    EXECUTE format(sequences_sql, schema, server);
    EXECUTE format(table_privs_sql, schema);
    EXECUTE format(column_privs_sql, schema);

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
    SELECT CASE
        -- numeric types
        --
        WHEN v_type IN ('smallint', 'tinyint') THEN 'smallint'
        WHEN v_type IN ('int') THEN 'int'
        WHEN v_type IN ('bigint') THEN 'bigint'
        WHEN v_type IN ('money', 'decimal') THEN 'numeric'
        WHEN v_type IN ('smallmoney') THEN format('numeric(6,4)')
        WHEN v_type IN ('float') THEN 'double precision'
        WHEN v_type IN ('real') THEN 'real'

        -- text types
        --
        WHEN v_type IN ('text') THEN 'text'
        WHEN v_type IN ('xml') THEN 'xml'
        WHEN v_type IN ('sysname') THEN 'varchar(128)'
        WHEN v_type IN ('char', 'nchar') THEN CASE
            WHEN v_length = -1 THEN 'char'
            ELSE format('char(%s)', v_length)
        END
        WHEN v_type IN ('varchar', 'nvarchar') THEN CASE
            WHEN v_length = -1 THEN 'text'
            ELSE format('varchar(%s)', v_length)
        END

        -- date types
        --
        WHEN v_type IN ('datetime', 'datetime2', 'smalldatetime') THEN 'timestamp'
        WHEN v_type IN ('datetimeoffset') THEN 'timestamp with time zone'
        WHEN v_type IN ('time') THEN 'time'
        WHEN v_type IN ('date') THEN 'date'

        -- binary types
        --
        WHEN v_type IN ('binary', 'varbinary', 'timestamp', 'rowversion', 'image') THEN 'bytea'

        -- other types
        WHEN v_type IN ('bit') THEN 'boolean'
        WHEN v_type IN ('uniqueidentifier') THEN 'uuid'

        -- unknown types
        ELSE v_type END
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
DECLARE
    v_ident_regexp     text := '[a-zA-Z_@#][a-zA-Z0-9_@#]+';
    v_timestamp_regexp text := '[^'']?(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})[^'']?';
    v_reserved_words   text := '^(MINVALUE|MAXVALUE)$';
BEGIN
    /* prevent double-quoting reserved partition bound expressions */
    IF s ~ v_reserved_words THEN RETURN s; END IF;

    s := regexp_replace(s, 'getdate\s*\(\)', 'current_timestamp', 'gi');
    s := regexp_replace(s, 'newid\s*\(\)', 'gen_random_uuid()', 'gi');
    s := regexp_replace(s, 'dateadd\s*\((\w+)\s*,\s*(\(?-?\d+\)?),\s*([a-zA-Z_]+)\s*\)', 
                           '\3+INTERVAL ''\2 \1''', 'gi');

    /* quote timestamp expressions */
    s := regexp_replace(s, v_timestamp_regexp, $$'\1'$$, 'g');

    /* double-quote identifiers if necessary */
    s := regexp_replace(s, '\[(' || v_ident_regexp || ')\]', '"\1"', 'g');
    IF s ~* ('^' || v_ident_regexp || '$') THEN
        s := format('%I', s);
    END IF;

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
        '   OPTIONS (schema_name ''%s'', table_name ''%s'')',
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