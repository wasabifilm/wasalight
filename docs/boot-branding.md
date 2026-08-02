# Logo e schermata di avvio

Wasalight usa Plymouth per mostrare una schermata pulita tra GRUB e l’avvio di
Openbox. Il tema ha sfondo quasi nero `#080b10` e un logo centrale discreto.

## Immagine predefinita

Il repository contiene due file:

```text
assets/branding/wasabi-logo.png   marchio Wasabi bianco/verde trasparente
assets/branding/boot-logo.png     immagine pronta per il boot
```

`boot-logo.png` usa la variante bianca e verde del marchio, con fondo
trasparente e senza targa: è quindi adatto direttamente allo sfondo scuro.
La risoluzione del file è **1200 × 627 px**, PNG RGBA. Plymouth non lo mostra a
grandezza piena: lo centra, limita la larghezza al **34%** dello schermo e
l’altezza al **24%**, senza ingrandire l’immagine oltre la dimensione originale.

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

Quando cambia il logo ufficiale incluso in Wasalight, l’aggiornamento sostituisce
automaticamente solo una copia identica al precedente logo predefinito. Un file
personalizzato in `/data` viene riconosciuto dal checksum e non viene modificato.

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

## Avvio silenzioso e recupero

La configurazione normale usa `quiet splash`, nasconde il menu GRUB per un
secondo e riduce i messaggi di sistema. Tenere premuto **Esc** durante il
passaggio firmware/GRUB permette di richiamare il menu quando serve una modalità
di recupero. Messaggi del firmware o del BIOS/UEFI precedenti a GRUB non possono
essere sostituiti da Plymouth.
