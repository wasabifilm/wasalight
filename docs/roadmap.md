# Roadmap Wasalight

Ultimo aggiornamento: 21 agosto 2026.

Questo documento è la fonte permanente per le funzionalità richieste e il loro
stato. La [checklist hardware](hardware-test-checklist.md) resta invece la fonte
per le prove da eseguire su UTM e sulle macchine fisiche. Una funzione può
quindi risultare implementata qui, ma ancora non collaudata sulla checklist.

Legenda:

- `[x]` implementato e presente nel repository;
- `[~]` implementato, ma ancora da pubblicare o collaudare completamente;
- `[ ]` pianificato e non ancora implementato.

## Fase 0 — Piattaforma e sicurezza di base

- [x] Ubuntu Server 24.04 LTS minimale amd64 come piattaforma supportata.
- [x] Xorg, Openbox, autologin `chamsys` e interfaccia adatta al touchscreen.
- [x] Partizione ext4 separata montata in `/data` per i dati persistenti.
- [x] SHOW protetto tramite overlayroot e MAINTENANCE scrivibile.
- [x] NetworkManager come unico gestore persistente della rete.
- [x] Supporti USB distinti sotto `/stick/<dispositivo>`.
- [x] Utente `chamsys` amministratore con password scelta dall’installatore.
- [x] MagicQ eseguito con il launcher root ristretto verificato sull’hardware.
- [x] Dipendenze OpenGL, GLU, XCB, Qt e ALSA richieste da MagicQ.
- [x] Dati, show, configurazioni e log MagicQ persistenti sotto `/data`.
- [x] Pulizia sicura di Snap, stampa, Bluetooth, ModemManager, Avahi, servizi
      cloud e componenti storage non utilizzati.
- [x] Rimozione di `os-prober` e configurazione GRUB per appliance a sistema
      singolo.
- [x] Disattivazione di sospensione, ibernazione, DPMS e aggiornamenti automatici.
- [x] Mount persistenti con `noatime`; `/tmp`, `/var/tmp` e journald resi
      volatili per ridurre le scritture sul disco di sistema.
- [x] Chrony per la sincronizzazione dell’orologio e SMART per la diagnostica
      dello storage.
- [ ] Abilitare e verificare `fstrim.timer` quando root o `/data` risiedono su
      SSD/NVMe con supporto discard. Usare TRIM periodico, non l’opzione mount
      `discard`, per non introdurre latenza durante lo show.
- [ ] Definire la politica swap sull’hardware reale dopo aver misurato RAM e
      carico MagicQ/Companion: conservare una swap di emergenza limitata oppure
      disabilitarla, senza confonderla con `overlayroot tmpfs:swap=0`.
- [ ] Definire e documentare la politica firewall definitiva: inventariare
      prima le porte necessarie a MagicQ, Companion, SSH, VNC, Art-Net, sACN e
      OSC, quindi scegliere consapevolmente tra firewall disabilitato oppure
      regole minime. Non rimuoverlo alla cieca prima del collaudo di rete.
- [ ] Misurare sul computer fisico tempi di boot, CPU, RAM, temperature,
      governor, latenza di rete e attività disco; applicare ulteriori
      ottimizzazioni solo se i dati mostrano un vantaggio reale.
- [ ] Dopo le misure, decidere esplicitamente governor CPU, scheduler I/O ed
      eventuale uso di `irqbalance`/`thermald`; mantenere i valori Ubuntu quando
      una modifica non produce un miglioramento ripetibile.

### Registro ottimizzazioni di sistema

Questo registro evita di confondere un dato mostrato dall’audit con una
configurazione realmente applicata:

| Ottimizzazione | Stato |
| --- | --- |
| Pulizia pacchetti e servizi estranei | Implementata |
| NetworkManager unico gestore di rete | Implementata |
| APT automatico e `unattended-upgrades` disabilitati | Implementata |
| `/tmp`, `/var/tmp` e journald volatili | Implementata |
| Mount `/data` con `noatime` | Implementata |
| Sospensione, ibernazione, screensaver e DPMS disabilitati | Implementata |
| Chrony e strumento grafico data/fuso | Implementata |
| SMART, temperature, governor e TRIM mostrati nell’audit | Implementata |
| `fstrim.timer` abilitato e verificato | Da fare |
| Politica swap | Da decidere dopo le misure |
| Politica firewall | Da decidere dopo il collaudo delle porte |
| Governor CPU e scheduler I/O personalizzati | Da misurare prima di cambiare |
| `irqbalance` e `thermald` | Da valutare sull’hardware fisico |

