# Logo e schermata di avvio

Wasalight usa la stessa composizione in GRUB, Plymouth e sul desktop. Il tema ha
sfondo quasi nero `#080b10` e un logo centrale discreto, riducendo il tratto
nero fra firmware e splash che è controllabile dal sistema operativo.

## Immagine predefinita

Il repository contiene due file:

```text
assets/branding/wasabi-logo.png   marchio Wasabi bianco/verde trasparente
assets/branding/boot-logo.png     immagine pronta per il boot
```

`boot-logo.png` usa la variante bianca e verde del marchio, con fondo
trasparente e senza targa: è quindi adatto direttamente allo sfondo scuro.
La risoluzione del file è **1200 × 627 px**, PNG RGBA. Plymouth e il desktop non
lo mostrano a grandezza piena: lo centrano, limitano la larghezza al **34%** dello
schermo e l’altezza al **24%**, senza ingrandire l’immagine oltre la dimensione
originale. Entrambi usano lo stesso fondo quasi nero `#080b10`.

## Copia persistente

Alla prima installazione l’immagine predefinita viene copiata in:

```text
/data/system/branding/boot-logo.png
```

Questa è la sorgente attiva e persistente. Gli aggiornamenti successivi non la
sovrascrivono, così un logo personalizzato sopravvive sia agli update sia alla
modalità SHOW / PROTECTED. Durante l’installazione viene copiata nel tema
Plymouth e inserita nell’initramfs; `/data` non è ancora disponibile abbastanza
presto per essere letta direttamente durante il boot.

Su Ubuntu 24.04 il tema viene registrato e selezionato nel gruppo
`default.plymouth` di `update-alternatives`, che è la sorgente letta dallo hook
Ubuntu durante la rigenerazione dell’initramfs. Wasalight non usa il vecchio
comando `plymouth-set-default-theme`, non più distribuito da Plymouth 24.x.

L’installer genera inoltre `/boot/grub/wasalight-background.png` a 1920×1080 e
imposta GRUB in modalità grafica con payload Linux mantenuto. Sull’HP EliteDesk
con grafica Intel aggiunge `i915` all’initramfs: il kernel modesetting e
Plymouth possono così prendere lo schermo prima. UTM resta un ambiente di test;
questa ottimizzazione hardware è pensata per il target fisico Intel.

## Sostituire il logo

Usare un PNG con trasparenza o con un fondo che renda leggibile il marchio. Sono
accettate dimensioni da 64 a 8192 px per lato; per un logo orizzontale si
consigliano circa 1200–1600 px di larghezza e un file inferiore a 2 MB.

In modalità MAINTENANCE:

```bash
sudo install -o root -g root -m 0644 MIO-LOGO.png \
  /data/system/branding/boot-logo.png
sudo wasalight-update
```

L’aggiornamento valida la firma PNG, controlla le dimensioni e rigenera il tema.
Se l’immagine persistente non è valida, non viene cancellata: l’installer usa
temporaneamente il logo predefinito di GitHub e mostra un avviso.

## Sfondo del desktop

All’avvio di Openbox, `wasalight-desktop-wallpaper` legge la risoluzione attiva
di Xorg e genera:

```text
/home/chamsys/.cache/wasalight/desktop-wallpaper.png
```

La composizione usa direttamente il logo persistente in `/data`, con le stesse
regole di posizione, dimensione e colore del tema Plymouth. PCManFM carica poi
il PNG già delle dimensioni esatte dello schermo. Cambiando il logo persistente
e riavviando la sessione o il sistema vengono quindi aggiornati insieme boot e
desktop; non serve mantenere una seconda immagine.

## Avvio silenzioso e recupero

La configurazione normale usa `quiet splash`, mostra il fondo Wasalight già in
GRUB, nasconde il menu per un secondo e riduce i messaggi di sistema. Tenere
premuto **Esc** durante il
passaggio firmware/GRUB permette di richiamare il menu quando serve una modalità
di recupero. Messaggi del firmware o del BIOS/UEFI precedenti a GRUB non possono
essere sostituiti da Plymouth.

## Passaggio silenzioso a Xorg

Anche il login automatico su `tty1` è silenzioso: `agetty` non mostra
`/etc/issue`, `.hushlogin` sopprime MOTD e ultimo accesso, mentre la schermata
viene pulita e il cursore nascosto prima di avviare Xorg. L’output di `startx`
non appare sul monitor ma viene conservato in:

```text
/data/log/wasalight-xorg-startup.log
```

Se `/data` non è disponibile viene usato temporaneamente
`/tmp/wasalight-xorg-startup.log`. Alla chiusura di Xorg il cursore viene sempre
ripristinato; in caso di errore la console mostra soltanto il percorso del log,
così il sistema resta diagnosticabile senza sporcare l’avvio normale.
