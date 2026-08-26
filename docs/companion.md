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
/data/companion/browser/    profilo persistente del browser locale GNOME Web
```

Sono montati rispettivamente su `/home/companion` e `/etc/companion`. I file
restano scrivibili anche in SHOW, così pulsanti, connessioni e moduli non si
perdono. Il log viene ruotato insieme agli altri log Wasalight.

## Wasalight Control e comandi

La scheda **Servizi** di Wasalight Control mostra indirizzo,
versione e stato, permette di aprire l'interfaccia locale e di avviare, fermare
o riavviare il servizio.

Nella scheda **Plugin**, Companion può essere installato, disabilitato o
riabilitato persistentemente. La scheda mostra la versione installata e, quando
Companion è abilitato, espone **Crea backup** e **Aggiorna**. Sono utilizzabili
in MAINTENANCE; l'aggiornamento crea prima un backup e
installa esclusivamente la versione Companion approvata dalla release
Wasalight corrente. L’autorizzazione viene chiesta dalla finestra grafica
Polkit, mentre il terminale mostra avanzamento ed errori. In SHOW il pulsante
resta visibile ma disabilitato.

Quando Companion è installato, il dock aggiunge automaticamente un pulsante con
l’icona ufficiale; la stessa apertura resta disponibile dalla voce **Companion**
in Applicazioni. Entrambe aprono `http://127.0.0.1:8000` in GNOME Web. Se il
servizio è fermo, propongono di avviarlo per la sessione. La finestra viene
massimizzata lasciando visibile Tint2 e il titolo X11 viene mantenuto come
`Companion`. Il launcher riapplica `_NET_WM_ICON` dopo l'apertura, così il
taskbar usa l'icona ufficiale invece di quella generica del browser.

GNOME Web usa WebKitGTK aggiornato dai repository di sicurezza Ubuntu. Questo
elimina il vecchio Qt WebEngine di Falkon, basato su una generazione di Chromium
che non interpreta correttamente parte del layout moderno di Companion 5. La
barra nativa mantiene navigazione, menu e controlli zoom utilizzabili al tocco;
non vengono iniettate correzioni CSS nella pagina Companion.

Il profilo, i cookie e le preferenze del browser Companion restano in
`/data/companion/browser`; la cache viene invece collocata nella directory
runtime temporanea e viene persa al riavvio. Il browser generico usa lo stesso
motore e un profilo indipendente sotto `/data/browser`, quindi cronologia,
cookie, schede e preferenze non vengono mescolati con l'interfaccia locale
Companion. Entrambi funzionano offline dopo l'installazione perché GNOME Web e
WebKitGTK sono normali pacchetti Ubuntu `.deb`: Wasalight non richiede Snap.

Comandi disponibili:

```bash
sudo /usr/local/sbin/wasalight-companion-control start
sudo /usr/local/sbin/wasalight-companion-control stop
sudo /usr/local/sbin/wasalight-companion-control restart
sudo wasalight-companion-backup
sudo wasalight-companion-update
```

Avvio, arresto e riavvio sono disponibili anche in SHOW. Backup e aggiornamento si
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
`5.0.4+9704-stable-a69c14dec2`, identifica correttamente la versione base
`5.0.4`; una selezione upstream vuota o con una versione base diversa viene
invece trattata come errore e non aggiorna la versione registrata. Un cambio
della versione target deve quindi passare da una nuova build Wasalight e dai
relativi test.

La policy Polkit accetta l’autenticazione amministrativa soltanto dalla sessione
grafica attiva ed è vincolata al percorso esatto degli updater. Non autorizza
una shell, `systemctl` generico o altri comandi eseguiti come root.

La web UI sulla porta `8000` deve essere esposta soltanto su una LAN show
fidata. Le azioni amministrative di Wasalight Control passano attraverso wrapper con
argomenti limitati; non viene concesso un `sudo systemctl` generico.

Bitfocus raccomanda Chrome e indica che altri browser aggiornati dovrebbero
funzionare. GNOME Web è quindi sottoposto alla checklist hardware Wasalight: prima
dell'impiego verificare editor pulsanti, moduli, drag-and-drop, WebSocket e
riconnessione. Se una futura versione Companion non fosse compatibile, il
launcher dedicato potrà passare a un altro motore senza spostare i dati Companion.

Companion e CompanionPi sono progetti Bitfocus separati, scaricati dai repository
ufficiali e soggetti alle rispettive licenze. Non fanno parte del codice Apache
2.0 di Wasalight.
