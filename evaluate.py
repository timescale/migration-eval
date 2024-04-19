#!/usr/bin/env python3
# Copyright 2024 Timescale Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Repository: https://github.com/timescale/migration-eval
#
# This file runs SQL queries against your database and collects necessary data
# to generate a migration evaluation report, which allows us to recommend the
# most suitable migration strategy for your specific use case.
#
# To run: python3 evaluate.py "<POSTGRES_URI>" > report.txt
#
# The generated report will be printed in the terminal which can be redirected to a file.

import sys
import subprocess

SUPPORTED_EXTENSIONS = [
    "bloom",
    "btree_gin",
    "btree_gist",
    "citext",
    "cube",
    "dict_int",
    "dict_xsyn",
    "fuzzystrmatch",
    "hstore",
    "intarray",
    "isn",
    "lo",
    "ltree",
    "pg_stat_statements",
    "pg_trgm",
    "pgcrypto",
    "pgpcre",
    "pgrouting",
    "pgstattuple",
    "pgvector",
    "plpgsql",
    "postgis",
    "postgis_raster",
    "postgis_sfcgal",
    "postgis_tiger_geocoder",
    "postgis_topology",
    "seg",
    "tablefunc",
    "tcn",
    "timescaledb_toolkit",
    "timescaledb",
    "tsm_system_rows",
    "tsm_system_time",
    "unaccent",
    "uuid-ossp",
]

QUERIES = [
    {
        "name": "PostgreSQL version",
        "query": "select version()",
    }, {
        "name": "Database size",
        "query": "select pg_size_pretty(pg_database_size(current_database()))",
    }, {
        "name": "Num tables",
        "query": """
            select count(*) from information_schema.tables
            where
                table_type = 'BASE TABLE' and
                table_schema not in ('information_schema', 'pg_catalog')
            """,
    }, {
        "name": "Num regular PostgreSQL tables excl. Hypertables",
        "query": """
            select count(*) from information_schema.tables
            where
                table_type = 'BASE TABLE' and
                table_schema not in (
                    '_timescaledb_internal', '_timescaledb_config', '_timescaledb_catalog', '_timescaledb_cache',
                    'timescaledb_experimental', 'timescaledb_information', '_timescaledb_functions',
                    'information_schema', 'pg_catalog') and
                not exists (
                    select 1 from timescaledb_information.hypertables ht
                    where
                        ht.hypertable_schema = table_schema and
                        ht.hypertable_name = table_name)
            """,
    }, {
        "name": "Num declarative partitions",
        "query": "select count(*) from pg_partitioned_table",
    }, {
        "name": "Non-standard tablespaces",
        "query": "select array_agg(spcname) from pg_tablespace where spcname not in ('pg_default', 'pg_global')",
    }, {
        "name": "Current database",
        "query": "select current_database()",
    }, {
        "name": "Other databases",
        "query": "select array_agg(datname) from pg_database where datname not in ('template0', 'template1', 'rdsadmin', 'tsadmin', current_database())",
    }, {
        "name": "Schemas",
        "query": """
            select array_agg(schema_name) from information_schema.schemata
            where
                schema_name not in ('pg_catalog', 'information_schema', '_timescaledb_functions',
                'timescaledb_experimental', '_timescaledb_cache', '_timescaledb_catalog',
                '_timescaledb_config', '_timescaledb_internal', 'timescaledb_information')
            """
    }, {
        "name": "TimescaleDB version",
        "query": "select extversion from pg_extension where extname = 'timescaledb'",
    }, {
        "name": "Num TimescaleDB Hypertables",
        "query": "select count(*) from timescaledb_information.hypertables",
    }, {
        "name": "Num TimescaleDB Continuous Aggregates",
        "query": "select count(*) from timescaledb_information.continuous_aggregates",
    }, {
        "name": "Num old partial-form Continuous Aggregates",
        "query": "select count(*) from timescaledb_information.continuous_aggregates where not finalized",
    }, {
        "name": "Num TimescaleDB space dimensions",
        "query": "select count(*) from timescaledb_information.dimensions where dimension_type = 'Space'",
    }, {
        "name": "TimescaleDB extension schema",
        "query": """
            select n.nspname from pg_extension e
                join pg_namespace n on e.extnamespace = n.oid
                where extname = 'timescaledb'
            """
    }, {
        "name": "TimescaleDB features",
        "query": """
            select array_agg(feature) from (
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
                uses_feature
            """
    }, {
        "name": "Unsupported extensions in Timescale Cloud",
        "query": f"""
            select json_agg(json_build_object(extname, extversion)) from pg_extension
            where extname not in ({",".join([f"'{ext}'" for ext in SUPPORTED_EXTENSIONS])})
            """,
    }, {
        "name": "Do tables have generated columns",
        "query": f"""
            select exists(select 1 from information_schema.columns where is_generated = 'ALWAYS')
            """
    }, {
        "name": "Do tables attributes have NaN, Infinity or -Infinity*",
        "query": f"""
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
            )
            """
    }, {
        "name": "Rate of inserts, updates, deletes and transactions (per sec)",
        "query": f"""
            create temp table _mig_eval_t (
                n int, n_tup_ins numeric, n_tup_upd numeric, n_tup_del numeric, xact_commit numeric
            );

            begin;
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
            commit;

            select pg_sleep(@wait@);

            begin;
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
            commit;

            with before as (
                select * from _mig_eval_t where n = 1
            ), after as (
                select * from _mig_eval_t where n = 2
            )
            select
                round((after.n_tup_ins - before.n_tup_ins) / @wait@, 3) inserts_per_sec,
                ' ' || round((after.n_tup_upd - before.n_tup_upd) / @wait@, 3) updates_per_sec,
                ' ' || round((after.n_tup_del - before.n_tup_del) / @wait@, 3) deletes_per_sec,
                ' ' || round((after.xact_commit - before.xact_commit) / @wait@, 3) txns_per_sec
            from after, before;
            """,
    }, {
        "name": "WAL activity",
        "query": f"""
            create temp table _mig_eval_w (n int, wal_records numeric, wal_bytes numeric);

            begin;
                insert into _mig_eval_w
                select 1, wal_records, wal_bytes from pg_stat_wal;
            commit;

            select pg_sleep(@wait@);

            begin;
                insert into _mig_eval_w
                select 2, wal_records, wal_bytes from pg_stat_wal;
            commit;

            with before as (
                select * from _mig_eval_w where n = 1
            ), after as (
                select * from _mig_eval_w where n = 2
            )
            select
                round((after.wal_records - before.wal_records) / @wait@, 3)::text || ' wal_records_per_sec',
                ' ' || round((after.wal_bytes - before.wal_bytes) / (@wait@ * 1024 * 1024), 3)::text || ' wal_megabytes_per_sec'
            from after, before;
            """
    }
]

