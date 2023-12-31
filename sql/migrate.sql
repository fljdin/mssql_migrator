\connect - migrator
SET client_min_messages = WARNING;

/* set up staging schemas */
SELECT db_migrate_prepare(
   plugin => 'mssql_migrator',
   server => 'mssql',
   only_schemas => '{HumanResources,Person,Production,Purchasing,Sales}'
);

/* exclude unhandled data types */
DELETE FROM pgsql_stage.columns WHERE type_name = 'geography';

/* replace user data types */
UPDATE pgsql_stage.columns SET type_name = 'smallint'
 WHERE (schema, table_name, column_name) = ('Production', 'Document', 'FolderFlag');
UPDATE pgsql_stage.columns SET type_name = 'smallint' WHERE type_name IN ('Flag', 'NameStyle');
UPDATE pgsql_stage.columns SET type_name = 'text' WHERE type_name = 'hierarchyid';
UPDATE pgsql_stage.columns SET type_name = 'varchar(100)' WHERE type_name = 'Name';
UPDATE pgsql_stage.columns SET type_name = 'varchar(30)' WHERE type_name = 'AccountNumber';
UPDATE pgsql_stage.columns SET type_name = 'varchar(50)' WHERE type_name IN ('OrderNumber', 'Phone');

/* replace check constraints */
-- orig_condition = ("Shelf" like '[A-Za-z]' OR "Shelf"='N/A')
UPDATE pgsql_stage.checks SET condition = $$("Shelf" ~* '[a-z]' OR "Shelf" = 'N/A')$$
 WHERE constraint_name = 'CK_ProductInventory_Shelf';

/* perform the data migration */
SELECT db_migrate_mkforeign(
   plugin => 'mssql_migrator',
   server => 'mssql'
);

/* explicite conversions for hierarchyid columns */
ALTER FOREIGN TABLE "Production"."ProductDocument" OPTIONS (
   DROP schema_name, DROP table_name,
   ADD query 'SELECT ProductID, CAST(DocumentNode AS nvarchar(100)) AS DocumentNode, '
             'ModifiedDate FROM Production.ProductDocument'
);

ALTER FOREIGN TABLE "Production"."Document" OPTIONS (
   DROP schema_name, DROP table_name,
   ADD query E'SELECT CAST(DocumentNode AS nvarchar(100)) AS DocumentNode, DocumentLevel, '
              'Title, Owner, FolderFlag, FileName, FileExtension, Revision, ChangeNumber, '
              'Status, DocumentSummary, Document, rowguid, ModifiedDate FROM Production.Document'
);

ALTER FOREIGN TABLE "HumanResources"."Employee" OPTIONS (
   DROP schema_name, DROP table_name,
   ADD query E'SELECT BusinessEntityID, NationalIDNumber, LoginID, '
              'CAST(OrganizationNode AS nvarchar(100)) AS OrganizationNode, OrganizationLevel, '
              'JobTitle, BirthDate, MaritalStatus, Gender, HireDate, SalariedFlag, VacationHours, '
              'SickLeaveHours, CurrentFlag, rowguid, ModifiedDate FROM HumanResources.Employee'
);

/* migrate the rest of the database */
SELECT db_migrate_tables(
   plugin => 'mssql_migrator'
);

SELECT db_migrate_indexes(
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

/* check some results */
SELECT indexdef FROM pg_indexes WHERE indexname = 'IX_Person_rowguid_filtered';