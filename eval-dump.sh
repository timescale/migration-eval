#!/usr/bin/env bash

# This script is to be used to dump a customer's database to be given to Timescale for the purposes of evaluation for
# migration support. We only want to dump the database structures and the contents of some internal timescaledb schemas.
# The script below finds ALL schemas other than the few we want data from, and constructs the appropriate
# --exclude-table-data flags for pg_dump. It generates a custom pg_dump command, outputs it to a shell script, and then
# executes the shell script to affect the dump.

if [ -z "$SOURCE" ]; then
    echo "SOURCE env var is not set."
    exit 1;
fi

# default to 4 jobs in the generated pg_dump command
JOBS="${JOBS:-4}"

if [[ -f eval-dump-generated.sh ]] ; then rm eval-dump-generated.sh ; fi

psql -d "$SOURCE" -X -v JOBS=8 -v ON_ERROR_STOP=1 --echo-errors -f - <<'EOF'
-- we only want data from two timescaledb internal schemas
-- we want to exclude data from all other schemas
-- generate the appropriate flags for a pg_dump command and then run it
\echo generating pg_dump command...
select format(
$bash$#!/usr/bin/env bash
pg_dump -d "$SOURCE" \
  --format=directory \
  --jobs=%s \
  --quote-all-identifiers \
  --no-tablespaces \
  --no-owner \
  --no-privileges \
%s \
  --file=eval-dump
$bash$
, :JOBS
, string_agg(format($$  --exclude-table-data '%s.*'$$, n.nspname), E' \\\n' order by n.nspname)
)
from pg_namespace n
where n.nspname != '_timescaledb_catalog'
and n.nspname != '_timescaledb_config'
and n.nspname not like 'pg_%'
and n.nspname != 'information_schema'
\g (format=unaligned tuples_only=on) eval-dump-generated.sh
EOF

chmod +x ./eval-dump-generated.sh
echo "dumping the database.."
./eval-dump-generated.sh
if [ $? -eq 0 ]
then
  echo "dump succeeded"
else
  echo "dump failed"
fi
