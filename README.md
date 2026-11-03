# RAMDISK-XL
for Commodore64 - RAMDISK XL (Extended)

RAM-Disk XL is a machine-language utility for the Commodore 64 that turns the "hidden" RAM underneath the ROMs into a small virtual disk. It allows you to save and recall in a few moments:
- **BASIC** programs;
- complete **screens** (characters and color);
- any **memory areas**;
- **assembly programs**, with their relative entry point.

Commands are issued from the BASIC prompt, preceded by the `@` character (a "wedge"): for example `@P "SCREEN1"`.

The program resides in `$C000-$CFFF`. The data resides in the RAM located under the BASIC ROM, under the I/O area, and under the KERNAL ROM, therefore **they do not take anything away from the 38,911 bytes of BASIC**.

## Technical Characteristics
| Item                | Value                                              |
|---------------------|----------------------------------------------------|
| Capacity            | 79 blocks of 256 bytes (20,224 bytes)              |
| Dir entries         | 10 (indices from 0 to 9)                           |
| Name Lenght         | up to 15 characters                                |
| Blocks 0-31         | RAM `$A000-$BFFF` (under BASIC ROM)                |
| Blocks 32-78        | RAM `$D000-$FEFF` (under I/O and KERNAL)           |
| Unused              | page `$FF00-$FFFF` (contains hardware vectors)     |
| Resident program    | `$C000-$CF2F` (tables include)                     |
| User area (`@G`)    | `$CF30-$CFFF` (208 bytes)                          |
| Disk device         | 8 (fisso nel codice)                               |
|---------------------|----------------------------------------------------|

Copyright (c)2026 by KymyA
License and Terms of Use
This source code for the Commodore 64 is distributed for educational, study, and personal entertainment purposes.
You are permitted to download, modify, and distribute the code provided that:
Original attribution to the author is preserved.
Any significant modifications are reported to the author (e.g., via Pull Request on GitHub).
The code, its components, or compiled binaries are NOT used in any way for commercial purposes or sale without prior written authorization.


# RAMDISK-XL
per Commodore64 - RAMDISK XL (Extended)

RAMDisk XL è un’utility in linguaggio macchina per il Commodore 64 che trasforma la RAM «nascosta» sotto le ROM in un piccolo disco virtuale. Permette di salvare e richiamare in pochi istanti:

- programmi **BASIC**;
- **schermate** complete (caratteri e colore);
- **zone di memoria** qualsiasi;
- **programmi in assembly**, con relativo punto di ingresso.

I comandi si danno dal prompt del BASIC, preceduti dal carattere `@` (una «wedge»): per esempio `@P "SCHERMO1"`.

Il programma risiede in `$C000-$CFFF`. I dati stanno nella RAM che si trova sotto la ROM del BASIC, sotto l’area I/O e sotto la ROM del KERNAL, quindi **non sottraggono nulla ai 38911 byte del BASIC**.

## Caratteristiche tecniche

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

Copyright (c)2026 by KymyA
Questo codice sorgente per Commodore 64 è distribuito per scopi didattici, di studio e di intrattenimento personale.

È permesso scaricare, modificare e distribuire il codice a condizione che:
1. Venga mantenuta l'attribuzione originale all'autore.
2. Eventuali modifiche significative vengano segnalate all'autore (es. tramite Pull Request su GitHub).
3. Il codice, le sue parti o i binari compilati NON vengano usati in alcun modo per scopi commerciali o di vendita senza autorizzazione scritta.
