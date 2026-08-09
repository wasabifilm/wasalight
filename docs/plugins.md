# Plugin Wasalight e Control Center

Wasalight `2026.08.09.3` introduce un registro dichiarativo per le funzioni
opzionali e una sola interfaccia touch, **Wasalight Control**. Il precedente
comando `wasalight-hub` resta disponibile come alias e apre la nuova interfaccia.

## Obiettivi e confini

Il registro plugin descrive nome, versione, disponibilità, stato runtime e
azioni esposte all'operatore. Non sostituisce APT e non esegue script di
installazione scaricati da Internet. In questa prima versione i manifest sono
forniti dal repository Wasalight e installati sotto un percorso protetto da
root. Questo evita che un file modificabile dall'utente possa trasformarsi in
un comando amministrativo.

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
InstalledCheck=/usr/bin/example
DefaultEnabled=false

[Runtime]
Type=systemd
Unit=example.service
AutoEnable=true
ActiveLabel=Active
InactiveLabel=Stopped

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
privilegio e se deve essere avviata come processo separato.

## Wasalight Control

La nuova applicazione GTK3 resta massimizzata, non fullscreen, per mantenere
Tint2 accessibile. Le schede sono:

- **Dashboard**: stato completo e azioni principali MagicQ/Update/Files;
- **MagicQ**: programmi ChamSys rilevati;
- **Services**: stato e azioni dei plugin abilitati;
- **Applications**: programmi registrati;
- **Support**: rete, display, touch, audio e diagnostica;
- **Plugins**: disponibilità ed enable/disable persistente.

Il Control Center continua a leggere i launcher `.desktop` da `apps.d`, quindi
il vecchio sistema di registrazione applicazioni rimane compatibile. Le azioni
plugin vengono aggiornate periodicamente senza nascondere Tint2 o chiudere il
centro di controllo.

## Aggiunta futura di plugin esterni

Prima di supportare download o bundle USB bisognerà definire pacchetti `.deb`
firmati, verifica dell'origine, dipendenze dichiarate, migrazioni e rollback.
Fino ad allora copiare manualmente manifest modificabili sotto `/data` non è
supportato intenzionalmente.
