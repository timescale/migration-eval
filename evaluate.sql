--!/usr/bin/env python3
-- Copyright 2024 Timescale Inc.
--
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
--
-- http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.

-- Repository: https://github.com/timescale/migration-eval
--
-- This file runs SQL queries against your database and collects necessary data
-- to generate a migration evaluation report, which allows us to recommend the
-- most suitable migration strategy for your specific use case.
--
-- To run: psql -t -q -d "<POSTGRES_URI>" -f evaluate.sql
--
-- The generated report will be printed in the terminal which can be redirected to a file.

\pset tuples_only

\set ON_ERROR_STOP on

\if :{?sampling_interval}
\else
\set sampling_interval 60
\endif

select version() version \gset
\echo 'PostgreSQL version:' :version

select pg_size_pretty(pg_database_size(current_database())) db_size \gset
\echo 'Database size:' :db_size

-- Includes hypertables, chunks, and plain PG tables except PG & TSDB system tables.
select count(*) count from information_schema.tables
where
    table_type = 'BASE TABLE'
and
    table_schema not in (
        -- Ignore tables from PG system.
        'information_schema', 'pg_catalog',

        -- Ignore tables from TSDB system.
        '_timescaledb_catalog', '_timescaledb_cache', 'timescaledb_information',
        '_timescaledb_config', '_timescaledb_debug', '_timescaledb_functions', 'timescaledb_experimental'
    )
and
    -- Ignore tables from TSDB system under _timescaledb_internal schema.
    table_name not in (
        'bgw_job_stat', 'bgw_policy_chunk_stats', 'job_errors'
    )
\gset
\echo 'Num tables:' :count

select count(*) count from pg_partitioned_table \gset
\echo 'Num declarative partitions:' :count

select coalesce(array_agg(spcname), '{}'::text[]) coalesce from pg_tablespace where spcname not in ('pg_default', 'pg_global') \gset
\echo 'Non-standard tablespaces:' :coalesce

select current_database() \gset
\echo 'Current database:' :current_database

select coalesce(array_agg(datname), '{}'::text[]) coalesce from pg_database where datname not in (
    'template0', 'template1', 'rdsadmin', 'tsadmin', current_database()
) \gset
\echo 'Other databases:' :coalesce

select coalesce(array_agg(schema_name), '{}'::text[]) coalesce from information_schema.schemata
where
    schema_name not in ('pg_catalog', 'information_schema', '_timescaledb_functions',
    'timescaledb_experimental', '_timescaledb_cache', '_timescaledb_catalog',
    '_timescaledb_config', '_timescaledb_internal', 'timescaledb_information',
    'toolkit_experimental') \gset
\echo 'Schemas:' :coalesce

select exists(select 1 from pg_extension where extname = 'timescaledb') is_timescaledb \gset

\if :is_timescaledb
select extversion tsdb_version from pg_extension where extname = 'timescaledb' \gset
\echo 'TimescaleDB version:' :tsdb_version

select n.nspname nspname from pg_extension e
    join pg_namespace n on e.extnamespace = n.oid
    where extname = 'timescaledb' \gset
\echo 'TimescaleDB extension schema:' :nspname

-- Plain PG tables only (non-system tables).
select count(*) count from information_schema.tables
where
    table_type = 'BASE TABLE' and
    table_schema not in (
        '_timescaledb_internal', '_timescaledb_config', '_timescaledb_catalog', '_timescaledb_cache',
        'timescaledb_experimental', 'timescaledb_information', '_timescaledb_functions',
        'information_schema', 'pg_catalog') and
    not exists (
        select 1 from timescaledb_information.hypertables ht
        where
            ht.hypertable_schema = table_schema
        and
            ht.hypertable_name = table_name
    )
\gset
\echo 'Num regular PostgreSQL tables excl. Hypertables:' :count

select count(*) count from timescaledb_information.hypertables \gset
\echo 'Num TimescaleDB Hypertables:' :count

select count(*) count from timescaledb_information.continuous_aggregates \gset
\echo 'Num TimescaleDB Continuous Aggregates:' :count

select count(*) count from timescaledb_information.continuous_aggregates where not finalized \gset
\echo 'Num old partial-form Continuous Aggregates:' :count

select count(*) count from timescaledb_information.dimensions where dimension_type = 'Space' \gset
\echo 'Num TimescaleDB space dimensions:' :count

-- TimescaleDB features
select coalesce(array_agg(feature), '{}'::text[]) coalesce from (
    select
        'hypertables' as feature,
        count(*) > 0 as uses_feature
    from timescaledb_information.hypertables
union all
    select
        'continuous_aggregates' as feature,
        count(*) > 0 as uses_feature
    from timescaledb_information.continuous_aggregates
union all
    select
        'retention' as feature,
        count(*) > 0 as uses_feature
    from timescaledb_information.jobs where application_name like 'Retention Policy%'
union all
    select
        'compression' as feature,
        count(*) > 0 as uses_feature
    from timescaledb_information.compression_settings
union all
    select
        'background_jobs' as feature,
        count(*) > 0 as uses_feature
    from timescaledb_information.jobs where job_id >= 1000
) a
where
    uses_feature \gset
\echo 'TimescaleDB features:' :coalesce
\else
\echo 'TimescaleDB version: NA'
\endif

