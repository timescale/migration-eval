# migration-eval

The following are questions and queries which can help evaluate whether a 
database is a good candidate for a migration to Timescale.


What version of postgresql is in use?

```sql
select version();
```

Is the timescaledb extension in use? If so, what version and in which 
schema is it installed? 

```sql
\dx timescaledb
-- or
select
  x.extname
, x.extversion
, n.nspname
, r.rolname
from pg_extension x
inner join pg_namespace n on (x.extnamespace = n.oid)
inner join pg_roles r on (x.extowner = r.oid)
where x.extname = 'timescaledb'
;
```

What other extensions are in use?

```sql
\dx
-- or
select
  x.extname
, x.extversion
, n.nspname
, r.rolname
from pg_extension x
inner join pg_namespace n on (x.extnamespace = n.oid)
inner join pg_roles r on (x.extowner = r.oid)
;
```

Are the extension in use supported on Timescale? Run the query below on a 
Timescale instance to get a list of available extensions.

```sql
select a.*
from pg_available_extensions a
inner join
(
  select unnest(string_to_array(setting, ',')) as name
  from pg_settings
  where name = 'extwlist.extensions'
) w on (a.name = w.name)
;
```

Are you using a single database or multiple databases in the cluster? Timescale
only supports a single database per cluster.

```sql
\l
-- or
select 
  d.datname as "name"
, pg_catalog.pg_get_userbyid(d.datdba) as "owner"
, pg_catalog.pg_encoding_to_char(d.encoding) as "encoding"
, d.datcollate as "collate"
, d.datctype as "ctype"
, d.daticulocale as "icu locale"
, case d.datlocprovider when 'c' then 'libc' when 'i' then 'icu' end as "locale provider"
, pg_catalog.array_to_string(d.datacl, E'\n') as "access privileges"
from pg_catalog.pg_database d
order by 1;
```

How big is the database?

```sql
select
  current_database()
, pg_size_pretty(pg_database_size(current_database()))
;
```

Are you using schemas other than “public”?

```sql
select
  n.nspname
, count(k.oid) as objects
, count(h.id) as hypertables
from pg_namespace n
left outer join pg_class k on (n.oid = k.relnamespace)
left outer join _timescaledb_catalog.hypertable h on (n.nspname = h.schema_name and k.relname = h.table_name)
where n.nspname not like 'pg_%'
and n.nspname != 'information_schema'
group by 1
order by 1
;
```

Do you use any tablespaces other than the default? Timescale does not support
custom tablespaces.

```sql
\db
-- or
select
  spcname as "name"
, pg_catalog.pg_get_userbyid(spcowner) as "owner"
, pg_catalog.pg_tablespace_location(oid) as "location"
from pg_catalog.pg_tablespace
order by 1;
```

How many database users do you have? How many are used by your application? Do any make use of superuser privileges?

```sql
\du
-- or
select
  r.rolname
, r.rolsuper
, r.rolinherit
, r.rolcreaterole
, r.rolcreatedb
, r.rolcanlogin
, r.rolconnlimit
, r.rolvaliduntil
, array
  (
    select b.rolname
    from pg_catalog.pg_auth_members m
    inner join pg_catalog.pg_roles b on (m.roleid = b.oid)
    where m.member = r.oid
  ) as memberof
, r.rolreplication
, r.rolbypassrls
from pg_catalog.pg_roles r
where r.rolname !~ '^pg_'
order by 1;
```

Please share these settings with us.

```sql
select name, setting, unit
from pg_settings where name in
( 'max_connections'
, 'shared_buffers'
, 'work_mem'
, 'maintenance_work_mem'
, 'statement_timeout'
, 'shared_preload_libraries'
, 'search_path'
, 'max_worker_processes'
, 'max_wal_size'
, 'max_wal_senders'
, 'wal_level'
, 'max_locks_per_transaction'
, 'max_logical_replication_workers'
, 'server_encoding'
)
order by 1
;
```

What tables/views are defined? How many are hypertables? How big are they?

```sql
select
  n.nspname
, c.relname
, c.relkind
, h.id is not null as is_hypertable
, case
    when h.id is not null then
        (
            select pg_size_pretty(total_bytes)
            from _timescaledb_internal.hypertable_local_size(h.schema_name, h.table_name)
        )
    else pg_size_pretty(pg_table_size(c.oid::regclass))
  end as table_size
from pg_class c
inner join pg_namespace n on (c.relnamespace = n.oid)
left outer join _timescaledb_catalog.hypertable h on (h.schema_name = n.nspname and h.table_name = c.relname)
where c.relkind in ('r', 'v', 'm', 'p')
and n.nspname !~* '(_)*timescaledb_*'
and n.nspname not like 'pg_%'
and n.nspname != 'information_schema'
order by n.nspname, h.id, c.relname
;
```

