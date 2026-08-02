# MagicQ Ubuntu Appliance

Progetto per trasformare un’installazione minimale **Ubuntu Server 24.04 LTS
amd64** in una postazione MagicQ dedicata, con sistema operativo protetto dagli
spegnimenti improvvisi e dati dello show persistenti.

Progetto realizzato da **Michele Moser** e **Wasabi Lightbulb Farm**.

## Contenuto

```text
magicq-ubuntu-appliance/
├── install.sh                         avvio principale
├── bin/
│   └── chamsys_install_ubuntu.sh      installer completo
├── packages/
│   ├── README.md
│   └── magicq_ubuntu_v1_9_8_3.deb    da aggiungere
├── docs/
│   ├── hardware-test-checklist.md
│   ├── migration-24.04.md
│   ├── ssh.md
│   ├── system-cleanup.md
│   ├── touchscreen.md
│   ├── update.md
│   └── vnc.md
└── tests/
    └── verify-project.sh
```

## Prima dell’installazione

1. Installare Ubuntu Server 24.04 LTS minimale su una macchina amd64.
2. Preparare una partizione ext4 separata per i dati persistenti.
3. Copiare il pacchetto ChamSys in `packages/`.
4. Identificare la partizione dati con `lsblk -f` o `blkid`.

L’installer non formatta mai dischi. La partizione dati deve esistere già e può
essere indicata come `UUID=...`, `LABEL=...` oppure `/dev/...`.

Alcuni componenti grafici leggeri provengono dal repository ufficiale Ubuntu
`universe`. Se non è già attivo, l'installer lo abilita automaticamente.

### Creare la partizione dati riducendo Ubuntu

La partizione di sistema non può essere ridotta mentre Ubuntu la sta usando.
Eseguire prima un backup, avviare la macchina da una **live USB Ubuntu** e
lanciare GParted (sostituire il dispositivo con quello mostrato da `lsblk`):

```bash
sudo gparted /dev/nvme0n1
```

In GParted:

1. ridurre la partizione ext4 di Ubuntu lasciando lo spazio desiderato non
   allocato;
2. creare nello spazio libero una nuova partizione ext4 con etichetta `DATA`;
3. applicare le operazioni e riavviare Ubuntu normalmente.

Verificare quindi il risultato con:

```bash
lsblk -f
```

La nuova partizione può essere passata all’installer con
`--data-device LABEL=DATA`. Se il disco usa LVM, cifratura o RAID, non seguire
questa procedura: preparare la partizione durante una nuova installazione con
partizionamento manuale oppure usare una procedura specifica per quel layout.

## Verifica del progetto

```bash
./tests/verify-project.sh
```

Il passaggio da una precedente appliance Ubuntu 22.04 va eseguito come nuova
installazione, conservando o ripristinando separatamente `/data`. Consultare la
[guida di migrazione a Ubuntu 24.04](docs/migration-24.04.md).

## Installazione

Esempio con SSH abilitato:

```bash
sudo ./install.sh \
  --data-device UUID=UUID_DELLA_PARTIZIONE_DATA \
  --with-ssh
```

Per aggiungere la tastiera virtuale Onboard:

```bash
sudo ./install.sh \
  --data-device LABEL=DATA \
  --with-onscreen-keyboard
```

### Aggiornamenti successivi

Dopo la prima installazione, aggiornare codice e configurazione con:

```bash
sudo wasalight-update
```

Il comando funziona soltanto in MAINTENANCE, scarica il ramo `main` verificato
in `/data/system/wasalight`, conserva i pacchetti MagicQ proprietari in
`/data/system/packages` e rilancia l’installer lasciando la protezione
disattivata per il collaudo. Quando tutto è corretto usare
`sudo magicq-protect` oppure eseguire `sudo wasalight-update --protect`.
L’installer prova a inizializzare automaticamente questa copia persistente;
un problema temporaneo di rete produce un avviso e può essere recuperato con
`sudo wasalight-update --code-only`.
L’aggiornamento non usa `git reset --hard`: se trova modifiche locali ai file
tracciati si ferma senza cancellarle. La procedura completa è descritta nella
[guida aggiornamenti](docs/update.md).

La voce grafica **Update Wasalight** mostra chiaramente le quattro fasi e, solo
dopo un aggiornamento riuscito, propone **Riavvia ora** oppure **Più tardi**. È
interamente utilizzabile al touch. Da terminale si può ottenere lo stesso
risultato senza domanda finale con `sudo wasalight-update --reboot`, combinabile
con `--protect` quando il prossimo avvio deve tornare direttamente in SHOW mode.

