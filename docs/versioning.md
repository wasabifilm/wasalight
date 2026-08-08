# Versionamento Wasalight

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

## Sorgente unica

La versione ufficiale del codice è contenuta nel file `VERSION` alla radice del
repository. Gli script la leggono; non deve essere duplicata manualmente nel
codice.

```bash
./install.sh --version
```

L’installer valida il formato prima di modificare il sistema. La versione viene
registrata soltanto dopo il superamento dei controlli finali, in:

```text
/etc/wasalight/version
/data/system/installed-version
```

Il primo percorso descrive il sistema attivo. Il secondo è una copia persistente
utile per diagnosi e recupero.

## Stato sul desktop

Il pannello mostra:

- `VERSION`: versione realmente installata;
- `MAGICQ VER`: versione del pacchetto MagicQ realmente installato, letta dal
  database `dpkg` (è indipendente dalla versione Wasalight);
- `UPDATE CODE MATCH`: versione installata uguale al checkout in
  `/data/system/wasalight`;
- `UPDATE READY`: checkout persistente più recente del sistema installato;
- `UPDATE CHECKOUT OLDER`: checkout più vecchio, per esempio dopo un rollback;
- `UPDATE NOT CHECKED`: checkout o file `VERSION` non ancora disponibile.

`CODE MATCH` confronta il sistema con il codice già scaricato, non interroga
continuamente GitHub. Eseguire `sudo wasalight-update` per aggiornare il checkout,
verificare la versione disponibile e installarla.

Anche `magicq-status` riporta la versione installata alla voce `MAGICQ VER`. Se
il pacchetto non è installato, il pannello mostra `NOT INSTALLED` invece di
dedurre una versione dal nome del file `.deb`.

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