How many chunks do the hypertables have? How many chunks are compressed?

```sql
select
  hypertable_schema
, hypertable_name
, owner
, num_dimensions
, num_chunks
, compression_enabled
from timescaledb_information.hypertables h
order by 1, 2
;

select
  hypertable_schema
, hypertable_name
, count(*) as num_chunks
, count(*) filter (where not is_compressed) as num_uncompressed
, count(*) filter (where is_compressed) as num_compressed
, min(range_start) as min_range
, max(range_end) as max_range
, min(range_start) filter (where is_compressed) as min_range_compressed
, max(range_end) filter (where is_compressed) as max_range_compressed
, min(range_start_integer) as min_range_integer
, max(range_end_integer) as max_range_integer
, min(range_start_integer) filter (where is_compressed) as min_range_integer_compressed
, max(range_end_integer) filter (where is_compressed) as max_range_integer_compressed
from timescaledb_information.chunks
group by 1, 2
order by 1, 2
;
```

Do you use space dimensions?

```sql
select *
from
(
    select
      d.hypertable_id
    , row_number() over (partition by d.hypertable_id order by d.id) as dimension_nbr
    , d.column_name
    , d.column_type
    , d.num_slices
    from _timescaledb_catalog.dimension d
) x
where x.dimension_nbr = 2
```

What background jobs do you have defined?

```sql
select *
from timescaledb_information.jobs
;
```

Are there continuous aggregates defined?

```sql
select *
from timescaledb_information.continuous_aggregates;
```

Are there hierarchical continuous aggregates defined?

```sql
with recursive x as
(
    select
      array[a.raw_hypertable_id] as path
    , a.*
    from _timescaledb_catalog.continuous_agg a
    where not exists
    (
        select 1
        from _timescaledb_catalog.continuous_agg a2
        where a.raw_hypertable_id = a2.mat_hypertable_id
    )
    union all
    select
      x.path || array[a.raw_hypertable_id] as path
    , a.*
    from x
    inner join _timescaledb_catalog.continuous_agg a
    on (x.mat_hypertable_id = a.raw_hypertable_id)
)
select
  x.path
, array_length(x.path, 1) > 1 as is_hierarchical_cagg
, x.user_view_schema
, x.user_view_name
, r.schema_name as base_schema
, r.table_name as base_table
, m.schema_name as cagg_schema
, m.table_name as cagg_table
, x.materialized_only
, x.finalized
from x
inner join _timescaledb_catalog.hypertable r on (x.raw_hypertable_id = r.id)
inner join _timescaledb_catalog.hypertable m on (x.mat_hypertable_id = m.id)
order by x.path
;
```

Do you have non-timeseries tables (meta/relational data)? Are the data in these tables static or are they modified?

```sql
select
  n.nspname
, k.relname
, pg_size_pretty(pg_total_relation_size(k.oid::regclass))
from pg_class k
inner join pg_namespace n on (k.relnamespace = n.oid)
where k.relkind = 'r'
and not exists
(
    select 1
    from _timescaledb_catalog.hypertable h
    where n.nspname = h.schema_name
    and k.relname = h.table_name
)
order by 1, 2
```

Are there foreign key relationships between these and time-series tables? How large are these tables?

```sql
select
  h.schema_name as hypertable_schema
, h.table_name as hypertable_name
, f.conname as fk_name
, n.nspname as referenced_schema
, k.relname as referenced_table
, pg_size_pretty(pg_total_relation_size(k.oid::regclass))
from pg_constraint f
inner join pg_class hk on (f.conrelid = hk.oid)
inner join pg_namespace hn on (hk.relnamespace = hn.oid)
inner join _timescaledb_catalog.hypertable h on (hk.relname = h.table_name and hn.nspname = h.schema_name)
inner join pg_class k on (f.confrelid = k.oid)
inner join pg_namespace n on (k.relnamespace = n.oid)
where f.contype = 'f'
and hn.nspname != '_timescaledb_internal'
;
```

Is your time-series workload append-only, or do you update and delete rows too? Do you have late-arriving data?

Do you use compression? Please describe the configuration.

```sql
select *
from  timescaledb_information.compression_settings
;
```

Do you use retention policies? Please describe the configuration.

```sql
select 
  j.id
, hypertable_id
, h.schema_name
, h.table_name
, config->>'drop_after' as drop_after
, scheduled
, schedule_interval
, max_runtime
, max_retries
, retry_period
from _timescaledb_config.bgw_job j
inner join _timescaledb_catalog.hypertable h
on (j.hypertable_id = h.id)
where proc_schema = '_timescaledb_internal'
and proc_name = 'policy_retention'
;
```



