# Aggiornare Wasalight

Wasalight mantiene codice e pacchetti necessari agli aggiornamenti sulla
partizione persistente `/data`, fuori dall’overlay del sistema.

L'interfaccia guidata segue la lingua selezionata in Wasalight Control. L'output
del motore root e i log persistenti restano intenzionalmente in inglese tecnico,
così una stessa diagnosi è ricercabile e confrontabile su tutte le appliance.

Installer, aggiornamento, snapshot, backup e ripristino condividono un lock
globale basato su `flock`. Se una seconda operazione mutante viene avviata
mentre la prima è ancora attiva, termina senza modificare dati e mostra
`Operazione Wasalight già in corso`, insieme all’operazione e al PID registrati.
I processi figli autorizzati, come lo snapshot creato dall’updater, ereditano lo
stesso lock e possono completare la transazione senza bloccarsi tra loro.

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
/data/system/update-channel
                         canale persistente: stable oppure debug
/data/system/update-state
                         stato atomico della transazione e fase corrente
/data/system/wasalight.candidate
                         checkout candidato, mai attivo prima dei controlli
/data/system/update-backups
                         ultimi cinque snapshot pre-aggiornamento
/etc/wasalight/commit    commit Git realmente installato
/data/system/installed-commit
                         copia persistente del commit installato
/etc/wasalight/update-signers
                         chiavi SSH autorizzate per firmare le release stable
