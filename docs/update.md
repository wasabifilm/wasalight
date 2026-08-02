# Aggiornare Wasalight

Wasalight mantiene codice e pacchetti necessari agli aggiornamenti sulla
partizione persistente `/data`, fuori dall’overlay del sistema.

## Percorsi

```text
/data/system/wasalight   repository Git operativo
/data/system/packages   pacchetti MagicQ proprietari
/data/log/wasalight-update.log
                         registro degli aggiornamenti
```

Il repository pubblico non contiene il pacchetto MagicQ. Il `.deb` viene
copiato separatamente, verificato byte per byte e protetto con permessi
`root:root 0640`.

L’installer inizializza automaticamente il repository persistente quando
`/data` è disponibile. Se GitHub non è raggiungibile, mostra un avviso senza
rimuovere i dati già presenti; ripetere in seguito
`sudo wasalight-update --code-only`.

## Primo aggiornamento

Entrare in MAINTENANCE:

```bash
sudo magicq-maintenance
sudo reboot
```

Poi eseguire:

```bash
sudo wasalight-update
```

Dal desktop non serve aprire manualmente il terminale: clic destro →
**Update Wasalight**, oppure **Wasalight Hub → Support → Update Wasalight**.
Si apre una finestra con quattro fasi leggibili: controllo del pacchetto MagicQ,
download, verifica e installazione. Al termine compare un grande pulsante
**Riavvia ora**; scegliendo **Più tardi** l’aggiornamento resta installato e viene
ricordato che il riavvio è ancora necessario. Non occorre più premere Invio per
chiudere la finestra, quindi il flusso è utilizzabile interamente al touch.

In caso di errore non viene mai eseguito il riavvio automatico: appare un
messaggio breve e i dettagli restano in `/data/log/wasalight-update.log`.

Al primo utilizzo il comando:

1. cerca eventuali `.deb` nelle vecchie cartelle
   `/home/*/wasalight/packages` e `/root/wasalight/packages`;
2. valida formato e architettura `amd64`;
3. copia ogni pacchetto in `/data/system/packages`, confronta origine e
   destinazione e soltanto dopo elimina la vecchia copia;
4. scarica `https://github.com/wasabifilm/wasalight.git` in
   `/data/system/wasalight`;
5. esegue `tests/verify-project.sh` sul codice scaricato;
6. seleziona la versione MagicQ più recente e rilancia l’installer.

Per sicurezza l’installer lascia la macchina in MAINTENANCE. Dopo il collaudo:

```bash
sudo magicq-protect
sudo reboot
```

## Opzioni

Scaricare e verificare soltanto il codice:

```bash
sudo wasalight-update --code-only
```

Preparare direttamente il prossimo avvio protetto:

```bash
sudo wasalight-update --protect
```

Aggiornare e riavviare automaticamente, utile da SSH o terminale:

```bash
sudo wasalight-update --reboot
```

Le opzioni possono essere combinate, ad esempio
`sudo wasalight-update --protect --reboot`. `--code-only --reboot` viene invece
rifiutato perché il solo download non modifica la configurazione del sistema.

Mantenere SSH automatico oppure disabilitato all’avvio:

```bash
sudo wasalight-update --with-ssh
sudo wasalight-update --without-ssh
```

Senza queste opzioni viene conservato lo stato di abilitazione SSH esistente.
La tastiera Onboard viene conservata automaticamente quando è già installata.

## Protezioni

- Il comando rifiuta di operare in SHOW mode con overlay attivo.
- Un aggiornamento Git deve essere un avanzamento lineare (`fast-forward`).
- Le modifiche locali ai file tracciati interrompono l’operazione e non vengono
  cancellate.
- Una destinazione `.deb` con lo stesso nome ma contenuto diverso interrompe la
  migrazione.
- Il codice scaricato viene verificato prima di eseguire l’installer.
- Il log completo resta in `/data/log/wasalight-update.log`.

Se il download non riesce, correggere rete o DNS e ripetere lo stesso comando;
la copia persistente precedente resta disponibile.
