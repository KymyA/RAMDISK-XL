# RAMDISK-XL
per Commodore64 - RAMDISK XL (Extended)

RAMDisk XL è un’utility in linguaggio macchina per il Commodore 64 che trasforma la RAM «nascosta» sotto le ROM in un piccolo disco virtuale. Permette di salvare e richiamare in pochi istanti:

- programmi **BASIC**;
- **schermate** complete (caratteri e colore);
- **zone di memoria** qualsiasi;
- **programmi in assembly**, con relativo punto di ingresso.

I comandi si danno dal prompt del BASIC, preceduti dal carattere `@` (una «wedge»): per esempio `@P "SCHERMO1"`.

Il programma risiede in `$C000-$CFFF`. I dati stanno nella RAM che si trova sotto la ROM del BASIC, sotto l’area I/O e sotto la ROM del KERNAL, quindi **non sottraggono nulla ai 38911 byte del BASIC**.

## 2. Caratteristiche tecniche

| Voce                | Valore                                             |
|---------------------|----------------------------------------------------|
| Capacità            | 79 blocchi da 256 byte (20.224 byte)               |
| Voci in directory   | 10 (indici da 0 a 9)                               |
| Lunghezza nome      | fino a 15 caratteri                                |
| Blocchi 0-31        | RAM `$A000-$BFFF` (sotto la ROM del BASIC)         |
| Blocchi 32-78       | RAM `$D000-$FEFF` (sotto I/O e KERNAL)             |
| Non utilizzata      | pagina `$FF00-$FFFF` (contiene i vettori hardware) |
| Programma residente | `$C000-$CF2F` (tabelle comprese)                   |
| Area utente (`@G`)  | `$CF30-$CFFF` (208 byte)                           |
| Dispositivo disco   | 8 (fisso nel codice)                               |
|---------------------|----------------------------------------------------|


Copyright (c)2026 by KymyA

Questo codice sorgente per Commodore 64 è distribuito per scopi didattici, di studio e di intrattenimento personale.

È permesso scaricare, modificare e distribuire il codice a condizione che:
1. Venga mantenuta l'attribuzione originale all'autore.
2. Eventuali modifiche significative vengano segnalate all'autore (es. tramite Pull Request su GitHub).
3. Il codice, le sue parti o i binari compilati NON vengano usati in alcun modo per scopi commerciali o di vendita senza autorizzazione scritta.