select coalesce(json_agg(json_build_object(extname, extversion)), '[]'::json) agg FROM pg_extension
where extname not in (
    'bloom', 'btree_gin', 'btree_gist', 'citext', 'cube', 'dict_int', 'dict_xsyn', 'fuzzystrmatch',
    'hstore', 'intarray', 'isn', 'lo', 'ltree', 'pg_stat_statements', 'pg_trgm', 'pgcrypto', 'pgpcre',
    'pgrouting', 'pgstattuple', 'pgvector', 'pg_buffercache', 'plpgsql', 'postgis', 'postgis_raster', 'postgis_sfcgal',
    'postgis_tiger_geocoder', 'postgis_topology', 'seg', 'tablefunc', 'tcn', 'timescaledb_toolkit',
    'timescaledb', 'tsm_system_rows', 'tsm_system_time', 'unaccent', 'uuid-ossp') \gset
\echo 'Unsupported extensions in Timescale Cloud:' :agg

select exists(select 1 from information_schema.columns where is_generated = 'ALWAYS') \gset
\echo 'Do tables have generated columns:' :exists

select exists (
    select 1 from pg_stats where
        schemaname not in (
            '_timescaledb_internal', '_timescaledb_config', '_timescaledb_catalog', '_timescaledb_cache',
            'timescaledb_experimental', 'timescaledb_information', '_timescaledb_functions',
            'information_schema', 'pg_catalog')
    and
        (
            exists (
                select 1 from unnest(most_common_vals::text::text[]) as v
                where
                    v IN ('NaN', 'Infinity', '-Infinity')
            )
        or
            exists (
                select 1 from unnest(histogram_bounds::text::text[]) as h
                where
                    h IN ('NaN', 'Infinity', '-Infinity')
            )
        )
) \gset
\echo 'Do tables attributes have NaN, Infinity or -Infinity*:' :exists


-- Rate of inserts, updates, deletes and transactions (per sec)
create temp table _mig_eval_t (
    n int, n_tup_ins numeric, n_tup_upd numeric, n_tup_del numeric, xact_commit numeric
);

insert into _mig_eval_t
    select 1, sum(n_tup_ins) n_tup_ins, sum(n_tup_upd) n_tup_upd, sum(n_tup_del) n_tup_del, d.xact_commit
    from pg_stat_user_tables u join pg_stat_database d on true
    where
        u.relname not in ('_mig_eval_t') AND
        u.schemaname not in (
            '_timescaledb_config', '_timescaledb_catalog', '_timescaledb_cache',
            'timescaledb_experimental', 'timescaledb_information', '_timescaledb_functions',
            'information_schema', 'pg_catalog') AND
        d.datname = current_database()
    group by d.xact_commit;

select pg_sleep(:sampling_interval) \gset

insert into _mig_eval_t
    select 2, sum(n_tup_ins) n_tup_ins, sum(n_tup_upd) n_tup_upd, sum(n_tup_del) n_tup_del, d.xact_commit
    from pg_stat_user_tables u join pg_stat_database d on true
    where
        u.relname not in ('_mig_eval_t') AND
        u.schemaname not in (
            '_timescaledb_config', '_timescaledb_catalog', '_timescaledb_cache',
            'timescaledb_experimental', 'timescaledb_information', '_timescaledb_functions',
            'information_schema', 'pg_catalog') AND
        d.datname = current_database()
    group by d.xact_commit;

select count(*) = 2 has_sufficient_activity_t from _mig_eval_t \gset

\if :has_sufficient_activity_t
with before as (
    select * from _mig_eval_t where n = 1
), after as (
    select * from _mig_eval_t where n = 2
)
select
    round((after.n_tup_ins - before.n_tup_ins) / :sampling_interval, 3) || ' inserts_per_sec, ' ||
    round((after.n_tup_upd - before.n_tup_upd) / :sampling_interval, 3) || ' updates_per_sec, ' ||
    round((after.n_tup_del - before.n_tup_del) / :sampling_interval, 3) || ' deletes_per_sec, ' ||
    round((after.xact_commit - before.xact_commit) / :sampling_interval, 3) || ' txns_per_sec'
        as per_sec
from after, before \gset
\echo 'Rate of DML:' :per_sec
\else
\echo 'Rate of DML: Insufficient activity'
\endif

-- WAL activity
create temp table _mig_eval_w (n int, wal_records numeric, wal_bytes numeric);

insert into _mig_eval_w
    select 1, wal_records, wal_bytes from pg_stat_wal;

select pg_sleep(:sampling_interval) \gset

insert into _mig_eval_w
    select 2, wal_records, wal_bytes from pg_stat_wal;

select count(*) = 2 has_sufficient_activity_w from _mig_eval_t \gset

\if :has_sufficient_activity_w
with before as (
    select * from _mig_eval_w where n = 1
), after as (
    select * from _mig_eval_w where n = 2
)
select
    round((after.wal_records - before.wal_records) / :sampling_interval, 3)::text || ' wal_records_per_sec, ' ||
    round((after.wal_bytes - before.wal_bytes) / (:sampling_interval * 1024 * 1024), 3)::text || ' wal_megabytes_per_sec'
        as per_sec
from after, before \gset
\echo 'WAL activity:' :per_sec
\else
\echo 'WAL activity: Insufficient activity'
\endif
