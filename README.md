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