## Fase 1 — Desktop touch e Wasalight Control

- [x] Desktop singolo con sfondo coordinato al boot e logo Wasabi.
- [x] Dock Tint2 sempre visibile, scuro e utilizzabile con il touch.
- [x] Icone desktop protette per MagicQ, spegnimento e riavvio.
- [x] Pulsante X Openbox più grande, tema scuro e stati hover/pressione.
- [x] Conky semitrasparente con stato, modalità, versione, rete e servizi.
- [x] Rimozione della riga tecnica `SESSION` dall’interfaccia operatore.
- [x] Wasalight Control a istanza singola, con pagine Stato, MagicQ, Servizi,
      Applicazioni, Supporto, Plugin e Crediti.
- [x] Colore Wasabi `#76bd22`, font ridimensionati e pulsante Chiudi evidente.
- [x] Conferme centrate, in primo piano e con icone coerenti con l’azione.
- [x] SSH e VNC uniformati con toggle per stato e avvio automatico persistente.
- [x] MagicQ con toggle di avvio automatico e senza riavvio automatico dopo la
      chiusura.
- [x] MagicHD e MagicVis eseguiti tramite wrapper root ristretto.
- [x] File, Scanner IP e Art-Net Monitor nella pagina Applicazioni.
- [x] File manager, Mousepad, calcolatrice e monitor grafico LXTask.
- [x] Tastiera virtuale nel tray, eliminata dalla lista duplicata delle app.
- [x] Blocco schermo manuale con password e senza risparmio energetico.
- [x] Strumento grafico per data, ora, sincronizzazione NTP e fuso orario.
- [x] Crediti, contatti, licenza, citazione e proprietà del logo.
- [ ] Aggiungere un monitor OSC leggero per visualizzare indirizzo, porta,
      percorso OSC, argomenti e contatore dei messaggi ricevuti, senza
      interferire con le porte usate da MagicQ o Companion.

## Fase 2 — Companion, browser e plugin

- [x] Bitfocus Companion opzionale, isolato da MagicQ e persistente in `/data`.
- [x] Versione Companion fissata nel manifesto della release.
- [x] Abilitazione, disabilitazione, avvio, arresto, backup e aggiornamento.
- [x] Icona ufficiale Companion in Control, dock e taskbar Falkon.
- [x] Falkon leggero con profilo persistente, tema scuro, zoom touch e AdBlock
      disabilitato.
- [x] Profilo Companion senza bookmark, campo ricerca aggiuntivo o ripristino
      indesiderato delle schede.
- [x] Framework plugin con manifest, dipendenze, stato persistente e bundle USB.
- [x] SSH, VNC e Companion gestiti in sezioni coerenti senza icone duplicate.
- [x] Registro estensibile delle applicazioni per programmi futuri.
- [ ] Collaudare una superficie USB reale supportata da Companion, per esempio
      Stream Deck, insieme a MagicQ durante uno show di prova.

## Fase 3 — Manutenzione, backup e diagnostica

- [x] Salute periodica di filesystem, spazio, RAM, temperatura e SMART.
- [x] Audit di sistema in sola lettura con boot, servizi, porte, CPU, memoria,
      storage, TRIM, rete e processi.
- [x] Esportazione di un pacchetto diagnostico con checksum.
- [x] Backup completo di `/data` su USB, anche cifrato.
- [x] Ripristino completo o delle sole applicazioni su una macchina nuova.
- [x] Wizard del primo avvio.
- [x] Snapshot Wasalight prima degli aggiornamenti.
- [x] Interfaccia rollback con verifica checksum e cancellazione protetta da
      doppia conferma.
- [x] Log MagicQ, updater, salute e servizi persistenti con rotazione limitata.
- [ ] Collaudare backup e ripristino completi su una seconda installazione reale,
      verificando show, rete, Companion, plugin, permessi, ACL e attributi estesi.

