WASALIGHT UBUNTU ISO BUILDER v24
===============================

Il builder crea due immagini realmente diverse per Ubuntu Server 24.04.4 LTS
amd64:

- OFFLINE: circa 3,2 GB, basata sulla Live Server completa;
- NETBOOT: circa 100 MB, basata sulla Mini ISO ufficiale Canonical.

OFFLINE contiene localmente il sistema Ubuntu Minimal. NETBOOT contiene
bootloader, kernel e initrd, poi scarica in RAM la Live Server 24.04.4 ufficiale
da releases.ubuntu.com. Prima di avviarla controlla dimensione e SHA-256
Canonical. Non e' PXE: si avvia da USB o da ISO come l'immagine OFFLINE.

NETBOOT richiede:

- Ethernet con DHCP;
- DNS e accesso HTTPS a releases.ubuntu.com, archive.ubuntu.com e GitHub;
- almeno 8 GiB di RAM durante l'installazione, perche' la Live Server scaricata
  viene conservata in una regione di memoria protetta;
- una connessione stabile per scaricare circa 3,2 GB oltre ai pacchetti Ubuntu.

INSTALLAZIONE WASALIGHT
----------------------

Entrambe le varianti installano Git. Dopo Ubuntu, un servizio systemd completa
automaticamente Wasalight al primo avvio reale:

1. usa il checkout persistente /data/system/wasalight;
2. scarica o aggiorna il branch main da github.com/wasabifilm/wasalight.git;
3. accetta solo un checkout pulito e aggiornamenti fast-forward;
4. esegue tests/verify-project.sh;
5. registra il commit in /data/log/wasalight-first-boot.version;
6. esegue install.sh e riavvia in modalita' protetta.

Il log si trova in /data/log/wasalight-first-boot.log. Se rete o installazione
falliscono, il servizio non dichiara il completamento e riprova dopo 60 secondi.

La variante NETBOOT prepara gia' il checkout Git durante l'autoinstall, poi lo
aggiorna nuovamente al primo avvio per installare il main piu' recente.

DISCO E INTERFACCIA
-------------------

Entrambe includono:

- boot BIOS e UEFI conservato dalle immagini Canonical;
- selezione manuale del disco, minimo 16 GiB;
- esclusione del supporto USB di installazione, anche nel doppio avvio NETBOOT;
- conferma distruttiva digitando esattamente CANCELLA;
- GPT con EFI, /boot, LVM, root al 50% e /data sul resto;
- scelta della tastiera e password chamsys durante l'installazione;
- SSH inizialmente disabilitato;
- UI Wasalight alimentata dagli eventi Subiquity/curtin su Ctrl+Alt+F2;
- log tecnici su Ctrl+Alt+F1.

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

- ubuntu-24.04.4-live-server-amd64.iso
  SHA-256: e907d92eeec9df64163a7e454cbc8d7755e8ddc7ed42f99dbc80c40f1a138433
- ubuntu-mini-iso-24.04.4-mini-iso-amd64.iso
  SHA-256: 57bfe99e776698ae08358145cf3a58bfb74beafe8c8cf965ca86552233d2f53f

Il builder rifiuta automaticamente immagini con checksum diverso.

BUILD
-----

Per creare entrambe:

  bash Minimal-ISO-Builder/make-wasalight-minimal.sh

Output:

  Minimal-ISO-Builder/WASALIGHT-Installer-24.04-Minimal-Offline-v24.iso
  Minimal-ISO-Builder/WASALIGHT-Installer-24.04-Minimal-Netboot-v24.iso

Per una sola variante:

  bash Minimal-ISO-Builder/make-wasalight-minimal.sh --variant offline
  bash Minimal-ISO-Builder/make-wasalight-minimal.sh --variant netboot

Il menu non ha un timeout distruttivo: occorre premere ENTER.

CONTROLLO
---------

  bash -n Minimal-ISO-Builder/make-wasalight-minimal.sh
  bash -n Minimal-ISO-Builder/make-wasalight-netboot.sh
  bash -n Minimal-ISO-Builder/wasalight-first-boot.sh
  sh -n Minimal-ISO-Builder/netboot-iso-loader.sh
  sh -n Minimal-ISO-Builder/netboot-copy-seed.sh
  sh -n Minimal-ISO-Builder/select-disk.sh
  sh -n Minimal-ISO-Builder/select-keyboard.sh

Eseguire il test di installazione in una VM con disco vuoto e almeno 8 GiB di
RAM. ISO, immagini Canonical, cache e pacchetti .deb sono esclusi da Git.
