# migration-eval

This repository provides scripts that assist the Timescale migration team
in selecting the optimal migration strategy to Timescale Cloud for your
specific database.

You will need `Python 3.x` and `psql` to run the scripts.

To recommend a suitable migration strategy for your database, we'll need
some information about its current state. You can collect this information
by running the following command:

```sh
curl -sL https://assets.timescale.com/releases/migration/evaluate.py | python3 - "<POSTGRES_URI>" > report.txt
```

This command will:
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
```
