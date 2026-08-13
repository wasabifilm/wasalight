# Diagnostica, salute, backup e ripristino

Wasalight raccoglie le funzioni operative nella scheda **Supporto** di
Wasalight Control. Le operazioni che modificano `/data` sono disponibili solo
in **MAINTENANCE**, mentre i controlli in sola lettura sono utilizzabili anche
in SHOW.

## Salute del sistema

**Salute sistema** esegue `wasalight-health` e riporta filesystem root, spazio
libero e percentuale usata su `/data`, memoria, prima temperatura termica
disponibile e stato SMART del disco quando leggibile. La soglia di attenzione
per `/data` è 85%. Uno SMART non leggibile resta `unavailable`: non diventa un
falso guasto.

Un timer systemd ripete il controllo ogni 15 minuti, conserva l’ultimo stato in
`/data/system/health/status` e ruota lo storico
`/data/log/wasalight-health.log`. Il pannello desktop mostra `HEALTH OK` oppure
`HEALTH WARNING` senza interrogare continuamente l’hardware.

```bash
wasalight-health
```

## Pacchetto diagnostico

**Esporta diagnostica** crea `wasalight-support-AAAAMMGG-HHMMSS.tar.gz` e il
relativo `.sha256` in `/data/log` oppure nella root di una USB montata. Include
stato Wasalight, salute, kernel, storage, mount, USB, rete, NetworkManager,
unità systemd fallite, warning del journal e versioni dei pacchetti.

Il bundle elenca i nomi dei file sotto `/data/system` e `/data/log`, ma non
copia connessioni NetworkManager, password VNC, show MagicQ o configurazioni
private. Prima di inviarlo è comunque buona pratica controllarne il contenuto.

```bash
sudo wasalight-support-bundle /data/log
sudo wasalight-support-bundle /stick/NOME_USB
```

## Backup completo di `/data`

**Backup e ripristino** apre una procedura guidata. Richiede MAINTENANCE,
`/data` montata e una USB visibile sotto `/stick/<volume>`. Il backup conserva
proprietà numeriche, ACL, attributi estesi, MagicQ, Companion, plugin, pacchetti
persistenti, log e configurazione Wasalight.

Il file è `wasalight-data-AAAAMMGG-HHMMSS.tar.zst`; accanto viene scritto il
checksum SHA-256. L’opzione cifrata produce `.tar.zst.gpg` con AES-256 e chiede
una password GPG che Wasalight non memorizza.

```bash
sudo wasalight-data-transfer
sudo wasalight-data-transfer backup /stick/NOME_USB
sudo wasalight-data-transfer backup /stick/NOME_USB --encrypt
```

Non rimuovere la chiavetta finché non compare `Backup completed`. Il manifest
interno registra formato, data, versione Wasalight, hostname e dimensione
originaria di `/data`.
Per backup grandi preferire exFAT, NTFS o ext4: FAT32 ha un limite di 4 GB per
singolo file ed è consigliata soprattutto per il bootstrap iniziale di MagicQ.

## Ripristino su una nuova macchina

Installare prima Wasalight e creare/montare la nuova partizione `/data`, poi
entrare in MAINTENANCE. Il ripristino verifica checksum e struttura
dell’archivio, ferma MagicQ e Companion e richiede di digitare esattamente
`RESTORE-DATA`.

- **Completo** sostituisce l’intero contenuto persistente di `/data`.
- **Solo applicazioni** ripristina MagicQ, Companion, stato/plugin e pacchetti,
  lasciando il resto della nuova macchina.

```bash
sudo wasalight-data-transfer restore \
  /stick/NOME_USB/wasalight-data-AAAAMMGG-HHMMSS.tar.zst complete
```

Dopo un ripristino riavviare prima di aprire MagicQ. Il backup non sostituisce
una seconda copia conservata separatamente dalla console.

## Wizard del primo avvio

Al primo avvio grafico il wizard controlla rete, touchscreen, audio e presenza
di MagicQ, poi indica dove gestire SSH, VNC, backup e diagnostica. Il marker
`/data/system/first-run/complete` impedisce nuove aperture. Per ripeterlo,
rimuovere quel file in MAINTENANCE e riavviare la sessione grafica.

## Calcolatrice

La scheda **Applicazioni** include `galculator`, una calcolatrice GTK leggera
con modalità base e scientifica. Non richiede privilegi e salva le proprie
preferenze nel profilo di `chamsys`.

## Blocco schermo manuale

La voce **Blocca schermo** nella scheda **Supporto** mostra prima una conferma
e poi avvia `i3lock` in primo piano. Lo sblocco usa PAM e quindi la stessa
password Linux dell’utente `chamsys`. È necessaria una tastiera fisica: il lock
sicuro acquisisce direttamente l’input Xorg e non può affidarsi alla tastiera
virtuale della sessione.

Il blocco è esclusivamente manuale. Wasalight non installa né avvia
`xss-lock`, `xautolock` o altri timer. Subito prima e dopo lo sblocco riafferma
con `xset` che screensaver, blanking e DPMS sono disabilitati, quindi il monitor
resta acceso e la console non viene sospesa.
# Data, ora e fuso orario

**Wasalight Control → Strumenti → Data e ora** mostra ora locale, UTC, RTC,
fuso, stato di Chrony e scarto rispetto alla sorgente NTP. È possibile:

- sincronizzare immediatamente l’orologio e riattivare Chrony;
- scegliere un fuso dall’elenco ufficiale di `timedatectl`;
- impostare manualmente data e ora.

Le modifiche richiedono la password amministratore tramite una finestra Polkit.
L’impostazione manuale disattiva Chrony per evitare che il valore venga subito
sovrascritto; **Sincronizza ora** riattiva il servizio. L’operazione aggiorna
anche l’orologio hardware quando il sistema lo consente.

Uno scarto elevato può far rifiutare i repository Ubuntu con `Release file ...
is not valid yet`. In quel caso aprire lo strumento e usare **Sincronizza ora**
prima di rilanciare l’aggiornamento Wasalight.
