# Checklist di collaudo hardware

Eseguire questi controlli su una macchina di prova prima dell’impiego durante
uno spettacolo.

## Avvio e protezione

- [ ] `wasalight-status`, il pannello desktop e `/etc/wasalight/version` mostrano
      lo stesso numero `AAAA.MM.GG.BUILD` pubblicato nel file `VERSION`.
- [ ] Dopo GRUB appare lo sfondo quasi nero con il logo Wasabi centrato e
      discreto, senza testo Ubuntu sovrapposto durante un avvio normale.
- [ ] Il logo non supera circa un terzo della larghezza e un quarto dell’altezza
      dello schermo sia a 1280×720 sia alla risoluzione nativa del monitor.
- [ ] Dopo l’ingresso in Openbox, sfondo `#080b10`, logo, dimensione e posizione
      coincidono visivamente con la schermata Plymouth appena mostrata.
- [ ] `/home/chamsys/.cache/wasalight/desktop-wallpaper.png` ha la stessa
      risoluzione indicata da `xdpyinfo` e usa il logo persistente in `/data`.
- [ ] Tenendo premuto `Esc` durante il passaggio firmware/GRUB il menu di
      recupero resta raggiungibile.
- [ ] `/data/system/branding/boot-logo.png` esiste e una personalizzazione PNG
      valida sopravvive a un aggiornamento.
- [ ] Tra Plymouth e Openbox lo schermo resta nero, senza banner di login o
      messaggi Xorg; `/data/log/wasalight-xorg-startup.log` contiene l’output.
- [ ] `wasalight-status` mostra `PROTECTED` dopo il riavvio in SHOW mode.
- [ ] `/data` risulta ext4 e in lettura/scrittura.
- [ ] Le modifiche di prova sotto `/etc` scompaiono dopo un riavvio protetto.
- [ ] Show e impostazioni MagicQ restano presenti dopo il riavvio.
- [ ] `wasalight-maintenance`, riavvio e aggiornamento APT funzionano.
- [ ] `wasalight-protect` ripristina SHOW mode al riavvio seguente.
- [ ] In MAINTENANCE Openbox parte ma MagicQ e la sessione di lancio restano fermi.
- [ ] In MAINTENANCE `magicq-start` consente comunque l'avvio manuale.
- [ ] In SHOW / PROTECTED MagicQ parte automaticamente una volta.
- [ ] Il sistema riparte correttamente dopo più interruzioni di alimentazione.

## MagicQ e grafica

- [ ] Senza MagicQ installato e senza `.deb`, l’installer si ferma mostrando
      `--allow-missing-magicq`; ripetendo con l’opzione prosegue consapevolmente.
- [ ] `./install.sh -help` e `wasalight-update -help` mostrano tutte le opzioni.
- [ ] La versione nella riga `MAGICQ` del pannello e di `wasalight-status`
      coincide con `dpkg-query -W -f='${Version}\n' magicq` (per esempio
      `1.9.8.3`).
- [ ] Autologin dell’utente `chamsys` e avvio automatico di X/Openbox.
- [ ] Chiudendo MagicQ, l'applicazione resta chiusa e non viene riavviata.
- [ ] `magicq-stop` ferma applicazione e sessione di lancio; MagicQ resta chiuso.
- [ ] `magicq-start` riattiva MagicQ senza creare istanze duplicate.
- [ ] `ps -o user,args -C mqqt` mostra MagicQ eseguito come `root` tramite il
      launcher dedicato.
- [ ] Uno show di prova viene creato in `/home/chamsys/Documents/MagicQ` e in
      `/data/magicq/Documents/MagicQ`; l'eventuale percorso fallback
      `/root/Documents/MagicQ` mostra gli stessi file persistenti.
- [ ] Dopo aver chiuso MagicQ, lo show resta modificabile da `chamsys` senza
      usare `sudo`.
- [ ] `/data/log/wasalight-magicq-console.log` contiene l'output di avvio.
- [ ] `/data/log/wasalight-magicq-session.log` registra avvio e uscita senza retry.
- [ ] I log nativi datati di MagicQ restano separati sotto
      `/data/magicq/Documents/MagicQ/log/`.
