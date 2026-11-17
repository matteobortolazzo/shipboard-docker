# Dockerfile rotti

Sette Dockerfile per l'API, ognuno con **un solo** problema. Alcuni non si costruiscono, alcuni non partono, alcuni funzionano ma sono fatti male.

```bash
./docs/esempi/dockerfile-rotti/verifica.sh 1     # prova il caso 1
```

Lo script fa 5 controlli (build, dimensione, utente non root, `/health` sulla porta 8080, cache del restore) e vi da' un punteggio.

**Regole**
- A coppie. Niente LLM e niente `diff` con il Dockerfile giusto: leggete il messaggio d'errore, i log, `docker history`, `docker inspect`.
- Per ogni caso scrivete su un foglio: **sintomo** (cosa vedete), **causa** (quale riga), **fix**.
- Correggete il file e rilanciate `verifica.sh` finche' non fa 5/5.
- Un punto per ogni caso a 5/5 con sintomo e causa scritti bene. Il caso 7 vale doppio.

Comandi utili: `docker logs <id>`, `docker history <immagine>`, `docker image inspect <immagine> --format '{{.Config.User}}'`, `docker build --progress=plain ...`.
