# Bitfocus Companion in Wasalight

## Architettura

Wasalight integra Bitfocus Companion come servizio **headless nativo** e
opzionale. Non usa Docker, perché le superfici USB locali (per esempio Stream
Deck) richiedono accesso udev/libusb che il container ufficiale non supporta.

Companion gira con l'utente non privilegiato `companion`, indipendente da
`chamsys` e dal processo MagicQ. Un guasto o un riavvio di Companion non deve
fermare MagicQ.

La build approvata da questa versione Wasalight è registrata in:

```text
/etc/wasalight/companion-target-version
/etc/wasalight/companion-pi-commit
```

L'installer usa CompanionPi ufficiale fissato a quel commit e installa la
versione stabile esplicita, evitando un download non riproducibile da `main`.

## Installazione

Serve accesso Internet e la modalità MAINTENANCE:

```bash
sudo ./install.sh --with-companion
```

La prima installazione può essere richiesta anche tramite l'updater Wasalight:

```bash
sudo wasalight-update --with-companion
```

Se l'updater già installato sulla console risponde `Opzione sconosciuta`, prima
eseguire `sudo wasalight-update` senza opzioni e poi ripetere il comando sopra.
Questo passaggio è necessario una sola volta per aggiornare l'updater stesso.

L'opzione è necessaria soltanto per la prima installazione. I successivi update
Wasalight riconoscono `/opt/companion`, mantengono il servizio e non aggiornano
Companion automaticamente.

Il runtime upstream rimane in `/opt/companion`; il servizio systemd parte dopo
NetworkManager e ascolta normalmente sulla porta TCP `8000`. Aprire da un Mac,
tablet o altro computer:

```text
http://INDIRIZZO_WASALIGHT:8000
```

## Persistenza

Questi dati restano fuori dall'overlay root:

```text
/data/companion/home/       home, database, moduli e configurazione utente
/data/companion/etc/        configurazione di avvio config.yaml
/data/companion/log/        log del servizio
/data/companion/backups/    backup consistenti creati in MAINTENANCE
/data/companion/browser/    profilo persistente del browser locale Falkon
```

Sono montati rispettivamente su `/home/companion` e `/etc/companion`. I file
restano scrivibili anche in SHOW, così pulsanti, connessioni e moduli non si
perdono. Il log viene ruotato insieme agli altri log Wasalight.

## Wasalight Control e comandi

La scheda **Services** di Wasalight Control mostra indirizzo,
versione e stato, permette di aprire l'interfaccia locale e di avviare, fermare
o riavviare il servizio.

La voce separata **Companion Web UI** apre `http://127.0.0.1:8000` in Falkon.
Se il servizio è fermo, propone di avviarlo per la sessione. La finestra viene
massimizzata lasciando visibile Tint2, quindi resta possibile cambiare
applicazione o chiuderla con il grande pulsante del tema Wasalight.

Il profilo dedicato viene inizializzato con un'interfaccia scura e semplificata
per il touch: barra di navigazione alta, pulsanti grandi per indietro/avanti,
ricarica e home, campo indirizzo sempre visibile, barra dei preferiti e barra di
stato nascoste. La barra delle schede scompare quando ne è aperta una sola. Home
e nuova scheda puntano all'interfaccia Companion locale; all'avvio non viene
ripristinata la sessione precedente. Lo zoom predefinito è 120%, il livello
nativo Falkon più vicino al 125% inizialmente previsto.

Questi valori e `userChrome.css` vengono applicati una sola volta, al primo
avvio del profilo Wasalight. Gli aggiornamenti successivi conservano le scelte
dell'operatore. Per distribuire intenzionalmente un nuovo schema del profilo è
necessario incrementare `profile_schema` nello script di installazione; non si
deve cancellare il profilo dell'utente. Falkon resta massimizzato, non in vero
fullscreen, così Tint2 rimane sempre accessibile sul touchscreen.

Il profilo, i cookie e le preferenze del browser restano in
`/data/companion/browser`; la cache viene invece collocata nella directory
runtime temporanea e viene persa al riavvio. Falkon viene installato soltanto
quando Companion è richiesto oppure è già presente.

Il profilo dedicato mantiene AdBlock disattivato. Wasalight rimuove soltanto il
plugin interno `internal:adblock` dall'elenco Falkon e conserva eventuali altri
plugin scelti dall'operatore. Non vengono cancellati file del pacchetto Ubuntu e
gli altri profili Falkon non vengono modificati. Questa è l'unica preferenza
riapplicata a ogni apertura del browser; tema, zoom e disposizione dei comandi
restano invece modificabili dall'operatore dopo l'inizializzazione.

Comandi disponibili:

```bash
sudo /usr/local/sbin/wasalight-companion-control start
sudo /usr/local/sbin/wasalight-companion-control stop
sudo /usr/local/sbin/wasalight-companion-control restart
sudo wasalight-companion-backup
sudo wasalight-companion-update
```

Start/stop/restart sono disponibili anche in SHOW. Backup e aggiornamento si
rifiutano invece di funzionare quando `/` è un overlay: entrare prima in
MAINTENANCE. Il backup arresta brevemente il servizio, archivia home e
configurazione, poi ripristina lo stato precedente.

## Collegamento a MagicQ

Dalla web UI Companion installare dal relativo store uno dei moduli della
famiglia **ChamSys MagicQ** (OSC oppure UDP). Companion 4 e successivi
distribuiscono i moduli separatamente dal core; Wasalight non forza quindi un
modulo o una versione non scelti dall'operatore.

Poiché MagicQ e Companion girano sulla stessa console, configurare come host:

```text
127.0.0.1
```

Abilitare in MagicQ il protocollo remoto corrispondente e scegliere porte e
permessi coerenti con il modulo. Verificare poi azioni, feedback e riconnessione
dopo un riavvio prima di tornare in SHOW.

## Aggiornamenti e sicurezza

`wasalight-companion-update` installa soltanto la versione Companion approvata
dalla release Wasalight corrente. Non usa `latest` e conserva un backup prima
dell'aggiornamento. Al termine confronta inoltre il target con il file `BUILD`
del runtime. Il metadata SemVer aggiunto da Bitfocus, per esempio
`5.0.3+9703-stable-2daa0d7670`, identifica correttamente la versione base
`5.0.3`; una selezione upstream vuota o con una versione base diversa viene
invece trattata come errore e non aggiorna la versione registrata. Un cambio
della versione target deve quindi passare da una nuova build Wasalight e dai
relativi test.

La web UI sulla porta `8000` deve essere esposta soltanto su una LAN show
fidata. Le azioni amministrative del Hub passano attraverso wrapper con
argomenti limitati; non viene concesso un `sudo systemctl` generico.

Bitfocus raccomanda Chrome e indica che altri browser aggiornati dovrebbero
funzionare. Falkon è quindi sottoposto alla checklist hardware Wasalight: prima
dell'impiego verificare editor pulsanti, moduli, drag-and-drop, WebSocket e
riconnessione. Se una futura versione Companion non fosse compatibile, il
launcher dedicato potrà passare a un altro motore senza spostare i dati Companion.

Companion e CompanionPi sono progetti Bitfocus separati, scaricati dai repository
ufficiali e soggetti alle rispettive licenze. Non fanno parte del codice Apache
2.0 di Wasalight.