POSTGRES_URI = ""

def execute(sql: str) -> str:
    cmd = ["psql", "-X", "-A", "-t", "-q", "-F", ",", "-v", "ON_ERROR_STOP=1", "--echo-errors", "-d", POSTGRES_URI, "-c", sql]
    result = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    output = str(result.stdout)[:-1].strip()
    if result.returncode != 0:
        return "-"
    if output == "":
        return "-"
    return output

def test_conn() -> bool:
    cmd = ["psql", "-X", "-A", "-t", "-v", "ON_ERROR_STOP=1", "--echo-errors", "-d", POSTGRES_URI, "-c", "select 1"]
    result = subprocess.run(cmd, text=True, stdout=subprocess.PIPE)
    if result.returncode != 0:
        sys.exit(1)

if __name__ == "__main__":
    wait_duration = 60
    match len(sys.argv):
        case 3:
            POSTGRES_URI = sys.argv[1]
            wait_duration = int(sys.argv[2])
        case 2:
            POSTGRES_URI = sys.argv[1]
        case _:
            print('POSTGRES_URI not found. Please provide it as an argument\nEg: python3 evaluate.py "<POSTGRES_URI>"', file=sys.stderr)
            sys.exit(1)
    test_conn()
    for query in QUERIES:
        sql = query['query'].replace("@wait@", str(wait_duration))
        print(f"{query['name']}: {execute(sql)}", file=sys.stdout)
