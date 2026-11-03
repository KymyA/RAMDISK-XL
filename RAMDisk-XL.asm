; ============================================================================
; RAM DISK XL - Commodore 64
; by Kymya - Versione Unificata per C64Studio
; ============================================================================

; ============================================================================
; COSTANTI E DEFINIZIONI
; ============================================================================

          !cpu 6510

*=$C000

; --- Costanti di sistema ---
STROUT              = $AB1E
PRINTWORD           = $BDCD
CURSORPOS           = $E50A
CHROUT              = $FFD2
CHRIN               = $FFCF
CHRGET              = $0073
BASIC_INTERPRETER   = $A7AE
SYNTAX_MANAGER      = $AF08
ERR_ILLEGAL_QTY     = $B248          ; LDX #$0E ; JMP $A437 (gia' nella ROM)
ERR_ILLEGAL_DIRECT  = $B3AB          ; LDX #$15 ; JMP $A437 (gia' nella ROM)
ERR_OUT_OF_MEMORY   = $A435          ; LDX #$10 ; JMP $A437 (gia' nella ROM)
USER_AREA          = $CF30          ; area utente (@G): da qui a $CFFF, inizialmente solo un RTS
PLOT                = $FFF0
SETNAM              = $FFBD
SETLFS              = $FFBA
OPENF               = $FFC0
CLOSEF              = $FFC3
CHKIN               = $FFC6
CHKOUT              = $FFC9
CLRCHN              = $FFCC

; --- Costanti hardware ---
BORDER_COLOR        = $D020
BACK_COLOR          = $D021
VIC_MEMORY          = $D018

; --- Variabili di sistema ---
BASIC_START         = $2B
BASIC_END           = $2D
TEXT_PTR            = $7A
BASIC_MODE          = $D7

; --- Costanti della RAM disk ---
; Area dati fisica: RAM nascosta sotto ROM, resa visibile con attiva_ram
; (config $01 = LORAM=0,HIRAM=0 -> $A000-BFFF, $D000-DFFF, $E000-FFFF TUTTA RAM).
; Regione 1: $A000-$BFFF = 32 blocchi da 256 byte (blocchi 0-31)
; Regione 2: $D000-$FFFF = 48 blocchi da 256 byte (blocchi 32-79)
RAMDISK_BASE1       = $A0            ; high byte iniziale regione 1 ($A000-$BFFF)
RAMDISK_BASE1_BLOCKS = 32            ; blocchi nella regione 1: ($C000-$A000)/$100 = 32
RAMDISK_BASE2       = $D0            ; high byte iniziale regione 2 ($D000-$FEFF)
RAMDISK_BASE2_BLOCKS = 47            ; blocchi nella regione 2: fino a $FEFF, si esclude
                                      ; l'ultima pagina $FF00-$FFFF (vettori hardware
                                      ; NMI/RESET/IRQ a $FFFA-$FFFF, non mascherabili
                                      ; da SEI in caso di RESTORE durante il banking)
TOTAL_BLOCKS        = 79             ; 32 + 47
MAX_ENTRY           = 10
DESCRIPTOR_BUFFER   = $033C          ; Tape buffer

; --- Zero page ---
Page0_A             = $FB
Page0_B             = $FC
Page0_C             = $FD
Page0_D             = $FE


; ============================================================================
; INIZIALIZZAZIONE
; ============================================================================

START:
    LDA  #6
    STA  BORDER_COLOR
    LDA  #14
    STA  BACK_COLOR
    LDA  #1
    STA  646
    JSR  intromsg
    
    ; --- Hook per il comando @ ---
    LDA  #<newgone
    STA  $0308
    LDA  #>newgone
    STA  $0309
    
    ; --- Equivalente di NEW, scritto a mano: la routine della ROM ($A644)
    ;     a un certo punto azzera lo stack pointer (parte di CLR), il che
    ;     e' sicuro solo se chiamata direttamente dall'interprete BASIC dal
    ;     prompt, non da dentro una SYS. Replichiamo qui lo stesso effetto
    ;     senza mai toccare lo stack. ---
    LDA  #$00
    LDY  #$01
    STA  ($2B), Y              ; azzera puntatore riga successiva (hi) - TXTTAB
    DEY
    STA  ($2B), Y              ; azzera puntatore riga successiva (lo) -> "programma vuoto"
    
    LDA  $2B                   ; VARTAB = TXTTAB + 2
    CLC
    ADC  #$02
    STA  $2D
    LDA  $2C
    ADC  #$00
    STA  $2E
    
    LDA  $2D                   ; ARYTAB = STREND = VARTAB (nessuna variabile/array)
    LDY  $2E
    STA  $2F
    STY  $30
    STA  $31
    STY  $32
    
    LDA  $37                   ; FRETOP = cima della memoria (azzera le stringhe)
    LDY  $38
    STA  $33
    STY  $34
    
    JSR  $FFE7                 ; CLALL: chiude eventuali file aperti (KERNAL puro,
                                ; non tocca lo stack pointer)
    LDA  BAM                    ; BAM mai inizializzata (tutto a zero)?
    ORA  DIRECTORY_AREA
    BNE  start_bam_ok
    JSR  format_clear           ; si': formatta (altrimenti ogni salvataggio
                                ; darebbe OUT OF MEMORY fino al primo @F)
start_bam_ok:
    JSR  check_autoboot         ; se esiste "AUTOBOOT.ASM" lo esegue subito
                                ; (non ritorna in quel caso)
    RTS

intromsg:
    LDY  #>imsg
    LDA  #<imsg
    JMP  STROUT

