# Assistenza remota SSH

Wasalight installa OpenSSH Server per consentire una manutenzione remota
cifrata. Per impostazione predefinita il servizio è disabilitato e non ascolta
sulla rete.

## Uso dal touchscreen

Usare **Wasalight Control → Servizi → SSH**.

Il toggle **Servizio attivo** agisce soltanto sulla sessione corrente.
Il toggle **Avvio automatico** abilita o disabilita separatamente la persistenza
ai riavvii, salvata nel flag `/data/system/service-flags/ssh-autostart`. Conky mostra:

- `SSH  ACTIVE · MANUAL` per l’attivazione temporanea;
- `SSH  ACTIVE · AUTO` quando partirà anche ai prossimi avvii;
- `SSH  OFF · MANUAL/AUTO` quando non è in ascolto, indicando comunque il flag.

## Collegamento

Da Linux o macOS:

```bash
ssh chamsys@192.168.1.50
```

Sostituire l’indirizzo con quello mostrato dal pulsante o da Conky. L’utente è
`chamsys` e la password è la sua password Linux. Wasalight non genera, copia o
registra altre credenziali SSH.

## Avvio automatico

Il metodo normale è usare **Avvio automatico** nella scheda **Servizi**. La scelta
rimane in `/data` anche in SHOW protetto. Per impostare lo stesso flag durante
l’installazione o un aggiornamento in MAINTENANCE si può usare:

```bash
sudo ./install.sh --with-ssh --no-protection
```

Al termine riattivare la protezione quando la configurazione è conclusa.
`--without-ssh` forza invece il flag persistente su `disabled`.

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
