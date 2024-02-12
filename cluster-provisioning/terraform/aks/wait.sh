#!/bin/bash


while true; do
  if [ $(kubectl get pods -n cert-manager | grep -i Running | wc -l) -eq 3 ]; then
    break
  fi
  sleep 5
done
