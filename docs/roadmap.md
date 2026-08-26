# Roadmap Wasalight

Ultimo aggiornamento: 26 agosto 2026.

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
- [x] Prima USB montata direttamente in `/stick` per MagicQ; fino a otto
      supporti successivi stabili in `/stick2`–`/stick9`.
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
- [x] Abilitare `fstrim.timer` quando root o `/data` risiedono su SSD/NVMe con
      supporto discard rilevato. Usa TRIM periodico, non l'opzione mount
      `discard`, per non introdurre latenza durante lo show; l'esecuzione reale
      resta nella checklist hardware.
- [ ] Definire la politica swap sull’hardware reale dopo aver misurato RAM e
      carico MagicQ/Companion: conservare una swap di emergenza limitata oppure
      disabilitarla, senza confonderla con `overlayroot tmpfs:swap=0`.
- [x] Politica firewall definita: UFW disabilitato e rimosso per non interferire
      con MagicQ, Companion, Art-Net, sACN e OSC; protezione affidata alla rete
      tecnica a monte. SSH e VNC restano disabilitati finché non vengono
      attivati esplicitamente.
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
| `fstrim.timer` condizionale al supporto discard | Implementata |
| Politica swap | Da decidere dopo le misure |
| Politica firewall | UFW rimosso; protezione affidata alla rete tecnica a monte |
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
- [~] Pagina Rete touch integrata con Ethernet, Wi-Fi, DHCP, IP statico, DNS e
      fallback `nmtui` per configurazioni enterprise o legacy; resta da
      collaudare sulla macchina fisica.
- [x] Colore Wasabi `#76bd22`, font ridimensionati e pulsante Chiudi evidente.
- [x] Sistemare le icone dei messaggi di conferma (riavvio, spegnimento,
      blocco e operazioni analoghe), evitando l’interrogativo generico e
      mantenendo i dialoghi centrati e in primo piano.
- [x] SSH e VNC uniformati con toggle per stato e avvio automatico persistente.
- [x] MagicQ con toggle di avvio automatico e senza riavvio automatico dopo la
      chiusura.
- [x] MagicHD e MagicVis eseguiti tramite wrapper root ristretto.
- [x] File, Scanner IP, Art-Net Monitor e OSC Monitor nella pagina Applicazioni.
- [x] File manager, Mousepad, calcolatrice e monitor grafico LXTask.
- [x] Tastiera virtuale nel tray, eliminata dalla lista duplicata delle app;
      il toggle recupera anche un processo Onboard rimasto vivo ma invisibile.
- [x] Ridurre la geometria della tastiera Onboard di un ulteriore 20% rispetto
      alle dimensioni attuali, passando indicativamente da 80% × 30% a
      64% × 24% dello schermo, mantenere il tema Nightshade e impostare il font
      `DejaVu Sans condensed bold`, verificandone la leggibilità sul touch reale.
- [x] Sostituire il terminale **Touchscreen** con una pagina grafica in
      Wasalight Control per stato, associazione touch-monitor, rotazione,
      modalità automatica/ripristino e prova visiva a schermo intero,
      conservando il backend persistente `wasalight-touch`.
- [x] Blocco schermo manuale con password e senza risparmio energetico.
- [x] Strumento grafico per data, ora, sincronizzazione NTP e fuso orario.
- [x] Crediti, contatti, licenza, citazione e proprietà del logo.
- [x] Aggiungere un monitor OSC leggero per visualizzare indirizzo, porta,
      percorso OSC, argomenti e contatore dei messaggi ricevuti, senza
      interferire con le porte usate da MagicQ o Companion.

## Fase 2 — Companion, browser e plugin

- [x] Bitfocus Companion opzionale, isolato da MagicQ e persistente in `/data`.
- [x] Versione Companion fissata nel manifesto della release.
- [x] Companion aggiornato alla versione stabile upstream 5.0.4.
- [x] Abilitazione, disabilitazione, avvio, arresto, backup e aggiornamento.
- [x] Icona ufficiale Companion in Control, dock e taskbar Falkon.
- [x] Falkon leggero con profilo persistente, tema scuro, zoom touch e AdBlock
      disabilitato.
