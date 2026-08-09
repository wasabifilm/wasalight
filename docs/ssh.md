# Assistenza remota SSH

Wasalight installa OpenSSH Server per consentire una manutenzione remota
cifrata. Per impostazione predefinita il servizio è disabilitato e non ascolta
sulla rete.

## Uso dal touchscreen

Premere **SSH** sul desktop oppure usare **Wasalight Control → Services → SSH**.
Dopo la conferma, il servizio viene avviato e la finestra mostra
l’indirizzo di collegamento. Premendo nuovamente il pulsante è possibile
fermarlo.

L’attivazione fatta dal pulsante è temporanea: se il servizio non era stato
abilitato con `--with-ssh`, dopo il riavvio torna spento. Conky mostra:

- `SSH  ACTIVE · SESSION` per l’attivazione temporanea;
- `SSH  ACTIVE · AUTO` quando partirà anche ai prossimi avvii;
- `SSH  OFF` quando non è in ascolto.

## Collegamento

Da Linux o macOS:

```bash
ssh chamsys@192.168.1.50
```

Sostituire l’indirizzo con quello mostrato dal pulsante o da Conky. L’utente è
`chamsys` e la password è la sua password Linux. Wasalight non genera, copia o
registra altre credenziali SSH.

## Avvio automatico

Per mantenere SSH abilitato dopo ogni riavvio, eseguire l’installer in
MAINTENANCE con:

```bash
sudo ./install.sh --with-ssh --no-protection
```

Al termine riattivare la protezione quando la configurazione è conclusa.

## Sicurezza

- Attivare SSH soltanto su una rete fidata.
- Usare una password robusta per `chamsys`.
- Fermare il servizio dal pulsante quando la manutenzione è terminata.
- Il launcher grafico può eseguire soltanto i comandi controllati `start` e
  `stop`; non concede un comando `sudo` arbitrario.
- SSH cifra il traffico ed è preferibile a VNC diretto per terminale e tunnel.

Per verificare lo stato dalla macchina:

```bash
systemctl status ssh.service
ss -ltn | grep ':22 '
```
