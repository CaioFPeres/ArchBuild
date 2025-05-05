#!/bin/bash

cd packages

for pkgdir in */; do
  log_file="${pkgdir}/*.log"

  if grep -q 'march=x86-64' $log_file 2>/dev/null; then
    echo "Found march=x86-64 in: $pkgdir"
    echo "-------------------------------"
  fi
done