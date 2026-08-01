# Migrazione dell'appliance a Ubuntu 24.04 LTS

## Strategia consigliata

Il progetto ora accetta esclusivamente **Ubuntu Server 24.04 LTS amd64**. Per
una postazione da spettacolo è consigliata una nuova installazione, non un
aggiornamento sul posto da Ubuntu 22.04. Una reinstallazione rende verificabili
il boot, initramfs, overlayroot e tutti i pacchetti della sessione grafica senza
ereditare configurazioni obsolete nel filesystem di sistema.

La partizione `/data` resta separata dalla root Ubuntu e può essere conservata,
ma deve sempre esistere un backup esterno aggiornato prima di intervenire sul
disco.

## Dati da conservare

La partizione persistente contiene:

```text
/data/magicq/Documents/MagicQ
/data/magicq/.local/share
/data/magicq/.magicq_init.sh
/data/system/network
/data/system/touchscreen/config
```

Salvare inoltre fuori dalla macchina qualsiasi showfile o configurazione che
non risulti presente sotto `/data`.

## Procedura

1. Avviare la vecchia appliance e verificare che `/data` sia montata:

   ```bash
   findmnt /data
   magicq-status
   ```

2. Copiare l'intero contenuto di `/data` su un disco esterno e verificare che i
   file siano leggibili.
3. Annotare UUID, etichetta e dispositivo della partizione persistente:

   ```bash
   lsblk -f
   sudo blkid
   ```

4. Installare Ubuntu Server 24.04 LTS amd64. Nel partizionamento manuale
   selezionare soltanto la partizione di sistema come destinazione da
   formattare. **Non formattare la partizione dati esistente.**
5. Avviare il nuovo sistema e controllare nuovamente la partizione dati con
   `lsblk -f` prima di eseguire l'installer.
6. Copiare questo progetto e il pacchetto MagicQ verificato sulla macchina.
7. Eseguire l'installazione indicando `/data` tramite UUID o etichetta:

   ```bash
   sudo ./install.sh --data-device LABEL=DATA
   ```

8. Completare prima il collaudo in MAINTENANCE mode, quindi abilitare SHOW mode
   con `sudo magicq-protect` e riavviare.

## Controlli obbligatori dopo la migrazione

- `magicq-status` mostra la release prevista, `/data` persistente e i servizi
  essenziali corretti.
- MagicQ si avvia, apre uno show reale e salva una copia verificabile.
- Configurazioni di rete e touchscreen sono presenti e funzionanti.
- Le periferiche ChamSys, le uscite DMX/rete e i monitor superano la checklist.
- Un riavvio in SHOW mode conserva i dati e scarta una modifica di prova sotto
  `/etc`.
- Il ritorno temporaneo in MAINTENANCE mode funziona.

## Pacchetto MagicQ

La disponibilità dei pacchetti Ubuntu dell'appliance non dimostra da sola la
compatibilità del `.deb` proprietario MagicQ. Prima dell'impiego occorre
ispezionare `Architecture` e `Depends`, simulare l'installazione e infine
provare avvio, grafica, audio e periferiche sulla macchina definitiva. La
procedura è descritta in `packages/README.md`.

## Ripristino

Conservare il supporto di installazione precedente e il backup esterno fino al
superamento dell'intera checklist. Se il collaudo di Ubuntu 24.04 o del pacchetto
MagicQ fallisce, reinstallare la versione precedentemente validata e ripristinare
`/data` dal backup; non tentare di correggere la macchina durante uno show.
