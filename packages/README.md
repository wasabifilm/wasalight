# Pacchetto MagicQ

Il file tracciato `wasalight-runtime.txt` contiene invece l'elenco validato dei
pacchetti Ubuntu liberi installati da Wasalight e dalle ISO. Non contiene e non
sostituisce il pacchetto proprietario MagicQ descritto qui sotto.

Copiare in questa cartella il pacchetto originale:

```text
magicq_ubuntu_v1_9_8_3.deb
```

`install.sh` verifica che ogni `.deb` dichiari `Package: magicq` e architettura
`amd64`, poi seleziona automaticamente la versione Debian più recente.
Durante l’installazione il file viene copiato e verificato in
`/data/system/packages`.
Per forzare una versione specifica, indicarla esplicitamente:

```bash
sudo ./install.sh --data-device UUID=... ./packages/magicq_ubuntu_v1_9_8_3.deb
```

Per gli aggiornamenti è possibile lasciare il `.deb` nella root oppure nella
cartella `packages/` di una chiavetta. Dopo il montaggio in
`/stick/<dispositivo>`, **Update Wasalight** importa la versione più recente in
`/data` senza modificare il file sulla USB. Due file con la stessa versione ma
contenuto differente vengono considerati un conflitto e fermano l’operazione.

La stessa disposizione funziona durante la prima installazione, anche prima che
sia attivo l’automount in `/stick`. Il bootstrap riconosce tramite udev soltanto
dispositivi USB, monta temporaneamente le partizioni in sola lettura sotto
`/run/wasalight-usb-scan`, importa il pacchetto in `/data` e le smonta. Usare
preferibilmente FAT32, disponibile anche nell’installazione Ubuntu minimale;
exFAT, NTFS ed ext4 vengono provati quando supportati dal kernel presente.

Dopo che Wasalight è stato installato, anche una USB APFS non cifrata può essere
usata per importare un `.deb`, ma soltanto in lettura. Il bootstrap iniziale non
include ancora il lettore APFS: per la prima esecuzione usare FAT32. Per una USB
destinata anche al salvataggio degli show usare exFAT, non APFS.

Quando nessun pacchetto valido è disponibile e MagicQ non risulta già
installato, l’installazione si interrompe mostrando il comando esplicito
`--allow-missing-magicq`. Usarlo soltanto quando si vuole preparare Wasalight
senza installare l’applicazione ChamSys.

Prima dell’uso è consigliato controllare il checksum pubblicato dal fornitore e
verificare architettura, metadati e contenuto del pacchetto con:

```bash
dpkg-deb --info ./packages/magicq_ubuntu_v1_9_8_3.deb
dpkg-deb --contents ./packages/magicq_ubuntu_v1_9_8_3.deb
```

Il target del progetto è **Ubuntu Server 24.04 LTS amd64**. Prima del collaudo
hardware verificare anche la risoluzione delle dipendenze senza installare il
pacchetto:

```bash
dpkg-deb -f ./packages/magicq_ubuntu_v1_9_8_3.deb Architecture Depends
sudo apt-get --simulate install ./packages/magicq_ubuntu_v1_9_8_3.deb
```

La compatibilità binaria finale non può essere confermata finché il file `.deb`
non è presente in questa cartella.

## Dipendenze grafiche su Ubuntu 24.04

MagicQ richiede `libGLU.so.1`, fornita dal pacchetto Ubuntu `libglu1-mesa`.
L'installer Wasalight installa esplicitamente questo pacchetto insieme a
`libgl1-mesa-dri` e verifica sia la presenza di GLU sia le dipendenze dichiarate
dal binario `/opt/magicq/bin/mqqt`.
