#!/usr/bin/env bash
# Crea un App Service Linux GRATUITO (piano F1) che esegue l'immagine dell'API presa da GHCR.
# Uso:
#   az login
#   IMAGE=ghcr.io/<utente-github>/shipboard-api:latest ./infra/app-service.sh
# Il pacchetto su GHCR deve essere PUBBLICO, altrimenti App Service non riesce a scaricarlo.
set -euo pipefail

IMAGE="${IMAGE:?Imposta IMAGE, es. IMAGE=ghcr.io/mario-rossi/shipboard-api:latest}"
OWNER=$(echo "$IMAGE" | cut -d/ -f2 | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9-')
NAME="${NAME:-shipboard-$OWNER}"        # diventa https://$NAME.azurewebsites.net: deve essere unico al mondo
RG="${RG:-rg-shipboard}"
LOCATION="${LOCATION:-westeurope}"     # se la subscription non la permette: LOCATION=italynorth, swedencentral, ...
PLAN="${PLAN:-plan-shipboard}"

echo "==> Resource group $RG ($LOCATION)"
az group create -n "$RG" -l "$LOCATION" -o none

echo "==> Piano App Service Linux F1 (gratis: 1 GB di RAM, 60 minuti di CPU al giorno, niente Always On)"
az appservice plan create -n "$PLAN" -g "$RG" --is-linux --sku F1 -o none

echo "==> Web app $NAME con l'immagine $IMAGE"
az webapp create -n "$NAME" -g "$RG" -p "$PLAN" --container-image-name "$IMAGE" -o none

# L'immagine .NET ascolta sulla 8080: App Service deve saperlo per inoltrare il traffico.
az webapp config appsettings set -n "$NAME" -g "$RG" --settings WEBSITES_PORT=8080 -o none

# Log del container visibili con `az webapp log tail`.
az webapp log config -n "$NAME" -g "$RG" --docker-container-logging filesystem -o none

echo
echo "Fatto: https://$NAME.azurewebsites.net/info"
echo "Il primo avvio scarica l'immagine e puo' richiedere un minuto. Log: az webapp log tail -n $NAME -g $RG"
echo "A fine corso: az group delete -n $RG --yes --no-wait"
