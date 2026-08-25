# Plugin Wasalight e Control Center

Wasalight integra un registro dichiarativo per le funzioni opzionali e una sola
interfaccia touch, **Wasalight Control**.

## Obiettivi e confini

Il registro plugin descrive nome, versione, disponibilità, stato runtime e
azioni esposte all'operatore. I plugin integrati arrivano dal repository
Wasalight. I plugin esterni possono essere importati solo come bundle USB
firmati contenenti `manifest.ini` e `package.deb`; non vengono eseguiti script
arbitrari scaricati da Internet.

MagicQ, `/data`, overlayroot, USB, rete e aggiornamento del sistema restano nel
core: sono necessari per l'appliance e non possono essere disabilitati come
plugin. I primi plugin integrati sono:

- `ssh`: gestione del servizio OpenSSH;
- `vnc`: condivisione della sessione Xorg corrente;
- `companion`: Bitfocus Companion e relativa Web UI.

## Percorsi

```text
/usr/lib/wasalight/plugins/<id>/manifest.ini   manifest installato e root-owned
/data/system/plugins-state/<id>               enabled oppure disabled
/data/plugins/<id>/                           dati futuri specifici del plugin
/data/log/plugins/                             log futuri specifici del plugin
/etc/wasalight/trusted-plugin-keys.gpg         chiavi pubbliche autorizzate
```

I dati Companion esistenti restano sotto `/data/companion`; non vengono spostati
per il solo cambio di architettura. Lo stato enable/disable sopravvive agli
aggiornamenti e a SHOW mode perché risiede su `/data`.

## Installazione e aggiornamento

L'opzione generica è ripetibile:

```bash
sudo ./install.sh --plugin companion --plugin vnc
sudo wasalight-update --plugin companion
```

`--with-companion` rimane un alias compatibile. `--with-ssh` continua invece a
indicare che SSH deve essere abilitato automaticamente al boot: non va confuso
con la presenza del plugin SSH nel Control Center.

Un aggiornamento ordinario legge `/data/system/plugins-state` e inoltra i plugin
abilitati al nuovo installer. Un plugin disabilitato non viene riabilitato in
modo implicito. Il software e i dati già installati non vengono cancellati.

## Comandi

```bash
wasalight-plugin list
wasalight-plugin list --json
wasalight-plugin status companion
wasalight-plugin doctor
wasalight-plugin install companion
wasalight-plugin action companion start
wasalight-plugin action companion open
wasalight-plugin enable companion
wasalight-plugin disable companion
```

`enable` e `disable` modificano lo stato persistente e sono consentiti soltanto
in MAINTENANCE. Disabilitare ferma il relativo servizio/processo e ne impedisce
l'avvio al boot. Se il manifest dichiara `AutoEnable=true`, l'abilitazione avvia
e abilita immediatamente anche il servizio systemd. Le azioni operative
come start/stop di SSH e Companion restano disponibili in SHOW quando previsto
dal manifest.

## Sicurezza

`wasalight-plugin` non usa `shell=True`: divide il comando dichiarato e richiede
un eseguibile con percorso assoluto. Un'azione `Privilege=root` passa comunque
da `sudo -n` e deve corrispondere a uno dei wrapper già elencati esplicitamente
in `/etc/sudoers.d/chamsys-magicq`.

Enable/disable persistente passa da `wasalight-plugin-admin`, che:

1. accetta soltanto ID nel formato previsto;
2. richiede un manifest installato corrispondente;
3. rifiuta SHOW mode e l'assenza di `/data`;
4. scrive atomicamente soltanto il file di stato del plugin;
5. può gestire soltanto l'unità systemd dichiarata nel manifest root-owned.

La regola sudo elenca separatamente `ssh`, `vnc` e `companion`. Aggiungere un
nuovo plugin richiede quindi anche un aggiornamento intenzionale della policy.

### Bundle firmati da USB

Un bundle esterno deve avere accanto una firma detached con suffisso `.asc` e
trovarsi su un volume realmente montato in uno slot da `/stick` a `/stick9`.
`gpgv` verifica la
firma contro il keyring root-owned, l’estrazione rifiuta percorsi assoluti o
`..`, e il manifest deve dichiarare lo stesso `Package` del Debian `amd64`.
L’importazione è fail-closed: senza keyring o firma valida non installa nulla.

