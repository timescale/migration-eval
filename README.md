# migration-eval

This repository provides scripts that assist the Timescale migration team
in selecting the optimal migration strategy to Timescale Cloud for your
specific database.

You will need `Python 3.x` and `psql` to run the scripts.

To recommend a suitable migration strategy for your database, we'll need
some information about its current state. You can collect this information
by running the following command:

```sh
curl -sL https://assets.timescale.com/releases/migration/evaluate.py | python3 - "<POSTGRES_URI>" <wait-duration> > report.txt
```

where
- `<POSTGRES_URI>` is the URI of your source database.
- `<wait-duration>` is the amount of time in _seconds_ to consider while computing rate based metrics, eg, rate of transactions per second. This argument is optional and defaults to 1 minute.

The above command will:
- Download the latest evaluation script
- Run queries against your Postgres database
- Save the results necessary for evaluating the suitable migration strategy to a file named "report.txt"

Please share the generated "report.txt" file with us for further analysis.

When executed on a database with TimescaleDB installed, the script generates the following report:

```text
PostgreSQL version: PostgreSQL 15.6 on x86_64-pc-linux-gnu, compiled by gcc (GCC) 13.2.1 20231011 (Red Hat 13.2.1-4), 64-bit
Database size: 751 MB
Num tables: 74
Num regular PostgreSQL tables excl. Hypertables: 8
Num declarative partitions: 2
Non-standard tablespaces: -
Databases: {_timescaledb,defaultdb,tsbs}
TimescaleDB version: 2.13.1
Num TimescaleDB Hypertables: 2
Num TimescaleDB Continuous Aggregates: 1
Num TimescaleDB space dimensions: 2
TimescaleDB extension schema: public
TimescaleDB features: {hypertables,continuous_aggregates,retention,compression,background_jobs}
Unsupported extensions in Timescale Cloud: [{"aiven_extras" : "1.1.12"}]
Rate of inserts, updates, deletes and transactions (per sec): 10791.750, 0.000, 0.000, 43.667
Do compressed chunks have mutable (insert/update/delete) compression*: f
Do tables have generated columns: f
Do tables attributes have NaN, Infinity or -Infinity*: f
WAL activity: 19786.500 wal_records_per_sec, 2.172 wal_megabytes_per_sec
```

Note: Metrics with an asterisk (*) will require further confirmation from the user.
This is because they represent the temporary state of the database, and the actual answer
may vary depending on the applications.
