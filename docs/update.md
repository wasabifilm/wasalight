# Aggiornare Wasalight

Wasalight mantiene codice e pacchetti necessari agli aggiornamenti sulla
partizione persistente `/data`, fuori dall’overlay del sistema.

## Percorsi

```text
/data/system/wasalight   repository Git operativo
/data/system/packages   pacchetti MagicQ proprietari
/data/log/wasalight/updates/update-AAAAMMGG-HHMMSS.log
                         log completo della singola esecuzione
/data/log/wasalight-update.log
                         registro cumulativo compatibile
/data/system/update-check
                         ultima versione rilevata e data del controllo
```

Il repository pubblico non contiene il pacchetto MagicQ. Il `.deb` viene
copiato separatamente, verificato byte per byte e protetto con permessi
`root:root 0640`.

Durante ogni esecuzione l’updater mostra la versione installata letta da
`/etc/wasalight/version` e, dopo il download, la versione disponibile nel file
`VERSION` del checkout persistente. Il numero installato viene aggiornato solo
dopo un’installazione conclusa e verificata.

## Aggiornare MagicQ da USB

Copiare il pacchetto `.deb` di MagicQ in una delle due posizioni della
chiavetta, senza rinominarlo obbligatoriamente:

```text
MAGICQ_USB/*.deb
MAGICQ_USB/packages/*.deb
```

Dopo il montaggio automatico in `/stick/<dispositivo>`, entrare in MAINTENANCE
e avviare normalmente **Aggiorna Wasalight**. L’updater controlla tutte le USB
attualmente montate, non le directory residue, e accetta soltanto un archivio
Debian integro con `Package: magicq`, `Architecture: amd64` e una versione
Debian valida.

Il file scelto viene copiato in `/data/system/packages` e verificato byte per
byte; l’originale sulla chiavetta non viene mai spostato o cancellato. Versioni
precedenti vengono ignorate. Due pacchetti con la stessa versione ma contenuto
diverso bloccano l’operazione, evitando una sostituzione ambigua. Fra più USB e
più file viene selezionata la versione più recente usando i metadati Debian,
non il nome del file.

Alla prima installazione `/stick` non è ancora gestito da Wasalight. In quel
caso l’installer usa una scansione bootstrap separata: riconosce le partizioni
USB tramite udev, le monta in sola lettura sotto `/run/wasalight-usb-scan`,
importa il pacchetto e le smonta subito. La chiavetta FAT32 è la scelta più
compatibile con Ubuntu Server minimale.

L’assenza di un mount preesistente è il caso normale: il risultato “non
montato” di `findmnt` non interrompe l’installer. Non è quindi necessario creare
manualmente `/stick`, `/media` o un altro mountpoint prima di eseguire
`sudo ./install.sh`. La scansione interpreta esplicitamente le colonne
dispositivo, tipo e filesystem prodotte da `lsblk`, indipendentemente dall’`IFS`
restrittivo usato dal resto dell’installer.

Quando crea i bind persistenti, l’installer ricarica le unità generate da
`/etc/fstab` prima del primo mount. I file root già persistenti non vengono
sovrascritti: la copia iniziale usa la forma portabile `cp --update=none`
prevista da Ubuntu 24.04.

Dopo la prima installazione Wasalight dispone anche della lettura APFS tramite
`libfsapfs-utils`. I volumi APFS non cifrati vengono esposti in sola lettura
sotto `fsapfs1`, `fsapfs2`, ecc.; l’updater cerca il `.deb` anche nella radice e
in `packages/` di queste sottodirectory. APFS non è disponibile nel bootstrap
Ubuntu minimale precedente all’installazione dei pacchetti Wasalight.

L’installer inizializza automaticamente il repository persistente quando
`/data` è disponibile. Se GitHub non è raggiungibile, mostra un avviso senza
rimuovere i dati già presenti; ripetere in seguito
`sudo wasalight-update --code-only`.

## Primo aggiornamento

Entrare in MAINTENANCE:

```bash
sudo wasalight-maintenance
sudo reboot
```

Poi eseguire:

```bash
sudo wasalight-update
```

Dal desktop non serve aprire manualmente il terminale: clic destro →
**Aggiorna Wasalight**, oppure **Wasalight Control → Stato → Aggiorna**.
Si apre una finestra con quattro fasi leggibili: controllo del pacchetto MagicQ,
download, verifica e installazione. Al termine compare un grande pulsante
**Riavvia ora**; scegliendo **Più tardi** l’aggiornamento resta installato e viene
ricordato che il riavvio è ancora necessario. Non occorre più premere Invio per
chiudere la finestra, quindi il flusso è utilizzabile interamente al touch.

