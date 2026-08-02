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
- [ ] In MAINTENANCE Openbox parte ma MagicQ e supervisore restano fermi.
- [ ] In MAINTENANCE `magicq-start` consente comunque l'avvio manuale.
- [ ] In SHOW / PROTECTED MagicQ e supervisore partono automaticamente.
- [ ] Il sistema riparte correttamente dopo più interruzioni di alimentazione.

## MagicQ e grafica

- [ ] Autologin dell’utente `chamsys` e avvio automatico di X/Openbox.
- [ ] Avvio automatico e riavvio di MagicQ dopo una chiusura inattesa.
- [ ] La chiusura della sola finestra riavvia MagicQ entro pochi secondi.
- [ ] `magicq-stop` ferma applicazione e supervisore e MagicQ resta chiuso.
- [ ] `magicq-start` riattiva applicazione e supervisione senza creare duplicati.
- [ ] `ps -o user,args -C mqqt` mostra MagicQ eseguito come `root` tramite il
      launcher dedicato.
- [ ] Uno show di prova viene creato in `/home/chamsys/Documents/MagicQ` e in
      `/data/magicq/Documents/MagicQ`; l'eventuale percorso fallback
      `/root/Documents/MagicQ` mostra gli stessi file persistenti.
- [ ] Dopo aver chiuso MagicQ, lo show resta modificabile da `chamsys` senza
      usare `sudo`.
- [ ] `/data/log/wasalight-magicq-console.log` contiene l'output di avvio.
- [ ] `/data/log/wasalight-magicq-session.log` registra avvio, uscita e riavvio.
- [ ] I log nativi datati di MagicQ restano separati sotto
      `/data/magicq/Documents/MagicQ/log/`.
- [ ] `magicq-status` mostra `LOGS: persistent in /data/log`.
- [ ] `systemctl status magicq-logrotate.timer` mostra il timer abilitato.
- [ ] Un log di prova oltre 5 MiB viene ruotato senza interrompere MagicQ e
      restano al massimo cinque copie.
- [ ] Il controllo di `libqxcb.so`, eseguito con le librerie incluse da MagicQ,
      non mostra dipendenze `not found`.
- [ ] `/usr/share/alsa/alsa.conf` esiste e `magicq-audio-test` riproduce una
      volta i campioni Front Left e Front Right sul dispositivo predefinito.
- [ ] Gli eventuali avvisi `Unknown PCM` prodotti dall'enumerazione PortAudio
      sono distinti da errori reali: il test audio termina con successo e
      MagicQ completa l'inizializzazione.
- [ ] MagicQ parte in vero fullscreen, senza barra del titolo né pannello
      Tint2; chiudendolo e riavviandolo il fullscreen viene riapplicato.
- [ ] Openbox espone un solo desktop virtuale (`wmctrl -d` mostra una riga).
- [ ] Con MagicQ fermo, i sei pulsanti desktop hanno icone grandi e leggibili
      al touch e si avviano con un solo tocco senza mostrare «Apri con…».
- [ ] `chamsys` non può cancellare, rinominare o spostare i launcher desktop.
- [ ] Il pulsante VNC avvia la condivisione del display `:0`, mostra l'indirizzo
      e propone l'arresto quando viene premuto mentre VNC è già attivo.
- [ ] **Power off** e **Reboot** mostrano sempre la conferma; **Cancel** non
      esegue azioni e la conferma completa correttamente l'operazione scelta.
- [ ] Il pannello destro mostra CURRENT, NEXT BOOT, MagicQ, supervisore, data,
      log, rete/IP, touch, USB, VNC e audio con colori coerenti.
- [ ] Il pannello resta dietro alle applicazioni, non intercetta i tocchi e
      scompare alla vista quando MagicQ occupa il fullscreen.
- [ ] Toccando il bordo inferiore Tint2 compare senza la scritta `desktop 1` e
      consente di aprire il Hub o selezionare un'applicazione già aperta.
- [ ] Wasalight Hub mostra le schede MagicQ, Applications e Support con pulsanti
      grandi; gli strumenti di supporto si avviano correttamente.
- [ ] Un launcher registrato con `wasalight-app-register` compare nel Hub e
      sopravvive al riavvio protetto; dopo `--remove` non compare più.
- [ ] Il clic destro mostra soltanto il menu Wasalight minimale, senza
      preferenze Openbox generiche.
- [ ] Il clic destro sullo sfondo continua ad aprire il menu Openbox.
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

- [ ] `nmcli device status` mostra le interfacce Ethernet/Wi-Fi come gestite,
      non `unmanaged`.
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