## Fase 4 — Installer, qualità e versioni

- [x] Installer monolitico suddiviso in moduli e template rootfs testabili.
- [x] Installer principale ridotto a orchestratore delle fasi.
- [x] Manifesto unico per Ubuntu, Wasalight, Companion e riferimenti esterni.
- [x] Versione CalVer `AAAA.MM.GG.BUILD` mostrata sul sistema.
- [x] Lock globale con `flock` per installer, updater, snapshot, backup,
      ripristino e operazioni MagicQ.
- [x] Suite statica separata per dominio e test comportamentali.
- [x] CI con ShellCheck, Ruff, gettext, systemd, desktop-file-validate e link
      della documentazione obbligatori.
- [x] Builder della ISO minimale senza pubblicare file ISO nel repository Git.
- [ ] Generare e collaudare una nuova ISO minimale dopo la stabilizzazione della
      prima release firmata.

## Fase 5 — Updater transazionale

- [x] Canale `debug` dal ramo `main` e canale `stable` da release GitHub.
- [x] Download con timeout e retry, checkout candidato e attivazione atomica.
- [x] `--plan`, `--repair`, `--resume`, `--rollback` e `--code-only`.
- [x] Snapshot, stato transazionale, log per esecuzione e rollback automatico.
- [x] Interfaccia touch con autenticazione grafica Polkit e avanzamento visibile.
- [x] Nessuna reinstallazione se versione, commit e stato richiesto coincidono.
- [x] Protezione da modifiche Git locali, downgrade e riscritture non
      fast-forward.
- [x] Correzione della collisione tra stato readonly e libreria updater.
- [x] Test UTM di `--plan` senza modifiche persistenti.
- [ ] Completare `verify-update-idempotency.sh` dopo due repair consecutivi.
- [ ] Interrompere volontariamente la VM durante l’installer e verificare
      `RECOVERY REQUIRED` e `--resume`.
- [ ] Provocare un errore successivo all’installazione e verificare il ripristino
      coordinato di configurazione, canale e checkout.
- [ ] Creare chiave, tag e prima GitHub Release stable immutabile e firmata.
- [ ] Verificare il rifiuto di tag stable non firmati o firmati da chiavi non
      autorizzate.

## Fase 6 — Installazione e aggiornamento MagicQ offline

Il collaudo con una USB fisica è esplicitamente differito alla Fase 8 e non
blocca l'integrazione della funzione, già verificata offline in UTM usando gli
stessi percorsi di ricerca e preservazione del pacchetto.

- [~] Durante la prima installazione proporre ricerca USB, continuazione senza
      MagicQ oppure annullamento.
- [~] Mostrare **Installa MagicQ** sul desktop quando il pacchetto manca e
      sostituirlo con **MagicQ** dopo l’installazione.
- [~] Comando dedicato `wasalight-magicq-install`, separato dall’aggiornamento
      completo di Wasalight.
- [~] Ricerca in `/data/system/packages`, root USB, `packages/` e volumi APFS
      montati.
- [~] Installazione senza Internet, Git, `apt update` o download di dipendenze.
- [~] Simulazione preventiva, blocco dipendenze mancanti, downgrade e pacchetti
      della stessa versione con contenuto diverso.
- [~] Integrazione in Wasalight Control, policy Polkit, log dedicato e opzioni
      `--scan-only` e `--reinstall`.
- [x] Pubblicare il ramo `codex/magicq-offline-installer` e aprire la draft PR
      #31 con CI verde.
- [x] Installare la build `2026.08.21.1` in UTM.
- [x] Collaudare `--scan-only` e una reinstallazione reale dentro un namespace
      UTM senza rete, verificando dpkg, librerie e launcher.
- [ ] Ripetere durante il collaudo hardware della Fase 8 la prova con il `.deb`
      nella root e in `packages/` di una USB fisica assegnata alla VM.
- [ ] Verificare nella stessa prova differita che il `.deb` originale sulla USB
      resti invariato; il pacchetto persistente in `/data` è già risultato
      invariato nel test offline UTM.
