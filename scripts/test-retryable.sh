#!/bin/sh
# Retry only a shard whose failure messages all describe a timeout.
set -eu
awk '
    /^    / { n++; if ($0 !~ /Timed out while|Failed to get screenshot|Failed to terminate|^    Test exceeded execution time allowance of [0-9]+ minutes?$/) bad = 1 }
    END { exit (n == 0 || bad) }'
