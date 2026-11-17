#!/usr/bin/env bash
# Controlla un Dockerfile dell'API ShipBoard con 5 prove e da' un punteggio.
# Uso (da qualunque cartella):
#   ./docs/esempi/dockerfile-rotti/verifica.sh 3                       # caso numero 3
#   ./docs/esempi/dockerfile-rotti/verifica.sh src/ShipBoard.Api/Dockerfile   # un Dockerfile qualsiasi
# Requisiti: docker e curl. Niente LLM: leggete i messaggi e i log.
set -uo pipefail

qui=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$qui/../../.." && pwd)
arg=${1:?"Uso: $0 <numero del caso 1-7 | percorso di un Dockerfile>"}
if [[ -f "$arg" ]]; then df=$(cd "$(dirname "$arg")" && pwd)/$(basename "$arg"); else df="$qui/$arg/Dockerfile"; fi
[[ -f "$df" ]] || { echo "Dockerfile non trovato: $df"; exit 2; }
ctx="$root/src/ShipBoard.Api"
tag="shipboard-verifica:$$"
cid="shipboard-verifica-$$"
log=$(mktemp); tmp=$(mktemp -d)
pulisci() { docker rm -f "$cid" >/dev/null 2>&1; rm -rf "$log" "$tmp"; docker rmi "$tag" >/dev/null 2>&1; }
trap pulisci EXIT

punti=0
ok() { echo "   OK  $*"; punti=$((punti + 1)); }
ko() { echo "   NO  $*"; }
fine() { echo; echo "Punteggio: $punti/5   (il Dockerfile giusto fa 5/5)"; exit 0; }

echo "Verifico $df"
echo
echo "1. L'immagine si costruisce?"
if docker build --progress=plain -f "$df" -t "$tag" "$ctx" >"$log" 2>&1; then
  ok "build riuscita"
else
  ko "build fallita. Ultime righe del log:"
  grep -v '^#[0-9]* \(sha256\|transferring\|DONE\|CACHED\)' "$log" | tail -12 | sed 's/^/        /'
  fine
fi

echo "2. L'immagine e' piccola (meno di 400 MB)?"
mb=$(( $(docker image inspect -f '{{.Size}}' "$tag") / 1000000 ))
if (( mb < 400 )); then ok "$mb MB"; else ko "$mb MB: cosa c'e' nello stage finale? (docker history $tag)"; fi

echo "3. Gira come utente non root?"
user=$(docker image inspect -f '{{.Config.User}}' "$tag")
if [[ -n "$user" && "$user" != "root" && "$user" != "0" ]]; then ok "USER $user"; else ko "USER '${user:-vuoto}': il processo gira come root"; fi

echo "4. Il container parte e /health risponde sulla porta 8080?"
if ! docker run -d --name "$cid" -p 127.0.0.1::8080 "$tag" >/dev/null 2>"$log"; then
  ko "docker run fallito:"; grep -v '^$\|docker run --help' "$log" | sed 's/^/        /'
else
  porta=$(docker port "$cid" 8080/tcp 2>/dev/null | head -1 | sed 's/.*://')
  sano=no
  for _ in $(seq 1 20); do
    if curl -fsS "http://127.0.0.1:$porta/health" >/dev/null 2>&1; then sano=si; break; fi
    [[ "$(docker inspect -f '{{.State.Running}}' "$cid")" == "true" ]] || break
    sleep 1
  done
  if [[ $sano == si ]]; then
    ok "/health risponde"
  else
    stato=$(docker inspect -f '{{.State.Status}} (exit {{.State.ExitCode}})' "$cid")
    ko "/health non risponde. Stato del container: $stato. Log:"
    docker logs "$cid" 2>&1 | tail -10 | sed 's/^/        /'
  fi
fi

echo "5. Cambiando solo il codice, il restore resta in cache?"
cp -r "$ctx/." "$tmp/"
echo "// modifica di prova" >> "$tmp/Program.cs"
docker build --progress=plain -f "$df" -t "$tag" "$tmp" >"$log" 2>&1
passo=$(grep -m1 -E '^#[0-9]+ \[.*\] RUN dotnet restore' "$log" | cut -d' ' -f1)
if [[ -z "$passo" ]]; then
  ko "non trovo un passo RUN dotnet restore separato"
elif grep -q "^$passo CACHED" "$log"; then
  ok "restore CACHED"
else
  ko "il restore e' stato rifatto: guardate l'ordine di COPY e RUN"
fi
fine
