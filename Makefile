include docker/docker.mk
EXTENSION = mssql_migrator
DATA = mssql_migrator--*.sql
REGRESS = install migrate partitioning preserve_case

PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)

all:
	@echo 'Nothing to be built. Run "make install".'