# Licenza, marchio e citazione

## Codice e documentazione

Wasalight è distribuito sotto **Apache License 2.0**, una licenza open source
approvata OSI. Il testo completo è nel file `LICENSE` alla radice del
repository. La licenza consente uso, modifica e distribuzione, anche
commerciale, nel rispetto delle sue condizioni.

Michele Moser conserva il copyright sul codice originale. Pubblicare il
progetto con una licenza open source non trasferisce la titolarità e non
impedisce al titolare di vendere copie, appliance, installazione, assistenza,
garanzia, aggiornamenti o altri servizi. Anche i destinatari possono usare e
ridistribuire commercialmente il software: il diritto esclusivo di essere
l'unico venditore non è compatibile con la normale definizione di open source.

Le distribuzioni e le opere derivate devono conservare una copia della licenza,
indicare i file modificati e includere in forma leggibile le attribuzioni del
file `NOTICE` quando pertinenti. La citazione ufficiale è:

> Wasalight — created by Michele Moser / Wasabi Lightbulbfarm.

Il file `CITATION.cff` contiene gli stessi dati in formato riconosciuto da
GitHub e dagli strumenti bibliografici.

## Nome, marchio e distribuzioni ufficiali

La sezione 6 della licenza Apache 2.0 non concede diritti sui marchi, salvo il
normale uso necessario a descrivere l'origine del software. Le regole per i
nomi Wasalight e Wasabi Lightbulbfarm, i fork, le appliance e le espressioni
“ufficiale” o “certificato” sono definite in [`TRADEMARKS.md`](../TRADEMARKS.md).

In sintesi, è sempre possibile citare correttamente Wasalight e dichiarare che
un prodotto deriva dal progetto. Una versione modificata deve però avere nome e
identità grafica distinti, non può suggerire approvazione o assistenza del
titolare e deve dichiarare di non essere una distribuzione ufficiale.

## Logo Wasabi Lightbulbfarm

I due PNG in `assets/branding/` sono esclusi da Apache License 2.0 e rimangono
protetti da copyright. La licenza specifica della cartella consente di
mantenerli e redistribuirli invariati soltanto come branding incorporato in una
distribuzione ufficiale Wasalight non modificata.

Una derivazione o una versione rinominata deve rimuovere o sostituire quei file,
oppure ottenere un’autorizzazione scritta. Il software continua a funzionare con
un logo PNG sostitutivo seguendo `docs/boot-branding.md`.

Una copia ufficiale integra può conservare il branding incorporato nei limiti
di `assets/branding/LICENSE`, ma il rivenditore non acquisisce per questo una
qualifica di distributore autorizzato, partner o centro assistenza.

## Vendita e servizi commerciali

Il titolare può vendere, tra l'altro:

- hardware con Wasalight preinstallato e collaudato;
- immagini e procedure ufficiali, installazione e configurazione;
- assistenza, manutenzione, garanzia e aggiornamenti gestiti;
- certificazione e autorizzazioni commerciali separate per il branding.

La licenza Apache 2.0 resta applicabile al codice incluso. Contratti di vendita,
supporto o garanzia possono regolare separatamente il servizio offerto, senza
ridurre i diritti che la licenza open source concede sulle copie del software
già ricevute.

## Contatti del titolare

I contatti pubblici per attribuzione, autorizzazioni sul branding e richieste
commerciali sono:

> Wasabi sas di Michele Moser & C.<br>
> Viale Verona 190/11, 38123 Trento, Italy<br>
> P. IVA IT02274000229<br>
> [www.wasabi.eu](https://www.wasabi.eu/) ·
> [info@wasabi.eu](mailto:info@wasabi.eu)

Social e collegamenti ufficiali aggiornati sono raccolti in
[`CONTACT.md`](../CONTACT.md).

## Instagram

Per post, storie, reel o fotografie che mostrano Wasalight è gradito il tag:

```text
@wasabi_lightbulbfarm
```

Il tag è una richiesta volontaria, non una condizione della licenza software.
Una condizione che imponesse azioni su uno specifico social network introdurrebbe
un vincolo aggiuntivo non presente nella licenza Apache 2.0 e renderebbe meno
chiaro lo status open source del progetto.

## Componenti non inclusi

Il pacchetto proprietario ChamSys MagicQ non è contenuto nel repository e non è
coperto dalla licenza Wasalight. Ogni utilizzatore deve procurarselo e rispettare
separatamente le condizioni del produttore.

Anche Bitfocus Companion e il tooling CompanionPi sono componenti esterni:
l'opzione `--with-companion` li scarica dai repository ufficiali, ma non li
incorpora nel repository Wasalight. Restano soggetti alle licenze e alle note di
terze parti pubblicate da Bitfocus.

Quando Companion è installato, Wasalight prova inoltre a scaricare l’icona Linux
ufficiale dal repository `bitfocus/companion` a un commit fissato e ne verifica
lo SHA-256 prima dell’uso. Il core Companion è pubblicato da Bitfocus AS con
licenza MIT; l’icona resta un asset del progetto Bitfocus. Se il download o il
checksum non corrispondono viene mantenuta l’icona locale generica, senza usare
un file non verificato.
