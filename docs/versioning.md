# Versionamento Wasalight

La prima release stable sarà l’unico punto di partenza supportato. Le build di
sviluppo precedenti non fanno parte del percorso di aggiornamento: devono essere
sostituite da un’installazione pulita della ISO candidata.

## Formato

Wasalight usa un numero CalVer nel formato:

```text
AAAA.MM.GG.BUILD
```

Esempio: `2027.03.14.2` è la seconda build pubblicata il 14 marzo 2027. Il numero
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
ramo Wasalight, canali `stable`/`debug`, API GitHub Releases, file dei firmatari,
URL del controllo versione, basi Canonical dell'ISO Builder con
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
- `CHANNEL`: `STABLE` per le release firmate o `DEBUG` per l’ultimo `main`;
- `MAGICQ`: stato, versione del pacchetto MagicQ letta dal database `dpkg` e
  modalità di avvio, per esempio `READY · 1.9.8.3 · AUTO` (è indipendente dalla
  versione Wasalight);
- `UPDATE CODE MATCH`: versione installata uguale al checkout in
  `/data/system/wasalight`;
- `UPDATE READY`: checkout persistente più recente del sistema installato;
- `UPDATE CHECKOUT OLDER`: checkout più vecchio, per esempio dopo un rollback;
- `UPDATE NOT CHECKED`: checkout o file `VERSION` non ancora disponibile;
- `RECOVERY REQUIRED`: una transazione è rimasta `running` o `failed` e deve
  essere ripresa, riparata oppure annullata con rollback.

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
4. creare il commit e il tag annotato SSH firmato `vAAAA.MM.GG.BUILD`;
5. verificare localmente il tag con lo stesso file `allowed_signers` distribuito
   alle console;
6. pubblicare il tag e una GitHub Release non prerelease, quindi renderla
   immutabile prima di considerarla disponibile sul canale stable.

Anche le ISO della release devono essere costruite indicando il tag esatto,
così il primo avvio installa quella revisione anziché il successivo `main`:

```bash
bash Minimal-ISO-Builder/make-wasalight-minimal.sh \
  --wasalight-ref "v$(cat VERSION)"
```

Configurazione tipica della postazione di rilascio, indicando una chiave privata
protetta da passphrase e mai inclusa nel repository:

```bash
git config gpg.format ssh
git config user.signingkey ~/.ssh/wasalight_release_ed25519
git tag -s -a "v$(cat VERSION)" -m "Wasalight $(cat VERSION)"
git -c gpg.format=ssh \
  -c gpg.ssh.allowedSignersFile=installer/templates/rootfs/etc/wasalight/update-signers \
  verify-tag "v$(cat VERSION)"
```

Il file dei firmatari contiene soltanto la chiave pubblica, per esempio:

```text
release@wasalight.local ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA...
```

Se il file non contiene una chiave reale, la release non è immutabile, la firma
non è valida oppure tag e `VERSION` differiscono, il canale stable si ferma senza
ripiegare su debug.

Un aggiornamento che fallisce prima dei controlli finali non modifica la versione
installata e resta quindi riconoscibile come incompleto.
