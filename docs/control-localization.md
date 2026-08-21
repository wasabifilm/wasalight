# Localizzazione di Wasalight Control

Wasalight Control usa GNU gettext con dominio `wasalight-control`. Le stringhe
sorgente dell’interfaccia sono in inglese e ogni testo rivolto all’operatore
passa dalla funzione `_()` esportata da `wasalight_control.i18n`.

I cataloghi sorgente sono conservati in:

```text
ui/locale/it/LC_MESSAGES/wasalight-control.po
ui/locale/en/LC_MESSAGES/wasalight-control.po
```

L’installer aggiunge `gettext`, valida i cataloghi con `msgfmt --check` e
installa i file compilati sotto `/usr/local/share/locale`. Non vengono inseriti
file `.mo` generati nel repository.

## Scelta della lingua

La preferenza è salvata in `/data/system/control/language`, all’interno di una
directory persistente scrivibile esclusivamente dall’utente della sessione.
Sono ammessi `auto`, `en` e `it`. `auto` segue la locale della sessione; un
valore assente o non valido torna in modo sicuro alla selezione automatica.
L’installer inizializza le appliance esistenti e nuove con `it`, preservando la
lingua storica dell’interfaccia; `auto` rimane una scelta esplicita.
La variabile `WASALIGHT_CONTROL_LANGUAGE` è riservata a test e diagnostica.

Il selettore grafico è esposto nel menu lingua separato dalle pagine operative.
La nuova preferenza viene applicata al successivo accesso grafico, evitando di
dover ricostruire a caldo l'intero desktop e l'albero GTK.

## Aggiornare i cataloghi

Generare il template delle stringhe senza sovrascrivere le traduzioni:

```bash
xgettext --language=Python --keyword=_ --keyword=ngettext:1,2 \
  --from-code=UTF-8 --output=wasalight-control.pot \
  ui/wasalight-control-center.py ui/wasalight_control/*.py \
  ui/wasalight_control/pages/*.py
msgmerge --update ui/locale/it/LC_MESSAGES/wasalight-control.po \
  wasalight-control.pot
```

Prima di pubblicare, verificare ogni catalogo:

```bash
msgfmt --check --output-file=/dev/null \
  ui/locale/it/LC_MESSAGES/wasalight-control.po
```

Le frasi non devono essere costruite concatenando frammenti tradotti. Per valori
dinamici si usano placeholder nominati, ad esempio
`_("Version {version}").format(version=value)`. I plurali devono usare
`ngettext`.

I manifest plugin incorporati usano ancora testo italiano. Il catalogo inglese
ne contiene temporaneamente le traduzioni; i futuri manifest potranno esporre
campi localizzati senza modificare l’interfaccia GTK.

## Lingua dell'intera sessione

La preferenza salvata in `/data/system/control/language` è la fonte unica anche
per la sessione Wasalight, senza un secondo selettore o un altro file di
configurazione. `.xinitrc` carica l'helper root-owned
`/usr/local/libexec/wasalight-session-language` prima di Openbox. `auto`
conserva la locale ereditata dal sistema; `it` ed `en` impostano `LANG`,
`LANGUAGE` e `LC_MESSAGES` per il desktop e tutte le applicazioni avviate dalla
sessione. Valori assenti o non validi tornano in modo sicuro ad `auto`.

L'installer genera esplicitamente `en_US.UTF-8` e `it_IT.UTF-8`, senza cambiare
la locale globale di Ubuntu.

La localizzazione verrà estesa conservando i formati standard già utilizzati:

1. **Wasalight Control** continuerà a usare GNU gettext con dominio
   `wasalight-control` e stringhe sorgente in inglese.
2. **Dialoghi, script e utility autonome** usano il dominio gettext separato
   `wasalight-system`. L'helper comune root-owned `wasalight-i18n` configura il
   catalogo e offre un fallback inglese anche se gettext non è disponibile. I
   dialoghi di spegnimento e riavvio sono i primi strumenti migrati.
3. **Launcher e file `.desktop`** usano inglese nei campi base `Name=` e
   `Comment=` e le varianti standard `Name[it]=` e `Comment[it]=`. Wasalight
   Control seleziona la variante coerente con la propria preferenza; in modalità
   `auto` segue `LANGUAGE`, `LC_ALL`, `LC_MESSAGES` e `LANG`.
4. **Manifest dei plugin** adotteranno campi localizzati equivalenti, con
   fallback alla lingua base, eliminando progressivamente le traduzioni
   temporanee di stringhe italiane dal catalogo inglese.

Le icone grafiche non devono contenere parole e restano quindi indipendenti
dalla lingua. Vengono invece tradotti il nome mostrato sotto l’icona, la
didascalia, il tooltip, il testo accessibile e ogni conferma associata. Marchi e
nomi propri come Wasalight, MagicQ e Bitfocus Companion non vengono tradotti.

La verifica di qualità valida entrambi i domini gettext, controlla le varianti
localizzate dei launcher e fallisce se un nuovo testo
rivolto all’operatore viene aggiunto direttamente nel codice senza passare dal
meccanismo previsto. Il collaudo va eseguito in italiano, inglese e modalità
automatica, riaprendo la sessione grafica dopo ogni cambio lingua.

Il menu Openbox non duplica file XML: `wasalight-openbox-menu` lo rigenera in
modo atomico a ogni login, dopo l'applicazione della lingua di sessione.