- [ ] `wasalight-status` mostra `LOGS: persistent in /data/log`.
- [ ] `systemctl status wasalight-logrotate.timer` mostra il timer abilitato.
- [ ] Un log di prova oltre 5 MiB viene ruotato senza interrompere MagicQ e
      restano al massimo cinque copie.
- [ ] Il log `wasalight-update.log` mostra la pulizia dei pacchetti estranei
      prima dell’installazione Wasalight e un solo `autoremove --purge` finale.
- [ ] Ripetendo l’update della stessa versione/commit compare **sistema già
      aggiornato** senza snapshot, APT, installer o richiesta di riavvio.
- [ ] `wasalight-update --plan` mostra versione, commit, MagicQ, snapshot e
      modalità prevista senza modificare `/data`, configurazione, pacchetti USB,
      canale o checkout; `tests/utm/verify-update-plan.sh` termina con `PASS`.
- [ ] `wasalight-update --channel debug` segue `main`, salva `debug` soltanto a
      esito positivo e il pannello mostra `CHANNEL DEBUG`.
- [ ] Senza una chiave reale in `/etc/wasalight/update-signers`, il canale
      `stable` si ferma chiaramente e non ripiega su `main`.
- [ ] Con una release stable immutabile e firmata, tag, `VERSION`, commit
      installato e chiave autorizzata coincidono; un tag non firmato viene rifiutato.
- [ ] Interrompendo intenzionalmente la VM durante l’installer, il pannello
      mostra `RECOVERY REQUIRED`; l’avvio grafico dell’update propone
      **Riprendi** e `--resume` riutilizza lo snapshot registrato.
- [ ] Dopo un errore successivo all’installazione, configurazione, canale e
      checkout precedente vengono ripristinati insieme.
- [ ] Il test UTM `verify-update-idempotency.sh`, avviato con la conferma
      `WASALIGHT_IDEMPOTENCY_CONFIRM=UTM-ONLY`, termina con `PASS` dopo due repair.
- [ ] Il log cumulativo ruota a 5 MiB e in `updates/` restano al massimo venti
      esecuzioni, nessuna più vecchia di trenta giorni.
- [ ] Il controllo di `libqxcb.so`, eseguito con le librerie incluse da MagicQ,
      non mostra dipendenze `not found`.
- [ ] `/usr/share/alsa/alsa.conf` esiste e `wasalight-audio-test` riproduce una
      volta i campioni Front Left e Front Right sul dispositivo predefinito.
- [ ] Gli eventuali avvisi `Unknown PCM` prodotti dall'enumerazione PortAudio
      sono distinti da errori reali: il test audio termina con successo e
      MagicQ completa l'inizializzazione.
- [ ] MagicQ parte senza barra del titolo; Tint2 resta visibile e utilizzabile
      sul bordo inferiore anche dopo una chiusura e un successivo avvio manuale.
- [ ] Openbox espone un solo desktop virtuale (`wmctrl -d` mostra una riga).
- [ ] Il pulsante di chiusura Openbox mostra una X netta e il bersaglio touch è
      sensibilmente più grande del tema Ubuntu standard; la maschera XBM è
      24×24 px e il font titolo a 28 amplia anche la vera area cliccabile.
      Gli stati normale, inattivo, hover rosso e pressione non deformano o
      fanno scomparire l'icona.
- [ ] In **Rollback Wasalight**, il tasto **Elimina snapshot** richiede una
      seconda conferma, rimuove archivio e checksum selezionati e non funziona
      in modalità SHOW.
- [ ] Il pannello Conky ha un fondo scuro semitrasparente e testo leggibile;
      avviando MagicQ fullscreen, Picom libera la finestra dal compositing.
- [ ] Con MagicQ fermo, i tre pulsanti desktop MagicQ/Spegni/Riavvia hanno icone grandi e leggibili
      al touch e si avviano con un solo tocco senza mostrare «Apri con…».
- [ ] `chamsys` non può cancellare, rinominare o spostare i launcher desktop.
- [ ] `stat -c '%U:%G %a %n' /home/chamsys/Desktop /home/chamsys/Desktop/*.desktop`
      mostra la directory `root:root 755` e tre launcher `root:root 444`.
