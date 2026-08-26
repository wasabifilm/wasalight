WASALIGHT UBUNTU ISO BUILDER
============================

Il builder crea due immagini realmente diverse per Ubuntu Server 24.04.4 LTS
amd64:

- FULL: circa 3,2 GB, basata sulla Live Server completa;
- NETBOOT: circa 100 MB, basata sulla Mini ISO ufficiale Canonical.

FULL contiene localmente il sistema Ubuntu Minimal. Richiede comunque Internet
durante l'autoinstall per Git e aggiornamenti e al primo avvio per scaricare
Wasalight. Le build normali usano il branch del manifest; le build di release
possono fissare un tag esatto. Il nome FULL distingue quindi la base Ubuntu
locale da una installazione completamente offline.

NETBOOT contiene
bootloader, kernel e initrd, poi scarica in RAM la Live Server 24.04.4 ufficiale
da releases.ubuntu.com. Prima di avviarla controlla dimensione e SHA-256
Canonical. Non e' PXE: si avvia da USB o da ISO come l'immagine FULL.

NETBOOT richiede:

- Ethernet con DHCP;
- DNS e accesso HTTPS a releases.ubuntu.com, archive.ubuntu.com e GitHub;
- almeno 8 GiB di RAM durante l'installazione, perche' la Live Server scaricata
  viene conservata in una regione di memoria protetta;
- una connessione stabile per scaricare circa 3,2 GB oltre ai pacchetti Ubuntu.

INSTALLAZIONE WASALIGHT
----------------------

Entrambe le varianti installano durante l'autoinstall soltanto Git, letto da
packages/wasalight-bootstrap.txt e necessario per scaricare il progetto. Dopo Ubuntu, un servizio systemd completa
automaticamente Wasalight al primo avvio reale:

1. usa il checkout persistente /data/system/wasalight;
2. scarica con un clone shallow il riferimento configurato e verifica il
   commit esatto incorporato nella ISO;
3. accetta soltanto un checkout pulito;
4. lascia a install.sh la verifica dopo l'installazione del runtime completo;
5. registra il commit in /data/log/wasalight-first-boot.version;
6. pubblica fase ed esito in /data/log/wasalight-first-boot.status;
7. installa MagicQ quando trova un pacchetto amd64 valido in /data o su una
   USB, senza incorporarlo nella ISO o nel repository;
8. in assenza del pacchetto continua con gli strumenti per installarlo in un
   secondo momento;
9. esegue install.sh, unico motore anche per installazioni manuali e WasaUpdate:
   installa runtime standard, dipendenze MagicQ e componenti opzionali dagli
   elenchi dichiarativi, verifica il progetto, lascia overlayroot disattivato e
   riavvia in MAINTENANCE.

Il log si trova in /data/log/wasalight-first-boot.log. Se rete o installazione
falliscono, il servizio non dichiara il completamento e riprova dopo 60 secondi.
Durante questo bootstrap tty1 resta testuale e mostra l'avanzamento: la fase
attiva è evidenziata, i completamenti sono verdi, gli avvisi gialli e gli errori
rossi. Il file di log e il journal conservano invece testo semplice senza codici
ANSI. Il target
dei login, Openbox e l'autologin grafico attendono il servizio. Il marker
volatile scompare con il riavvio conclusivo, quindi la grafica parte soltanto
dal boot successivo. Se il servizio fallisce, il job termina e il login testuale
torna disponibile per il recupero mentre systemd prepara il tentativo successivo.
Anche dopo aver richiesto il riavvio, il servizio resta attivo fino a quando
systemd lo termina durante lo shutdown: tty1 non puo' quindi avviare Openbox
nel breve intervallo tra la richiesta e l'effettivo riavvio.
Dopo il boot in MAINTENANCE l'operatore puo' installare o verificare MagicQ e
passare volontariamente a SHOW con il comando o il controllo grafico gia'
previsto.

La variante NETBOOT prepara gia' il checkout Git fissato durante l'autoinstall;
al primo avvio ne ricontrolla il commit senza inseguire un main piu' recente.
Installazione e verifica avvengono sempre tramite install.sh al primo avvio.

DISCO E INTERFACCIA
-------------------

Entrambe includono:

- boot BIOS e UEFI conservato dalle immagini Canonical;
- selezione manuale del disco, minimo 32 GiB;
- esclusione del supporto USB di installazione, anche nel doppio avvio NETBOOT;
- interfaccia di installazione interamente in inglese;
- wizard Wasalight unico a schermo intero per tutte le scelte iniziali, con
  indicatore delle fasi e navigazione indietro; Subiquity resta il motore che
  esegue realmente installazione, partizionamento e bootloader;
- dimensionamento ricavato dalla console reale, pannello centrato fino a 116
  colonne, prompt interni alla cornice e colore rosso riservato agli avvisi
  distruttivi;
- schermata di avanzamento Subiquity su tty2 con la stessa larghezza, centratura
  e geometria del wizard iniziale;
- scelta separata della lingua dell'interfaccia Wasalight (italiano o inglese),
  senza modificare la lingua dell'installer o il layout della tastiera;
- conferma distruttiva digitando esattamente ERASE;
- GPT ibrida con BIOS GRUB, EFI, /boot, LVM, root al 50% e /data sul resto;
- scelta del layout tastiera indipendente dalla lingua inglese dell'installer,
  con preset oppure codice XKB personalizzato, applicazione immediata alla
  console live e schermata di prova;
- scelta del fuso orario e della password chamsys (minimo 6 caratteri) durante
  l'installazione;
- riepilogo di modalita', lingua, tastiera, fuso orario, boot e disco prima di
  ERASE;
