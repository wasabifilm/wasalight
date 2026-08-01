# Checklist di collaudo hardware

Eseguire questi controlli su una macchina di prova prima dell’impiego durante
uno spettacolo.

## Avvio e protezione

- [ ] `magicq-status` mostra `PROTECTED` dopo il riavvio in SHOW mode.
- [ ] `/data` risulta ext4 e in lettura/scrittura.
- [ ] Le modifiche di prova sotto `/etc` scompaiono dopo un riavvio protetto.
- [ ] Show e impostazioni MagicQ restano presenti dopo il riavvio.
- [ ] `magicq-maintenance`, riavvio e aggiornamento APT funzionano.
- [ ] `magicq-protect` ripristina SHOW mode al riavvio seguente.
- [ ] Il sistema riparte correttamente dopo più interruzioni di alimentazione.

## MagicQ e grafica

- [ ] Autologin dell’utente `chamsys` e avvio automatico di X/Openbox.
- [ ] Avvio automatico e riavvio di MagicQ dopo una chiusura inattesa.
- [ ] `ps -o user,args -C mqqt` mostra MagicQ eseguito come `root` tramite il
      launcher dedicato.
- [ ] Uno show di prova viene creato in `/home/chamsys/Documents/MagicQ` e in
      `/data/magicq/Documents/MagicQ`; l'eventuale percorso fallback
      `/root/Documents/MagicQ` mostra gli stessi file persistenti.
- [ ] Dopo aver chiuso MagicQ, lo show resta modificabile da `chamsys` senza
      usare `sudo`.
- [ ] `/data/log/magicq-console.log` contiene l'output di avvio di MagicQ.
- [ ] `/data/log/magicq-session.log` registra avvio, uscita e riavvio.
- [ ] `magicq-status` mostra `LOGS: persistent in /data/log`.
- [ ] `systemctl status magicq-logrotate.timer` mostra il timer abilitato.
- [ ] Un log di prova oltre 5 MiB viene ruotato senza interrompere MagicQ e
      restano al massimo cinque copie.
- [ ] Il controllo di `libqxcb.so`, eseguito con le librerie incluse da MagicQ,
      non mostra dipendenze `not found`.
- [ ] `/usr/share/alsa/alsa.conf` esiste e MagicQ non mostra errori di
      configurazione ALSA all'avvio.
- [ ] `chamsys` può creare, modificare e cancellare un file di prova nelle
      directory MagicQ persistenti e in `/data/log` senza usare `sudo`.
- [ ] `magicq-touch-status` rileva tutti e soli i touchscreen collegati.
- [ ] Con un monitor, la modalità `auto` mostra `target: ready`.
- [ ] Con più monitor, ogni touchscreen è associato all'uscita corretta.
- [ ] Pressione nei quattro angoli e al centro coincide con l'immagine.
- [ ] Trascinamento e, se previsto dal modello, multitouch funzionano.
- [ ] Rotazione del touch coerente con l'orientamento del monitor.
- [ ] Scollegamento e ricollegamento a caldo riapplicano la configurazione.
- [ ] Associazione e rotazione restano corrette dopo un riavvio protetto.
- [ ] Tastiera Onboard avviabile dal menu, se installata con l'opzione dedicata.
- [ ] Monitor, risoluzioni e accelerazione grafica corretti.
- [ ] Interfacce USB ChamSys rilevate e utilizzabili.
- [ ] Art-Net, sACN e le altre uscite richieste funzionano sulla rete show.
- [ ] Salvataggio, autosave, backup e ripristino di uno show reale.

## Rete

- [ ] `nm-connection-editor` salva DHCP e indirizzi statici.
- [ ] Le connessioni sopravvivono a un riavvio protetto.
- [ ] Nessun indirizzo o servizio inatteso interferisce con la rete show.
- [ ] SSH è raggiungibile solo se installato con `--with-ssh`.

## Chiavette USB

- [ ] FAT32, exFAT e NTFS vengono montati in `/stick/<dispositivo>` e sono
      visibili da MagicQ.
- [ ] Due o più chiavette collegate insieme restano tutte visibili nella vista
      Flash, ciascuna nella propria sottodirectory.
- [ ] Dopo la rimozione scompare soltanto la sottodirectory della chiavetta
      rimossa; le altre restano montate.
- [ ] Copia e rilettura di showfile grandi su ogni filesystem supportato.
- [ ] Prova controllata di rimozione subito dopo un salvataggio.
- [ ] Controllo filesystem della chiavetta su un’altra macchina dopo la prova.

## VNC temporaneo

- [ ] `magicq-vnc-start` richiede una password al primo utilizzo.
- [ ] Il client remoto mostra la stessa sessione Openbox/MagicQ del monitor.
- [ ] `magicq-status` mostra VNC attivo soltanto durante la condivisione.
- [ ] `magicq-vnc-stop` chiude la porta 5900 e termina `x11vnc`.
- [ ] Dopo un riavvio VNC non parte automaticamente.
