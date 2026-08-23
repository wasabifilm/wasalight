WASALIGHT UBUNTU ISO BUILDER
============================

Il builder crea due immagini realmente diverse per Ubuntu Server 24.04.4 LTS
amd64:

- FULL: circa 3,2 GB, basata sulla Live Server completa;
- NETBOOT: circa 100 MB, basata sulla Mini ISO ufficiale Canonical.

FULL contiene localmente il sistema Ubuntu Minimal. Richiede comunque Internet
durante l'autoinstall per Git e aggiornamenti e al primo avvio per scaricare e
installare l'ultimo branch main di Wasalight. Il nome FULL distingue quindi la
base Ubuntu locale da una installazione completamente offline.

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

Entrambe le varianti installano durante l'autoinstall Git e tutti i pacchetti
runtime standard elencati in packages/wasalight-runtime.txt. Dopo Ubuntu, un
servizio systemd completa automaticamente Wasalight al primo avvio reale:

1. usa il checkout persistente /data/system/wasalight;
2. scarica con un clone shallow o aggiorna il branch configurato nel manifest;
3. accetta solo un checkout pulito e aggiornamenti fast-forward;
4. esegue tests/verify-project.sh;
5. registra il commit in /data/log/wasalight-first-boot.version;
6. pubblica fase ed esito in /data/log/wasalight-first-boot.status;
7. esegue install.sh e riavvia in modalita' protetta.

Il log si trova in /data/log/wasalight-first-boot.log. Se rete o installazione
falliscono, il servizio non dichiara il completamento e riprova dopo 60 secondi.

La variante NETBOOT prepara gia' il checkout Git durante l'autoinstall, poi lo
aggiorna nuovamente al primo avvio per installare il main piu' recente. Ogni
checkout viene verificato una sola volta per esecuzione; poiche' i pacchetti
standard sono gia' presenti, install.sh salta il secondo aggiornamento APT.

DISCO E INTERFACCIA
-------------------

Entrambe includono:

- boot BIOS e UEFI conservato dalle immagini Canonical;
- selezione manuale del disco, minimo 32 GiB;
- esclusione del supporto USB di installazione, anche nel doppio avvio NETBOOT;
- interfaccia di installazione interamente in inglese;
- conferma distruttiva digitando esattamente ERASE;
- GPT ibrida con BIOS GRUB, EFI, /boot, LVM, root al 50% e /data sul resto;
- scelta della tastiera, del fuso orario e della password chamsys durante
  l'installazione;
- SSH inizialmente disabilitato;
- UI Wasalight alimentata dagli eventi Subiquity/curtin su Ctrl+Alt+F2;
- log tecnici su Ctrl+Alt+F1.

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

Output:

  Minimal-ISO-Builder/WASALIGHT-Installer-24.04-Minimal-Full-v<VERSION>.iso
  Minimal-ISO-Builder/WASALIGHT-Installer-24.04-Minimal-Netboot-v<VERSION>.iso

Per una sola variante:

  bash Minimal-ISO-Builder/make-wasalight-minimal.sh --variant full
  bash Minimal-ISO-Builder/make-wasalight-minimal.sh --variant netboot

`--variant offline` resta accettato come alias storico di `full`, ma tutti i
nuovi menu, messaggi e nomi file usano FULL per non suggerire assenza di rete.

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
  bash Minimal-ISO-Builder/tests/verify-release-config.sh
  ./tests/verify-project.sh

Eseguire il test di installazione in una VM con disco vuoto e almeno 8 GiB di
RAM. ISO, immagini Canonical, cache e pacchetti .deb sono esclusi da Git.