- [ ] La scheda **MagicQ** di Wasalight Control usa l'icona ufficiale
      `/usr/share/pixmaps/magicq.png`, mostra MagicQ, MagicHD e MagicVis in tre
      schede touch uguali e offre il toggle **Avvio automatico**, senza un
      pulsante Ferma.
- [ ] Il toggle **Servizio attivo** di VNC avvia e ferma la condivisione del display `:0`;
      al primo avvio apre il terminale protetto per creare la password.
- [ ] Il toggle **Servizio attivo** di SSH avvia e ferma OpenSSH; lo stato mostra
      indirizzo, porta e tipo di attivazione (`MANUALE` oppure `AUTO`).
- [ ] **Spegni** e **Riavvia** mostrano sempre la conferma; **Annulla** non
      esegue azioni e la conferma completa correttamente l'operazione scelta.
- [ ] Ogni conferma mostra l'icona coerente con l'azione (alimentazione,
      riavvio, blocco, SSH, VNC, rollback o eliminazione) e non l'interrogativo
      generico di Zenity.
- [ ] Le conferme Wasalight sono centrate, ricevono subito il focus e restano in
      primo piano anche sopra MagicQ, browser e altre finestre massimizzate.
- [ ] Il pannello destro mostra CURRENT, NEXT BOOT, versione e stato MagicQ,
      data, log, rete/IP, touch, USB, VNC, SSH e audio con colori
      coerenti, senza mostrare letteralmente sequenze `${color ...}`.
- [ ] Il pannello e `wasalight-status` non mostrano la riga tecnica `SESSION`;
      `magicq-session`, PID, lock e log continuano però a funzionare internamente.
- [ ] Il pannello Tint2 resta sempre visibile, non mostra `desktop 1` e consente
      con un tocco di aprire Wasalight Control o selezionare un’applicazione.
- [ ] Le finestre attive e inattive mantengono colori scuri; il pulsante X è
      grande, facilmente premibile al touch e diventa rosso quando evidenziato.
- [ ] Wasalight Control mostra Stato, MagicQ, Servizi, Applicazioni,
      Supporto, Plugin e Crediti con pulsanti grandi e lascia Tint2 visibile.
- [ ] MagicQ e Servizi condividono intestazione, griglia a tre colonne e schede
      uniformi; testi, toggle e azioni restano allineati.
- [ ] File, Scanner IP e Art-Net Monitor compaiono in Applicazioni e non in
      Supporto.
- [ ] Mousepad compare in Applicazioni e apre l’editor di testo con un solo
      tocco.
- [ ] Crediti riporta Michele Moser / Wasabi Lightbulbfarm, Apache 2.0,
      protezione del logo, indirizzo, sito, email, GitHub, Instagram, Facebook,
      YouTube, LinkedIn e i riconoscimenti esterni.
- [ ] Icona, titolo e focus di Wasalight Control usano il verde Wasabi
      `#76bd22`; la scheda selezionata è verde scuro con sottolineatura Wasabi
      e tutte le pagine restano scure, senza grandi superfici bianche o verde acceso.
- [ ] Nella home Stato non compare File: il pulsante mostra **Passa a
      MAINTENANCE** in SHOW e **Passa a SHOW** in MAINTENANCE, prepara il boot
      selezionato e propone il riavvio.
- [ ] SSH e VNC compaiono soltanto in **Servizi**, non nella scheda **Plugin** e
      non come icone desktop, in Supporto o nel menu Openbox.
- [ ] Companion in **Plugin** offre Abilita/Disabilita e, quando installato,
      **Aggiorna**; quest'ultimo è attivo solo in MAINTENANCE.
- [ ] `wasalight-plugin list` mostra SSH, VNC e Companion; lo stato attivo
      coincide con processi/servizi reali e sopravvive al riavvio.
- [ ] **Avvio automatico** per SSH e VNC scrive i rispettivi flag sotto
      `/data/system/service-flags`; Conky mostra `AUTO` o `MANUAL` anche quando
      il servizio è fermo.
- [ ] Dopo un riavvio, SSH riparte soltanto con `ssh-autostart=enabled`; VNC
      riparte soltanto con `vnc-autostart=enabled` e una password VNC valida.