- backend separati dal wizard che rivalidano configurazione e disco, inclusa
  l'esclusione del supporto d'installazione, immediatamente prima di consegnare
  autoinstall.yaml a Subiquity;
- preflight bloccante prima della formattazione: almeno 2 GiB di RAM e Internet
  funzionante con interfaccia, IP, route, DNS e HTTPS verso il repository
  Wasalight; tra 2 e 4 GiB viene mostrato un avviso;
- SSH inizialmente disabilitato;
- UI Wasalight alimentata dagli eventi Subiquity/curtin su Ctrl+Alt+F2;
- log tecnici su Ctrl+Alt+F1.

Internet e' obbligatoria sia in FULL sia in NETBOOT: FULL contiene Ubuntu ma
scarica comunque Wasalight e i relativi componenti durante il completamento.

I log Subiquity, curtin e Wasalight vengono salvati anche nel sistema installato
in /data/log/installer. Il file autoinstall e gli hash password presenti nei log
vengono oscurati durante la copia. Se l'installazione fallisce prima che il
volume /data sia montato, la copia persistente non e' tecnicamente possibile.

Al termine, l'installer non riavvia immediatamente dal supporto ancora
inserito. Mostra invece una schermata finale in inglese: premendo ENTER il
sistema si spegne in sicurezza. Solo a macchina spenta si rimuove la USB (o si
espelle la ISO virtuale), quindi si riaccende dal disco interno. Al primo avvio
il servizio systemd completa Wasalight e riavvia in modalita' protetta.

In caso di errore l'hash della password viene oscurato prima di mostrare
autoinstall.yaml. Premendo INVIO viene aperta una shell con controlling terminal
sulla console 3. Il firmware usato (BIOS oppure UEFI) viene rilevato durante la
scelta del disco e Curtin riceve il dispositivo GRUB appropriato.
Il fuso orario predefinito e' Europe/Rome; il menu propone anche le principali
zone europee, UTC e l'inserimento manuale di un identificatore IANA validato
contro il database zoneinfo incluso nell'ambiente di installazione.

MAGICQ E SICUREZZA
------------------

Nessun pacchetto MagicQ proprietario viene incluso, scaricato o pubblicato.
Il bootstrap autorizza esplicitamente `install.sh --allow-missing-magicq`, quindi
Wasalight viene installato anche senza MagicQ. Un .deb autorizzato puo' essere
aggiunto successivamente in /data/system/packages e applicato in modalita'
MAINTENANCE con `sudo wasalight-update`.

Il branch main garantisce la versione Wasalight piu' recente richiesta, ma non
una build riproducibile bloccata a un checksum noto. Il commit effettivamente
installato viene sempre registrato.

BASI CANONICAL VERIFICATE
-------------------------

Nella root del progetto, release-manifest.ini e' l'unica fonte per:

- repository e branch Wasalight;
- versione e architettura Ubuntu;
- nome, URL, dimensione e SHA-256 della Live Server ISO;
- nome e SHA-256 della Mini ISO;
- percorso del file VERSION dell'ISO Builder.

I due builder caricano il manifest tramite lib/wasalight-release-manifest.sh e
rifiutano valori mancanti o non validi. Il builder rifiuta inoltre immagini con
checksum diverso da quello dichiarato. Una copia del manifest e del loader viene
incorporata nella ISO e installata nel sistema: il first boot usa quella copia
per repository e branch, senza valori Git duplicati nello script.

BUILD
-----

Per creare entrambe:

  bash Minimal-ISO-Builder/make-wasalight-minimal.sh

Per creare una coppia riproducibile vincolata a un tag di release:

  bash Minimal-ISO-Builder/make-wasalight-minimal.sh \
    --wasalight-ref v2026.08.25.1-rc.2

Il riferimento viene scritto soltanto nel manifest incorporato nelle ISO; il
manifest sorgente continua a usare `main` per le normali build di sviluppo.

Output:

  Minimal-ISO-Builder/WASALIGHT-Installer-24.04-Minimal-Full-v<VERSION>.iso
  Minimal-ISO-Builder/WASALIGHT-Installer-24.04-Minimal-Netboot-v<VERSION>.iso

Per una sola variante:

  bash Minimal-ISO-Builder/make-wasalight-minimal.sh --variant full
  bash Minimal-ISO-Builder/make-wasalight-minimal.sh --variant netboot

La variante completa usa esclusivamente il nome canonico `full`.

Il menu non ha un timeout distruttivo: occorre premere ENTER.
Il numero dell'installer e' definito una sola volta nel file VERSION. Le ISO
vengono create con un nome temporaneo nella cartella di destinazione e
sostituiscono una build precedente soltanto dopo tutti i controlli finali.
Per aggiornare una base Canonical occorre modificare soltanto la sezione
[ISOBuilder] del release-manifest.ini centrale e rieseguire i controlli.

CONTROLLO
---------

  bash -n Minimal-ISO-Builder/make-wasalight-minimal.sh
  bash -n Minimal-ISO-Builder/make-wasalight-netboot.sh
  bash -n Minimal-ISO-Builder/wasalight-first-boot.sh
  sh -n Minimal-ISO-Builder/netboot-iso-loader.sh
  sh -n Minimal-ISO-Builder/netboot-copy-seed.sh
  sh -n Minimal-ISO-Builder/select-disk.sh
  sh -n Minimal-ISO-Builder/select-keyboard.sh
  python3 -m py_compile Minimal-ISO-Builder/install-wizard.py
  bash Minimal-ISO-Builder/tests/verify-release-config.sh
  ./tests/verify-project.sh

Eseguire il test di installazione in una VM con disco vuoto e almeno 8 GiB di
RAM. ISO, immagini Canonical, cache e pacchetti .deb sono esclusi da Git.
