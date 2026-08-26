# Touchscreen: configurazione e collaudo

L'appliance usa Xorg con il driver `libinput`. I touchscreen USB che il kernel
classifica come `ID_INPUT_TOUCHSCREEN=1` vengono rilevati senza dipendere dal
nome commerciale del dispositivo. L'installer aggiunge `xinput` e
`libinput-tools` per configurazione e diagnosi.

## Comportamento predefinito

La configurazione iniziale usa la modalità `auto`. All'avvio della sessione
grafica il touchscreen viene associato al monitor soltanto quando sono presenti
**esattamente un touchscreen e un'uscita video connessa**. Con due monitor o due
touchscreen non viene fatta alcuna scelta implicita: `wasalight-status` segnala
`target: attention` e occorre configurare l'associazione manualmente.

Il gestore unico `wasalight-input-watch` rileva i cambiamenti dei dispositivi di
input e delle uscite video, riapplica l'associazione touchscreen e gestisce la
visibilità del puntatore. Pubblica inoltre lo stato runtime condiviso sotto
`/run/user/<uid>`, senza mantenere due processi di rilevamento separati.

La pagina **Touchscreen** di Wasalight Control permette di scegliere modalità,
dispositivo, schermo e rotazione e offre una prova visuale a schermo intero.

## Diagnosi

Eseguire questi comandi dal terminale della sessione grafica dell'utente
`chamsys`:

```bash
wasalight-touch-status
xrandr --query
```

Il primo comando mostra:

- percorso della configurazione attiva;
- modalità automatica, manuale o disabilitata;
- rotazione configurata;
- uscite video connesse;
- nome Xorg, chiave persistente, ID corrente e nodo `/dev/input/event*` di ogni
  touchscreen;
- stato `ready`, `attention` oppure `disabled`.

Per verificare il riconoscimento a livello kernel/libinput, anche fuori dalla
sessione grafica:

```bash
sudo libinput list-devices
sudo libinput debug-events
```

Il secondo comando stampa gli eventi in tempo reale e termina con `Ctrl+C`.
Durante uno show è preferibile non lasciarlo in esecuzione.

## Un touchscreen e un monitor

La modalità predefinita è sufficiente. Per ripristinarla esplicitamente:

```bash
wasalight-touch-config auto
```

Il comando salva la scelta e la applica subito.

## Più monitor o più touchscreen

Prima elencare i nomi esatti:

```bash
wasalight-touch-config list
```

Associare quindi il touchscreen all'uscita desiderata. I nomi contenenti spazi
devono essere racchiusi tra virgolette:

```bash
wasalight-touch-config set "ILITEK ILITEK-TP" HDMI-1 normal
```

`DEVICE` deve coincidere con un nome o con una `key` mostrata sotto
`TOUCHSCREENS`; `OUTPUT` deve coincidere con un nome mostrato sotto `OUTPUTS`.
La chiave deriva, in ordine di preferenza, dal seriale hardware o dalla porta
fisica USB. Usare la chiave quando due pannelli hanno lo stesso nome. I numeri
ID di Xorg e i nodi `/dev/input/event*` non vanno salvati perché possono
cambiare dopo un riavvio o una riconnessione.

Esempio con due pannelli identici:

```bash
wasalight-touch-config set "pci-0000:00:14.0-usb-0:2:1.0" HDMI-1 normal
```

## Rotazione

I valori ammessi sono:

| Valore | Correzione degli assi touch |
| --- | --- |
| `normal` | nessuna rotazione aggiuntiva |
| `right` | 90 gradi in senso orario |
| `inverted` | 180 gradi |
| `left` | 90 gradi in senso antiorario |

Esempio:

```bash
wasalight-touch-config set "ILITEK ILITEK-TP" HDMI-1 right
```

La rotazione modifica gli assi del touch, non l'immagine del monitor. Impostare
prima l'orientamento video con `lxrandr`, poi provare `normal`; usare una
correzione diversa solo se il punto toccato non coincide con l'immagine. La
matrice applicata viene combinata con la calibrazione predefinita fornita dal
driver, anziché sostituirla.

## Disabilitare o ripristinare la gestione

Per non applicare associazioni o rotazioni:

```bash
wasalight-touch-config disable
```

Per tornare alla scelta automatica:

```bash
wasalight-touch-config auto normal
```

## Persistenza

Con `/data` montato, la configurazione viene salvata qui:

```text
/data/system/touchscreen/config
```

Il file appartiene all'utente `chamsys` e sopravvive ai riavvii in SHOW mode.
Se `/data` non è disponibile, viene usato il fallback
`/home/chamsys/.config/wasalight-touch/config`; tale fallback non offre la stessa
garanzia di persistenza con overlayroot attivo.

## Tastiera virtuale

Onboard è un componente standard di Wasalight. Non viene aperta automaticamente
e non interferisce con quella di MagicQ: quando è chiusa non resta alcun processo
residente. Il pulsante **Tastiera** posto a destra nella barra inferiore funziona
da interruttore: il primo tocco la apre sopra la barra, il secondo la chiude.
Non viene ripetuto in **Wasalight Control → Applicazioni**. Il comando equivalente
è `wasalight-keyboard-toggle`. Onboard non aggiunge una seconda icona nell'area di
notifica e non usa apertura o chiusura automatica: resta visibile quando cambia
il focus e viene chiuso soltanto premendo di nuovo il pulsante verde. Su Ubuntu
24.04 usa il backend GTK di Onboard, più stabile quando il sistema espone
contemporaneamente touchscreen/tablet e mouse; l'installer include inoltre il
typelib AT-SPI raccomandato da Onboard.

Il toggle distingue la finestra realmente visibile dal solo processo Python.
Se Onboard viene chiuso con il proprio pulsante X ma resta attivo senza alcuna
finestra mappata, il tocco successivo elimina l'istanza nascosta e apre subito
una nuova tastiera. La chiusura attende prima l'uscita normale e usa un arresto
forzato soltanto se Onboard interpreta `SIGTERM` come semplice richiesta di
nascondersi.

La geometria viene calcolata dalla risoluzione corrente e occupa il 64% della
larghezza e il 24% dell’altezza. Usa il tema Nightshade con il font condensato
e senza grazie `DejaVu Sans condensed bold`. Se il window manager non riesce a posizionarla,
Onboard resta comunque disponibile usando la propria geometria salvata.
Quando il tema Nightshade è presente viene selezionato automaticamente per
integrarsi con l’interfaccia scura Wasalight.

## Limiti e criteri di sicurezza

- Non viene selezionato automaticamente un monitor in una configurazione
  ambigua.
- La calibrazione geometrica fine dipende dall'hardware; il progetto gestisce
  associazione e rotazione, non una procedura interattiva a punti.
- Driver proprietari o touchscreen non esposti come dispositivi Linux standard
  richiedono una procedura specifica del produttore.
- Ogni modello deve superare la checklist hardware prima dell'uso durante uno
  spettacolo.
