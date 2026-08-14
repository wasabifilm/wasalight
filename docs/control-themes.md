# Temi di Wasalight Control

Wasalight Control separa colori e struttura GTK. La palette installata si trova
in `/usr/local/share/wasalight-control/themes/console-dark.ini`.

Il tema predefinito è `console-dark.ini`, ispirato alle superfici delle console
professionali: grigi antracite, blu tecnico e verde Wasabi per selezioni e stati
positivi. Non esiste una variante chiara né un selettore nell’interfaccia.

## Modificare la palette

Modificare `ui/themes/console-dark.ini`. La palette deve definire tutti i token
seguenti:

```ini
[theme]
name=Console Dark

[colors]
background=#1b1f20
panel=#282d30
panel_alt=#353b3e
surface=#222729
surface_hover=#303639
separator=#4a5154
text=#f1f3f3
text_muted=#aeb5b7
technical=#0088bd
technical_hover=#079bd2
brand=#76bd22
brand_hover=#8dcc3e
brand_text=#10130d
warning=#e0a928
danger=#b93636
danger_hover=#ce4646
```

I colori accettano soltanto il formato esadecimale `#RRGGBB`. Se il file è
incompleto, non valido o assente, Control usa automaticamente la palette
incorporata `Console Dark`, evitando che un errore grafico impedisca l’avvio.

I nomi dei token descrivono la funzione, non il singolo widget. Questo permette
di cambiare l’identità cromatica senza modificare il codice Python o il CSS.
Il pulsante **Chiudi** dell’intestazione usa intenzionalmente `danger` e
`danger_hover`: è più grande degli altri controlli di intestazione e resta
immediatamente riconoscibile anche su touchscreen.
