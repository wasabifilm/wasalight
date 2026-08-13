# Versionamento Wasalight

La prima base supportata del progetto è `2026.08.09.6`. Versioni e prototipi
precedenti non fanno parte del percorso di aggiornamento supportato.

## Formato

Wasalight usa un numero CalVer nel formato:

```text
AAAA.MM.GG.BUILD
```

Esempio: `2026.08.08.1` è la prima build pubblicata l’8 agosto 2026. Il numero
`BUILD` parte da `1` e aumenta quando vengono pubblicate più build nello stesso
giorno. Una nuova data riparte dalla build `1`.

Il formato non usa `+`: in Semantic Versioning quel simbolo introduce metadati
che non partecipano alla precedenza, mentre per Wasalight il numero di build deve
essere confrontabile con `sort -V`.

## Sorgenti dichiarative

La versione ufficiale del codice è contenuta nel file `VERSION` alla radice del
repository. Gli script la leggono; non deve essere duplicata manualmente nel
codice.

`release-manifest.ini` centralizza invece i valori della release che prima
erano distribuiti negli script: Ubuntu supportato, architettura, repository e
ramo Wasalight, URL del controllo versione, basi Canonical dell'ISO Builder con
nomi/dimensioni/checksum, versione/commit/checksum di Companion e requisiti del
pacchetto MagicQ. I campi `VersionFile` collegano il manifesto ai rispettivi file
di versione; `VERSION` alla radice resta l’unica sorgente del numero CalVer.

```bash
./install.sh --version
```

L’installer valida il formato prima di modificare il sistema. La versione viene
registrata soltanto dopo il superamento dei controlli finali, in:

```text
/etc/wasalight/version
/data/system/installed-version
/etc/wasalight/commit
/data/system/installed-commit
```

I primi due percorsi registrano il numero CalVer; gli altri due il commit Git
esatto. Le copie sotto `/data` sono persistenti e utili per diagnosi e recupero.
L’updater usa la coppia versione/commit per riconoscere un vero no-op e impedire
che una release venga modificata senza incrementarne `VERSION`.

## Stato sul desktop

Il pannello mostra:

- `VERSION`: versione realmente installata;
- `MAGICQ`: stato, versione del pacchetto MagicQ letta dal database `dpkg` e
  modalità di avvio, per esempio `READY · 1.9.8.3 · AUTO` (è indipendente dalla
  versione Wasalight);
- `UPDATE CODE MATCH`: versione installata uguale al checkout in
  `/data/system/wasalight`;
- `UPDATE READY`: checkout persistente più recente del sistema installato;
- `UPDATE CHECKOUT OLDER`: checkout più vecchio, per esempio dopo un rollback;
- `UPDATE NOT CHECKED`: checkout o file `VERSION` non ancora disponibile.

`CODE MATCH` confronta il sistema con il codice già scaricato, non interroga
continuamente GitHub. Eseguire `sudo wasalight-update` per aggiornare il checkout,
verificare la versione disponibile e installarla.

Anche `wasalight-status` riporta stato, versione e modalità in una sola voce
`MAGICQ`. Se il pacchetto non è installato, il pannello mostra `NOT INSTALLED`
invece di dedurre una versione dal nome del file `.deb`.

## Pubblicare una build

Prima del commit destinato alla pubblicazione:

1. impostare in `VERSION` la data della release;
2. usare build `1`, oppure incrementarla se esiste già una build nella stessa
   data;
3. eseguire `./tests/verify-project.sh`;
4. creare il commit e, quando si inizieranno a pubblicare release formali, il tag
   Git `vAAAA.MM.GG.BUILD`.

Un aggiornamento che fallisce prima dei controlli finali non modifica la versione
installata e resta quindi riconoscibile come incompleto.