### Account amministratore `chamsys`

`chamsys` è sempre aggiunto a `sudo` e, quando presenti, ai gruppi `adm` e
`systemd-journal`. Al primo avvio dell'installer viene richiesta
interattivamente la sua password. Per sostituirla successivamente usare:

```bash
sudo ./install.sh --reset-chamsys-password
```

È possibile inserire la stessa password dell'utente amministratore Ubuntu, ma
la password non viene letta da quell'account, copiata, salvata nei file del
progetto o mostrata nei log.

`chamsys` continua a eseguire l'autologin grafico: chiunque abbia accesso fisico
alla postazione può quindi usare la sessione, anche se per elevare i privilegi
deve conoscere la password.

Su questo hardware MagicQ viene eseguito con privilegi `root` tramite un launcher
dedicato e senza richiesta di password. Per riprodurre esattamente l'avvio
manuale verificato, MagicQ mantiene `HOME=/root`; configurazione e dati locali
di root sono però bind persistenti sotto `/data/magicq/root-home`.

Il file XDG `user-dirs.dirs` indica `/home/chamsys/Documents` come cartella
Documenti. Uno show come `nomeshow` viene quindi proposto in
`/home/chamsys/Documents/MagicQ/nomeshow`, collegato a
`/data/magicq/Documents/MagicQ/nomeshow`. Anche
`/root/Documents/MagicQ` è un bind di sicurezza verso la stessa directory: se
MagicQ ignora XDG, il file resta comunque su `/data` e non nell'overlay root.

Il comando concesso senza password è soltanto il launcher fisso, non un comando
arbitrario. Alla chiusura di MagicQ il launcher ripristina inoltre proprietà e
permessi dei dati persistenti affinché restino accessibili da `chamsys`.
L’installer esegue la stessa riparazione subito dopo l’installazione del file
`.deb`: alcuni pacchetti MagicQ ricreano infatti `Documents/MagicQ` come
`root:root`. Il controllo finale interrompe l’installazione se le directory
persistenti non risultano realmente scrivibili da `chamsys`.

OpenSSH viene installato per il pulsante di assistenza, ma senza `--with-ssh`
il servizio viene disabilitato e fermato fino a un’attivazione manuale.

Su una postazione fisica dedicata l'installer elimina automaticamente
`cloud-init`, `multipath-tools`, `open-iscsi` e `pollinate` quando non servono
al disco di sistema o a `/data`. La verifica distingue LVM da un vero volume
multipath e conserva automaticamente i componenti SAN/iSCSI se sono in uso.
Usare `--keep-cloud-init` soltanto quando la macchina dipende ancora dalla
configurazione cloud.

Wasalight non installa QEMU. Il messaggio di `needrestart` secondo cui nessun
guest usa vecchi binari QEMU è un controllo riuscito, non un errore e non
indica la presenza dell'hypervisor. Dettagli e verifiche sono nella
[guida alla pulizia del sistema](docs/system-cleanup.md).

Per preparare temporaneamente la macchina senza attivare la protezione:

```bash
sudo ./install.sh --no-protection
```

## Modalità operative

La configurazione normale è **SHOW / PROTECTED**:

- la root Ubuntu usa un overlay volatile in RAM;
- `/tmp`, `/var/tmp` e journald sono volatili;
- `/data` rimane ext4 in lettura/scrittura;
- show, impostazioni MagicQ e configurazioni di rete restano persistenti;
- console ed eventi MagicQ restano disponibili in `/data/log` con rotazione;
- ogni chiavetta viene montata nella propria sottodirectory di `/stick`, il
  percorso usato dalla vista Flash di MagicQ;

Comandi disponibili:

```bash
magicq-status
magicq-start
magicq-stop
magicq-touch-status
magicq-touch-config list
magicq-audio-test
magicq-vnc-start
magicq-vnc-stop
wasalight-hub
wasalight-ip-scanner
wasalight-artnet-monitor
wasalight-vnc-toggle
sudo wasalight-app-register --list
sudo magicq-maintenance
sudo magicq-protect
```

`magicq-maintenance` e `magicq-protect` preparano la modalità del boot
successivo. Dopo il comando occorre riavviare quando si è pronti.

In modalità **SHOW / PROTECTED**, MagicQ parte automaticamente ed è sorvegliato:
chiudere soltanto la sua finestra viene interpretato come un arresto inatteso e
provoca il riavvio dopo tre secondi.

