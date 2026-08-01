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
│   ├── system-cleanup.md
│   ├── touchscreen.md
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
dedicato e senza richiesta di password. Il launcher non usa la home di root:
imposta `HOME=/home/chamsys` e reindirizza anche le directory XDG persistenti.
Di conseguenza uno show come `nomeshow` viene salvato in
`/home/chamsys/Documents/MagicQ/nomeshow`, collegato a
`/data/magicq/Documents/MagicQ/nomeshow`, e mai in `/root/Documents`.

Il comando concesso senza password è soltanto il launcher fisso, non un comando
arbitrario. Alla chiusura di MagicQ il launcher ripristina inoltre proprietà e
permessi dei dati persistenti affinché restino accessibili da `chamsys`.

Senza `--with-ssh`, OpenSSH non viene installato e un eventuale servizio SSH
preesistente viene disabilitato.

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
- ogni chiavetta viene montata nella propria sottodirectory di `/stick`, il
  percorso usato dalla vista Flash di MagicQ;

Comandi disponibili:

```bash
magicq-status
magicq-touch-status
magicq-touch-config list
magicq-vnc-start
magicq-vnc-stop
sudo magicq-maintenance
sudo magicq-protect
```

`magicq-maintenance` e `magicq-protect` preparano la modalità del boot
successivo. Dopo il comando occorre riavviare quando si è pronti.

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
non resta attivo dopo un riavvio. Per avviarlo dalla sessione `chamsys`:

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
/etc/NetworkManager/system-connections
                                → /data/system/network
/data/system/touchscreen/config → configurazione touch persistente
/data/system/vnc/passwd         → password VNC persistente e protetta
```

MagicQ gira con UID root, ma il launcher imposta la prima riga come sua cartella
Documenti effettiva. Non avviare direttamente `sudo ./runmagicq.sh`: quel comando
salterebbe il reindirizzamento e tornerebbe a usare `/root/Documents`.

## Limitazioni note

- Una scrittura USB sincrona riduce la finestra di rischio, ma nessun filesystem
  può garantire l’integrità se la chiavetta viene estratta durante una scrittura.
- Il primo avvio protetto e le periferiche ChamSys devono essere verificati sulla
  macchina definitiva.
- Il pacchetto `.deb` non è redistribuito da questo progetto: usare il file
  originale scaricato da ChamSys.