- [x] Correggere nel browser Companion i pulsanti dello zoom già presenti ma
      privi di etichetta visibile, mostrando chiaramente `−` e `+` e mantenendo
      dimensioni adeguate all'uso touch.
- [x] Browser web generico con profilo persistente separato da Companion,
      navigazione completa e controlli touch.
- [x] Profilo Companion senza bookmark, campo ricerca aggiuntivo o ripristino
      indesiderato delle schede.
- [x] Framework plugin con manifest, dipendenze, stato persistente e bundle USB.
- [x] SSH, VNC e Companion gestiti in sezioni coerenti senza icone duplicate.
- [x] Registro estensibile delle applicazioni per programmi futuri.
- [ ] Collaudare una superficie USB reale supportata da Companion, per esempio
      Stream Deck, insieme a MagicQ durante uno show di prova.

## Fase 3 — Manutenzione, backup e diagnostica

- [x] Controllo salute di filesystem, spazio, RAM, temperatura e SMART una
      volta all’avvio e all’apertura di Wasalight Control, senza timer o log
      periodici persistenti.
- [x] Audit di sistema in sola lettura con boot, servizi, porte, CPU, memoria,
      storage, TRIM, rete e processi.
- [x] Esportazione di un pacchetto diagnostico con checksum.
- [x] Backup completo di `/data` su USB, anche cifrato.
- [x] Ripristino completo o delle sole applicazioni su una macchina nuova.
- [x] Wizard del primo avvio.
- [x] Snapshot Wasalight prima degli aggiornamenti.
- [x] Interfaccia rollback con verifica checksum e cancellazione protetta da
      doppia conferma.
- [x] Log MagicQ, updater e servizi persistenti con rotazione limitata; stato
      salute conservato soltanto nel runtime volatile.
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
- [x] Da SHOW, conferma e riavvio guidato in MAINTENANCE, aggiornamento
      automatico visibile e ritorno a SHOW soltanto dopo verifica riuscita;
      gli errori lasciano la macchina in MAINTENANCE senza ciclo di reboot.
- [x] Nessuna reinstallazione se versione, commit e stato richiesto coincidono.
- [x] Protezione da modifiche Git locali, downgrade e riscritture non
      fast-forward.
- [x] Correzione della collisione tra stato readonly e libreria updater.
- [~] Ripetere sulla ISO candidata il test UTM di `--plan` senza modifiche
      persistenti.
- [~] Ripetere `verify-update-idempotency.sh` dopo due repair consecutivi.
- [~] Verificare sulla ISO candidata `RECOVERY REQUIRED` e `--resume` dopo
      un’interruzione volontaria durante l’installer.
- [~] Verificare sulla ISO candidata il ripristino coordinato di configurazione,
      canale e checkout dopo un errore post-installazione.
- [ ] Creare chiave, tag e prima GitHub Release stable immutabile e firmata.
- [ ] Verificare il rifiuto di tag stable non firmati o firmati da chiavi non
      autorizzate.

## Fase 6 — Installazione e aggiornamento MagicQ offline

Il collaudo con una USB fisica è esplicitamente differito alla Fase 8. La nuova
installazione da zero deve verificare anche i percorsi offline prima della
prima release stable.

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
- [x] Integrazione in Wasalight Control, policy Polkit, log dedicato e opzioni
      `--scan-only` e `--reinstall`.
- [x] Rendere esplicita l'installazione offline nella GUI: mantenere aperta per
      tutta l'operazione una finestra non annullabile con le fasi ricerca,
      copia, verifica dipendenze, installazione e controllo finale, quindi
      mostrare il risultato conclusivo già previsto.
- [~] Collaudare `--scan-only` e una reinstallazione reale dentro un namespace
      UTM senza rete, verificando dpkg, librerie e launcher sulla ISO candidata.
- [ ] Ripetere durante il collaudo hardware della Fase 8 la prova con il `.deb`
      nella root e in `packages/` di una USB fisica assegnata alla VM.
- [ ] Verificare nella stessa prova differita che il `.deb` originale sulla USB
      resti invariato e che la copia persistente in `/data` abbia lo stesso
      checksum.

## Fase 7 — Localizzazione completa

- [x] Usare `/data/system/control/language` come unica preferenza di lingua;
      applicazione alla sessione verificata in UTM dopo un nuovo login.
