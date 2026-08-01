# Pacchetto MagicQ

Copiare in questa cartella il pacchetto originale:

```text
magicq_ubuntu_v1_9_8_3.deb
```

Se è presente un solo file `.deb`, `install.sh` lo seleziona automaticamente.
Se sono presenti più versioni, indicare esplicitamente quella desiderata:

```bash
sudo ./install.sh --data-device UUID=... ./packages/magicq_ubuntu_v1_9_8_3.deb
```

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

Se MagicQ era già stato installato con una versione precedente di Wasalight e
mostra `libGLU.so.1: cannot open shared object file`, entrare prima in
MAINTENANCE mode, riavviare e aggiornare il progetto. Non installare la libreria
soltanto nell'overlay volatile di SHOW mode.
