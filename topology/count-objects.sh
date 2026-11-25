#!/bin/bash

for file in paths-*.txt; do
    echo "=== $file ==="
    echo "Jumlah objek: $(grep -cve '^[[:space:]]*$' "$file")"
    echo
done