- [~] Unire la fase in `main` dopo il collaudo UTM; la prova USB fisica resta
      tracciata come verifica hardware successiva.

## Fase 7 — Localizzazione completa

- [~] Usare `/data/system/control/language` come unica preferenza di lingua;
      applicazione alla sessione implementata, ancora da collaudare in UTM.
- [~] Supportare italiano, inglese e modalità automatica per tutta la sessione;
      ambiente Openbox implementato, ancora da verificare dopo un nuovo login.
- [~] Conservare `wasalight-control` per la GUI e introdurre il dominio gettext
      `wasalight-system`; infrastruttura e dialoghi alimentazione completati,
      migrazione degli altri strumenti in corso.
- [~] Tradurre menu Openbox, tooltip, conferme, errori e testi dell’updater;
      menu, alimentazione e interfaccia guidata updater completati; motore
      updater e altri strumenti in corso.
- [x] Usare campi standard `Name[it]` e `Comment[it]` nei launcher `.desktop`.
- [ ] Aggiungere campi localizzati ai manifest dei plugin.
- [ ] Eliminare testo traducibile incorporato nelle icone.
- [ ] Estendere i controlli qualità per rilevare stringhe utente non catalogate.
- [ ] Collaudare il cambio lingua dopo un nuovo accesso in `it`, `en` e `auto`.

## Fase 8 — Collaudo hardware e prima release stabile

- [ ] Completare tutte le prove della checklist su UTM.
- [ ] Ripetere le prove su HP EliteDesk 800 G3 Mini o hardware equivalente.
- [ ] Verificare boot silenzioso, logo anticipato, risoluzioni diverse e accesso
      al menu di recupero GRUB.
- [ ] Verificare touchscreen singolo, più display, rotazione e hot-plug.
- [ ] Verificare accelerazione grafica, fullscreen e pulsante X con MagicQ reale.
- [ ] Verificare audio ALSA e distinguere warning PortAudio da errori reali.
- [ ] Verificare USB multiple FAT32, exFAT, NTFS, ext4 e APFS in sola lettura.
- [ ] Verificare interfacce USB ChamSys, Art-Net, sACN e OSC sulla rete show.
- [ ] Verificare SSH, VNC e Companion su una rete reale controllata.
- [ ] Eseguire prove di spegnimento improvviso e riavvio ripetuto in SHOW.
- [ ] Eseguire backup, sostituzione macchina e ripristino completo.
- [ ] Pubblicare la prima release stable soltanto dopo il collaudo firmato.

## Richieste precedenti recuperate dalla cronologia

Queste richieste erano presenti nelle liste e conversazioni precedenti. Sono
riportate esplicitamente per evitare che vadano perse:

- [x] logo Wasabi nel boot e come sfondo desktop;
- [x] avvio Xorg senza testi visibili;
- [x] icone touch e barra scura non auto-nascosta;
- [x] pulsanti spegnimento, riavvio, rete, tastiera e Companion;
- [x] una sola istanza di Wasalight Control;
- [x] avvio MagicQ automatico una volta, ma non riavvio dopo la chiusura;
- [x] persistenza separata di log nativi MagicQ e log Wasalight;
- [x] più USB contemporanee visibili in `/stick`;
- [x] APFS in sola lettura;
- [x] Companion opzionale e aggiornabile;
- [x] Falkon personalizzato con icona Companion;
- [x] plugin, applicazioni future e interfaccia unificata;
- [x] aggiornamento grafico con password Polkit;
- [x] rollback grafico e cancellazione snapshot;
- [x] backup/ripristino completo di `/data`;
- [x] calcolatrice, Mousepad, monitor sistema, data/ora e lock screen;
- [x] tastiera virtuale nel tray;
- [x] audit di sistema e CI completa;
- [x] installer modulare, lock globale e manifest unico;
- [x] canali aggiornamento stable/debug;
- [~] installazione e aggiornamento MagicQ offline;
- [ ] monitor OSC;
- [ ] politica firewall e ottimizzazioni misurate;
- [ ] TRIM periodico e politica swap;
- [ ] localizzazione completa dell’intero desktop;
- [ ] collaudo hardware e prima release stable firmata.
