#!/usr/bin/env bash
# Permette a GitHub Actions di fare il deploy sull'App Service SENZA password:
# - crea una User Assigned Managed Identity
# - le aggiunge una credenziale federata che si fida solo dei job del vostro repo nell'environment indicato
# - le da' il ruolo "Website Contributor" solo sulla vostra web app (privilegio minimo)
# Uso:
#   REPO=<utente-github>/shipboard-docker NAME=<nome della web app> ./infra/github-oidc.sh
# Requisiti: az login fatto, ruolo Owner (o User Access Administrator) sul resource group.
set -euo pipefail

REPO="${REPO:?Imposta REPO, es. REPO=mario-rossi/shipboard-docker (esattamente come su GitHub)}"
NAME="${NAME:?Imposta NAME, il nome della web app creata da app-service.sh}"
RG="${RG:-rg-shipboard}"
ENVIRONMENT="${ENVIRONMENT:-production}"
IDENTITY="${IDENTITY:-id-github-deploy}"

echo "==> Managed Identity $IDENTITY"
az identity create -n "$IDENTITY" -g "$RG" -o none
CLIENT_ID=$(az identity show -n "$IDENTITY" -g "$RG" --query clientId -o tsv)
PRINCIPAL_ID=$(az identity show -n "$IDENTITY" -g "$RG" --query principalId -o tsv)

echo "==> Credenziale federata: si fida solo di repo:$REPO:environment:$ENVIRONMENT"
az identity federated-credential create -n "github-$ENVIRONMENT" --identity-name "$IDENTITY" -g "$RG" \
  --issuer https://token.actions.githubusercontent.com \
  --subject "repo:$REPO:environment:$ENVIRONMENT" \
  --audiences api://AzureADTokenExchange -o none

echo "==> Ruolo Website Contributor sulla sola web app $NAME"
WEBAPP_ID=$(az webapp show -n "$NAME" -g "$RG" --query id -o tsv)
az role assignment create --assignee-object-id "$PRINCIPAL_ID" --assignee-principal-type ServicePrincipal \
  --role "Website Contributor" --scope "$WEBAPP_ID" -o none

TENANT_ID=$(az account show --query tenantId -o tsv)
SUBSCRIPTION_ID=$(az account show --query id -o tsv)

# Non sono segreti: senza la credenziale federata (che vale solo per il vostro repo) non servono a nulla.
declare -A VARS=(
  [AZURE_CLIENT_ID]="$CLIENT_ID"
  [AZURE_TENANT_ID]="$TENANT_ID"
  [AZURE_SUBSCRIPTION_ID]="$SUBSCRIPTION_ID"
  [AZURE_WEBAPP_NAME]="$NAME"
)

if command -v gh >/dev/null && gh auth status >/dev/null 2>&1; then
  echo "==> Environment $ENVIRONMENT e variabili su GitHub (con la gh CLI)"
  gh api -X PUT "repos/$REPO/environments/$ENVIRONMENT" >/dev/null
  for k in "${!VARS[@]}"; do gh variable set "$k" --env "$ENVIRONMENT" --repo "$REPO" --body "${VARS[$k]}"; done
  echo "Fatto. Controllate in Settings > Environments > $ENVIRONMENT."
else
  echo
  echo "Ora su GitHub: Settings > Environments > New environment '$ENVIRONMENT', poi aggiungete queste VARIABLES (non secrets):"
  for k in "${!VARS[@]}"; do echo "  $k = ${VARS[$k]}"; done
fi
echo
echo "Il ruolo puo' impiegare un paio di minuti a propagarsi: se il primo deploy da' 403, rilanciatelo."
