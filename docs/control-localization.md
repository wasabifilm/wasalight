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

Il selettore grafico verrà esposto nella pagina **Sistema → Lingua**. La nuova
preferenza sarà applicata al successivo avvio di Control, evitando di dover
ricostruire a caldo l’intero albero GTK.

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

## Estensione pianificata all’intero desktop

La preferenza già salvata in `/data/system/control/language` diventerà la fonte
unica anche per la sessione Wasalight, senza aggiungere un secondo selettore o
un altro file di configurazione. Al successivo accesso Openbox, `auto` seguirà
la locale di sistema, mentre `it` ed `en` imposteranno la lingua della sessione
e di tutti gli strumenti Wasalight.

La localizzazione verrà estesa conservando i formati standard già utilizzati:

1. **Wasalight Control** continuerà a usare GNU gettext con dominio
   `wasalight-control` e stringhe sorgente in inglese.
2. **Dialoghi, script e utility autonome** useranno un dominio gettext separato
   `wasalight-system`. Una piccola libreria comune leggerà la stessa preferenza
   persistente prima di mostrare testi, pulsanti o messaggi d’errore.
3. **Launcher e file `.desktop`** useranno inglese nei campi base `Name=` e
   `Comment=` e le varianti standard `Name[it]=` e `Comment[it]=`. Wasalight
   Control selezionerà la variante coerente con la propria lingua anche quando
   questa differisce dalla locale predefinita del sistema.
4. **Manifest dei plugin** adotteranno campi localizzati equivalenti, con
   fallback alla lingua base, eliminando progressivamente le traduzioni
   temporanee di stringhe italiane dal catalogo inglese.

Le icone grafiche non devono contenere parole e restano quindi indipendenti
dalla lingua. Vengono invece tradotti il nome mostrato sotto l’icona, la
didascalia, il tooltip, il testo accessibile e ogni conferma associata. Marchi e
nomi propri come Wasalight, MagicQ e Bitfocus Companion non vengono tradotti.

La verifica di qualità dovrà estrarre e validare entrambi i domini gettext,
controllare le varianti localizzate dei launcher e fallire se un nuovo testo
rivolto all’operatore viene aggiunto direttamente nel codice senza passare dal
meccanismo previsto. Il collaudo va eseguito in italiano, inglese e modalità
automatica, riaprendo la sessione grafica dopo ogni cambio lingua.
