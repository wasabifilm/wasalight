# Assistenza remota temporanea con VNC

Wasalight usa `x11vnc` per condividere la sessione Xorg/Openbox esistente
dell'utente `chamsys`. Non crea un secondo desktop e permette quindi di vedere
esattamente ciò che appare sul monitor della postazione MagicQ.

Dal desktop touch usare il pulsante **VNC** oppure **Wasalight Control → Services**.
Lo stesso pulsante avvia la condivisione quando è spenta e
propone di fermarla quando è già attiva. Al primo utilizzo apre un terminale
dedicato per impostare la password senza inserirla negli argomenti dei processi
o nei log.

## Proprietà di sicurezza

- VNC è disabilitato per impostazione predefinita.
- Non esiste un servizio systemd VNC e non viene eseguito alcun avvio automatico.
- Il processo termina con `magicq-vnc-stop` o al riavvio della macchina.
- L'accesso richiede una password VNC distinta dalla password Linux.
- La password è salvata con permessi `0600` in `/data/system/vnc/passwd`.
- PID e log sono conservati soltanto sotto `/run/user/...` oppure `/tmp`.

Il protocollo VNC classico non cifra completamente il traffico. La modalità
LAN deve essere usata soltanto su una rete locale fidata e disattivata appena
terminata l'assistenza.

## Avvio sulla rete locale

Aprire un terminale nella sessione grafica `chamsys` ed eseguire:

```bash
magicq-vnc-start
```

Al primo avvio viene chiesta la password VNC. Il comando stampa un indirizzo
simile a:

```text
vnc://192.168.1.50:5900
```

Su macOS aprire Finder, premere `Cmd+K` e inserire quell'indirizzo. La finestra
remota mostra la sessione Openbox già in esecuzione.

## Modalità cifrata tramite SSH

Se Wasalight è stato installato con `--with-ssh`, avviare VNC in ascolto
soltanto sull'interfaccia locale:

```bash
magicq-vnc-start --localhost
```

Sul computer remoto creare il tunnel, sostituendo utente e indirizzo:

```bash
ssh -L 5900:localhost:5900 wasabi@192.168.1.50
```

Lasciare aperto il terminale SSH e collegare il client a:

```text
vnc://localhost:5900
```

In questa configurazione il traffico attraversa il tunnel SSH cifrato.

## Stato e arresto

Controllare lo stato generale:

```bash
magicq-status
```

Arrestare VNC:

```bash
magicq-vnc-stop
```

Il comando termina soltanto il processo `x11vnc` avviato e registrato da
Wasalight; un PID obsoleto non viene usato per terminare processi estranei.

## Cambio password

Arrestare prima il server e impostare una nuova password:

```bash
magicq-vnc-stop
magicq-vnc-password
magicq-vnc-start
```

## Log diagnostico

Il percorso del log viene stampato da `magicq-vnc-start`. Normalmente è:

```text
/run/user/UID/wasalight-x11vnc.log
```

Per leggerlo:

```bash
cat "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wasalight-x11vnc.log"
```

## Rimozione completa

Per rimuovere VNC dalla macchina, entrare in MAINTENANCE mode, riavviare e usare
un account amministratore:

```bash
sudo apt purge -y x11vnc
sudo apt autoremove -y
sudo rm -f /data/system/vnc/passwd
```

Una successiva esecuzione dell'installer Wasalight reinstallerà `x11vnc`,
perché fa parte delle dipendenze dell'appliance.
