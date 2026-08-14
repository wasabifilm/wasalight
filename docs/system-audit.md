# Audit di sistema Wasalight

`wasalight-system-audit` fornisce una fotografia tecnica leggibile della
console. Funziona sia in SHOW sia in MAINTENANCE, non richiede `sudo` e non
modifica il sistema. Può essere aperto dal terminale oppure da **Wasalight
Control → Supporto → Audit sistema**.

```bash
wasalight-system-audit
```

## Informazioni raccolte

- versione Wasalight, modalità corrente e uptime;
- tempo totale di boot e quindici unità systemd più lente;
- unità fallite, numero dei servizi attivi e porte in ascolto;
- modello CPU, carico, governor e temperature quando `sensors` è disponibile;
- memoria, swap, filesystem, dispositivi, supporto discard/TRIM e dischi
  rotazionali;
- indirizzi, stato delle interfacce e contatori di errore UDP/IP;
- processi con maggiore uso di CPU e memoria;
- eventuali pacchetti guest/telemetria già noti alla pulizia Wasalight.

I comandi systemd e hardware hanno un timeout breve. Un dato non disponibile
resta indicato come tale e non blocca il resto del rapporto.

## Come interpretarlo

In una console pronta per lo show ci si aspetta `/` di tipo `overlay`, `/data`
ext4 in lettura/scrittura, nessuna unità fallita e NetworkManager attivo. In
MAINTENANCE la root è normalmente ext4. Una porta in ascolto non è
automaticamente un problema: confrontarla con i servizi volutamente abilitati,
per esempio SSH, VNC o Companion.

`DISC-MAX` maggiore di zero indica che il dispositivo dichiara il supporto al
discard; `fstrim.timer` indica se il trim periodico è abilitato. `ROTA=1`
identifica in genere un disco meccanico, `ROTA=0` un SSD o storage virtuale.

L'elenco finale dei pacchetti è solo informativo. L'audit non propone rimozioni
arbitrarie e non esegue `apt`, modifiche systemd, mount o scritture. Per
condividere informazioni più complete con l'assistenza usare invece **Esporta
diagnostica**, verificando il contenuto dell'archivio prima dell'invio.
