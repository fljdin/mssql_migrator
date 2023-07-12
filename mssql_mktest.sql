SET QUOTED_IDENTIFIER ON;

-- Indexes

IF EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_Person_rowguid_filtered')
    DROP INDEX IX_Person_rowguid_filtered ON Person.Person;
GO

CREATE NONCLUSTERED INDEX IX_Person_rowguid_filtered ON Person.Person(rowguid) WHERE EmailPromotion = 1;
GO

-- Partitioning

IF NOT EXISTS (SELECT name FROM sys.schemas WHERE name = 'Partitions')
	EXEC('CREATE SCHEMA [Partitions]');
GO

/* partition by date range */
IF EXISTS (SELECT name FROM sys.tables WHERE name = 'PartByDateRange')
BEGIN 
	DROP TABLE [Partitions].[PartByDateRange];
	DROP PARTITION SCHEME upsByDateRange;
	DROP PARTITION FUNCTION ufnByDateRange;
END
GO

CREATE PARTITION FUNCTION ufnByDateRange (datetime2(0))
    AS RANGE RIGHT FOR VALUES ('2022-04-01', '2022-05-01', '2022-06-01');
GO

CREATE PARTITION SCHEME upsByDateRange
    AS PARTITION ufnByDateRange
    ALL TO ('PRIMARY');
GO

CREATE TABLE [Partitions].[PartByDateRange] (
    col1 datetime2(0) CONSTRAINT PK_PartByDateRange_col1 PRIMARY KEY,
    col2 char(10) NOT NULL,
) ON upsByDateRange (col1);
GO

INSERT INTO [Partitions].[PartByDateRange]
VALUES 
    ('2022-04-01', 'text1'),
    ('2022-05-01', 'text2'),
    ('2022-06-01', 'text3');
GO

/* partition by int range */
IF EXISTS (SELECT name FROM sys.tables WHERE name = 'PartByIntRange')
BEGIN 
    DROP TABLE [Partitions].[PartByIntRange];
    DROP PARTITION SCHEME upsByIntRange;
    DROP PARTITION FUNCTION ufnByIntRange;
END
GO

CREATE PARTITION FUNCTION ufnByIntRange (int)
    AS RANGE RIGHT FOR VALUES (100, 200, 300);
GO

CREATE PARTITION SCHEME upsByIntRange
    AS PARTITION ufnByIntRange
    ALL TO ('PRIMARY');
GO

CREATE TABLE [Partitions].[PartByIntRange] (
    col1 int CONSTRAINT PK_PartByIntRange_col1 PRIMARY KEY,
    col2 char(10) NOT NULL,
) ON upsByIntRange (col1);
GO

INSERT INTO [Partitions].[PartByIntRange]
VALUES 
    (100, 'text1'),
    (200, 'text2'),
    (300, 'text3');
GO
