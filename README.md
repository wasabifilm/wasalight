# MagicQ Ubuntu Appliance

Progetto per trasformare un’installazione minimale **Ubuntu Server 24.04 LTS
amd64** in una postazione MagicQ dedicata, con sistema operativo protetto dagli
spegnimenti improvvisi e dati dello show persistenti.

Progetto realizzato da **Michele Moser** e **Wasabi Lightbulbfarm**.

Citazione del progetto: **“Wasalight — created by Michele Moser / Wasabi
Lightbulbfarm.”** Instagram: **[@wasabi_lightbulbfarm](https://www.instagram.com/wasabi_lightbulbfarm/)**.

Contatti ufficiali: [www.wasabi.eu](https://www.wasabi.eu/) ·
[info@wasabi.eu](mailto:info@wasabi.eu) · Viale Verona 190/11, 38123 Trento,
Italy. Tutti i riferimenti sono raccolti in [`CONTACT.md`](CONTACT.md).

## Contenuto

```text
magicq-ubuntu-appliance/
├── install.sh                         avvio principale
├── LICENSE                            Apache License 2.0
├── NOTICE                             attribuzione da conservare
├── CONTACT.md                         contatti e canali ufficiali
├── TRADEMARKS.md                      uso di nome, logo e distribuzioni ufficiali
├── CITATION.cff                       citazione standard del progetto
├── VERSION                            versione CalVer dell’installer
├── release-manifest.ini               piattaforma, repository e versioni esterne
├── bin/
│   └── chamsys_install_ubuntu.sh      orchestratore dell’installer
├── installer/
│   ├── modules/                       fasi funzionali separate
│   └── templates/rootfs/              file installati, testabili direttamente
├── lib/                               lettura manifest e lock globale
├── Minimal-ISO-Builder/               builder ISO Ubuntu 24.04.4
│   ├── README.txt
│   ├── make-wasalight-minimal.sh
│   └── autoinstall.yaml
├── packages/
│   ├── README.md
│   └── magicq_ubuntu_v1_9_8_3.deb    da aggiungere
├── docs/
│   ├── hardware-test-checklist.md
│   ├── roadmap.md                       funzionalità, fasi e attività residue
│   ├── companion.md
│   ├── maintenance-tools.md
│   ├── system-audit.md
│   ├── plugins.md
│   ├── boot-branding.md
│   ├── licensing.md
│   ├── versioning.md
│   ├── ssh.md
│   ├── system-cleanup.md
│   ├── touchscreen.md
│   ├── update.md
│   └── vnc.md
└── tests/
    ├── behavior/                       prove eseguibili isolate
    ├── static/                         controlli divisi per dominio
    ├── quality.sh                      lint e validazione degli asset
    └── verify-project.sh               orchestratore della suite
```

## Licenza e attribuzione

Codice e documentazione sono open source con licenza **Apache License 2.0**.
Il copyright resta di Michele Moser, che può usare e vendere il proprio lavoro
anche come appliance, installazione, assistenza o servizio commerciale. La
licenza consente anche a terzi uso, modifica e distribuzione commerciale: chi
ridistribuisce Wasalight o una sua derivazione deve rispettarne le condizioni,
conservare la licenza e includere l’attribuzione contenuta in `NOTICE` quando
pertinente.

La licenza software non concede il diritto di presentare fork, appliance o
servizi di terzi come prodotti ufficiali o certificati Wasalight. I nomi
Wasalight e Wasabi Lightbulbfarm e i relativi segni distintivi sono disciplinati
dalla [policy sul marchio](TRADEMARKS.md).

I file `assets/branding/wasabi-logo.png` e `boot-logo.png` sono esclusi dalla
licenza Apache e restano proprietà di Michele Moser / Wasabi Lightbulbfarm. È
permesso mantenerli invariati in una copia ufficiale integra e non modificata;
per derivazioni, rebranding o altri usi devono essere rimossi, sostituiti oppure
autorizzati per iscritto. I dettagli sono in
[`assets/branding/LICENSE`](assets/branding/LICENSE).

Quando il progetto viene mostrato sui social, il tag Instagram
**@wasabi_lightbulbfarm** è molto gradito, ma non è obbligatorio: imporlo come
condizione d’uso renderebbe la licenza meno compatibile con il normale modello
open source. La forma di citazione consigliata e i metadati per GitHub sono
descritti nella [guida alla licenza](docs/licensing.md) e in `CITATION.cff`.

## Versione Wasalight

La release dell’installer usa il formato `AAAA.MM.GG.BUILD`, per esempio
`2026.08.08.1`. La sorgente unica è il file `VERSION`; per leggerla senza
installare nulla:

```bash
./install.sh --version
```

Dopo un’installazione riuscita la stessa versione appare sul pannello desktop e
in `wasalight-status`. `UPDATE READY` indica che il codice già scaricato in `/data`
è più recente della configurazione installata. Dettagli e procedura di incremento
sono nella [guida al versionamento](docs/versioning.md).

Gli aggiornamenti usano due canali espliciti: `stable`, predefinito e vincolato
a una GitHub Release immutabile con tag SSH firmato, e `debug`, destinato ai test
da `main`. Il piano `--plan` è realmente non mutante e una transazione interrotta
può essere ripresa con `--resume`; dettagli operativi e recovery sono nella
[guida aggiornamenti](docs/update.md).

Versioni della piattaforma, repository, commit e checksum esterni sono
centralizzati in `release-manifest.ini`. L’architettura modulare e le regole per
aggiungere una fase o un template sono descritte in
[architettura installer](docs/installer-architecture.md).

La riga `MAGICQ` riunisce stato, versione del pacchetto realmente installato
secondo `dpkg` e modalità di avvio, per esempio
`READY · 1.9.8.3 · AUTO`. La versione non viene ricavata dal nome del file
`.deb` e `READY` indica che MagicQ è disponibile per l’avvio, non un errore.

## Prima dell’installazione

1. Installare Ubuntu Server 24.04 LTS minimale su una macchina amd64.
2. Preparare una partizione ext4 separata per i dati persistenti.
3. Copiare il pacchetto ChamSys in `packages/`, oppure lasciarlo nella root o
   nella cartella `packages/` di una chiavetta USB, preferibilmente FAT32.
4. Identificare la partizione dati con `lsblk -f` o `blkid`.

Se MagicQ non è già installato e lo script non trova un `.deb` valido, durante
un’installazione interattiva propone tre scelte: inserire la USB e ripetere la
ricerca, continuare senza MagicQ oppure interrompere. Continuando senza
l’applicazione, sul desktop compare **Installa MagicQ**. Nelle esecuzioni non
interattive lo script si ferma e indica `--allow-missing-magicq`. Tutte le
opzioni sono consultabili anche con:

```bash
sudo ./install.sh -help
```

Durante la prima installazione le regole di automount Wasalight non sono ancora
presenti. L’installer identifica quindi direttamente le partizioni appartenenti
a dispositivi USB, le monta temporaneamente in sola lettura sotto `/run`, copia
e verifica MagicQ in `/data/system/packages`, quindi le smonta prima di
proseguire. Dischi interni, root, boot e `/data` non vengono montati dalla
procedura bootstrap.

L’installer non formatta mai dischi. La partizione dati deve esistere già e può
essere indicata come `UUID=...`, `LABEL=...` oppure `/dev/...`.

Alcuni componenti grafici leggeri provengono dal repository ufficiale Ubuntu
`universe`. Se non è già attivo, l'installer lo abilita automaticamente.

### Creare la partizione dati riducendo Ubuntu

La partizione di sistema non può essere ridotta mentre Ubuntu la sta usando.
Eseguire prima un backup, avviare la macchina da una **live USB Ubuntu** e
lanciare GParted (sostituire il dispositivo con quello mostrato da `lsblk`):

```bash
sudo gparted /dev/nvme0n1
```

In GParted:

1. ridurre la partizione ext4 di Ubuntu lasciando lo spazio desiderato non
   allocato;
2. creare nello spazio libero una nuova partizione ext4 con etichetta `DATA`;
3. applicare le operazioni e riavviare Ubuntu normalmente.

Verificare quindi il risultato con:

```bash
lsblk -f
```

La nuova partizione può essere passata all’installer con
`--data-device LABEL=DATA`. Se il disco usa LVM, cifratura o RAID, non seguire
questa procedura: preparare la partizione durante una nuova installazione con
partizionamento manuale oppure usare una procedura specifica per quel layout.

## Builder ISO minimale

[`Minimal-ISO-Builder`](Minimal-ISO-Builder/README.txt) crea due installer
Wasalight basati sulle immagini ufficiali Ubuntu Server 24.04.4 amd64:

- **OFFLINE**, basato sulla Live Server completa;
- **NETBOOT**, circa 100 MB, che scarica e verifica la Live Server durante
  l’installazione e richiede Ethernet, Internet stabile e almeno 8 GiB di RAM.

Per creare entrambe le varianti, dopo aver installato `xorriso`:

```bash
bash Minimal-ISO-Builder/make-wasalight-minimal.sh
```

Il builder verifica i checksum Canonical, non incorpora MagicQ e configura
Ubuntu affinché Wasalight venga scaricato e installato al primo avvio. Immagini
ISO sorgenti e generate, pacchetti `.deb`, cache e directory di lavoro sono
esclusi dal repository Git.

## Verifica del progetto

```bash
./tests/verify-project.sh
```

Questa release è la prima base supportata di Wasalight. Non contiene procedure
di aggiornamento o migrazione da prototipi precedenti: l'installazione parte da
Ubuntu Server 24.04 LTS minimale e da una partizione `/data` preparata secondo
questa guida.

## Installazione

Esempio con SSH abilitato:

```bash
sudo ./install.sh \
  --data-device UUID=UUID_DELLA_PARTIZIONE_DATA \
  --with-ssh
```

La tastiera virtuale touch Onboard è sempre installata. Rimane completamente
chiusa finché non viene richiamata dal dock o da **Wasalight Control →
Applicazioni**, quindi non occupa memoria durante il normale utilizzo di MagicQ.
Lo stesso pulsante la apre e la chiude.

Per installare anche Bitfocus Companion headless con configurazione persistente:

```bash
sudo ./install.sh \
  --data-device LABEL=DATA \
  --with-companion
```

La stessa funzione è disponibile tramite il nuovo sistema plugin; `--plugin`
può essere ripetuto per le estensioni desiderate:

```bash
sudo ./install.sh --data-device LABEL=DATA --plugin companion --plugin vnc
```

Su una console Wasalight già configurata è possibile abilitarlo direttamente
durante l'aggiornamento:

```bash
sudo wasalight-update --with-companion
```

### Aggiornamenti successivi

Dopo la prima installazione, aggiornare codice e configurazione con:

```bash
sudo wasalight-update
```

Il comando funziona soltanto in MAINTENANCE, scarica il ramo `main` verificato
in `/data/system/wasalight`, conserva i pacchetti MagicQ proprietari in
`/data/system/packages` e rilancia l’installer lasciando la protezione
disattivata per il collaudo. Quando tutto è corretto usare
`sudo wasalight-protect` oppure eseguire `sudo wasalight-update --protect`.
Per installare o aggiornare soltanto MagicQ basta inserire il `.deb` nella root
o nella cartella `packages/` di una chiavetta e scegliere **Installa o aggiorna
MagicQ** in Wasalight Control. Il flusso è separato da **Aggiorna Wasalight**,
funziona senza Internet, conserva il file in `/data` senza cancellare
l’originale e sceglie la versione più recente dai metadati Debian.
Prima dell’installazione crea uno snapshot della configurazione; in caso di
errore tenta il rollback automatico. L’ultimo snapshot può essere ripristinato
manualmente con `sudo wasalight-update --rollback`.
L’installer prova a inizializzare automaticamente questa copia persistente;
un problema temporaneo di rete produce un avviso e può essere recuperato con
`sudo wasalight-update --code-only`.
L’aggiornamento non usa `git reset --hard`: se trova modifiche locali ai file
tracciati o non tracciati si ferma senza cancellarle. Scarica prima un checkout
candidato, applica timeout e retry, verifica versione e commit e sostituisce la
copia attiva solo dopo i test. Se il sistema è già identico evita snapshot, APT,
installer e riavvio. `--plan` mostra le operazioni previste e `--repair` forza
una reinstallazione intenzionale. La procedura completa è descritta nella
[guida aggiornamenti](docs/update.md).

La voce grafica **Aggiorna Wasalight** mostra chiaramente le quattro fasi e, solo
dopo un aggiornamento riuscito, propone **Riavvia ora** oppure **Più tardi**. È
interamente utilizzabile al touch. Da terminale si può ottenere lo stesso
risultato senza domanda finale con `sudo wasalight-update --reboot`, combinabile
con `--protect` quando il prossimo avvio deve tornare direttamente in SHOW mode.

### Logo e avvio silenzioso

Il progetto include il logo Wasabi Lightbulbfarm per GRUB, Plymouth e desktop.
Il marchio appare centrato e discreto su fondo quasi nero; il framebuffer entra
nell’initramfs su tutti i sistemi e, sul target Intel, viene precaricato anche
il driver `i915`. Su qualunque sistema UEFI compatibile, SimpleDRM mantiene
inoltre il framebuffer del firmware senza dipendere dalla scheda video e senza
fissare la risoluzione del monitor. Alla prima installazione il
file viene copiato in `/data/system/branding/boot-logo.png`: sostituendo questa
immagine è possibile personalizzare insieme i boot successivi e lo sfondo
Openbox, senza perdere la modifica con gli aggiornamenti. Logo, dimensione,
posizione e colore di fondo sono gli stessi. Specifiche e procedura sono nella
[guida al branding di avvio](docs/boot-branding.md).

### Pulizia dei pacchetti

L’installer rimuove i componenti sicuramente inutili prima di installare lo
stack Wasalight. Le rimozioni dipendenti dall’hardware restano successive ai
controlli su disco, multipath e iSCSI; un unico `autoremove --purge` conclusivo
evita di cancellare e riscaricare dipendenze. La sequenza completa è descritta
nella [guida alla pulizia del sistema](docs/system-cleanup.md).

### Account amministratore `chamsys`

`chamsys` è sempre aggiunto a `sudo` e, quando presenti, ai gruppi `adm` e
`systemd-journal`. Al primo avvio dell'installer viene richiesta
interattivamente la sua password. Per sostituirla successivamente usare:

```bash
sudo ./install.sh --reset-chamsys-password
```

È possibile inserire la stessa password dell'utente amministratore Ubuntu, ma
la password non viene letta da quell'account, copiata, salvata nei file del
progetto o mostrata nei log.

`chamsys` continua a eseguire l'autologin grafico: chiunque abbia accesso fisico
alla postazione può quindi usare la sessione, anche se per elevare i privilegi
deve conoscere la password.

Su questo hardware MagicQ viene eseguito con privilegi `root` tramite un launcher
dedicato e senza richiesta di password. Per riprodurre esattamente l'avvio
manuale verificato, MagicQ mantiene `HOME=/root`; configurazione e dati locali
di root sono però bind persistenti sotto `/data/magicq/root-home`.

Il file XDG `user-dirs.dirs` indica `/home/chamsys/Documents` come cartella
Documenti. Uno show come `nomeshow` viene quindi proposto in
`/home/chamsys/Documents/MagicQ/nomeshow`, collegato a
`/data/magicq/Documents/MagicQ/nomeshow`. Anche
`/root/Documents/MagicQ` è un bind di sicurezza verso la stessa directory: se
MagicQ ignora XDG, il file resta comunque su `/data` e non nell'overlay root.

Il comando concesso senza password è soltanto il launcher fisso, non un comando
arbitrario. Alla chiusura di MagicQ il launcher ripristina inoltre proprietà e
permessi dei dati persistenti affinché restino accessibili da `chamsys`.
L’installer esegue la stessa riparazione subito dopo l’installazione del file
`.deb`: alcuni pacchetti MagicQ ricreano infatti `Documents/MagicQ` come
`root:root`. Il controllo finale interrompe l’installazione se le directory
persistenti non risultano realmente scrivibili da `chamsys`.

OpenSSH viene installato per il pulsante di assistenza. Avvio corrente e avvio
automatico sono controlli distinti; il secondo usa un flag persistente in
`/data/system/service-flags` e può essere inizializzato con `--with-ssh`.

Su una postazione fisica dedicata l'installer elimina automaticamente
`cloud-init`, `multipath-tools`, `open-iscsi` e `pollinate` quando non servono
al disco di sistema o a `/data`. La verifica distingue LVM da un vero volume
multipath e conserva automaticamente i componenti SAN/iSCSI se sono in uso.
Usare `--keep-cloud-init` soltanto quando la macchina dipende ancora dalla
configurazione cloud.

Wasalight non installa QEMU. Il messaggio di `needrestart` secondo cui nessun
guest usa vecchi binari QEMU è un controllo riuscito, non un errore e non
indica la presenza dell'hypervisor. Dettagli e verifiche sono nella
[guida alla pulizia del sistema](docs/system-cleanup.md).

Per preparare temporaneamente la macchina senza attivare la protezione:

```bash
sudo ./install.sh --no-protection
```

## Modalità operative

La configurazione normale è **SHOW / PROTECTED**:

- la root Ubuntu usa un overlay volatile in RAM;
- `/tmp`, `/var/tmp` e journald sono volatili;
- `/data` rimane ext4 in lettura/scrittura;
- show, impostazioni MagicQ e configurazioni di rete restano persistenti;
- console ed eventi MagicQ restano disponibili in `/data/log` con rotazione;
- ogni chiavetta viene montata nella propria sottodirectory di `/stick`, il
  percorso usato dalla vista Flash di MagicQ;

Comandi disponibili:

I comandi pubblici seguono una regola unica: `magicq-*` controlla esclusivamente
l'applicazione MagicQ, mentre `wasalight-*` gestisce appliance, modalità,
diagnostica e strumenti di supporto.

```bash
wasalight-status
magicq-start
magicq-stop
wasalight-touch-status
wasalight-touch-config list
wasalight-audio-test
wasalight-system-audit
wasalight-vnc-start
wasalight-vnc-stop
wasalight-control
wasalight-plugin list
wasalight-ip-scanner
wasalight-artnet-monitor
wasalight-vnc-toggle
sudo wasalight-app-register --list
sudo wasalight-maintenance
sudo wasalight-protect
```

`wasalight-system-audit` analizza avvio, servizi, porte, CPU, memoria, storage,
rete e processi senza richiedere privilegi e senza modificare il sistema. È
disponibile anche da **Wasalight Control → Supporto → Audit sistema**; dettagli
e interpretazione dell'output sono nella [guida all'audit](docs/system-audit.md).

`wasalight-maintenance` e `wasalight-protect` preparano la modalità del boot
successivo. Dopo il comando occorre riavviare quando si è pronti.

In modalità **SHOW / PROTECTED**, MagicQ parte automaticamente una sola volta
all'avvio della sessione grafica. Se viene chiuso, resta chiuso: Wasalight non
lo riavvia automaticamente. Il toggle **Avvio automatico** nella scheda MagicQ
salva la scelta in `/data/system/service-flags/magicq-autostart`: disattivandolo,
MagicQ resta chiuso anche ai successivi avvii SHOW finché non viene aperto
manualmente.

In modalità **MAINTENANCE**, Openbox parte normalmente ma MagicQ resta chiuso.
Questo evita che l'applicazione interferisca con aggiornamenti, copie e diagnosi.
Per aprirlo intenzionalmente durante la manutenzione usare **Avvia MagicQ** nel
menu oppure:

```bash
magicq-start
```

Per mantenerlo chiuso intenzionalmente usare:

```bash
magicq-stop
```

Il comando termina la sessione di lancio e poi il processo MagicQ eseguito come
root. MagicQ resta chiuso fino al comando seguente. In SHOW partirà nuovamente
al prossimo login o riavvio; in MAINTENANCE resterà invece fermo:

```bash
magicq-start
```

Le stesse azioni sono disponibili nel menu Openbox come **Avvia MagicQ** e
**Ferma MagicQ**. `wasalight-status` mostra soltanto lo stato operativo
`MAGICQ`; il processo tecnico `magicq-session`, il lock, il PID e il relativo
log rimangono disponibili internamente per impedire duplicati e diagnosticare
gli errori di avvio.

### Fullscreen automatico

MagicQ 1.9.x apre la finestra principale massimizzata, ma non richiede a
Openbox il vero stato fullscreen. Senza un intervento aggiuntivo resta visibile
anche la barra del titolo.

Wasalight avvia `magicq-fullscreen-watch` insieme a Openbox. Il controllo
attende la finestra principale `MagicQ PC` e le applica lo stato EWMH
fullscreen tramite `wmctrl`. Funziona sia con l'avvio automatico in SHOW sia
con **Avvia MagicQ** in MAINTENANCE e viene riapplicato quando MagicQ crea una
nuova finestra dopo un riavvio. Non forza continuamente lo stato: dopo la prima
applicazione, un operatore può disattivarlo temporaneamente durante una
diagnosi senza che venga riattivato sulla stessa finestra.
Tint2 rimane intenzionalmente sopra il bordo inferiore anche quando la finestra
MagicQ è fullscreen, perché deve essere sempre raggiungibile dal touchscreen.

### Desktop di manutenzione

Openbox viene limitato a **un solo desktop virtuale**: all'avvio `wmctrl -n 1`
elimina gli altri spazi di lavoro della sessione. PCManFM disegna uno sfondo
nero con icone SVG da 64 pixel, ad alto contrasto e indipendenti dal tema di
Ubuntu. L’installer aggiunge `librsvg2-common`, il loader GDK-Pixbuf che manca
nell’immagine Server minimale e che serve a PCManFM per visualizzare realmente
gli SVG. I launcher restano file protetti appartenenti a `root`; LibFM usa
`single_click=1` e `quick_exec=1`, quindi sul touchscreen basta un tocco e non
appare la richiesta «Apri con…». Non viene usato il metadato GIO
`metadata::trusted`, assente nel profilo PCManFM/GVFS dell’installazione
Server. `chamsys` può avviare i launcher ma non cancellarli, rinominarli,
spostarli o modificarli accidentalmente.
Sul desktop rimangono **MagicQ**, **Spegni** e **Riavvia**. L'icona MagicQ usa
l'immagine originale ChamSys e consente l'avvio rapido con un solo tocco.
**Wasalight Control** e **File** restano nel dock inferiore sempre visibile e
non sono duplicati sul desktop. Quando Bitfocus Companion è installato, nello
stesso dock compare automaticamente il pulsante per aprirne l’interfaccia web.

SSH e VNC sono gestiti esclusivamente nella scheda **Servizi** di Wasalight
Control. Entrambi presentano gli stessi toggle: **Servizio attivo** modifica la
sessione corrente e **Avvio automatico** conserva in `/data` la scelta per i
riavvii. Le due impostazioni restano indipendenti.

Spegnimento e riavvio mostrano sempre una grande finestra di conferma. Soltanto
dopo la conferma viene eseguito un comando amministrativo ristretto, senza
chiedere la password e senza concedere al desktop un accesso `sudo` generico.
Tutti i dialoghi Wasalight vengono centrati da Openbox, ricevono il focus e
restano sopra le altre finestre fino alla conferma o all'annullamento. Le
conferme mostrano l'icona dell'azione effettiva (spegnimento, riavvio, blocco,
SSH, VNC, rollback o eliminazione) al posto del simbolo interrogativo generico.

Sul lato destro Conky mostra un pannello aggiornato ogni due secondi con:

- modalità corrente e modalità prevista al prossimo avvio;
- stato operativo di MagicQ;
- montaggio e spazio libero di `/data`;
- persistenza dei log;
- rete e indirizzo IP, evidenziando dispositivi `unmanaged`;
- touchscreen, chiavette USB, VNC, SSH, Bitfocus Companion e audio ALSA.

Verde significa operativo, giallo indica uno stato fermo o non collegato ma non
necessariamente errato, rosso richiede attenzione. Il pannello esegue solo
letture, non produce log e non scrive periodicamente su `/data`. Il fondo scuro
è semitrasparente grazie a una configurazione Picom minimale, senza ombre o
animazioni; le applicazioni fullscreen vengono escluse automaticamente dal
compositing per non aggiungere latenza a MagicQ.

Il clic destro sullo sfondo continua ad aprire il menu Openbox. I pulsanti sono
visibili quando MagicQ è chiuso, in particolare durante la modalità
MAINTENANCE. In SHOW la finestra fullscreen di MagicQ copre intenzionalmente il
desktop e il pannello di stato; per intervenire sulla configurazione si deve
prima passare a MAINTENANCE oppure fermare MagicQ con `magicq-stop`.

### Wasalight Control, plugin e applicazioni future

**Wasalight Control** è il centro di gestione GTK progettato per il touchscreen.
Riunisce dashboard, MagicQ, servizi, applicazioni, supporto, plugin e crediti in una
finestra massimizzata, lasciando sempre visibile Tint2. Rimane attiva una sola
istanza per sessione: un nuovo tocco sull'icona porta in primo piano la finestra
già aperta. Stato e plugin vengono letti in background, così il cambio scheda e
i comandi touch restano reattivi anche quando `systemctl` o la rete sono lenti.
Il colore identificativo di Control è il verde Wasabi `#76bd22`, applicato a
icona, titolo, focus e pressione dei pulsanti. La scheda selezionata usa un verde
scuro `#223016`, testo `#9bd95a` e una sottolineatura Wasabi: mantiene così il
branding senza creare una fascia troppo accesa. Schede, pagine e aree scorrevoli
rimangono nella stessa famiglia quasi nera del desktop.

I programmi continuano a essere organizzati tramite il registro `apps.d`:

- **MagicQ**: MagicQ, MagicHD e MagicVis usano tre schede touch grandi e uguali;
  stato `APERTO/CHIUSO · AUTO/MANUALE` e toggle dell'avvio automatico restano
  nella riga superiore; non esiste un pulsante Ferma, perché l'applicazione si
  chiude normalmente dalla propria X;
- **Servizi**: usa la stessa intestazione e la stessa griglia a tre colonne di
  MagicQ; icona, nome, stato, descrizione, toggle e azioni mantengono posizioni
  coerenti in ogni scheda;
- **Applicazioni**: programmi registrati dall'amministratore, compresi File,
  Scanner IP, Art-Net Monitor, OSC Monitor, la calcolatrice `galculator` e
  l’editor di testo leggero Mousepad;
- **Supporto**: rete, monitor, touchscreen, audio, terminale, stato,
  diagnostica, salute, backup/ripristino, blocco schermo manuale e aggiornamento
  Wasalight;
- **Crediti**: autore, versione, licenza, attribuzioni e collegamenti ufficiali
  del progetto; ChamSys e Bitfocus sono indicati come prodotti esterni.

Nella home **Stato**, il pulsante File è sostituito dal cambio modalità:
**Passa a MAINTENANCE** quando la console è in SHOW oppure **Passa a SHOW** in
MAINTENANCE. Dopo la conferma viene preparato il prossimo avvio e viene proposto
il riavvio immediato. Il File Manager resta nel dock e in Applicazioni.

Il rilevamento automatico è intenzionalmente limitato ai companion riconoscibili
come MagicVis, MagicHD e strumenti Remote/Viewer ChamSys. Il programma MagicQ
principale continua a essere avviato soltanto dal launcher Wasalight controllato;
Control usa `/usr/share/pixmaps/magicq.png`, fornita dal pacchetto ufficiale,
invece di un'icona generica.
Control rispetta anche la chiave standard `Path`. Per MagicHD e MagicVis riconosce
i launcher originali ChamSys e li inoltra a un wrapper root ristretto ai soli due
comandi. In questo modo usano `/opt/magicq`, l’ambiente X11 e lo stesso runtime
Qt/OpenGL con cui MagicQ funziona sul target, senza concedere a Control un sudo
generico. Gli errori rimangono nel log persistente di Control.

Per registrare un programma installato in futuro usare il relativo launcher
standard presente normalmente sotto `/usr/share/applications`:

```bash
sudo wasalight-app-register /usr/share/applications/NOME.desktop
sudo wasalight-app-register --list
sudo wasalight-app-register --remove NOME.desktop
```

Con `/data` montata, le registrazioni sono conservate in
`/data/system/apps.d`; in assenza di `/data` vengono mantenute sotto
`/etc/wasalight/apps.d`. Control rispetta `TryExec` e non mostra un'applicazione
quando il suo eseguibile non è disponibile.

Se un launcher di terze parti contiene un valore booleano non standard, Control
lo ignora invece di terminare. Gli eventuali errori di avvio vengono mostrati
a schermo e registrati in `/data/log/wasalight-control.log` (oppure in `/tmp` se
`/data` non è disponibile).

Control è predisposto per più lingue tramite GNU gettext. La preferenza
persistente e la procedura per mantenere i cataloghi italiano e inglese sono
descritte in [`docs/control-localization.md`](docs/control-localization.md).

Il registro plugin integrato gestisce inizialmente SSH, VNC e Bitfocus Companion.
Manifest e programmi sono protetti sotto `/usr/lib/wasalight/plugins`, mentre
enable/disable persiste in `/data/system/plugins-state`. Le modifiche persistenti
sono ammesse soltanto in MAINTENANCE; dettagli e formato dei manifest sono in
[`docs/plugins.md`](docs/plugins.md).

I plugin esterni sono accettati soltanto da bundle USB firmati verificati con
un keyring root-owned. I metadati dichiarano licenza, homepage, dipendenze,
percorsi di backup e canale update. La procedura operativa per diagnostica e
backup completo di `/data` è in
[`docs/maintenance-tools.md`](docs/maintenance-tools.md).
La stessa guida documenta il blocco manuale con password `chamsys`: non viene
mai attivato per inattività e non abilita sospensione, spegnimento del display o
DPMS.

Tint2 non mostra più la scritta **desktop 1** e resta sempre visibile in basso.
Il pannello riserva lo spazio necessario e offre i pulsanti Control e File,
le applicazioni aperte, le icone di stato e l’orologio. Questa scelta evita il
gesto sul bordo, poco affidabile con molti touchscreen, e mantiene sempre
raggiungibili i controlli. Il tema è quasi nero (`#080b10`), con selezioni
antracite discrete e senza il precedente fondo blu acceso.

Il clic destro apre soltanto un menu Wasalight minimale: Avvia/Ferma MagicQ,
Control, File, Terminale, Aggiorna Wasalight, riavvio e spegnimento. Le
preferenze Openbox e le impostazioni di sistema generiche non sono esposte.

Le finestre Openbox usano il tema scuro **Wasalight** sia quando sono attive sia
quando sono in secondo piano. La barra del titolo ha spaziatura maggiorata e un
pulsante **X** interno di Openbox dentro una zona di tocco di circa 44×44 px; al
passaggio o alla pressione diventa rosso. I piccoli pulsanti
minimizza/massimizza sono rimossi dalla barra:
le finestre restano gestibili dalla barra inferiore, più adatta al touchscreen.

Nella scheda **Applicazioni** di Wasalight Control sono disponibili anche:

- **IP Scanner**, che usa `arp-scan` sulle interfacce Ethernet/Wi-Fi connesse e
  mostra interfaccia, IP, MAC e produttore in una tabella aggiornabile;
- **Art-Net Monitor**, che ascolta passivamente il traffico Art-Net su tutte le
  interfacce e raggruppa sorgente, destinazione, tipo di pacchetto, universo,
  numero di canali e contatore dei pacchetti;
- **OSC Monitor**, che decodifica passivamente messaggi e bundle OSC senza
  occupare porte UDP e mostra sorgente, porta di destinazione, percorso,
  argomenti e contatore dei messaggi;
- **Monitor sistema**, un equivalente grafico e leggero di `htop` basato su
  LXTask, con elenco dei processi e indicatori in tempo reale di CPU e memoria.

### Bitfocus Companion

Con l'opzione `--with-companion`, Wasalight installa una build headless nativa
e verificabile di Bitfocus Companion. Il servizio usa l'utente dedicato
`companion`, parte automaticamente dopo la rete e mantiene home, configurazione,
moduli, log e backup sotto `/data/companion`.

Il pannello Conky e `wasalight-status` mostrano lo stato Companion. La scheda
Companion di Wasalight Control offre avvio, arresto e riavvio; in **Plugin**
mostra la versione installata e offre backup e aggiornamento. In **Sistema**
indica l'interfaccia web come `INDIRIZZO:8000`. Backup e aggiornamento sono
consentiti solo in MAINTENANCE; in SHOW la configurazione rimane persistente ma
il runtime protetto non viene modificato.

Il pulsante Companion nel dock e la voce **Companion** in Applicazioni aprono
l'interfaccia locale in Falkon, massimizzata ma con la barra Tint2 ancora
accessibile al touch. Profilo e preferenze sono persistenti in
`/data/companion/browser`, mentre la cache resta temporanea.

Per controllare MagicQ dalla stessa macchina, installare nella web UI Companion
il modulo ChamSys MagicQ OSC o UDP e usare `127.0.0.1` come host. Installazione,
percorsi, sicurezza e comandi sono descritti nella
[guida Companion](docs/companion.md).

Le interfacce Wasalight sono grandi e utilizzabili al tocco. Solo la cattura di
rete passa attraverso helper amministrativi senza argomenti, esplicitamente limitati
in `sudoers`; le interfacce grafiche continuano a funzionare come `chamsys`. Gli
errori confluiscono nel log persistente `/data/log/wasalight-network-tools.log`,
gestito dalla stessa rotazione degli altri log Wasalight.

### VNC della sessione corrente

Il toggle **Servizio attivo** di VNC condivide esclusivamente il display Xorg corrente `:0`:

- se VNC è spento, lo avvia e mostra l'indirizzo di connessione;
- se è attivo, chiede conferma prima di fermarlo;
- al primo utilizzo apre un terminale dedicato per creare la password senza
  inserirla negli argomenti dei processi o nei log;
- lo stato aggiornato rimane visibile nel pannello Conky.

### SSH remoto

OpenSSH è installato ma resta spento finché non viene avviato. In Wasalight
Control, **Servizio attivo** gestisce la sessione corrente e **Avvio automatico** il flag
persistente dei riavvii. L’accesso usa `chamsys` e la sua password Linux.
`--with-ssh` e `--without-ssh` impostano lo stesso flag dall'installer. Il
pannello Conky distingue `MANUAL` da `AUTO`. Dettagli nella [guida SSH](docs/ssh.md).

### Audio ALSA

L'installer verifica che la configurazione ALSA e gli strumenti diagnostici
siano presenti. Per provare realmente l'uscita predefinita eseguire:

```bash
wasalight-audio-test
```

Il comando elenca le schede disponibili e riproduce una volta i campioni
**Front Left** e **Front Right**. Alcune versioni di PortAudio usate da MagicQ
provano anche nomi PCM storici (`front`, `rear`, `surround`) o ingressi non
offerti dalle uscite HDMI. I conseguenti messaggi `Unknown PCM` e le asserzioni
di enumerazione nel log non indicano da soli un guasto. L'audio è considerato
funzionante quando `wasalight-audio-test` termina correttamente e MagicQ completa
l'inizializzazione. Errori come l'assenza di `alsa.conf`, nessuna scheda in
`aplay -l` o l'impossibilità di aprire il dispositivo predefinito restano invece
problemi reali e non vengono nascosti dai log.

### Rete gestita da NetworkManager

Ubuntu Server crea normalmente la prima configurazione Netplan usando
`systemd-networkd`. In questo stato `nm-connection-editor` si apre, ma
NetworkManager mostra l'interfaccia come `unmanaged` e la lista può apparire
vuota. Wasalight installa quindi il file
`/etc/netplan/99-wasalight-networkmanager.yaml`, che seleziona
`NetworkManager` come renderer conservando le definizioni DHCP, statiche, DNS e
route già presenti negli altri file Netplan.

Le nuove connessioni salvate dalla voce **Network** in Wasalight Control sono
conservate nel bind persistente
`/etc/NetworkManager/system-connections` → `/data/system/network`. Lo stato si
controlla con:

```bash
nmcli device status
wasalight-status
```

Le interfacce Ethernet e Wi-Fi devono risultare gestite, anche quando sono
semplicemente `disconnected`; non devono risultare `unmanaged`. Durante una
reinstallazione da SSH o VNC, `netplan apply` può interrompere brevemente la
connessione mentre il controllo passa da `systemd-networkd` a NetworkManager.

## Log persistenti

Il journal generale di Ubuntu resta volatile per limitare le scritture e
proteggere il disco di sistema. La diagnostica utile di MagicQ viene invece
salvata separatamente:

Questi due file appartengono a **Wasalight**, non sono i log interni prodotti da
MagicQ:

```text
/data/log/wasalight-magicq-console.log  output stdout/stderr e diagnostica Linux
/data/log/wasalight-magicq-session.log  avvio e uscita della sessione MagicQ
```

MagicQ continua a creare autonomamente un file `.log` per ogni sessione, con un
nome basato su giorno e ora, nella propria cartella nativa:

```text
/data/magicq/Documents/MagicQ/log/
```

La stessa directory è raggiungibile da
`/home/chamsys/Documents/MagicQ/log/` e, tramite il bind di sicurezza,
`/root/Documents/MagicQ/log/`. MagicQ gestisce direttamente questi file e li
elimina automaticamente dopo circa un mese; la rotazione Wasalight non li
modifica. Il comportamento e la creazione dei pacchetti di supporto sono
descritti nel [manuale ChamSys](https://secure.chamsys.co.uk/docs/magicq/manual/system_management.html#saving-support-files).

Per seguire un errore in tempo reale o leggere gli ultimi eventi:

```bash
tail -f /data/log/wasalight-magicq-console.log
tail -n 100 /data/log/wasalight-magicq-session.log
```

Un timer controlla i file ogni 10 minuti. Ogni log viene ruotato a 5 MiB,
conservando cinque copie e comprimendo quelle meno recenti. In questo modo i
log diagnostici non possono crescere indefinitamente sulla partizione dati.
`wasalight-status` mostra `LOGS: persistent in /data/log` quando il percorso è
disponibile. Se `/data` non è montata, l'output passa temporaneamente nella
directory runtime volatile della sessione.

Gli aggiornamenti Ubuntu e l’installazione di un nuovo pacchetto MagicQ devono
essere eseguiti esclusivamente dopo il riavvio in MAINTENANCE mode.

## Touchscreen

Xorg usa il driver `libinput`. Con un solo touchscreen e un solo monitor,
l'associazione viene applicata automaticamente. In presenza di più dispositivi
la configurazione si ferma in modo sicuro e richiede una scelta esplicita.

Esempio per associare un touchscreen a `HDMI-1`:

```bash
wasalight-touch-config list
wasalight-touch-config set "NOME TOUCHSCREEN" HDMI-1 normal
```

La configurazione viene riapplicata anche dopo una riconnessione a caldo. Per
diagnosi, rotazioni, configurazioni multimonitor e tastiera virtuale consultare
[la guida touchscreen](docs/touchscreen.md).

## Assistenza remota VNC

Wasalight installa `x11vnc` per condividere la sessione Openbox/MagicQ già
visibile sul monitor. L'avvio automatico è disabilitato inizialmente e può
essere attivato, dopo aver creato la password VNC, con **Avvio automatico** in
**Wasalight Control → Servizi → VNC**. Per un avvio soltanto corrente usare il
toggle **Servizio attivo** oppure, dalla sessione `chamsys`, il comando:

```bash
wasalight-vnc-start
```

Al primo utilizzo viene richiesta una password VNC separata dalla password
Linux. Per arrestare immediatamente l'accesso remoto:

```bash
wasalight-vnc-stop
```

La modalità LAN usa la porta TCP 5900 e non offre cifratura completa. Per uso,
tunnel SSH, cambio password e rimozione consultare la [guida VNC](docs/vnc.md).

## Assistenza remota SSH

Usare i toggle **Servizio attivo** e **Avvio automatico** nella scheda
**Servizi** di Wasalight Control.
Quando è attivo, collegarsi con:

```bash
ssh chamsys@INDIRIZZO_IP
```

SSH usa la password Linux di `chamsys`; non crea né salva una nuova password.
Per modalità temporanea, attivazione automatica e sicurezza consultare la
[guida SSH](docs/ssh.md).

## Chiavette USB per MagicQ

MagicQ cerca i supporti rimovibili nel percorso `/stick`. L'installer crea una
sottodirectory distinta per ogni partizione USB supportata, usando il nome del
dispositivo: per esempio `/stick/sdb1` e `/stick/sdc1`. FAT32, exFAT e NTFS
possono quindi restare montati in lettura/scrittura e visibili contemporaneamente
nella vista Flash di MagicQ. Una seconda chiavetta non nasconde né sostituisce
la prima.

In una macchina virtuale UTM, montare la chiavetta nel Finder non la collega
automaticamente a Linux: occorre usare il pulsante **USB** della finestra UTM e
assegnare il dispositivo alla VM. Prima del pass-through, `lsusb` e `lsblk` non
mostrano il supporto e Wasalight non può creare alcuna directory sotto `/stick`.
Se UTM mostra **Disconnect…** ma `lsusb` continua a non vedere la chiavetta, il
redirect USB di UTM è rimasto bloccato prima del kernel guest: spegnere davvero
la VM (non metterla in pausa), scollegare e ricollegare il dispositivo dal menu
USB, quindi riavviare. In questo caso non esiste ancora un problema di mount
Linux da correggere.

APFS è supportato tramite il pacchetto Ubuntu `libfsapfs-utils`, ma
**esclusivamente in lettura**. Serve per aprire o importare file provenienti da
un Mac, compreso un installer MagicQ collocato nella radice di un volume APFS o
in `packages/`; non può essere usato per salvare show. I volumi del container
appaiono come sottodirectory `fsapfs1`, `fsapfs2`, ecc. I container cifrati che
richiedono una password non vengono aperti automaticamente. Per lavorare tra
macOS e Wasalight resta consigliato exFAT.

Sui filesystem scrivibili, le scritture vengono richieste in modalità sincrona
per ridurre il rischio di
perdita dati. Prima di estrarre una chiavetta attendere comunque la conclusione
del salvataggio; nessun filesystem può garantire l'integrità durante una
rimozione fisica nel mezzo di una scrittura.

Lo stato del supporto montato è visibile con:

```bash
wasalight-status
findmnt | grep '/stick/'
```

## Percorsi persistenti

```text
/home/chamsys/Documents/MagicQ  → /data/magicq/Documents/MagicQ
/home/chamsys/.local/share      → /data/magicq/.local/share
/home/chamsys/.magicq_init.sh   → /data/magicq/.magicq_init.sh
/root/.config                   → /data/magicq/root-home/.config
/root/.local/share              → /data/magicq/root-home/.local/share
/root/Documents/MagicQ          → /data/magicq/Documents/MagicQ (fallback)
/etc/NetworkManager/system-connections
                                → /data/system/network
/data/system/touchscreen/config → configurazione touch persistente
/data/system/vnc/passwd         → password VNC persistente e protetta
/data/system/service-flags/*    → flag di avvio automatico SSH e VNC
/data/system/wasalight          → copia Git persistente per gli aggiornamenti
/data/system/packages           → pacchetti MagicQ proprietari persistenti
```

MagicQ gira con UID e gruppo root, come nell'avvio manuale che è stato verificato
sull'hardware. Usare comunque `magicq-session`: il launcher prepara ambiente,
runtime e riparazione finale dei proprietari dei file show.

## Limitazioni note

- Una scrittura USB sincrona riduce la finestra di rischio, ma nessun filesystem
  può garantire l’integrità se la chiavetta viene estratta durante una scrittura.
- Il primo avvio protetto e le periferiche ChamSys devono essere verificati sulla
  macchina definitiva.
- Il pacchetto `.deb` non è redistribuito da questo progetto: usare il file
  originale scaricato da ChamSys.
