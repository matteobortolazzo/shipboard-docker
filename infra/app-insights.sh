#!/usr/bin/env bash
# Crea Application Insights e lo collega all'App Service: l'API manda li' la stessa telemetria
# che in locale vedete nella dashboard di Aspire.
# Uso: NAME=<nome della web app> ./infra/app-insights.sh
set -euo pipefail

NAME="${NAME:?Imposta NAME, il nome della web app}"
RG="${RG:-rg-shipboard}"
LOCATION="${LOCATION:-$(az group show -n "$RG" --query location -o tsv)}"

echo "==> Log Analytics workspace e Application Insights (piano a consumo: pochi MB al giorno sono gratis)"
az monitor log-analytics workspace create -n "log-shipboard" -g "$RG" -l "$LOCATION" -o none
WORKSPACE_ID=$(az monitor log-analytics workspace show -n "log-shipboard" -g "$RG" --query id -o tsv)
az monitor app-insights component create --app "appi-shipboard" -g "$RG" -l "$LOCATION" \
  --workspace "$WORKSPACE_ID" --application-type web -o none
CONN=$(az monitor app-insights component show --app "appi-shipboard" -g "$RG" --query connectionString -o tsv)

echo "==> Connection string nelle impostazioni della web app (l'app si riavvia)"
az webapp config appsettings set -n "$NAME" -g "$RG" \
  --settings APPLICATIONINSIGHTS_CONNECTION_STRING="$CONN" -o none

echo
echo "Fatto. Fate qualche richiesta, poi portale: appi-shipboard > Transaction search / Live metrics."