- [x] Supportare italiano, inglese e modalità automatica per tutta la sessione;
      `it` ed `en` sono espliciti, mentre `auto` segue correttamente la locale
      di sistema (`C.UTF-8`, quindi inglese, nella VM di prova).
- [x] Conservare `wasalight-control` per la GUI e introdurre il dominio gettext
      `wasalight-system`; infrastruttura, dialoghi e utility grafiche completati.
- [x] Tradurre menu Openbox, tooltip, conferme, errori e testi dell’updater;
      menu, alimentazione e interfaccia guidata updater completati; log e
      diagnostica tecnica uniformati in inglese; utility operative completate.
- [x] Usare campi standard `Name[it]` e `Comment[it]` nei launcher `.desktop`.
- [x] Aggiungere campi localizzati ai manifest dei plugin.
- [x] Eliminare testo traducibile incorporato nelle icone; le icone distribuite
      non contengono elementi testuali.
- [x] Estendere i controlli qualità per validare i cataloghi, bloccare traduzioni
      italiane mancanti e verificare campi localizzati di launcher e plugin.
- [x] Collaudare in UTM il cambio lingua dopo un nuovo accesso in `it`, `en` e
      `auto`, includendo desktop, Control, menu Openbox, updater e conferme.
- [x] Localizzare anche gli stati dinamici della Panoramica (MagicQ, SSH, VNC e
      aggiornamenti) senza tradurre numeri di versione, porte o dati tecnici.
- [x] Portare esplicitamente in primo piano la prima finestra di Wasalight
      Control dopo il mapping, evitando che PCManFM la lasci dietro al desktop.
- [x] Correggere **Data e ora**: apertura sempre visibile, errore esplicito se
      il processo non parte e nessun fallimento silenzioso dal launcher.
- [x] Semplificare la pagina **Tools** rimuovendo i duplicati **Rete**, **Stato
      sistema**, **Salute sistema**, **Audit sistema** e **Aggiorna Wasalight**;
      conservare la pagina Rete, il controllo salute automatico, i comandi
      tecnici e l'aggiornamento nella Panoramica.
- [x] Mantenere **Esporta diagnostica**, rinominandolo **Esporta diagnostica per
      assistenza** e chiarendo che crea un archivio privo di password, show
      MagicQ e configurazioni private.
- [x] Rimuovere dai messaggi e dagli avvisi visibili all'operatore ogni
      riferimento a UTM, che è una macchina di sviluppo privata; conservarlo
      soltanto nella documentazione e nelle procedure interne di collaudo.
- [x] Unificare `wasalight-touch-watch` e `wasalight-pointer-watch` in un solo
      gestore dell'input che rilevi touchscreen, mouse e monitor e pubblichi
      uno stato runtime condiviso sotto `/run`.
- [x] Eliminare le interrogazioni duplicate di touchscreen, rete, MagicQ, SSH
      e VNC creando una sola fotografia di stato condivisa da Conky,
      Wasalight Control, `wasalight-status` e diagnostica.
- [x] Sostituire il polling MagicQ continuo: usare una regola Openbox o un
      evento X11 per il fullscreen e cercare aggiornamenti `.deb` soltanto in
      risposta al montaggio di una USB.
- [x] Ridurre la frequenza degli aggiornamenti puramente informativi, portando
      indicativamente Conky e il refresh periodico di Wasalight Control a 10
      secondi senza rallentare pulsanti e operazioni manuali.
- [x] Prima della prima Stable rimuovere le compatibilità nate durante le RC:
      alias storico `offline` del builder, nomi alternativi del canale update,
      migrazioni di vecchi launcher e percorsi destinati esclusivamente alle
      installazioni di sviluppo precedenti.
- [x] Dopo l'unificazione dello stato mantenere i backend di salute, audit e
      diagnostica, ma farli usare dalla raccolta condivisa e non reintrodurre
      nella pagina Tools i pulsanti ridondanti già rimossi.
- [x] Al termine delle ottimizzazioni riesaminare tutti i pacchetti runtime e
      rimuovere soltanto dipendenze divenute realmente inutilizzate, senza
      eliminare backup, rollback, salute automatica, NetworkManager o gli
      strumenti necessari all'assistenza.

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
