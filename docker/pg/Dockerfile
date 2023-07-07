FROM postgres:latest
RUN apt-get update && apt-get install -y \
    make \
    wget \
    postgresql-15-tds-fdw

ADD locales.conf /etc/freetds/locales.conf
RUN mkdir -p /usr/local/src

# install db_migrator
ARG db_migrator_release="1.0.0"
ENV db_migrator_url="https://github.com/cybertec-postgresql/db_migrator/archive/refs/heads/master.tar.gz"
RUN wget ${db_migrator_url} -O - | tar -xzC /usr/local/src ; \
    make -C /usr/local/src/db_migrator-master install