#!/bin/env bash

if [[ -z $1 || ( $1 != start && $1 != shutdown ) ]]; then
  echo "usage: $0 < start || shutdown >"
  exit 1
fi

for i in {1..3}; do
  sudo virsh ${1} --domain vm${i}
done