La chiave deve essere verificata fuori banda e installata dall’amministratore in
MAINTENANCE; non va accettata dalla stessa USB del bundle senza averne prima
controllato impronta e provenienza. Per una chiave ASCII già verificata:

```bash
gpg --dearmor < PRODUTTORE-PLUGIN.asc | sudo tee \
  /etc/wasalight/trusted-plugin-keys.gpg >/dev/null
sudo chown root:root /etc/wasalight/trusted-plugin-keys.gpg
sudo chmod 0644 /etc/wasalight/trusted-plugin-keys.gpg
```

```bash
sudo wasalight-plugin-bundle /stick/plugin-example.tar.gz
```

## Manifest

Esempio minimo:

```ini
[Plugin]
Id=example
Name=Example Tool
Description=Funzione dimostrativa
Version=1
MinimumWasalight=2026.08.09.3
Category=Services
Icon=applications-system
Homepage=https://example.org
License=MIT
Package=example
Dependencies=network,systemd
BackupPaths=/data/plugins/example
UpdateChannel=pinned
InstalledCheck=/usr/bin/example
DefaultEnabled=false

[Runtime]
Type=systemd
Unit=example.service
AutoEnable=true
ActiveLabel=Active
InactiveLabel=Stopped

[Control runtime]
Label=Servizio attivo
State=active
OnAction=start
OffAction=stop
Modes=show,maintenance

[Action start]
Label=Start
Command=/usr/local/sbin/wasalight-example-control start
Privilege=root
Modes=show,maintenance
```

L'ID deve coincidere con il nome della directory. `MinimumWasalight` impedisce
di abilitare o avviare il plugin con un core troppo vecchio. `InstalledCheck` determina se
il software è realmente disponibile. Un runtime può essere `systemd`, `process`
oppure omesso. Ogni azione dichiara modalità ammesse, eventuale conferma,
privilegio e se deve essere avviata come processo separato. Una sezione
`[Control ID]` trasforma due azioni esplicite in un toggle: `State` seleziona
lo stato `active` oppure `persistent`, mentre `OnAction` e `OffAction` indicano
le operazioni. Le azioni collegate non vengono duplicate come pulsanti. Lo
schema è generico e riutilizzabile dai servizi futuri. I metadati `Homepage`,
`License`, `Package`, `Dependencies`, `BackupPaths` e `UpdateChannel` sono
esposti anche nell’output JSON e preparano catalogo, backup e aggiornamenti
futuri senza concedere privilegi aggiuntivi.

## Wasalight Control

La nuova applicazione GTK3 resta massimizzata, non fullscreen, per mantenere
Tint2 accessibile. Le schede sono:

- **Stato**: stato completo, aggiornamento e cambio tra SHOW e MAINTENANCE;
- **MagicQ**: programmi ChamSys rilevati;
- **Servizi**: stato e azioni dei plugin abilitati;
- **Applicazioni**: programmi registrati;
- **Supporto**: rete, schermo, touch, audio e diagnostica;
- **Plugin**: disponibilità e abilitazione persistente.

SSH e VNC sono servizi fondamentali e compaiono soltanto in **Servizi**.
`Optional=false` impedisce di disabilitarli come plugin. Companion è invece un
componente opzionale: dalla scheda **Plugin** può essere installato,
abilitato/disabilitato e aggiornato in MAINTENANCE.

Per SSH e VNC i toggle **Servizio attivo** e **Avvio automatico** hanno lo stesso
aspetto e restano indipendenti. Il secondo gestisce un flag separato sotto
`/data/system/service-flags`. Il registro espone il campo JSON `persistent` e
aggiunge `AUTO` o `MANUALE` allo stato. L'autostart VNC può essere abilitato
soltanto dopo aver creato la password VNC persistente.

Il Control Center legge i launcher `.desktop` da `apps.d`. Le azioni plugin
vengono aggiornate periodicamente senza nascondere Tint2 o chiudere il centro di
controllo. Control mantiene una sola istanza per sessione grafica; una nuova
attivazione porta in primo piano la finestra esistente. L'aggiornamento periodico
di stato e plugin viene eseguito fuori dal thread GTK e ricostruisce le schede
soltanto quando i dati cambiano.

## Limiti dei plugin esterni

Il bundle deve essere costruito e firmato fuori dalla console. Wasalight non
importa automaticamente nuove chiavi e non accetta manifest modificabili sotto
`/data`. Migrazioni complesse e downgrade di pacchetti restano responsabilità
del produttore del plugin.