In modalità **MAINTENANCE**, Openbox parte normalmente ma MagicQ resta chiuso.
Questo evita che l'applicazione interferisca con aggiornamenti, copie e diagnosi.
Per aprirlo intenzionalmente durante la manutenzione usare **Start MagicQ** nel
menu oppure:

```bash
magicq-start
```

Per mantenerlo chiuso intenzionalmente usare:

```bash
magicq-stop
```

Il comando ferma prima il supervisore e poi il processo MagicQ eseguito come
root. MagicQ resta chiuso fino al comando seguente. In SHOW ripartirà anche al
prossimo login o riavvio; in MAINTENANCE resterà invece fermo:

```bash
magicq-start
```

Le stesse azioni sono disponibili nel menu Openbox come **Start MagicQ** e
**Stop MagicQ**. `magicq-status` distingue applicazione e supervisore con le
righe `MAGICQ` e `SUPERVISOR`.

### Fullscreen automatico

MagicQ 1.9.x apre la finestra principale massimizzata, ma non richiede a
Openbox il vero stato fullscreen. Senza un intervento aggiuntivo resta visibile
anche la barra del titolo.

Wasalight avvia `magicq-fullscreen-watch` insieme a Openbox. Il controllo
attende la finestra principale `MagicQ PC` e le applica lo stato EWMH
fullscreen tramite `wmctrl`. Funziona sia con l'avvio automatico in SHOW sia
con **Start MagicQ** in MAINTENANCE e viene riapplicato quando MagicQ crea una
nuova finestra dopo un riavvio. Non forza continuamente lo stato: dopo la prima
applicazione, un operatore può disattivarlo temporaneamente durante una
diagnosi senza che venga riattivato sulla stessa finestra.
Tint2 rimane intenzionalmente sopra il bordo inferiore anche quando la finestra
MagicQ è fullscreen, perché deve essere sempre raggiungibile dal touchscreen.

### Desktop di manutenzione

Openbox viene limitato a **un solo desktop virtuale**: all'avvio `wmctrl -n 1`
elimina gli altri spazi di lavoro della sessione. PCManFM disegna uno sfondo
nero con icone SVG da 64 pixel, ad alto contrasto e indipendenti dal tema di
Ubuntu. L’installer aggiunge `librsvg2-common`, il loader GDK-Pixbuf che manca
nell’immagine Server minimale e che serve a PCManFM per visualizzare realmente
gli SVG. I launcher restano file protetti appartenenti a `root`; LibFM usa
`single_click=1` e `quick_exec=1`, quindi sul touchscreen basta un tocco e non
appare la richiesta «Apri con…». Non viene usato il metadato GIO
`metadata::trusted`, assente nel profilo PCManFM/GVFS dell’installazione
Server. `chamsys` può avviare i launcher ma non cancellarli, rinominarli,
spostarli o modificarli accidentalmente.
Sono disponibili soltanto i comandi principali:

- **Start MagicQ**;
- **Stop MagicQ**;
- **Wasalight Hub**;
- **VNC**;
- **SSH**;
- **Power off**;
- **Reboot**.

Spegnimento e riavvio mostrano sempre una grande finestra di conferma. Soltanto
dopo la conferma viene eseguito un comando amministrativo ristretto, senza
chiedere la password e senza concedere al desktop un accesso `sudo` generico.

Sul lato destro Conky mostra un pannello aggiornato ogni due secondi con:

- modalità corrente e modalità prevista al prossimo avvio;
- stato di MagicQ e del supervisore;
- montaggio e spazio libero di `/data`;
- persistenza dei log;
- rete e indirizzo IP, evidenziando dispositivi `unmanaged`;
- touchscreen, chiavette USB, VNC, SSH e audio ALSA.

Verde significa operativo, giallo indica uno stato fermo o non collegato ma non
necessariamente errato, rosso richiede attenzione. Il pannello esegue solo
letture, non produce log e non scrive periodicamente su `/data`.

Il clic destro sullo sfondo continua ad aprire il menu Openbox. I pulsanti sono
visibili quando MagicQ è chiuso, in particolare durante la modalità
MAINTENANCE. In SHOW la finestra fullscreen di MagicQ copre intenzionalmente il
desktop e il pannello di stato; per intervenire sulla configurazione si deve
prima passare a MAINTENANCE oppure fermare MagicQ con `magicq-stop`.

