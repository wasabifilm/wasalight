# Architettura dell’installer Wasalight

`bin/chamsys_install_ubuntu.sh` è un orchestratore breve. Definisce il contesto
della release, carica in ordine i moduli e richiama le fasi da `main`. L’ordine
dei nomi numerici in `installer/modules` è intenzionale e viene verificato dai
test.

## Moduli

```text
00-common.sh             validazione, primitive e gestione errori
10-base.sh               /data, pacchetti base e NetworkManager
20-network-services.sh   utente, touchscreen, SSH e VNC
30-updates.sh            updater e controllo nuove versioni
40-companion.sh          installazione e strumenti Companion
50-graphical-session.sh  Xorg, Openbox, MagicQ e applicazioni desktop
60-plugins.sh            runtime e Wasalight Control
70-management.sh         diagnostica, backup e strumenti amministrativi
75-persistent-logs.sh    log persistenti e rotazione
80-magicq-usb.sh         automount USB e installazione MagicQ
90-system.sh             ottimizzazione, modalità, boot, overlay e verifiche
```

I moduli sono file Bash da caricare con `source`: non devono eseguire azioni al
momento del caricamento, ma soltanto dichiarare funzioni. Le operazioni restano
ordinate esplicitamente nella funzione `main` dell’orchestratore.

## Template rootfs

I file statici prima costruiti con heredoc si trovano in
`installer/templates/rootfs`, usando lo stesso percorso che avranno sul sistema
destinazione. Per esempio:

```text
installer/templates/rootfs/etc/systemd/system/wasalight-usb@.service
installer/templates/rootfs/etc/sudoers.d/wasalight-management
installer/templates/rootfs/usr/local/sbin/wasalight-update
```

`install_template PERCORSO MODO` copia il file preservando il percorso relativo
alla root e applicando i permessi dichiarati dal modulo. Solo i file che
contengono valori calcolati durante l’installazione rimangono heredoc dinamici.
Gli script statici vengono controllati direttamente da `verify-project.sh`.

## Manifesto della release

`release-manifest.ini` è dichiarativo e non viene eseguito come codice shell.
La libreria `lib/wasalight-release-manifest.sh` legge una chiave per sezione e
rifiuta campi mancanti o vuoti; i consumatori possono inoltre imporre formato e
tipo. Anche l'ISO Builder usa questo loader per release Ubuntu, immagini
Canonical, repository e branch. Una copia viene incorporata nelle ISO e
installata in `/etc/wasalight/release-manifest.ini`, così first boot, updater e
Companion usano gli stessi valori verificati.

La sezione `[Updates]` separa il canale `stable`, basato su una GitHub Release
immutabile e un tag SSH firmato, dal canale `debug`, basato su
`refs/heads/main`. La configurazione dichiara gli endpoint e il percorso del
file `allowed_signers`; la logica di verifica resta nel modulo updater e non nel
manifesto.

## Transazione di aggiornamento

L’updater installa dal checkout `/data/system/wasalight.candidate` e attiva
`/data/system/wasalight` soltanto dopo test, installer e health check. Lo stato
atomico `/data/system/update-state` consente di distinguere download, snapshot,
installazione, verifica e attivazione e contiene il riferimento allo snapshot da
usare per `--resume` o `--rollback`. Il canale viene scritto atomicamente solo a
esito positivo e viene ripristinato insieme al checkout se la chiusura della
transazione fallisce.

L’ambiente `WASALIGHT_PROGRESS_FILE` è accettato esclusivamente per il percorso
volatile `/run/wasalight-update-progress-detail`. L’orchestratore pubblica lì il
nome dei 25 passaggi con una sostituzione atomica; l’updater lo mostra senza
mescolare l’intero output di APT nel terminale touch-friendly.

## Lock delle operazioni

`lib/wasalight-operation-lock.sh` gestisce
`/run/lock/wasalight-operation.lock`. Installer, updater, snapshot e trasferimento
dati acquisiscono lo stesso lock non bloccante. Il descrittore viene ereditato
dai processi figli: una singola procedura può quindi chiamare snapshot e
installer, mentre una seconda procedura indipendente viene respinta. Il lock è
rilasciato automaticamente dal kernel alla terminazione del processo, anche in
caso di errore o interruzione.

## Verifica

Eseguire sempre:

```bash
./tests/verify-project.sh
./tests/quality.sh
```

`verify-project.sh` prepara una sola volta installer combinato e template, poi
carica le suite di dominio in `tests/static/installer.sh`,
`tests/static/control-plugins.sh` e `tests/static/runtime.sh`. Le suite
controllano sintassi dei moduli, manifesto, template, ordine delle fasi e
invarianti di installazione. `quality.sh` aggiunge ShellCheck, Ruff,
`systemd-analyze verify`, `desktop-file-validate`, gettext e link locali della
documentazione; in CI usa `--require-tools` per rendere obbligatori tutti i
validatori. Una nuova fase deve essere aggiunta come modulo quando è
indipendente; un nuovo file statico destinato al sistema deve essere un
template, non un heredoc.

I test autonomi in `tests/behavior` verificano eseguendo il codice reale il lock
globale, il parser del manifesto e la politica di retry Git dell'updater. Vengono
richiamati automaticamente da `verify-project.sh` e possono essere eseguiti da
soli durante lo sviluppo:

```bash
./tests/behavior/run.sh
```

La suite del lock simula intenzionalmente anche l’esecuzione dentro un updater
che possiede già il descrittore globale. Il processo di test elimina soltanto la
propria copia dello stato ereditato, senza rilasciare il lock dell’updater padre;
questo evita falsi risultati rientranti durante la verifica di una nuova release.