- [ ] MagicQ parte in SHOW soltanto con `magicq-autostart=enabled`; l'icona sul
      desktop e **Apri MagicQ** funzionano anche quando il flag è disabilitato.
- [ ] Entro circa 20 secondi dall'avvio, con rete disponibile, `wasalight-status`
      mostra `UPDATE: up to date` oppure la nuova versione senza finestre modali.
- [ ] In SHOW enable/disable di un plugin viene rifiutato chiaramente. In
      MAINTENANCE la modifica persiste sotto `/data/system/plugins-state` e un
      update ordinario non riabilita un plugin disabilitato.
- [ ] MagicHD e MagicVis avviati dal Control Center passano dal wrapper root ristretto,
      usano `/opt/magicq` come directory di lavoro e rimangono aperti.
- [ ] Un launcher registrato con `wasalight-app-register` compare nel Control Center e
      sopravvive al riavvio protetto; dopo `--remove` non compare più.
- [ ] **Scanner IP** elenca IP e MAC almeno del gateway o di un secondo host
      collegato alla stessa rete; una nuova scansione aggiorna la tabella.
- [ ] **Art-Net Monitor** mostra sorgente, universo e contatore quando un nodo o
      MagicQ trasmette ArtDMX; **Azzera** svuota correttamente l’elenco.
- [ ] **Monitor sistema** apre LXTask e aggiorna processi, CPU e memoria senza
      richiedere password o privilegi amministrativi.
- [ ] **Audit sistema** è apribile da Supporto e da terminale; mostra boot,
      servizi, porte, CPU, RAM, storage, rete e processi senza chiedere password
      e senza cambiare file, mount, pacchetti o servizi.
- [ ] Il clic destro mostra soltanto il menu Wasalight minimale, senza
      preferenze Openbox generiche.
- [ ] Il clic destro sullo sfondo continua ad aprire il menu Openbox.
- [ ] `chamsys` può creare, modificare e cancellare un file di prova nelle
      directory MagicQ persistenti e in `/data/log` senza usare `sudo`.
- [ ] `wasalight-touch-status` rileva tutti e soli i touchscreen collegati.
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
- [ ] SSH non è raggiungibile finché non viene attivato dal pulsante oppure
      installato con `--with-ssh` per l’avvio automatico.

## Bitfocus Companion opzionale

- [ ] Una prima installazione con `--with-companion` installa la versione
      indicata in `/etc/wasalight/companion-target-version` e abilita
      `companion.service` senza installare Docker.
- [ ] `systemctl status companion` mostra il processo eseguito dall'utente
      dedicato `companion`; MagicQ continua a funzionare dopo stop o restart
      del solo servizio Companion.
- [ ] Da un altro dispositivo della LAN la web UI risponde su
      `http://INDIRIZZO_WASALIGHT:8000`.
- [ ] `/home/companion` e `/etc/companion` risultano bind mount provenienti da
      `/data/companion`; una configurazione di prova resta presente dopo un
      riavvio in SHOW.
- [ ] Il pannello Conky e `wasalight-status` mostrano uno stato coerente; la scheda
      Plugin mostra versione, backup e aggiornamento, mentre Sistema mostra
      `INDIRIZZO:8000` accanto allo stato Companion.
- [ ] **Companion** in Applicazioni avvia Falkon su `http://127.0.0.1:8000`; se il servizio
      è fermo ne propone l'avvio e la finestra massimizzata lascia Tint2 visibile.
- [ ] Quando Companion è installato, il dock mostra il pulsante con l’icona
      ufficiale e lo nasconde su un’installazione senza Companion.
- [ ] La finestra Companion aperta in Falkon mostra nel taskbar Tint2 l'icona
      Companion, non l'icona generica Falkon (`WM_CLASS=WasalightCompanion`).
- [ ] Editor pulsanti, installazione moduli, drag-and-drop, WebSocket e feedback
      funzionano correttamente nel Falkon fornito da Ubuntu 24.04.
- [ ] Preferenze e cookie Falkon sopravvivono in `/data/companion/browser`, ma
      la cache sotto la directory runtime scompare al riavvio.
