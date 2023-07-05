export COMPOSE_FILE=docker/docker-compose.yml
export COMPOSE_PROJECT_NAME=mssql_migrator

export PGHOST=localhost
export PGPORT=5432
export PGUSER=postgres

docker-up:
	docker-compose build
	docker-compose up --detach --remove-orphans

docker-install:
	docker exec -it \
	  -w /usr/local/src/mssql_migrator \
	  $(COMPOSE_PROJECT_NAME)-postgresql_db-1 \
	  make install