In caso di errore non viene mai eseguito il riavvio automatico: il terminale
mostra fase, comando, linea e codice di uscita. Il log completo della singola
esecuzione resta in `/data/log/wasalight/updates/`, mentre
`/data/log/wasalight-update.log` conserva la cronologia cumulativa.

Ad ogni avvio grafico un controllo asincrono confronta la versione installata
con `VERSION` pubblicato su GitHub. Non rallenta Openbox o MagicQ, non installa
nulla e, in assenza di rete, termina senza finestre di errore. Quando trova una
release nuova mostra una notifica discreta e la riga `UPDATE` di
`wasalight-status` riporta la versione disponibile.

Ad ogni utilizzo il comando:

1. cerca MagicQ nella root e in `packages/` di ogni USB montata;
2. valida nome del pacchetto, formato, versione e architettura `amd64`;
3. conserva in `/data/system/packages` soltanto candidati non precedenti;
4. scarica `https://github.com/wasabifilm/wasalight.git` in
   `/data/system/wasalight`;
5. esegue `tests/verify-project.sh` sul codice scaricato;
6. seleziona la versione MagicQ più recente tramite `dpkg` e rilancia
   l’installer.

Per sicurezza l’installer lascia la macchina in MAINTENANCE. Dopo il collaudo:

```bash
sudo wasalight-protect
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

Per una diagnosi dettagliata visualizzare anche ogni comando mentre viene
eseguito; il log rimane comunque completo anche senza questa opzione:

```bash
sudo wasalight-update --verbose
```

Le opzioni possono essere combinate, ad esempio
`sudo wasalight-update --protect --reboot`. `--code-only --reboot` viene invece
rifiutato perché il solo download non modifica la configurazione del sistema.

Mantenere SSH automatico oppure disabilitato all’avvio:

```bash
sudo wasalight-update --with-ssh
sudo wasalight-update --without-ssh
```

Senza queste opzioni viene conservato il flag persistente
`/data/system/service-flags/ssh-autostart`, lo stesso gestito dal toggle
**Avvio automatico** in Wasalight Control.
La tastiera Onboard viene conservata automaticamente quando è già installata.

Per installare Bitfocus Companion durante un aggiornamento Wasalight:

```bash
sudo wasalight-update --with-companion
```

L'opzione serve per la prima installazione. Dopo che Companion è presente, gli
aggiornamenti normali lo riconoscono e ne conservano servizio e dati persistenti
anche senza ripetere `--with-companion`. L'opzione non aggiorna automaticamente
una versione Companion già installata: per quello usare il comando dedicato in
MAINTENANCE descritto in `docs/companion.md`.

Se MagicQ non è installato e non viene trovato alcun `.deb` valido, il comando
si ferma invece di creare silenziosamente una postazione incompleta. Per
continuare consapevolmente senza MagicQ:

```bash
sudo wasalight-update --allow-missing-magicq
```

L’elenco completo e aggiornato delle opzioni è disponibile con una qualsiasi
delle forme:

```bash
sudo wasalight-update -h
sudo wasalight-update -help
sudo wasalight-update --help
```

## Protezioni

- Il comando rifiuta di operare in SHOW mode con overlay attivo.
- Un aggiornamento Git deve essere un avanzamento lineare (`fast-forward`).
- Le modifiche locali ai file tracciati interrompono l’operazione e non vengono
  cancellate.
- Due `.deb` con la stessa versione MagicQ ma contenuto diverso interrompono
  l’aggiornamento, anche quando hanno nomi differenti.
- I file trovati sulle USB sono soltanto letti e copiati, mai rimossi.
- Il codice scaricato viene verificato prima di eseguire l’installer.
- Il log completo resta in `/data/log/wasalight-update.log`.

L’interfaccia grafica dell’aggiornamento disabilita AT-SPI soltanto per i propri
popup Zenity, perché la sessione Openbox minimale non avvia il relativo bus di
accessibilità. Questo evita il falso `Gtk-WARNING` finale senza modificare
l’accessibilità delle altre applicazioni. La ricerca GRUB di altri sistemi
operativi è disabilitata esplicitamente perché Wasalight è un’appliance a sistema
singolo.

Se il download non riesce, correggere rete o DNS e ripetere lo stesso comando;
la copia persistente precedente resta disponibile.