- [ ] Nel profilo Companion, Falkon mostra AdBlock disattivato; riavvio del
      browser e update Wasalight non lo riattivano e non rimuovono altri plugin.
- [ ] Falkon usa il tema scuro, pulsanti touch grandi e zoom 120%; campo indirizzo
      e Tint2 restano visibili, mentre preferiti, stato e la barra con una sola
      scheda sono nascosti.
- [ ] Chiudendo e riaprendo Falkon compare la home Companion senza ripristinare
      le vecchie schede. Dopo aver cambiato una preferenza, un update Wasalight
      non la riporta al valore iniziale.
- [ ] Avvio, arresto e riavvio da Control funzionano in SHOW senza chiedere password;
      backup e update vengono invece rifiutati fino al riavvio in MAINTENANCE.
- [ ] Un backup valido compare in `/data/companion/backups` e l'aggiornamento
      conserva lo stato precedente del servizio.
- [ ] Un modulo ChamSys MagicQ OSC o UDP configurato verso `127.0.0.1` riceve
      feedback ed esegue almeno un comando di prova.
- [ ] Una superficie USB supportata (per esempio Stream Deck) viene rilevata
      anche dopo scollegamento, ricollegamento e riavvio protetto.

## Chiavette USB

- [ ] In UTM, la chiavetta è assegnata alla VM dal pulsante **USB**; prima del
      pass-through è normale che non compaia né in `lsusb` né sotto `/stick`.
- [ ] Se UTM indica il dispositivo con **Disconnect…** ma `lsusb` non cambia,
      un arresto completo della VM seguito da riconnessione USB ripristina il
      redirect; non si interviene sugli script di mount finché manca `/dev/sdX`.
- [ ] Su Ubuntu minimale non ancora configurato, una chiavetta FAT32 non
      montata con MagicQ nella root viene rilevata dal bootstrap, montata in
      sola lettura, importata in `/data/system/packages` e smontata.
- [ ] La stessa prima installazione funziona con il `.deb` in `packages/`.
- [ ] Il bootstrap non monta root, boot, `/data` o un dispositivo non USB e non
      lascia mount attivi sotto `/run/wasalight-usb-scan` dopo un errore.
- [ ] Con un `.deb` MagicQ più recente nella root della USB, **Update
      Wasalight** lo valida, lo copia in `/data/system/packages` e lo installa.
- [ ] La stessa prova riesce collocando il file in `packages/` sulla USB.
- [ ] Il `.deb` originale resta invariato sulla chiavetta dopo l’aggiornamento.
- [ ] Un pacchetto non `magicq`, non `amd64` o precedente viene ignorato e due
      file della stessa versione con contenuto diverso bloccano l’operazione.
- [ ] FAT32, exFAT e NTFS vengono montati in `/stick/<dispositivo>` e sono
      visibili da MagicQ.
- [ ] Un container APFS non cifrato viene montato tramite `fsapfsmount`; i
      volumi `fsapfs1`, `fsapfs2`, ecc. sono leggibili da `chamsys` ma non
      consentono creazione, modifica o cancellazione di file.
- [ ] **Aggiorna Wasalight** trova un `.deb` nella radice o in `packages/` di un
      volume APFS; un container cifrato fallisce senza chiedere password sullo
      schermo dello show.
- [ ] Due o più chiavette collegate insieme restano tutte visibili nella vista
      Flash, ciascuna nella propria sottodirectory.
- [ ] Dopo la rimozione scompare soltanto la sottodirectory della chiavetta
      rimossa; le altre restano montate.
- [ ] Copia e rilettura di showfile grandi su ogni filesystem supportato.
- [ ] Prova controllata di rimozione subito dopo un salvataggio.
- [ ] Controllo filesystem della chiavetta su un’altra macchina dopo la prova.

## VNC temporaneo

- [ ] `wasalight-vnc-start` richiede una password al primo utilizzo.
- [ ] Il client remoto mostra la stessa sessione Openbox/MagicQ del monitor.
- [ ] `wasalight-status` mostra VNC attivo soltanto durante la condivisione.
- [ ] `wasalight-vnc-stop` chiude la porta 5900 e termina `x11vnc`.
- [ ] Senza il flag automatico, dopo un riavvio VNC resta fermo.