```

Il repository pubblico non contiene il pacchetto MagicQ. Il `.deb` viene
copiato separatamente, verificato byte per byte e protetto con permessi
`root:root 0640`.

Durante ogni esecuzione l’updater mostra canale, versione e commit installati e, dopo
il download, versione e commit disponibili. Entrambi vengono registrati solo
dopo un’installazione conclusa e verificata. Un downgrade, una riscrittura non
fast-forward di `main` o lo stesso numero `VERSION` pubblicato da un commit
differente vengono bloccati.

## Aggiornare MagicQ da USB

Copiare il pacchetto `.deb` di MagicQ in una delle due posizioni della
chiavetta, senza rinominarlo obbligatoriamente:

```text
MAGICQ_USB/*.deb
MAGICQ_USB/packages/*.deb
```

Dopo il montaggio automatico in `/stick/<dispositivo>`, entrare in MAINTENANCE
e scegliere **Installa o aggiorna MagicQ** nella pagina MagicQ di Wasalight
Control oppure usare:

```bash
sudo wasalight-magicq-install
```

Il comando aggiorna soltanto MagicQ: non esegue `git`, `apt update`, download o
un reinstall completo di Wasalight. Controlla tutte le USB effettivamente
montate, non le directory residue, e accetta soltanto un archivio Debian integro
con `Package: magicq`, `Architecture: amd64` e una versione Debian valida.

Il file scelto viene copiato in `/data/system/packages` e verificato byte per
byte; l’originale sulla chiavetta non viene mai spostato o cancellato. Versioni
precedenti vengono ignorate. Due pacchetti con la stessa versione ma contenuto
diverso bloccano l’operazione, evitando una sostituzione ambigua. Fra più USB e
più file viene selezionata la versione più recente usando i metadati Debian,
non il nome del file.

Prima di modificare MagicQ viene simulata l’installazione con download
disabilitati. Se manca anche una sola dipendenza o APT dovrebbe installare un
altro pacchetto, l’operazione termina lasciando MagicQ invariato e indica i
componenti da predisporre. L’installazione reale passa direttamente a `dpkg`
l’archivio locale verificato, quindi resta offline anche quando la macchina ha
una connessione di rete e non può modificare altre dipendenze.
`--scan-only` importa e mostra il candidato senza installarlo; `--reinstall`
consente di reinstallare intenzionalmente la stessa versione. I downgrade sono
bloccati.

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

Quando l’installazione parte da un clone Git verificabile, l’installer inizializza
il repository persistente copiando direttamente quella sorgente: la prima
installazione non dipende da una seconda connessione a GitHub. Se la sorgente
iniziale non contiene i metadati Git, il primo aggiornamento crea normalmente il
checkout candidato dal remoto.

## Canali stable e debug

Il canale predefinito è `stable`. Non segue un ramo mobile: legge l’ultima
GitHub Release, richiede che non sia bozza o prerelease e che sia stata resa
immutabile, quindi scarica il relativo tag `vAAAA.MM.GG.BUILD`. Il tag deve
essere annotato e firmato con una chiave SSH presente in
`/etc/wasalight/update-signers`; `VERSION` deve coincidere esattamente con il
nome del tag. Se una di queste verifiche manca, l’update si ferma. Non passa mai
automaticamente a `main`.

Il canale `debug` segue invece l’ultimo commit di `refs/heads/main`. Esegue gli
stessi controlli di progetto, versione, downgrade e fast-forward, ma non richiede
la firma del tag perché serve a collaudare codice non ancora pubblicato come
release. Va usato sulle macchine di sviluppo e su UTM, non sulle console dello
show.

```bash
sudo wasalight-update --channel stable
sudo wasalight-update --channel debug
wasalight-update-terminal --channel debug
```

La scelta viene salvata in `/data/system/update-channel` soltanto dopo un esito
positivo. Anche il controllo automatico all’avvio usa quel canale: per `stable`
legge la release immutabile, per `debug` legge `VERSION` da `main`. La riga
`CHANNEL` compare sia in `wasalight-status` sia nel pannello desktop.

Il repository include intenzionalmente soltanto un file signatari di esempio.
Prima della prima release stable va inserita la chiave pubblica reale nel formato
OpenSSH `allowed_signers`, mentre la chiave privata resta fuori dal repository e
dalle console. Finché questo passaggio non viene eseguito, `stable` fallisce in
modo esplicito; `debug` rimane disponibile per il collaudo.

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
Si apre una finestra scura con i colori Wasalight e fasi leggibili:
controllo del pacchetto MagicQ, download, verifica e installazione. Le operazioni
lunghe mostrano un indicatore animato, il tempo trascorso e il nome del modulo
installer corrente (25 passaggi), così è sempre evidente
che l’aggiornamento sta proseguendo. Prima di modificare il sistema, l’agente
grafico Polkit mostra una finestra centrata per la password amministrativa di
`chamsys`; la password non viene digitata nel terminale e non viene salvata.
Il terminale usa una vista compatta: nasconde l’output ripetitivo di Git, test,
snapshot, APT e initramfs, ma conserva ogni riga nei log. Con `--verbose` mostra
anche l’output grezzo. Poiché al termine è comunque necessario riavviare,
`needrestart` non esegue il proprio riepilogo intermedio; inoltre GRUB e
initramfs non ereditano il descrittore del lock globale, evitando il falso warning
di LVM senza rilasciare la protezione dell’aggiornamento. Se l’autenticazione
viene annullata, l’aggiornamento termina senza modificare il sistema. Al termine
compare un grande pulsante
**Riavvia ora**; scegliendo **Più tardi** l’aggiornamento resta installato e viene
ricordato che il riavvio è ancora necessario. Non occorre più premere Invio per
chiudere la finestra, quindi il flusso è utilizzabile interamente al touch.

In caso di errore non viene mai eseguito il riavvio automatico: il terminale
mostra le ultime righe dell’output grezzo, poi fase, comando, linea e codice di
uscita. Il log completo della singola esecuzione resta in
`/data/log/wasalight/updates/`, mentre
`/data/log/wasalight-update.log` conserva la cronologia cumulativa. Il registro
cumulativo viene ruotato a 5 MiB mantenendo cinque copie compresse; dei log per
singola esecuzione restano al massimo i venti più recenti e nessuno oltre
trenta giorni.
Prima di modificare il sistema viene creato uno snapshot verificato della
configurazione Wasalight, dei manifest e dei comandi installati. Se l’installer
fallisce, l’updater tenta automaticamente di ripristinarlo e indica il percorso
dello snapshot. I pacchetti Ubuntu già aggiornati da APT non vengono
downgradati: il rollback riguarda la configurazione dell’appliance.
Ogni transazione registra in modo atomico stato, fase, versione, commit, canale,
checkout candidato, snapshot e orario in `/data/system/update-state`. Un arresto
improvviso lascia quindi informazioni sufficienti per scegliere consapevolmente:

```bash
sudo wasalight-update --resume
sudo wasalight-update --repair
sudo wasalight-update --rollback
```

`--resume` riutilizza lo snapshot esistente e ripete le fasi idempotenti;
`--repair` forza una reinstallazione verificata; `--rollback` preferisce lo
snapshot associato alla transazione interrotta. Senza una di queste opzioni, uno
stato `running` o `failed` blocca un nuovo aggiornamento e mostra i tre comandi.
Se l’installazione fallisce, configurazione, canale e checkout precedente vengono
ripristinati insieme quando possibile. Il pannello desktop segnala
`RECOVERY REQUIRED` finché la situazione non è conclusa.

L’helper temporaneo viene interpretato esplicitamente con Bash, quindi funziona
anche con `/run` montato `noexec`. Se la creazione fallisce, l’errore viene
mostrato una sola volta e l’installer non viene avviato.

Ad ogni avvio grafico un controllo asincrono confronta la versione installata
con `VERSION` pubblicato su GitHub. Non rallenta Openbox o MagicQ, non installa
nulla e, in assenza di rete, termina senza finestre di errore. Quando trova una
release nuova mostra una notifica discreta. La riga `UPDATE` di
`wasalight-status` e quella del pannello desktop leggono lo stesso risultato del
controllo remoto e riportano la versione disponibile, anche prima che il checkout
persistente venga aggiornato.

Il refresh di Wasalight Control esegue in parallelo stato, registro plugin e
stato MagicQ. Le sonde lente, come il rilevamento XInput del touchscreen, hanno
un limite proprio e non possono più consumare l’intero tempo del pannello. La
soglia del Control resta più ampia per tollerare hardware o VM momentaneamente
occupati senza mostrare un falso errore di timeout.

Ad ogni utilizzo il comando:

1. cerca MagicQ nella root e in `packages/` di ogni USB montata;
2. valida nome del pacchetto, formato, versione e architettura `amd64`;
3. conserva in `/data/system/packages` soltanto candidati non precedenti;
4. prepara un checkout candidato separato con timeout e fino a tre tentativi;
5. verifica fast-forward, commit, `VERSION` e assenza di downgrade;
6. esegue `tests/verify-project.sh` sul checkout candidato;
7. sincronizza l’orologio tramite Chrony prima di snapshot e operazioni APT;
8. mostra il piano e termina subito se release, commit, MagicQ e stato richiesto
   sono già identici;
9. crea lo snapshot e rilancia l’installer dal candidato soltanto quando serve;
10. controlla versione, commit, sintassi dell’updater installato e mount `/data`;
11. attiva atomicamente il checkout soltanto dopo tutti i controlli finali.

La sincronizzazione avviene dopo `--plan` e dopo il controllo di aggiornamento
già installato, quindi una semplice simulazione o un no-op non modifica
l’orologio. Se dopo il tentativo automatico Chrony rileva ancora uno scarto
superiore a cinque minuti, l’updater termina prima dello snapshot con
un’indicazione esplicita: questo evita l’errore poco leggibile `Release file ...
is not valid yet` di APT.

Lo scambio del checkout avviene soltanto dopo test e installazione riuscita. Se l’alimentazione viene
interrotta nel breve passaggio di rinomina, l’esecuzione successiva recupera
automaticamente la copia precedente. I file non tracciati vengono considerati
modifiche locali e bloccano lo scambio invece di essere cancellati.

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

Mostrare il piano senza snapshot o installazione:

```bash
sudo wasalight-update --plan
```

Il piano usa esclusivamente un checkout temporaneo in `/tmp`, non crea log o
stato su `/data`, non importa pacchetti dalle USB e non modifica configurazione,
canale o checkout persistente. Il lock e i file di avanzamento in `/run` sono
volatili e scompaiono al riavvio. Anche i lock opzionali di Git sono disattivati,
così una semplice lettura dello stato non riscrive l’indice persistente.

Reinstallare intenzionalmente la stessa release e lo stesso commit per riparare
file di configurazione alterati:

```bash
sudo wasalight-update --repair
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

Ripristinare manualmente l’ultimo snapshot disponibile:

```bash
sudo wasalight-update --rollback
```

Il comando è ammesso soltanto in MAINTENANCE e richiede un riavvio successivo.

La stessa operazione è disponibile in **Wasalight Control → Supporto → Rollback
Wasalight**. L’interfaccia mostra gli ultimi cinque snapshot con versione, data,
dimensione e stato del checksum, richiede MAINTENANCE e una conferma esplicita,
quindi propone il riavvio. Dalla stessa selezione si può eliminare definitivamente
una snapshot: il comando richiede una seconda conferma, rimuove archivio e
checksum e resta disponibile soltanto in MAINTENANCE. L’autenticazione
amministrativa è sempre richiesta:
non viene concessa un’autorizzazione permanente senza password. Il ripristino
riguarda configurazione, comandi e tema Wasalight; non sostituisce `/data`, gli
show MagicQ, i pacchetti Ubuntu o il pacchetto MagicQ.

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
La tastiera Onboard è parte dell’installazione standard: un aggiornamento la
installa se manca e mantiene l’avvio esclusivamente manuale.

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
- Un aggiornamento Git deve essere un avanzamento lineare (`fast-forward`) e
  download lenti o bloccati terminano entro 120 secondi per tentativo.
- Le modifiche locali, compresi i file non tracciati, interrompono l’operazione
  e non vengono cancellate.
- Due `.deb` con la stessa versione MagicQ ma contenuto diverso interrompono
  l’aggiornamento, anche quando hanno nomi differenti.
- I file trovati sulle USB sono soltanto letti e copiati, mai rimossi.
- Il codice scaricato viene verificato prima di eseguire l’installer.
- Le release `stable` devono essere immutabili e avere un tag SSH firmato da una
  chiave autorizzata localmente; non esiste fallback automatico al canale debug.
- L’interfaccia usa `pkexec` con due azioni Polkit vincolate agli updater
  Wasalight e Companion; non concede un comando root generico o `NOPASSWD`.
- Nel canale debug il commit installato deve coincidere con `refs/heads/main`;
  nel canale stable deve coincidere col commit del tag firmato.
- Lo stesso numero di versione non può indicare due commit differenti.
- Lo snapshot precedente viene verificato con SHA-256 prima del ripristino.
- Il log completo resta in `/data/log/wasalight-update.log`.

L’interfaccia grafica dell’aggiornamento disabilita AT-SPI soltanto per i propri
popup Zenity, perché la sessione Openbox minimale non avvia il relativo bus di
accessibilità. Questo evita il falso `Gtk-WARNING` finale senza modificare
l’accessibilità delle altre applicazioni. La ricerca GRUB di altri sistemi
operativi è disabilitata esplicitamente perché Wasalight è un’appliance a sistema
singolo.

Se il download non riesce, correggere rete o DNS e ripetere lo stesso comando;
la copia persistente precedente resta disponibile.

## Collaudo su UTM

La suite statica verifica sintassi, manifest, stato atomico, alias dei canali e
rifiuto delle release GitHub non immutabili. Sul clone UTM usa inoltre:

```bash
sudo tests/utm/verify-update-plan.sh
sudo WASALIGHT_IDEMPOTENCY_CONFIRM=UTM-ONLY \
  tests/utm/verify-update-idempotency.sh
```

Il primo confronta gli hash dei file persistenti prima e dopo `--plan`. Il
secondo, destinato esclusivamente alla VM usa-e-getta, esegue due installazioni
`--repair` dal canale debug e verifica che la configurazione gestita risultante
sia identica. Entrambi richiedono MAINTENANCE.
