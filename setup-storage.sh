#!/bin/env bash

kubectl apply -f sc.yaml

for VM_NUM in {2..3}; do
  for LV_NUM in {0..9}; do
    export VM_NUM
    export LV_NUM
    envsubst < pv.yaml | kubectl apply -f -
  done
done