; ----------------------------------------------------------------------------
; CHECK_AUTOBOOT - se esiste una entry "AUTOBOOT.ASM" di tipo ASM nella
;                  directory, la carica e la esegue subito (utile dopo aver
;                  ripristinato un'immagine completa con @X). Se non la
;                  trova, ritorna normalmente. Riusa la stessa logica di
;                  ricerca/caricamento di @L.
; ----------------------------------------------------------------------------

check_autoboot:
    LDX  #12                   ; copia "AUTOBOOT.ASM",0 in DESCRIPTOR_BUFFER+1
cab_copy_name:
    LDA  autoboot_name, X
    STA  DESCRIPTOR_BUFFER+1, X
    DEX
    BPL  cab_copy_name
    JSR  find_name
    BCC  cab_none
    JMP  loadfile_by_index_noidx  ; riusa il caricamento di @L (un file ASM
                                   ; finisce con il salto all'entry point)
cab_none:
    RTS

autoboot_name:
    !text "AUTOBOOT.ASM",0

; ============================================================================
; GESTORE COMANDI @
; ============================================================================

newgone:
    JSR  CHRGET
    PHP
    CMP  #$40                ; '@'?
    BEQ  newdispatch
    PLP
    JMP  $A7E4 + 3
newdispatch:
    PLP
    JSR  dispatch
    ; Al ritorno del comando, NEWSTT ($A7AE) legge il byte puntato da TXTPTR:
    ; se non e' $00 (fine riga) o ':' da' ?SYNTAX ERROR. Dopo gli argomenti
    ; (nome tra virgolette, cifre...) TXTPTR e' rimasto indietro, quindi lo
    ; porto alla fine dell'istruzione.
    LDY  #0
nd_skip:
    LDA  ($7A), Y
    BEQ  nd_done
    CMP  #$3A
    BEQ  nd_done
    INC  $7A
    BNE  nd_skip
    INC  $7B
    BNE  nd_skip
nd_done:
    JMP  BASIC_INTERPRETER

dispatch:
    JSR  CHRGET
    CMP  #$40
    BCS  dispatch_ok1
    JMP  SYNTAX_MANAGER
dispatch_ok1:
    CMP  #$5B
    BCC  dispatch_ok2
    JMP  SYNTAX_MANAGER
dispatch_ok2:
    SEC
    SBC  #$40
    CMP  #$5A
    ASL
    TAX
    LDA  cmd_table + 1, X
    PHA
    LDA  cmd_table, X
    PHA
    JMP  $0073

notimp:
    JMP  SYNTAX_MANAGER                ; SYNTAX

; ============================================================================
; ROUTINE DI BASE
; ============================================================================

; ----------------------------------------------------------------------------
; ATTIVA_RAM / ATTIVA_ROM
; ----------------------------------------------------------------------------

; BANK_IN / BANK_OUT - disattivano ROM e I/O (tutta RAM) salvando $01 in
; work_zone+22, e ripristinano la configurazione precedente. Non annidabili.
bank_in:
    SEI
    LDA  $01
    STA  work_zone+22
    AND  #%11111000
    STA  $01
    RTS
bank_out:
    LDA  work_zone+22
    STA  $01
    CLI
    RTS

; ----------------------------------------------------------------------------
; ERR_CHECK - da chiamare dopo un BCS su SaveCommon/SaveFileMeta: X=$FF vuol
;             dire che il nome esisteva gia' (FILE EXISTS, unico messaggio
;             custom rimasto: non esiste un errore standard equivalente),
;             altrimenti spazio esaurito (OUT OF MEMORY standard).
; ----------------------------------------------------------------------------
err_check:
    CPX  #$FF
    BEQ  err_file_exists
    JMP  ERR_OUT_OF_MEMORY
err_file_exists:
    LDY  #>file_exists_msg
    LDA  #<file_exists_msg
    JMP  STROUT

; ----------------------------------------------------------------------------
; CHECK_DIRECT - verifica che si sia in modalita' diretta (non da programma).
;                Se non lo siamo, segnala ILLEGAL DIRECT (messaggio standard
;                della ROM, nessuna stringa custom necessaria) e non ritorna.
; ----------------------------------------------------------------------------
check_direct:
    LDX  $3A
    INX
    BEQ  check_direct_ok
    JMP  ERR_ILLEGAL_DIRECT
check_direct_ok:
    RTS

; ----------------------------------------------------------------------------
; IS_DIRECT - come CHECK_DIRECT ma senza generare errori: ritorna con Z=1
;             (BEQ) se siamo in modalita' diretta, Z=0 (BNE) altrimenti.
;             Usata per rendere condizionali i soli messaggi di stato, senza
;             bloccare l'operazione quando chiamata da un programma.
; ----------------------------------------------------------------------------
is_direct:
    LDA  $3A
    CMP  #$FF
    RTS

; ----------------------------------------------------------------------------
; PRINT_OK - stampa il messaggio di conferma (OK), ma solo in modalita'
;            diretta. Sostituisce le varie "LDY #>done / LDA #<done /
;            JMP STROUT" sparse nel codice: 4 byte in meno a ogni chiamata.
; ----------------------------------------------------------------------------
print_ok:
    JSR  is_direct
    BNE  print_ok_done
    LDY  #>done
    LDA  #<done
    JSR  STROUT
print_ok_done:
    RTS

; ----------------------------------------------------------------------------
; INIZIO_MAPPA_VIDEO
; ----------------------------------------------------------------------------

inizio_mappa_video:
    LDA  VIC_MEMORY
    AND  #%11110000
    LSR
    LSR
    TAX
    RTS

; ----------------------------------------------------------------------------
; PRINTHEX - Stampa un byte in esadecimale
; ----------------------------------------------------------------------------

printhex:
    PHA
    LSR
    LSR
    LSR
    LSR
    TAX
    LDA  HEXTABLE, X
    JSR  CHROUT
    PLA
    AND  #$0F
    TAX
    LDA  HEXTABLE, X
    JMP  CHROUT

; ----------------------------------------------------------------------------
; HEX_TO_VALUE - Converte carattere ASCII in valore esadecimale
; ----------------------------------------------------------------------------

hex_to_value:
    CMP  #$30
    BCC  hex_error
    CMP  #$3A
    BCC  hex_digit
    CMP  #$41
    BCC  hex_error
    CMP  #$47
    BCC  hex_letter
    CMP  #$61
    BCC  hex_error
    CMP  #$67
    BCC  hex_letter
hex_error:
    SEC
    RTS
hex_digit:
    SEC
    SBC  #$30
    CLC
    RTS
hex_letter:
    SEC
    SBC  #$37
    CLC
    RTS

; ----------------------------------------------------------------------------
; GET_HEX_PARAM - Legge parametro esadecimale dalla riga di comando
; ----------------------------------------------------------------------------

get_hex_param:
    CMP  #$20
    BEQ  get_hex_skip
    CMP  #$2C
    BEQ  get_hex_skip
    JMP  get_hex_check
get_hex_skip:
    JSR  CHRGET
    CMP  #$20
    BEQ  get_hex_skip
    CMP  #$2C
    BEQ  get_hex_skip
get_hex_check:
    CMP  #$24                ; '$' ? (prefisso esadecimale)
    BEQ  get_hex_dollar
    JMP  get_hex_decimal
get_hex_dollar:
    JSR  CHRGET
get_hex_d1:
    JSR  hex_byte
    BCS  get_hex_error
    TAY                      ; Y = byte alto (prima coppia di cifre digitate)
    JSR  CHRGET
    JSR  hex_byte
    BCS  get_hex_error
    TAX                      ; X = byte basso (seconda coppia di cifre digitate)
    JSR  CHRGET              ; prefetch del carattere successivo: chi chiama
                              ; di nuovo (2°/3° parametro) o dopo (nome
                              ; opzionale) lo trova gia' pronto in A
    CLC
    RTS
get_hex_error:
    SEC
    RTS

; hex_byte - A = primo carattere (gia' letto); legge il secondo con CHRGET.
;            Ritorna A = byte, oppure C=1 se un carattere non e' esadecimale.
hex_byte:
    JSR  hex_to_value
    BCS  hex_byte_end
    ASL
    ASL
    ASL
    ASL
    STA  work_zone+14
    JSR  CHRGET
    JSR  hex_to_value
    BCS  hex_byte_end
    ORA  work_zone+14
hex_byte_end:
    RTS

; --- Parsing decimale (0-65535), usato quando il primo carattere non e'
;     '$'. work_zone+9/10 = accumulatore, work_zone+11/12 = scratch. ---
get_hex_decimal:
    LDX  #0
    STX  work_zone+9
    STX  work_zone+10
ghd_loop:
    CMP  #$30
    BCC  ghd_done
    CMP  #$3A
    BCS  ghd_done
    PHA
    ASL  work_zone+9
    ROL  work_zone+10        ; *2
    LDA  work_zone+9
    STA  work_zone+11
    LDA  work_zone+10
    STA  work_zone+12        ; scratch = *2
    ASL  work_zone+9
    ROL  work_zone+10        ; *4
    ASL  work_zone+9
    ROL  work_zone+10        ; *8
    CLC
    LDA  work_zone+9
    ADC  work_zone+11
    STA  work_zone+9
    LDA  work_zone+10
    ADC  work_zone+12
    STA  work_zone+10        ; *8 + *2 = *10
    PLA
    SEC
    SBC  #$30
    CLC
    ADC  work_zone+9
    STA  work_zone+9
    LDA  #0
    ADC  work_zone+10
    STA  work_zone+10
    ; avanza di UN carattere senza il salto automatico degli spazi di
    ; CHRGET (altrimenti "1024 1280" verrebbe letto come un unico numero,
    ; saltando lo spazio di separazione)
    INC  $7A
    BNE  ghd_noinc
    INC  $7B
ghd_noinc:
    LDY  #0
    LDA  ($7A), Y
    JMP  ghd_loop
ghd_done:
ghd_skip_trailing_space:
    CMP  #$20
    BNE  ghd_finish
    INC  $7A
    BNE  ghd_skip_ni
    INC  $7B
ghd_skip_ni:
    LDY  #0
    LDA  ($7A), Y
    JMP  ghd_skip_trailing_space
ghd_finish:
    LDX  work_zone+9
    LDY  work_zone+10
    CLC
    RTS

; ----------------------------------------------------------------------------
; PRINTFILE_TYPE - Stampa il tipo di file
; ----------------------------------------------------------------------------

PrintFileType:
    CPY  #1
    BNE  pft_1
    LDA  #<file_type_bas
    LDX  #>file_type_bas
    JMP  pft_print
pft_1:
    CPY  #2
    BNE  pft_2
    LDA  #<file_type_scr
    LDX  #>file_type_scr
    JMP  pft_print
pft_2:
    CPY  #3
    BNE  pft_3
    LDA  #<file_type_asm
    LDX  #>file_type_asm
    JMP  pft_print
pft_3:
    LDA  #<file_type_byt
    LDX  #>file_type_byt
pft_print:
    STA  Page0_C
    STX  Page0_D
    LDY  #0
pft_loop:
    LDA  (Page0_C), Y
    BEQ  pft_done
    JSR  CHROUT
    INY
    CPY  #4
    BNE  pft_loop
pft_done:
    RTS

; ----------------------------------------------------------------------------
; GET_1_PARAM - Legge un parametro numerico dalla riga di comando
; ----------------------------------------------------------------------------

get_1_param:
    JSR  $B79E
    RTS

; ============================================================================
; BAM E DIRECTORY ROUTINES
; ============================================================================

; ----------------------------------------------------------------------------
; CNV_INDEX_TO_BAM - Calcola indirizzo entry della directory
; ----------------------------------------------------------------------------

cnv_index_to_bam:
    TYA
    ASL
    ASL
    ASL
    ASL
    STA  Page0_A
    LDA  #0
    STA  Page0_B
    
    TYA
    ASL
    ASL
    ASL
    CLC
    ADC  Page0_A
    STA  Page0_A
    LDA  #0
    ADC  Page0_B
    STA  Page0_B
    
    CLC
    LDA  #<DIRECTORY_AREA
    ADC  Page0_A
    STA  Page0_A
    LDA  #>DIRECTORY_AREA
    ADC  Page0_B
    STA  Page0_B
    RTS

; ----------------------------------------------------------------------------
; FREE_BAM_INDEX - Trova una entry libera nella directory
; ----------------------------------------------------------------------------

free_bam_index:
    LDA  #0
    STA  work_zone
free_bam_loop:
    LDY  work_zone
    JSR  cnv_index_to_bam
    LDY  #0
    LDA  (Page0_A), Y
    BEQ  free_bam_found
    INC  work_zone
    LDA  work_zone
    CMP  #MAX_ENTRY
    BMI  free_bam_loop
    LDY  #$FF
    RTS
free_bam_found:
    LDY  work_zone
    RTS

; ----------------------------------------------------------------------------
; OCCUPA_BAM - Assegna blocchi della BAM a una entry
; ----------------------------------------------------------------------------

Occupa_BAM:
    STX  work_zone+5        ; blocchi richiesti
    STY  work_zone+6         ; indice directory (proprietario)
    LDA  #$FF
    STA  work_zone+14        ; nessun blocco iniziale trovato ancora
    STA  work_zone+15        ; nessun blocco precedente ancora
    LDY  #0
occ_loop:
    CPY  #TOTAL_BLOCKS
    BEQ  occ_error
    LDA  BAM, Y
    CMP  #$FF
    BNE  occ_next
    
    ; blocco Y libero: lo assegniamo
    LDA  work_zone+6
    STA  BAM, Y
    LDA  #$FF
    STA  BAM_NEXT, Y         ; per ora e' l'ultimo della catena
    
    LDA  work_zone+14
    CMP  #$FF
    BNE  occ_link_prev
    STY  work_zone+14        ; primo blocco della catena
    JMP  occ_after_link
occ_link_prev:
    LDX  work_zone+15
    TYA
    STA  BAM_NEXT, X          ; il blocco precedente punta a questo
occ_after_link:
    STY  work_zone+15         ; questo diventa il "precedente" per il prossimo
    
    DEC  work_zone+5
    LDA  work_zone+5
    BEQ  occ_done
    INY
    JMP  occ_loop
occ_next:
    INY
    JMP  occ_loop
occ_done:
    LDX  work_zone+14         ; ritorna il blocco iniziale assegnato
    CLC
    RTS
occ_error:
    SEC
    RTS

; ----------------------------------------------------------------------------
; BLOCK_TO_ADDR - converte un numero di blocco (X, 0..TOTAL_BLOCKS-1)
;                 nell'indirizzo fisico reale (A = high byte, low byte = 0)
; ----------------------------------------------------------------------------

block_to_addr:                 ; Page0_A/B = indirizzo fisico del blocco work_zone+15
    LDA  #0
    STA  Page0_A
    LDX  work_zone+15
    TXA
    CLC
    ADC  #RAMDISK_BASE1
    CPX  #RAMDISK_BASE1_BLOCKS
    BCC  b2a_store             ; regione 1: $A0 + blocco
    ADC  #(RAMDISK_BASE2-RAMDISK_BASE1-RAMDISK_BASE1_BLOCKS-1)   ; C=1: regione 2
b2a_store:
    STA  Page0_B
    RTS

; ============================================================================
; COPY DATA ROUTINES
; ============================================================================

; ----------------------------------------------------------------------------
; COPY_DATA_TO_RAMDISK
; Copia work_zone+9/10 byte da (work_zone+3/4, memoria reale) alla catena di
; blocchi che parte da work_zone+15 (il "cursore"), seguendo BAM_NEXT quando
; un blocco si esaurisce. Puo' essere richiamata piu' volte di seguito (es.
; SAVESCREEN) per continuare a scrivere sulla stessa catena da dove si era
; interrotta.
; ----------------------------------------------------------------------------

CopyDataToRamDisk:
    JSR  bank_in
    
    LDA  work_zone+3
    STA  Page0_C
    LDA  work_zone+4
    STA  Page0_D
    
copy_to_block_loop:
    JSR  block_to_addr
    
    LDA  work_zone+10       ; byte rimanenti, high byte
    BEQ  copy_to_partial
    
    ; --- blocco pieno da 256 byte ---
    LDY  #0
    LDX  #0                  ; 0 = 256 iterazioni
copy_to_full_loop:
    LDA  (Page0_C), Y
    STA  (Page0_A), Y
    INY
    DEX
    BNE  copy_to_full_loop
    INC  Page0_D              ; la sorgente avanza di una pagina intera
    DEC  work_zone+10
    JMP  copy_to_next_block
    
copy_to_partial:
    LDX  work_zone+9         ; byte rimanenti, low byte (< 256)
    BEQ  copy_to_done
    LDY  #0
copy_to_partial_loop:
    LDA  (Page0_C), Y
    STA  (Page0_A), Y
    INY
    DEX
    BNE  copy_to_partial_loop
    LDA  #0
    STA  work_zone+9
    
copy_to_next_block:
    LDX  work_zone+15
    LDA  BAM_NEXT, X
    STA  work_zone+15         ; avanza il cursore al blocco successivo
    LDA  work_zone+9
    ORA  work_zone+10
    BNE  copy_to_block_loop   ; restano ancora byte da copiare
    
copy_to_done:
    JMP  bank_out

; ----------------------------------------------------------------------------
; COPY_DATA_FROM_RAMDISK
; Simmetrica a CopyDataToRamDisk: legge work_zone+9/10 byte dalla catena che
; parte da work_zone+15, scrivendoli a (Page0_C/D, gia' impostato dal
; chiamante come indirizzo di destinazione in memoria reale).
; ----------------------------------------------------------------------------

CopyDataFromRamDisk:
    JSR  bank_in
    
copy_from_block_loop:
    JSR  block_to_addr
    
    LDA  work_zone+10
    BEQ  copy_from_partial
    
    LDY  #0
    LDX  #0
copy_from_full_loop:
    LDA  (Page0_A), Y
    STA  (Page0_C), Y
    INY
    DEX
    BNE  copy_from_full_loop
    INC  Page0_D
    DEC  work_zone+10
    JMP  copy_from_next_block
    
copy_from_partial:
    LDX  work_zone+9
    BEQ  copy_from_done
    LDY  #0
copy_from_partial_loop:
    LDA  (Page0_A), Y
    STA  (Page0_C), Y
    INY
    DEX
    BNE  copy_from_partial_loop
    LDA  #0
    STA  work_zone+9
    
copy_from_next_block:
    LDX  work_zone+15
    LDA  BAM_NEXT, X
    STA  work_zone+15
    LDA  work_zone+9
    ORA  work_zone+10
    BNE  copy_from_block_loop
    
copy_from_done:
    JMP  bank_out

; ----------------------------------------------------------------------------
; COLORE ($D800-$DBE7) - la RAM colore e' un chip speciale visibile SOLO in
; banking normale: durante attiva_ram quella finestra e' invece la RAM
; nascosta della ramdisk. Le CopyData*RamDisk normali NON possono quindi
; leggere/scrivere il colore vero (girano tutte dentro attiva_ram). Queste
; routine passano da un buffer di appoggio (STAGING_BUFFER), cambiando
; banking ad ogni meta' blocco (128 byte), esattamente come BACKUP/RESTORE.
; ----------------------------------------------------------------------------

; color_xfer_normal: trasferisce work_zone+21 byte tra (Page0_C),Y e
; STAGING_BUFFER (banking normale, colore vero), avanza Page0_C/D.
; Direzione work_zone+23: 0 = leggi il colore vero in STAGING_BUFFER,
; 1 = scrivi STAGING_BUFFER nel colore vero.
color_xfer_normal:
    LDY  #0
    LDX  #0
cxn_loop:
    LDA  work_zone+23
    BNE  cxn_write
    LDA  (Page0_C), Y
    STA  STAGING_BUFFER, X
    JMP  cxn_next
cxn_write:
    LDA  STAGING_BUFFER, X
    STA  (Page0_C), Y
cxn_next:
    INY
    INX
    CPX  work_zone+21
    BNE  cxn_loop
    TYA
    CLC
    ADC  Page0_C
    STA  Page0_C
    LDA  #0
    ADC  Page0_D
    STA  Page0_D
    RTS

; color_xfer_ram: trasferisce work_zone+21 byte tra il blocco ramdisk
; corrente (work_zone+15, offset work_zone+20) e STAGING_BUFFER (gestisce
; da sola attiva_ram/attiva_rom). Direzione work_zone+23: 0 = scrivi
; STAGING_BUFFER nel blocco, 1 = leggi il blocco in STAGING_BUFFER.
color_xfer_ram:
    JSR  bank_in
    
    JSR  block_to_addr
    
    LDY  work_zone+20
    LDX  #0
cxr_loop:
    LDA  work_zone+23
    BNE  cxr_read
    LDA  STAGING_BUFFER, X
    STA  (Page0_A), Y
    JMP  cxr_next
cxr_read:
    LDA  (Page0_A), Y
    STA  STAGING_BUFFER, X
cxr_next:
    INY
    INX
    CPX  work_zone+21
    BNE  cxr_loop
    
    JMP  bank_out

; CopyColorTransfer: trasferisce i 1000 byte di colore ($D800-$DBE7)
; da/verso la catena a partire dal cursore work_zone+15 (deve gia' essere
; posizionato subito dopo i 4 blocchi dello schermo). Direzione in
; work_zone+23: 0 = salva (colore vero -> ramdisk), 1 = carica (ramdisk ->
; colore vero).
CopyColorTransfer:
    LDA  #$00
    STA  Page0_C
    LDA  #$D8
    STA  Page0_D
    LDA  #0
    STA  work_zone+19         ; blocchi pieni completati (0..3)
cct_block:
    LDA  #0
    STA  work_zone+20
    LDA  #128
    STA  work_zone+21
cct_half:
    JSR  cct_dispatch
    LDA  work_zone+20
    BNE  cct_half_done
    LDA  #128
    STA  work_zone+20
    JMP  cct_half
cct_half_done:
    LDX  work_zone+15
    LDA  BAM_NEXT, X
    STA  work_zone+15
    INC  work_zone+19
    LDA  work_zone+19
    CMP  #3
    BNE  cct_block
    
    ; --- ultimo blocco: 232 byte (128 + 104) ---
    LDA  #0
    STA  work_zone+20
    LDA  #128
    STA  work_zone+21
    JSR  cct_dispatch
    LDA  #128
    STA  work_zone+20
    LDA  #104
    STA  work_zone+21
    JMP  cct_dispatch

cct_dispatch:
    LDA  work_zone+23
    BNE  cct_load_dir
    JSR  color_xfer_normal    ; salva: leggi il colore vero...
    JMP  color_xfer_ram        ; ...poi scrivilo nella ramdisk
cct_load_dir:
    JSR  color_xfer_ram         ; carica: leggi dalla ramdisk...
    JMP  color_xfer_normal       ; ...poi scrivilo nel colore vero

; ============================================================================
; SAVEFILE - Routine generica di salvataggio
; ============================================================================

SaveFile:
    JSR  SaveFileMeta
    BCS  savefile_error
    JSR  CopyDataToRamDisk
    CLC
    RTS
savefile_error:
    SEC
    RTS

; ----------------------------------------------------------------------------
; FIND_NAME - cerca in directory una voce occupata il cui nome coincide con
;             quello in DESCRIPTOR_BUFFER+1 (terminato da 0, max 15 caratteri).
;             Out: C=1 trovata (X e work_zone+1 = indice, Page0_A = voce);
;                  C=0 non trovata. Usata da @L/@R, dai salvataggi (FILE
;                  EXISTS) e dall'autoboot.
; ----------------------------------------------------------------------------
find_name:
    LDA  #<DESCRIPTOR_BUFFER
    STA  Page0_C
    LDA  #>DESCRIPTOR_BUFFER
    STA  Page0_D
    LDX  #0
fn_loop:
    STX  work_zone+1
    TXA
    TAY
    JSR  cnv_index_to_bam      ; (non tocca X)
    LDY  #0
    LDA  (Page0_A), Y
    BEQ  fn_next               ; voce libera
    LDY  #1
fn_cmp:
    LDA  (Page0_A), Y
    CMP  (Page0_C), Y
    BNE  fn_next
    CMP  #0
    BEQ  fn_found              ; entrambi finiscono qui
    INY
    CPY  #16
    BNE  fn_cmp                ; 15 caratteri uguali = nomi uguali
fn_found:
    SEC
    RTS
fn_next:
    INX
    CPX  #MAX_ENTRY
    BNE  fn_loop
    CLC
    RTS

; SaveFileMeta: fa solo la contabilita' (directory + BAM), senza copiare i
; dati. Usata da SAVESCREEN che deve poi copiare i dati lei stessa in due
; blocchi separati (schermo e colore non sono contigui in memoria).
; Al ritorno (se CLC): work_zone+3/4 = SORGENTE (invariati, per compatibilita'
; con chi copia i dati subito dopo), work_zone+12/13 = indirizzo fisico
; ramdisk di partenza.
SaveFileMeta:
    JSR  find_name
    BCC  savefilemeta_nameok
    LDX  #$FF                ; segnala al chiamante: nome gia' esistente
    SEC
    RTS
savefilemeta_nameok:
    JSR  free_bam_index
    CPY  #$FF
    BNE  savefilemeta_noerr
    LDX  #0                  ; segnala al chiamante: spazio esaurito
    SEC
    RTS
savefilemeta_noerr:
    STY  work_zone+1
    
    LDY  work_zone+1
    JSR  cnv_index_to_bam
    
    LDY  #0
savefile_copy_entry:
    LDA  (Page0_C), Y
    STA  (Page0_A), Y
    INY
    CPY  #16
    BNE  savefile_copy_entry
    
    LDY  #16
    LDA  (Page0_C), Y
    STA  (Page0_A), Y
    INY
    LDA  (Page0_C), Y
    STA  (Page0_A), Y
    
    LDY  #18
    LDA  (Page0_C), Y
    STA  (Page0_A), Y
    INY
    LDA  (Page0_C), Y
    STA  (Page0_A), Y
    
    LDY  #21
    LDA  (Page0_C), Y
    STA  (Page0_A), Y
    INY
    LDA  (Page0_C), Y
    STA  (Page0_A), Y
    
    ; --- Calcola lunghezza (END - START) e blocchi usati ---
    LDY  #16
    LDA  (Page0_C), Y      ; START_lo
    STA  work_zone+9
    INY
    LDA  (Page0_C), Y      ; START_hi
    STA  work_zone+10
    
    LDY  #18
    LDA  (Page0_C), Y      ; END_lo
    SEC
    SBC  work_zone+9
    PHA
    INY
    LDA  (Page0_C), Y      ; END_hi
    SBC  work_zone+10
    STA  work_zone+10      ; LENGTH_hi
    PLA
    STA  work_zone+9       ; LENGTH_lo
    
    CLC
    LDA  work_zone+9
    ADC  #$FF
    STA  work_zone+5
    LDA  work_zone+10
    ADC  #0
    STA  work_zone+6
    
    LDY  #23
    LDA  work_zone+6
    STA  (Page0_A), Y
    
    LDX  work_zone+6
    LDY  work_zone+1
    JSR  Occupa_BAM         ; ritorna in X il blocco iniziale assegnato
    BCS  savefilemeta_error
    
    STX  work_zone+11       ; blocco iniziale nella ramdisk
    LDY  #20
    LDA  work_zone+11
    STA  (Page0_A), Y       ; lo scrive nella directory (offset 20)
    
    LDA  work_zone+11
    STA  work_zone+15       ; cursore di scrittura = blocco iniziale
    
    CLC
    RTS
savefilemeta_error:
    SEC
    RTS

; ----------------------------------------------------------------------------
; SaveCommon - costruisce il descrittore (nome gia' pronto in
; DESCRIPTOR_BUFFER+1..., terminato da 0) e fa la contabilita' BAM/directory.
; Ingresso: A = tipo file (1=BAS,2=SCR,3=ASM,4=BYT)
;           work_zone+3/4 = START, work_zone+5/6 = END,
;           work_zone+7/8 = ENTRY POINT (0,0 se non usato)
; Uscita:   CC = ok (il chiamante deve poi fare JSR CopyDataToRamDisk)
;           CS = errore (spazio esaurito)
; ----------------------------------------------------------------------------
SaveCommon:
    STA  DESCRIPTOR_BUFFER
    
    LDA  #<DESCRIPTOR_BUFFER
    STA  Page0_C
    LDA  #>DESCRIPTOR_BUFFER
    STA  Page0_D
    
    LDY  #16
    LDA  work_zone+3
    STA  (Page0_C), Y
    INY
    LDA  work_zone+4
    STA  (Page0_C), Y
    INY
    LDA  work_zone+5
    STA  (Page0_C), Y
    INY
    LDA  work_zone+6
    STA  (Page0_C), Y
    
    LDY  #21
    LDA  work_zone+7
    STA  (Page0_C), Y
    INY
    LDA  work_zone+8
    STA  (Page0_C), Y
    
    JMP  SaveFileMeta

; ----------------------------------------------------------------------------
; parse_optional_name - legge un nome opzionale (quotato, digitato dopo uno
; spazio, o di default) e lo scrive in DESCRIPTOR_BUFFER+1 (pronto per
; SaveCommon).
; Ingresso: Page0_A/Page0_B = puntatore al nome di default (terminato da 0)
;           A = carattere corrente, gia' letto da chi chiama (dal trampolino
;           di dispatch, o dall'ultima CHRGET di get_hex_param)
; ----------------------------------------------------------------------------
parse_optional_name:
    CMP  #$00
    BEQ  pon_default
    CMP  #$22
    BEQ  pon_quoted
    JMP  pon_parse
    
pon_default:
    LDY  #0
pon_defname:
    LDA  (Page0_A), Y
    BEQ  pon_defname_end
    STA  DESCRIPTOR_BUFFER+1, Y
    INY
    JMP  pon_defname
pon_defname_end:
    LDA  #0
    STA  DESCRIPTOR_BUFFER+1, Y
    RTS
    
pon_quoted:
    LDY  #0
pon_qname:
    JSR  CHRGET
    CMP  #$22
    BEQ  pon_qname_done
    CMP  #$00
    BEQ  pon_qname_done
    STA  DESCRIPTOR_BUFFER+1, Y
    INY
    CPY  #15
    BCC  pon_qname
pon_qname_done:
    LDA  #0
    STA  DESCRIPTOR_BUFFER+1, Y
    RTS
    
pon_parse:
    LDY  #0
pon_pname:
    LDA  ($7A), Y
    CMP  #$20
    BEQ  pon_pname_done
    CMP  #$00
    BEQ  pon_pname_done
    CMP  #$2C
    BEQ  pon_pname_done
    STA  DESCRIPTOR_BUFFER+1, Y
    INY
    CPY  #15
    BCC  pon_pname
pon_pname_done:
    LDA  #0
    STA  DESCRIPTOR_BUFFER+1, Y
    RTS

; ============================================================================
; COMANDI
; ============================================================================

; ----------------------------------------------------------------------------
; FORMAT
; ----------------------------------------------------------------------------

FORMAT:
    JSR  format_clear
    JMP  print_ok

; format_clear - azzera BAM/BAM_NEXT/directory (chiamata anche da START)
format_clear:
    LDX  #0
format_bam:
    LDA  #$FF
    STA  BAM, X
    STA  BAM_NEXT, X
    INX
    CPX  #TOTAL_BLOCKS
    BNE  format_bam
    
    LDX  #0
format_dir:
    LDA  #0
    STA  DIRECTORY_AREA, X
    INX
    CPX  #MAX_ENTRY * 24
    BNE  format_dir
    RTS

; ----------------------------------------------------------------------------
; DIRECTORY
; ----------------------------------------------------------------------------

DIRECTORY:
    LDY  #>bam_header
    LDA  #<bam_header
    JSR  STROUT
    
    LDA  #TOTAL_BLOCKS
    STA  work_zone+2
    LDA  #0
    STA  work_zone+1
    
dir_loop:
    LDY  work_zone+1
    JSR  cnv_index_to_bam
    
    LDY  #0
    LDA  (Page0_A), Y
    BNE  dir_occupied
    JMP  dir_empty
dir_occupied:
    STA  work_zone+16        ; ricorda il tipo (serve per il campo END)
    
    LDA  work_zone+1
    JSR  printhex
    LDA  #32
    JSR  CHROUT
    
    LDA  #34
    JSR  CHROUT
    LDY  #1
    LDX  #0
dir_name:
    LDA  (Page0_A), Y
    BEQ  dir_name_pad
    JSR  CHROUT
    INY
    INX
    CPX  #15
    BNE  dir_name
    JMP  dir_name_done
dir_name_pad:
    LDA  #32
    JSR  CHROUT
    INX
    CPX  #15
    BNE  dir_name_pad
dir_name_done:
    LDA  #34
    JSR  CHROUT
    LDA  #32
    JSR  CHROUT
    
    LDY  #0
    LDA  (Page0_A), Y
    TAY
    JSR  PrintFileType
    
    LDY  #17
    LDA  (Page0_A), Y
    JSR  printhex
    LDY  #16
    LDA  (Page0_A), Y
    JSR  printhex
    
    LDA  #32
    JSR  CHROUT
    JSR  CHROUT
    JSR  CHROUT
    
    LDA  work_zone+16
    CMP  #2                  ; tipo SCR? l'END non ha senso (zone di
    BNE  dir_print_end        ; memoria diverse, non contigue)
    LDA  #45                 ; '-'
    JSR  CHROUT
    JSR  CHROUT
    JSR  CHROUT
    JSR  CHROUT
    JMP  dir_end_done
dir_print_end:
    LDY  #19
    LDA  (Page0_A), Y
    JSR  printhex
    LDY  #18
    LDA  (Page0_A), Y
    JSR  printhex
dir_end_done:
    
    LDA  #32
    JSR  CHROUT
    LDY  #23
    LDA  (Page0_A), Y
    STA  Page0_A
    JSR  printhex
    
    LDA  work_zone+2
    SEC
    SBC  Page0_A
    STA  work_zone+2
    
    LDA  #13
    JSR  CHROUT
    
dir_empty:
    INC  work_zone+1
    LDA  work_zone+1
    CMP  #MAX_ENTRY
    BEQ  dir_done
    JMP  dir_loop

dir_done:
    JSR  is_direct
    BNE  dir_end
    LDA  #40
    JSR  CHROUT
    LDA  #0
    LDX  work_zone+2
    JSR  PRINTWORD
    LDA  #47
    JSR  CHROUT
    LDX  #TOTAL_BLOCKS
    LDA  #0
    JSR  PRINTWORD
    LDY  #>bam_free_msg
    LDA  #<bam_free_msg
    JSR  STROUT
dir_end:
    RTS

; ----------------------------------------------------------------------------
; SAVESCREEN
; ----------------------------------------------------------------------------

SAVESCREEN:
    PHA
    LDA  #<default_screen_name
    STA  Page0_A
    LDA  #>default_screen_name
    STA  Page0_B
    PLA
    JSR  parse_optional_name
    
    JSR  inizio_mappa_video  ; X = byte alto dell'inizio della mappa caratteri
    LDA  #$00
    STA  work_zone+3
    STX  work_zone+4         ; START = inizio mappa video
    TXA
    CLC
    ADC  #7
    STA  work_zone+6         ; END = START + $07D0 (schermo + colore = 2000)
    LDA  #$D0
    STA  work_zone+5
    LDA  #0
    STA  work_zone+7
    STA  work_zone+8
    
    LDA  #2                  ; tipo SCR
    JSR  SaveCommon
    BCS  savesc_error
    
    ; --- Copia 1: mappa caratteri (1000 byte), START gia' in work_zone+3/4 ---
    LDA  #$E8
    STA  work_zone+9
    LDA  #$03
    STA  work_zone+10
    JSR  CopyDataToRamDisk
    
    ; --- Copia 2: colore $D800-$DBE7 (1000 byte), continua sulla stessa catena ---
    LDA  #0
    STA  work_zone+23
    JSR  CopyColorTransfer
    
    JMP  print_ok
savesc_error:
    JMP  err_check

; ----------------------------------------------------------------------------
; SAVEBASIC
; ----------------------------------------------------------------------------

SAVEBASIC:
    JSR  check_direct
    PHA
    LDA  BASIC_START
    STA  work_zone+3
    LDA  BASIC_START+1
    STA  work_zone+4
    LDA  BASIC_END
    STA  work_zone+5
    LDA  BASIC_END+1
    STA  work_zone+6
    
    ; --- Verifica che ci sia un programma (link della 1a riga != 0) ---
    LDY  #1
    LDA  (BASIC_START), Y
    BNE  savebasic_ok
    PLA
    JMP  savebasic_empty
    
savebasic_ok:
    LDA  #0
    STA  work_zone+7
    STA  work_zone+8
    
    LDA  #<default_program_name
    STA  Page0_A
    LDA  #>default_program_name
    STA  Page0_B
    PLA
    JSR  parse_optional_name
    
    LDA  #1                    ; tipo = BAS
    JSR  SaveCommon
    BCS  savebasic_error
    JSR  CopyDataToRamDisk
    
    JMP  print_ok
    
savebasic_empty:
    JMP  ERR_OUT_OF_MEMORY
savebasic_error:
    JMP  err_check

; ----------------------------------------------------------------------------
; SAVEBLOCK
; ----------------------------------------------------------------------------

SAVEBLOCK:
    JSR  check_direct
    JSR  get_hex_param
    BCC  saveblock_syntax_ok
    JMP  saveblock_syntax_error
saveblock_syntax_ok:
    STX  work_zone+3
    STY  work_zone+4
    
    JSR  get_hex_param
    BCC  saveblock_syntax_ok2
    JMP  saveblock_syntax_error
saveblock_syntax_ok2:
    STX  work_zone+5
    STY  work_zone+6
    PHA
    
    LDA  work_zone+5
    CMP  work_zone+3
    LDA  work_zone+6
    SBC  work_zone+4
    BCS  saveblock_range_ok
    PLA
    JMP  saveblock_range_error
saveblock_range_ok:
    ; --- Leggi NOME (opzionale) ---
    LDA  #0
    STA  work_zone+7
    STA  work_zone+8
    
    LDA  #<default_block_name
    STA  Page0_A
    LDA  #>default_block_name
    STA  Page0_B
    PLA
    JSR  parse_optional_name
    
    LDA  #4                    ; tipo = BYT
    JSR  SaveCommon
    BCS  saveblock_error
    JSR  CopyDataToRamDisk
    
    JMP  print_ok
    
saveblock_syntax_error:
    JMP  SYNTAX_MANAGER                ; SYNTAX
saveblock_range_error:
    JMP  ERR_ILLEGAL_QTY                ; ILLEGAL QUANTITY
saveblock_error:
    JMP  err_check

; ----------------------------------------------------------------------------
; LOADFILE
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; DELETEFILE - Cancella un file dato il suo indice in directory: libera la
;              catena di blocchi nella BAM (seguendo BAM_NEXT) e azzera la
;              entry di directory.
; Sintassi: @E indice
; ----------------------------------------------------------------------------

DELETEFILE:
    JSR  check_direct
    JSR  get_1_param
    CPX  #MAX_ENTRY
    BMI  del_idx_ok
    JMP  ERR_ILLEGAL_QTY                ; ILLEGAL QUANTITY
del_idx_ok:
    STX  work_zone+1
    LDY  work_zone+1
    JSR  cnv_index_to_bam
    
    LDY  #0
    LDA  (Page0_A), Y
    BNE  del_found
    LDX  #$04                ; FILE NOT FOUND
    JMP  ( $0300 )
del_found:
    LDY  #20
    LDA  (Page0_A), Y
    STA  work_zone+15        ; blocco corrente della catena da liberare
del_free_loop:
    LDX  work_zone+15
    LDA  #$FF
    STA  BAM, X
    LDA  BAM_NEXT, X
    CMP  #$FF
    BEQ  del_free_done
    STA  work_zone+15
    JMP  del_free_loop
del_free_done:
    
    LDY  #0
    LDX  #0
    LDA  #0
del_clear_loop:
    STA  (Page0_A), Y
    INY
    INX
    CPX  #24
    BNE  del_clear_loop
    
    JMP  print_ok

; ----------------------------------------------------------------------------
; LOADAT - Come LOADFILE, ma il primo parametro e' l'indirizzo dove caricare
;          il file. Ammesso solo per tipo SCR (solo mappa caratteri, 1000
;          byte) e BYT. Errore (SYNTAX standard) per BAS/ASM.
; Sintassi: @R ADDR NAME/INDEX
; ----------------------------------------------------------------------------

LOADAT:
    JSR  check_direct
    PHA
    LDA  #$FF
    STA  work_zone+18
    PLA
    JSR  get_hex_param
    BCC  loadat_addr_ok
    JMP  SYNTAX_MANAGER                ; SYNTAX
loadat_addr_ok:
    STX  work_zone+16        ; indirizzo di destinazione forzato (basso)
    STY  work_zone+17        ; indirizzo di destinazione forzato (alto)
    JMP  loadfile_check_char

; ----------------------------------------------------------------------------
; LOADFILE
; ----------------------------------------------------------------------------

LOADFILE:
    PHA
    LDA  #0
    STA  work_zone+18        ; nessun indirizzo forzato (chiamata normale)
    PLA
    JMP  loadfile_check_char  ; il carattere corrente e' gia' stato letto dal
                              ; trampolino di dispatch (vedi 'dispatch': la
                              ; sua JMP $0073 chiama gia' CHRGET). Richiamare
                              ; CHRGET di nuovo qui salterebbe il primo
                              ; carattere del parametro (bug di "@L 0"/"@L").
loadfile_parse_name:
    JSR  CHRGET
loadfile_check_char:
    CMP  #$00
    BEQ  loadfile_first
    CMP  #$22
    BEQ  loadfile_quoted
    CMP  #$20
    BEQ  loadfile_parse_name
    CMP  #$30
    BCC  loadfile_name
    CMP  #$3A
    BCC  loadfile_index
    JMP  loadfile_name
    
loadfile_first:
    LDX  #0
    JMP  loadfile_by_index
    
loadfile_index:
    SEC
    SBC  #$30
    TAX
    CPX  #MAX_ENTRY
    BMI  loadfile_by_index
    JMP  ERR_ILLEGAL_QTY                ; ILLEGAL QUANTITY
    
loadfile_quoted:
    LDY  #0
loadfile_qname:
    JSR  CHRGET
    CMP  #$22
    BEQ  loadfile_qname_done
    CMP  #$00
    BEQ  loadfile_qname_done
    STA  DESCRIPTOR_BUFFER+1, Y
    INY
    CPY  #15
    BNE  loadfile_qname
loadfile_qname_done:
    LDA  #0
    STA  DESCRIPTOR_BUFFER+1, Y
    JMP  loadfile_find_name
    
loadfile_name:
    LDY  #0
loadfile_pname:
    LDA  ($7A), Y
    CMP  #$20
    BEQ  loadfile_pname_done
    CMP  #$00
    BEQ  loadfile_pname_done
    CMP  #$2C
    BEQ  loadfile_pname_done
    STA  DESCRIPTOR_BUFFER+1, Y
    INY
    CPY  #15
    BNE  loadfile_pname
loadfile_pname_done:
    LDA  #0
    STA  DESCRIPTOR_BUFFER+1, Y
    
loadfile_find_name:
    JSR  find_name
    BCS  loadfile_by_index_noidx
    LDX  #$04                ; FILE NOT FOUND
    JMP  ($0300)
    
loadfile_by_index:
    STX  work_zone+1
loadfile_by_index_noidx:
    LDY  work_zone+1
    JSR  cnv_index_to_bam
    
    LDY  #0
    LDA  (Page0_A), Y
    STA  work_zone+2
    
    LDY  #16
    LDA  (Page0_A), Y
    STA  work_zone+3
    INY
    LDA  (Page0_A), Y
    STA  work_zone+4
    
    LDY  #18
    LDA  (Page0_A), Y
    STA  work_zone+5
    INY
    LDA  (Page0_A), Y
    STA  work_zone+6
    
    LDY  #21
    LDA  (Page0_A), Y
    STA  work_zone+7
    INY
    LDA  (Page0_A), Y
    STA  work_zone+8
    
    SEC
    LDA  work_zone+5
    SBC  work_zone+3
    STA  work_zone+9
    LDA  work_zone+6
    SBC  work_zone+4
    STA  work_zone+10
    
    LDY  #20
    LDA  (Page0_A), Y
    STA  work_zone+11       ; blocco iniziale nella ramdisk
    STA  work_zone+15       ; cursore di lettura = blocco iniziale
    
    LDA  work_zone+18
    BEQ  loadfile_type_dispatch
    
    ; --- @R (LOADAT): indirizzo forzato, ammesso solo per SCR/BYT ---
    LDA  work_zone+2
    CMP  #2
    BEQ  loadat_override_ok
    CMP  #4
    BEQ  loadat_override_ok
    JMP  SYNTAX_MANAGER                ; SYNTAX: tipo non ammesso con @R
loadat_override_ok:
    LDA  work_zone+16
    STA  work_zone+3
    LDA  work_zone+17
    STA  work_zone+4
    LDA  work_zone+2
    CMP  #2
    BEQ  loadat_screen_only
    JMP  loadfile_byte
loadat_screen_only:
    LDA  work_zone+3
    STA  Page0_C
    LDA  work_zone+4
    STA  Page0_D
    LDA  #$E8
    STA  work_zone+9
    LDA  #$03
    STA  work_zone+10
    JSR  CopyDataFromRamDisk
    JMP  print_ok
    
loadfile_type_dispatch:
    LDA  work_zone+2
    CMP  #1
    BEQ  loadfile_basic
    CMP  #2
    BEQ  loadfile_screen
    CMP  #3
    BEQ  loadfile_asm
    JMP  loadfile_byte

loadfile_basic:
    LDA  work_zone+3
    STA  Page0_C
    LDA  work_zone+4
    STA  Page0_D
    JSR  CopyDataFromRamDisk
    
    LDA  work_zone+3         ; TXTTAB = inizio programma
    STA  BASIC_START
    LDA  work_zone+4
    STA  BASIC_START+1
    LDA  work_zone+5         ; VARTAB = ARYTAB = STREND = fine programma
    STA  BASIC_END
    STA  $2F
    STA  $31
    LDA  work_zone+6
    STA  BASIC_END+1
    STA  $30
    STA  $32
    JMP  print_ok

loadfile_screen:
    JSR  inizio_mappa_video
    LDA  #$00
    STA  Page0_C
    STX  Page0_D
    LDA  #$E8
    STA  work_zone+9
    LDA  #$03
    STA  work_zone+10
    JSR  CopyDataFromRamDisk
    
    LDA  #1
    STA  work_zone+23
    JSR  CopyColorTransfer
    
    JMP  print_ok

loadfile_asm:
    ; --- Copia i dati dalla RAM disk ---
    LDA  work_zone+3
    STA  Page0_C
    LDA  work_zone+4
    STA  Page0_D
    JSR  CopyDataFromRamDisk
    
    ; --- Stampa messaggio ---
    JSR  print_ok
    
    ; --- Salta all'entry point ---
    LDA  work_zone+7
    LDX  work_zone+8
    JMP  ( work_zone+7 )

loadfile_byte:
    LDA  work_zone+3
    STA  Page0_C
    LDA  work_zone+4
    STA  Page0_D
    JSR  CopyDataFromRamDisk
    
    JMP  print_ok
; ============================================================================
; SAVEASM - Salva un programma Assembly (tipo ASM)
; Sintassi: @A start end entry [nomefile]
;   start  = indirizzo di inizio (es. 0400, C000)
;   end    = indirizzo di fine (es. 0500, C100)
;   entry  = entry point (es. 0410, C000)
;   nomefile = nome del file (opzionale)
;
; Esempi:
;   @A 0400 0500 0410 "PROG"   ; Salva e esegui da $0410
;   @A C000 C100 C000          ; Salva e esegui da $C000
; ============================================================================

; ============================================================================
; SAVEASM - Salva un programma Assembly (tipo ASM)
; Sintassi: @A start end entry [nomefile]
; ============================================================================

SAVEASM:
    JSR  check_direct
    ; --- Leggi START ---
    JSR  get_hex_param
    BCC  saveasm_start_ok
    JMP  saveasm_syntax_error
saveasm_start_ok:
    STX  work_zone+3
    STY  work_zone+4
    
    ; --- Leggi END ---
    JSR  get_hex_param
    BCC  saveasm_end_ok
    JMP  saveasm_syntax_error
saveasm_end_ok:
    STX  work_zone+5
    STY  work_zone+6
    
    ; --- Leggi ENTRY POINT ---
    JSR  get_hex_param
    BCC  saveasm_entry_ok
    JMP  saveasm_syntax_error
saveasm_entry_ok:
    STX  work_zone+7
    STY  work_zone+8
    PHA
    
    ; --- Controlli di intervallo (carry = A >= B nei confronti a 16 bit) ---
    LDA  work_zone+3         ; START >= END  -> errore (copre END<START e END=START)
    CMP  work_zone+5
    LDA  work_zone+4
    SBC  work_zone+6
    BCS  saveasm_range_error
    LDA  work_zone+7         ; ENTRY < START -> errore
    CMP  work_zone+3
    LDA  work_zone+8
    SBC  work_zone+4
    BCC  saveasm_entry_error
    LDA  work_zone+5         ; END < ENTRY -> errore
    CMP  work_zone+7
    LDA  work_zone+6
    SBC  work_zone+8
    BCC  saveasm_entry_error
    
    ; --- Leggi NOME (opzionale) ---
    LDA  #<default_asm_name
    STA  Page0_A
    LDA  #>default_asm_name
    STA  Page0_B
    PLA
    JSR  parse_optional_name
    
    LDA  #3                    ; tipo = ASM
    JSR  SaveCommon
    BCS  saveasm_error
    JSR  CopyDataToRamDisk
    
    JMP  print_ok
    
saveasm_syntax_error:
    JMP  SYNTAX_MANAGER                ; SYNTAX
saveasm_range_error:
    PLA
    JMP  ERR_ILLEGAL_QTY                ; ILLEGAL QUANTITY
saveasm_entry_error:
    PLA
    JMP  ERR_ILLEGAL_QTY                ; ILLEGAL QUANTITY
saveasm_error:
    JMP  err_check
        
; ----------------------------------------------------------------------------
; SAVEALL - Salva $A000-$CFFF (48 pagine: ramdisk regione 1 + programma
;           residente + BAM/BAM_NEXT/DIRECTORY) su disco fisico come file
;           PRG standard, caricabile con un semplice LOAD "...",8,1 seguito
;           da SYS49152. NON copre $D000-$FEFF (regione 2): le scritture li'
;           durante un LOAD normale andrebbero sui registri hardware (VIC/
;           SID/CIA) invece che in RAM, col rischio di bloccare il bus
;           seriale usato dal LOAD stesso. Per un backup/ripristino completo
;           di tutti i 79 blocchi restano @B/@R.
; Sintassi: @X n   (n = indice 0-9, nome file "IMAGEn.RDXL")
; ----------------------------------------------------------------------------

SAVEALL:
    JSR  check_direct
    JSR  get_1_param
    CPX  #10
    BMI  saveall_idx_ok
    LDX  #$0F                  ; OVERFLOW: indice non valido
    JMP  ($0300)
saveall_idx_ok:
    TXA
    CLC
    ADC  #48
    STA  saveall_filename+5
    
    LDX  #<saveall_filename
    LDY  #>saveall_filename
    LDA  #saveall_filename_end-saveall_filename
    JSR  SETNAM
    LDA  #2
    LDX  #8
    LDY  #1
    JSR  SETLFS
    JSR  OPENF
    BCC  *+5
    JMP  saveall_error
    LDX  #2
    JSR  CHKOUT
    BCC  *+5
    JMP  saveall_error
    
    ; --- Header PRG: indirizzo di caricamento $A000 ---
    LDA  #$00
    JSR  CHROUT
    LDA  #$A0
    JSR  CHROUT
    
    LDA  #0
    STA  work_zone+15          ; pagina corrente (0..47)
saveall_page_loop:
    LDA  #0
    STA  work_zone+16          ; 0 = prima meta' pagina, 128 = seconda meta'
saveall_half_loop:
    JSR  bank_in
    
    LDA  #0
    STA  Page0_A
    LDA  #$A0
    CLC
    ADC  work_zone+15
    STA  Page0_B
    
    LDY  work_zone+16
    LDX  #0
saveall_stage_loop:
    LDA  (Page0_A), Y
    STA  STAGING_BUFFER, X
    INY
    INX
    CPX  #128
    BNE  saveall_stage_loop
    
    JSR  bank_out
    
    LDX  #0
saveall_write_loop:
    LDA  STAGING_BUFFER, X
    JSR  CHROUT
    INX
    CPX  #128
    BNE  saveall_write_loop
    
    LDA  work_zone+16
    BNE  saveall_half_done
    LDA  #128
    STA  work_zone+16
    JMP  saveall_half_loop
saveall_half_done:
    
    INC  work_zone+15
    LDA  work_zone+15
    CMP  #48
    BNE  saveall_page_loop
    
    LDA  #2
    JSR  CLOSEF
    JSR  CLRCHN
    
    JMP  print_ok
saveall_error:
    LDX  #$1D                ; LOAD
    JMP  ($0300)

saveall_filename:
    !text "IMAGE0.RDXL"
saveall_filename_end:


; ----------------------------------------------------------------------------
; BACKUP - Salva l'intera ramdisk (BAM + BAM_NEXT + DIRECTORY + tutti i
;          blocchi dati) su disco fisico, per un ripristino coerente.
; ----------------------------------------------------------------------------

BACKUP:
    JSR  check_direct
    LDX  #<backup_filename_w
    LDY  #>backup_filename_w
    LDA  #backup_filename_w_end-backup_filename_w
    JSR  SETNAM
    LDA  #2
    LDX  #8
    LDY  #2
    JSR  SETLFS
    JSR  OPENF
    BCC  *+5
    JMP  backup_error
    LDX  #2
    JSR  CHKOUT
    BCC  *+5
    JMP  backup_error
    
    LDX  #0
backup_bam_loop:
    LDA  BAM, X
    JSR  CHROUT
    INX
    CPX  #TOTAL_BLOCKS
    BNE  backup_bam_loop
    
    LDX  #0
backup_bamnext_loop:
    LDA  BAM_NEXT, X
    JSR  CHROUT
    INX
    CPX  #TOTAL_BLOCKS
    BNE  backup_bamnext_loop
    
    LDX  #0
backup_dir_loop:
    LDA  DIRECTORY_AREA, X
    JSR  CHROUT
    INX
    CPX  #MAX_ENTRY * 24
    BNE  backup_dir_loop
    
    LDA  #0
    STA  work_zone+15
backup_block_loop:
    LDA  #0
    STA  work_zone+16      ; 0 = prima meta' del blocco, 128 = seconda meta'
backup_half_loop:
    JSR  bank_in
    
    JSR  block_to_addr
    
    LDY  work_zone+16
    LDX  #0
backup_stage_loop:
    LDA  (Page0_A), Y
    STA  STAGING_BUFFER, X
    INY
    INX
    CPX  #128
    BNE  backup_stage_loop
    
    JSR  bank_out
    
    LDX  #0
backup_write_loop:
    LDA  STAGING_BUFFER, X
    JSR  CHROUT
    INX
    CPX  #128
    BNE  backup_write_loop
    
    LDA  work_zone+16
    BNE  backup_half_done
    LDA  #128
    STA  work_zone+16
    JMP  backup_half_loop
backup_half_done:
    
    INC  work_zone+15
    LDA  work_zone+15
    CMP  #TOTAL_BLOCKS
    BNE  backup_block_loop
    
    JSR  CLRCHN
    LDA  #2
    JSR  CLOSEF
    
    JMP  print_ok
    
backup_error:
    JSR  CLRCHN
    LDA  #2
    JSR  CLOSEF              ; chiude il canale (altrimenti resta aperto sul drive)
    LDX  #$1D                ; LOAD
    JMP  ($0300)

; ----------------------------------------------------------------------------
; RESTORE - Ricarica da disco fisico l'intera ramdisk salvata con @B
; ----------------------------------------------------------------------------

RESTORE:
    JSR  check_direct
    LDX  #<backup_filename_r
    LDY  #>backup_filename_r
    LDA  #backup_filename_r_end-backup_filename_r
    JSR  SETNAM
    LDA  #2
    LDX  #8
    LDY  #2                  ; canale di lettura (il secondario 1 e' riservato al SAVE)
    JSR  SETLFS
    JSR  OPENF
    BCC  *+5
    JMP  restore_error
    LDX  #2
    JSR  CHKIN
    BCC  *+5
    JMP  restore_error
    
    LDX  #0
restore_bam_loop:
    JSR  CHRIN
    STA  BAM, X
    INX
    CPX  #TOTAL_BLOCKS
    BNE  restore_bam_loop
    
    LDX  #0
restore_bamnext_loop:
    JSR  CHRIN
    STA  BAM_NEXT, X
    INX
    CPX  #TOTAL_BLOCKS
    BNE  restore_bamnext_loop
    
    LDX  #0
restore_dir_loop:
    JSR  CHRIN
    STA  DIRECTORY_AREA, X
    INX
    CPX  #MAX_ENTRY * 24
    BNE  restore_dir_loop
    
    LDA  #0
    STA  work_zone+15
restore_block_loop:
    LDA  #0
    STA  work_zone+16      ; 0 = prima meta' del blocco, 128 = seconda meta'
restore_half_loop:
    LDX  #0
restore_read_loop:
    JSR  CHRIN
    STA  STAGING_BUFFER, X
    INX
    CPX  #128
    BNE  restore_read_loop
    
    JSR  bank_in
    
    JSR  block_to_addr
    
    LDY  work_zone+16
    LDX  #0
restore_stage_loop:
    LDA  STAGING_BUFFER, X
    STA  (Page0_A), Y
    INY
    INX
    CPX  #128
    BNE  restore_stage_loop
    
    JSR  bank_out
    
    LDA  work_zone+16
    BNE  restore_half_done
    LDA  #128
    STA  work_zone+16
    JMP  restore_half_loop
restore_half_done:
    
    INC  work_zone+15
    LDA  work_zone+15
    CMP  #TOTAL_BLOCKS
    BNE  restore_block_loop
    
    JSR  CLRCHN
    LDA  #2
    JSR  CLOSEF
    
    JMP  print_ok
    
restore_error:
    JSR  CLRCHN
    LDA  #2
    JSR  CLOSEF              ; chiude il canale (altrimenti resta aperto sul drive)
    LDX  #$1D                ; LOAD
    JMP  ($0300)


; --- Work zone ---
work_zone:
    !fill 24, 0

; ============================================================================
; MESSAGGI
; ============================================================================

imsg:
    !text $93,$0D
    !text " ** COMMODORE64 RAM-DISK XL BY KYMYA **",$0D,$0D
    !text " 64K RAM SYSTEM  38911 BASIC BYTES FREE",$0D,$00

done:
    !text "OK",$0D,$00

bam_header:
    !text $0D,18
    !text "# FILENAME           TY  START  END  BLK",146,13,0

bam_free_msg:
    !text ") BLOCKS FREE.",$0D,$00

file_type_bas:
    !text "BAS "
file_type_scr:
    !text "SCR "
file_type_asm:
    !text "ASM "
file_type_byt:
    !text "BYT "

default_screen_name:
    !text "SCREEN",0

default_asm_name:
    !text  "ASM", 0

default_program_name:
    !text "PROGRAM",0
default_block_name:
    !text "BLOCK",0

backup_filename_w:
    !text "@0:RAMDISK.IMG,S,W"
backup_filename_w_end:
backup_filename_r:
    !text "RAMDISK.IMG,S,R"
backup_filename_r_end:

file_exists_msg:
    !text "FILE EXISTS",$0D,$00

; ============================================================================
; HEXTABLE
; ============================================================================

HEXTABLE:
          !text  "0123456789ABCDEF"
    
; ============================================================================
; TABELLA COMANDI
; ============================================================================

cmd_table:
    !word notimp-1          ; @
    !word SAVEASM-1         ; A   @A START END ENTRY NAME
    !word BACKUP-1          ; B   @B  Backup intera ramdisk su disco
    !word notimp-1          ; C
    !word DIRECTORY-1       ; D   D
    !word DELETEFILE-1      ; E   @E indice  Cancella file
    !word FORMAT-1          ; F
    !word USER_AREA-1       ; G   @G [...]  Salta all'area utente (A = primo carattere dopo @G)
    !word notimp-1          ; H
    !word RESTORE-1         ; I   @I  Importa (ripristina) l'intera ramdisk da disco
    !word notimp-1          ; J
    !word notimp-1          ; K
    !word LOADFILE-1        ; L   Load NAME/INDEX
    !word notimp-1          ; M
    !word notimp-1          ; N
    !word notimp-1          ; O
    !word SAVESCREEN-1      ; P   @P [nomefile]  SaveScreen
    !word notimp-1          ; Q
    !word LOADAT-1          ; R   @R ADDR NAME/INDEX  Carica BYT/SCR a indirizzo
    !word SAVEBASIC-1       ; S   SaveBasic INDEX
    !word notimp-1          ; T
    !word SAVEBLOCK-1       ; U   SaveBytes START END NAME
    !word notimp-1          ; V
    !word notimp-1          ; W
    !word SAVEALL-1         ; X   @X n  Salva $A000-$CFFF (immagine avviabile)
    !word notimp-1          ; Y
    !word notimp-1          ; Z

; ============================================================================
; BAM E DIRECTORY DATA
; ============================================================================

BAM:
    !fill TOTAL_BLOCKS, 0

BAM_NEXT:
    !fill TOTAL_BLOCKS, 0

DIRECTORY_AREA:
    !fill MAX_ENTRY * 24, 0

; ============================================================================
; AREA UTENTE - da USER_AREA a $CFFF, libera per piccoli comandi dell'utente
; da richiamare con @G. Inizialmente contiene soltanto un RTS. Se il codice
; sopra cresce oltre USER_AREA, !fill sotto da' errore di assemblaggio.
; L'area e' inclusa nelle immagini salvate con @X.
; ============================================================================
    !fill USER_AREA - *, 0
user_area:
    RTS

STAGING_BUFFER      = DESCRIPTOR_BUFFER  ; riuso il tape buffer (libero durante backup/restore)

; ============================================================================
; FINE
; ============================================================================