### Wasalight Hub e applicazioni future

**Wasalight Hub** è un launcher GTK progettato per il touchscreen. Organizza i
programmi in tre schede:

- **MagicQ**: applicazioni companion ChamSys rilevate quando realmente
  installate;
- **Applications**: programmi registrati dall'amministratore;
- **Support**: rete, monitor, touchscreen, audio, file, terminale, stato, VNC,
  SSH e aggiornamento Wasalight.

Il rilevamento automatico è intenzionalmente limitato ai companion riconoscibili
come MagicVis, MagicHD e strumenti Remote/Viewer ChamSys. Il programma MagicQ
principale continua a essere avviato soltanto dal launcher Wasalight controllato
e non attraverso un generico file `.desktop` del pacchetto.
Il Hub rispetta anche la chiave standard `Path`. Per MagicHD e MagicVis riconosce
i launcher originali ChamSys e li inoltra a un wrapper root ristretto ai soli due
comandi. In questo modo usano `/opt/magicq`, l’ambiente X11 e lo stesso runtime
Qt/OpenGL con cui MagicQ funziona sul target, senza concedere al Hub un sudo
generico. Gli errori rimangono nel log persistente del Hub.

Per registrare un programma installato in futuro usare il relativo launcher
standard presente normalmente sotto `/usr/share/applications`:

```bash
sudo wasalight-app-register /usr/share/applications/NOME.desktop
sudo wasalight-app-register --list
sudo wasalight-app-register --remove NOME.desktop
```

Con `/data` montata, le registrazioni sono conservate in
`/data/system/apps.d`; in assenza di `/data` vengono mantenute sotto
`/etc/wasalight/apps.d`. Il Hub rispetta `TryExec` e non mostra un'applicazione
quando il suo eseguibile non è disponibile.

Se un launcher di terze parti contiene un valore booleano non standard, il Hub
lo ignora invece di terminare. Gli eventuali errori di avvio vengono mostrati
a schermo e registrati in `/data/log/wasalight-hub.log` (oppure in `/tmp` se
`/data` non è disponibile).

Tint2 non mostra più la scritta **desktop 1** e resta sempre visibile in basso.
Il pannello riserva lo spazio necessario e offre i pulsanti Hub e File Manager,
le applicazioni aperte, le icone di stato e l’orologio. Questa scelta evita il
gesto sul bordo, poco affidabile con molti touchscreen, e mantiene sempre
raggiungibili i controlli. Il tema è quasi nero (`#080b10`), con selezioni
antracite discrete e senza il precedente fondo blu acceso.

Il clic destro apre soltanto un menu Wasalight minimale: Start/Stop MagicQ,
Hub, File Manager, Terminale, Update, VNC, SSH, riavvio e spegnimento. Le
preferenze Openbox e le impostazioni di sistema generiche non sono esposte.

Le finestre Openbox usano il tema scuro **Wasalight** sia quando sono attive sia
quando sono in secondo piano. La barra del titolo ha spaziatura maggiorata e un
pulsante **X** da 16 px con una zona di tocco ampia; al passaggio o alla pressione
diventa rosso. I piccoli pulsanti minimizza/massimizza sono rimossi dalla barra:
le finestre restano gestibili dalla barra inferiore, più adatta al touchscreen.

Nella scheda **Support** del Hub sono disponibili anche:

- **IP Scanner**, che usa `arp-scan` sulle interfacce Ethernet/Wi-Fi connesse e
  mostra interfaccia, IP, MAC e produttore in una tabella aggiornabile;
- **Art-Net Monitor**, che ascolta passivamente il traffico Art-Net su tutte le
  interfacce e raggruppa sorgente, destinazione, tipo di pacchetto, universo,
  numero di canali e contatore dei pacchetti.

Le due interfacce sono grandi e utilizzabili al tocco. Solo la cattura di rete
passa attraverso helper amministrativi senza argomenti, esplicitamente limitati
in `sudoers`; le interfacce grafiche continuano a funzionare come `chamsys`. Gli
errori confluiscono nel log persistente `/data/log/wasalight-network-tools.log`,
gestito dalla stessa rotazione degli altri log Wasalight.

### VNC della sessione corrente

Il pulsante **VNC** condivide esclusivamente il display Xorg corrente `:0`:

- se VNC è spento, lo avvia e mostra l'indirizzo di connessione;
- se è attivo, chiede conferma prima di fermarlo;
- al primo utilizzo apre un terminale dedicato per creare la password senza
  inserirla negli argomenti dei processi o nei log;
- lo stato aggiornato rimane visibile nel pannello Conky.

### SSH temporaneo

OpenSSH è installato ma, senza `--with-ssh`, resta disabilitato e fermo. Il
pulsante **SSH** sul desktop o nel Hub chiede conferma e avvia il servizio per
la sessione corrente; una seconda pressione consente di fermarlo. L’accesso usa
`chamsys` e la sua password Linux. Con `--with-ssh` il servizio viene invece
abilitato anche agli avvii successivi. Il pannello Conky distingue `SESSION` da
`AUTO`. Dettagli e comandi sono nella [guida SSH](docs/ssh.md).

### Audio ALSA

L'installer verifica che la configurazione ALSA e gli strumenti diagnostici
siano presenti. Per provare realmente l'uscita predefinita eseguire:

```bash
magicq-audio-test
```

Il comando elenca le schede disponibili e riproduce una volta i campioni
**Front Left** e **Front Right**. Alcune versioni di PortAudio usate da MagicQ
provano anche nomi PCM storici (`front`, `rear`, `surround`) o ingressi non
offerti dalle uscite HDMI. I conseguenti messaggi `Unknown PCM` e le asserzioni
di enumerazione nel log non indicano da soli un guasto. L'audio è considerato
funzionante quando `magicq-audio-test` termina correttamente e MagicQ completa
l'inizializzazione. Errori come l'assenza di `alsa.conf`, nessuna scheda in
`aplay -l` o l'impossibilità di aprire il dispositivo predefinito restano invece
problemi reali e non vengono nascosti dai log.

### Rete gestita da NetworkManager

Ubuntu Server crea normalmente la prima configurazione Netplan usando
`systemd-networkd`. In questo stato `nm-connection-editor` si apre, ma
NetworkManager mostra l'interfaccia come `unmanaged` e la lista può apparire
vuota. Wasalight installa quindi il file
`/etc/netplan/99-wasalight-networkmanager.yaml`, che seleziona
`NetworkManager` come renderer conservando le definizioni DHCP, statiche, DNS e
route già presenti negli altri file Netplan.

Le nuove connessioni salvate dalla voce **Network** nel Wasalight Hub sono
conservate nel bind persistente
`/etc/NetworkManager/system-connections` → `/data/system/network`. Lo stato si
controlla con:

```bash
nmcli device status
magicq-status
```

Le interfacce Ethernet e Wi-Fi devono risultare gestite, anche quando sono
semplicemente `disconnected`; non devono risultare `unmanaged`. Durante una
reinstallazione da SSH o VNC, `netplan apply` può interrompere brevemente la
connessione mentre il controllo passa da `systemd-networkd` a NetworkManager.

## Log persistenti

Il journal generale di Ubuntu resta volatile per limitare le scritture e
proteggere il disco di sistema. La diagnostica utile di MagicQ viene invece
salvata separatamente:

Questi due file appartengono a **Wasalight**, non sono i log interni prodotti da
MagicQ:

```text
/data/log/wasalight-magicq-console.log  output stdout/stderr e diagnostica Linux
/data/log/wasalight-magicq-session.log  avvii, uscite e riavvii del supervisore
```

MagicQ continua a creare autonomamente un file `.log` per ogni sessione, con un
nome basato su giorno e ora, nella propria cartella nativa:

```text
/data/magicq/Documents/MagicQ/log/
```

La stessa directory è raggiungibile da
`/home/chamsys/Documents/MagicQ/log/` e, tramite il bind di sicurezza,
`/root/Documents/MagicQ/log/`. MagicQ gestisce direttamente questi file e li
elimina automaticamente dopo circa un mese; la rotazione Wasalight non li
modifica. Il comportamento e la creazione dei pacchetti di supporto sono
descritti nel [manuale ChamSys](https://secure.chamsys.co.uk/docs/magicq/manual/system_management.html#saving-support-files).

Per seguire un errore in tempo reale o leggere gli ultimi eventi:

```bash
tail -f /data/log/wasalight-magicq-console.log
tail -n 100 /data/log/wasalight-magicq-session.log
```

Un timer controlla i file ogni 10 minuti. Ogni log viene ruotato a 5 MiB,
conservando cinque copie e comprimendo quelle meno recenti. In questo modo i
log diagnostici non possono crescere indefinitamente sulla partizione dati.
`magicq-status` mostra `LOGS: persistent in /data/log` quando il percorso è
disponibile. Se `/data` non è montata, l'output passa temporaneamente nella
directory runtime volatile della sessione.

Gli aggiornamenti Ubuntu e l’installazione di un nuovo pacchetto MagicQ devono
essere eseguiti esclusivamente dopo il riavvio in MAINTENANCE mode.

## Touchscreen

Xorg usa il driver `libinput`. Con un solo touchscreen e un solo monitor,
l'associazione viene applicata automaticamente. In presenza di più dispositivi
la configurazione si ferma in modo sicuro e richiede una scelta esplicita.

Esempio per associare un touchscreen a `HDMI-1`:

```bash
magicq-touch-config list
magicq-touch-config set "NOME TOUCHSCREEN" HDMI-1 normal
```

La configurazione viene riapplicata anche dopo una riconnessione a caldo. Per
diagnosi, rotazioni, configurazioni multimonitor e tastiera virtuale consultare
[la guida touchscreen](docs/touchscreen.md).

## Assistenza remota VNC

Wasalight installa `x11vnc` per condividere temporaneamente la sessione
Openbox/MagicQ già visibile sul monitor. Il server non parte automaticamente e
non resta attivo dopo un riavvio. Usare il pulsante desktop **VNC**, la voce nel
Wasalight Hub oppure, dalla sessione `chamsys`, il comando:

```bash
magicq-vnc-start
```

Al primo utilizzo viene richiesta una password VNC separata dalla password
Linux. Per arrestare immediatamente l'accesso remoto:

```bash
magicq-vnc-stop
```

La modalità LAN usa la porta TCP 5900 e non offre cifratura completa. Per uso,
tunnel SSH, cambio password e rimozione consultare la [guida VNC](docs/vnc.md).

## Assistenza remota SSH

Usare il pulsante desktop **SSH** o la voce **SSH access** nel Wasalight Hub.
Quando è attivo, collegarsi con:

```bash
ssh chamsys@INDIRIZZO_IP
```

SSH usa la password Linux di `chamsys`; non crea né salva una nuova password.
Per modalità temporanea, attivazione automatica e sicurezza consultare la
[guida SSH](docs/ssh.md).

## Chiavette USB per MagicQ

MagicQ cerca i supporti rimovibili nel percorso `/stick`. L'installer crea una
sottodirectory distinta per ogni partizione USB supportata, usando il nome del
dispositivo: per esempio `/stick/sdb1` e `/stick/sdc1`. FAT32, exFAT e NTFS
possono quindi restare montati e visibili contemporaneamente nella vista Flash
di MagicQ. Una seconda chiavetta non nasconde né sostituisce la prima.

Le scritture vengono richieste in modalità sincrona per ridurre il rischio di
perdita dati. Prima di estrarre una chiavetta attendere comunque la conclusione
del salvataggio; nessun filesystem può garantire l'integrità durante una
rimozione fisica nel mezzo di una scrittura.

Lo stato del supporto montato è visibile con:

```bash
magicq-status
findmnt | grep '/stick/'
```

## Percorsi persistenti

```text
/home/chamsys/Documents/MagicQ  → /data/magicq/Documents/MagicQ
/home/chamsys/.local/share      → /data/magicq/.local/share
/home/chamsys/.magicq_init.sh   → /data/magicq/.magicq_init.sh
/root/.config                   → /data/magicq/root-home/.config
/root/.local/share              → /data/magicq/root-home/.local/share
/root/Documents/MagicQ          → /data/magicq/Documents/MagicQ (fallback)
/etc/NetworkManager/system-connections
                                → /data/system/network
/data/system/touchscreen/config → configurazione touch persistente
/data/system/vnc/passwd         → password VNC persistente e protetta
/data/system/wasalight          → copia Git persistente per gli aggiornamenti
/data/system/packages           → pacchetti MagicQ proprietari persistenti
```

MagicQ gira con UID e gruppo root, come nell'avvio manuale che è stato verificato
sull'hardware. Usare comunque `magicq-session`: il launcher prepara ambiente,
runtime e riparazione finale dei proprietari dei file show.

## Limitazioni note

- Una scrittura USB sincrona riduce la finestra di rischio, ma nessun filesystem
  può garantire l’integrità se la chiavetta viene estratta durante una scrittura.
- Il primo avvio protetto e le periferiche ChamSys devono essere verificati sulla
  macchina definitiva.
- Il pacchetto `.deb` non è redistribuito da questo progetto: usare il file
  originale scaricato da ChamSys.
