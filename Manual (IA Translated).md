# RAM-Disk XL for Commodore 64 — Operating Manual
**Manual Version:** 1.0 (draft)  
**Program Author:** KymyA  
**License:** CC BY-NC 4.0  

---

## 1. What it is
RAM-Disk XL is a machine-language utility for the Commodore 64 that turns the "hidden" RAM underneath the ROMs into a small virtual disk. It allows you to save and recall in a few moments:
- **BASIC** programs;
- complete **screens** (characters and color);
- any **memory areas**;
- **assembly programs**, with their relative entry point.

Commands are issued from the BASIC prompt, preceded by the `@` character (a "wedge"): for example `@P "SCREEN1"`.

The program resides in `$C000-$CFFF`. The data resides in the RAM located under the BASIC ROM, under the I/O area, and under the KERNAL ROM, therefore **they do not take anything away from the 38,911 bytes of BASIC**.

## 2. Technical Characteristics
| Item | Value |
|---|---|
| Capacity | 79 blocks of 256 bytes (20,224 bytes) |
| Directory entries | 10 (indices from 0 to 9) |
| Name length | up to 15 characters |
| Blocks 0-31 | RAM `$A000-$BFFF` (under BASIC ROM) |
| Blocks 32-78 | RAM `$D000-$FEFF` (under I/O and KERNAL) |
| Unused | page `$FF00-$FFFF` (contains hardware vectors) |
| Resident program | `$C000-$CF2F` (tables included) |
| User area (`@G`) | `$CF30-$CFFF` (208 bytes) |
| Disk device | 8 (fixed in code) |

Files do not need to be contiguous: each file occupies a chain of blocks, described in a second table (secondary BAM). A file uses `ceil(length / 256)` blocks.

## 3. Startup
1. Load the program: `LOAD "RAMDISK",8,1`
2. Start it: `SYS 49152`

At startup, the program:
- prints the banner;
- installs the `@` command;
- **clears the BASIC program present in memory** (equivalent to a `NEW`);
- if the ramdisk has never been initialized (BAM all zeros), **formats it by itself**;
- if a file named `AUTOBOOT.ASM` exists in the directory (to be created with `@A`, so that it is of type ASM), it **loads and executes it immediately** (see §8).

A second `SYS 49152` on an already-in-use ramdisk **does not** delete the files.

## 4. General Syntax
Notation used in the manual: `<…>` mandatory parameter, `[…]` optional parameter.

### 4.1 Numbers
- **Decimal** (default): `1024`, values from 0 to 65535.
- **Hexadecimal**, preceded by `$` and **always with 4 digits**: `$0400`. Writing `$400` produces `?SYNTAX ERROR`.
- The two formats can be mixed: `@U $0400 1279 "DATA"`.

> **Warning:** `0400` without `$` is the decimal number 400, not the hexadecimal `$0400`.

The `@E` and `@X` commands read their number using the BASIC evaluation routine, so they accept **only decimals** (from 0 to 9).

### 4.2 Names
- In quotes: `"MY FILE"` (maximum 15 characters, spaces allowed).
- Without quotes: `MYFILE` (ends at the first space).
- If the name is optional and you omit it, the command's default name is used.

> **Known bug:** separates parameters with **spaces**. With a comma immediately before the name (`@U 1024,1279,NAME`) the name turns out empty.

### 4.3 Indices
The index is the number on the left in the `@D` listing. It must be written as **a single digit** (0-9). A name starting with a digit must be put in quotes, otherwise `@L` mistakes it for an index.

### 4.4 Direct and Program Mode
Almost all commands work **only in direct mode** (typed from the prompt). Used inside a BASIC program they give `?ILLEGAL DIRECT ERROR`. Exceptions are:

| Also usable from program | `@D`, `@F`, `@G`, `@L`, `@P` |
|---|---|

The confirmation message `OK` is printed **only in direct mode**.

## 5. Command Reference
| Command | Function |
|---|---|
| `@F` | Format the ramdisk |
| `@D` | File listing (directory) |
| `@P [name]` | Save the screen |
| `@S [name]` | Save the BASIC program |
| `@U start end [name]` | Save a memory area |
| `@A start end entry [name]` | Save an assembly program |
| `@L [index \| name]` | Load a file |
| `@R address [index \| name]` | Load a file to another address |
| `@E index` | Delete a file |
| `@G [parameters]` | Jump to user area |
| `@X n` | Save a bootable image to disk |
| `@B` | Complete backup to disk |
| `@I` | Complete restore from disk |

### `@F` — Format
Clears BAM and directory: **all files are lost**. Can also be used from a BASIC program (in that case it does not print `OK`).

### `@D` — Directory
Shows one line for each file:
```
# FILENAME           TY  START  END  BLK
00 "SCREEN1        " SCR 0400   ---- 08
01 "PROGRAM        " BAS 0801   080D 01
(70/79) BLOCKS FREE.
```
- `TY` is the type (§6); `START` and `END` are in **hexadecimal**.
- For SCR files, the end does not make sense (screen and color are in different zones) and `----` appears.
- `BLK` is the number of blocks used (hexadecimal).
- The last line (free/total blocks) appears only in direct mode.

### `@P [name]` — Save screen
Saves the character map (1000 bytes) **and** the color memory (1000 bytes) in 8 blocks. Default name: `SCREEN`. The start of the character map is read from register `$D018`, so it also works with a shifted screen (limited to VIC bank 0).

### `@S [name]` — Save BASIC program
Saves the program text, from the beginning up to the variables pointer. **Variables are not saved.** Default name: `PROGRAM`. With no program in memory, you get `?OUT OF MEMORY ERROR`.

### `@U start end [name]` — Save memory
Saves bytes from `start` to `end - 1` (the `end` address is not included). Default name: `BLOCK`. If `end` is less than `start`: `?ILLEGAL QUANTITY ERROR`.

### `@A start end entry [name]` — Save assembly program
Like `@U`, but also stores the **entry point** `entry`, which must lie between `start` and `end`. `end` must be greater than `start`. Default name: `ASM`. Range errors: `?ILLEGAL QUANTITY ERROR`.

### `@L [index | name]` — Load
Brings the file back **to its original position**. Without parameters, loads entry 0. Behavior depends on the type:
- **BAS** — copies the program back and repositions BASIC pointers; then use `RUN`. Variables are cleared.
- **SCR** — restores characters and color.
- **BYT** — copies the bytes back to where they were.
- **ASM** — copies the program back and **executes it immediately** by jumping to the entry point.

Non-existent name: `?FILE NOT FOUND ERROR`.

### `@R address [index | name]` — Load elsewhere
Loads a **BYT** or **SCR** file to an address different from the original one, thus "moving" the data. For SCR files, loads **only the character map** (1000 bytes), not the color. With BAS or ASM files: `?SYNTAX ERROR`. Direct mode only.
```
@R $2000 "SCREEN1"
```

### `@E index` — Delete
Deletes the entry and frees its blocks. Index greater than 9: `?ILLEGAL QUANTITY ERROR`; already empty entry: `?FILE NOT FOUND ERROR`.

### `@G [parameters]` — User area
`@G` jumps to address `$CF30`, where the user can put their own small machine language program (up to 208 bytes, `$CF30-$CFFF`) and recall it conveniently from BASIC. By default there is only an `RTS`, so `@G` does nothing until something is loaded there. Works both in direct mode and from a program. (The letter `X` is already used by the image command.)

**How your routine is called**
- On entry, the **accumulator contains the first character after `@G`** (spaces are already skipped) and the BASIC text pointer (`$7A/$7B`) points to that character.
- If you need to read more, the routine can call `CHRGET` (`JSR $0073`) or BASIC and KERNAL routines.
- Return with `RTS`. What remains of the line is skipped automatically, so there is no need to consume all parameters.
- Do not leave extra bytes on the stack.
- Zero page `$FB-$FE` can be used freely: the program uses it only during its own commands.

**Example:** `@G n` adds the digit `n` to the first 256 screen characters.
```assembly
        SEC
        SBC  #$30         ; from character to value: '3' -> 3
        STA  $FB
        LDX  #0
LOOP    LDA  $0400,X
        CLC
        ADC  $FB
        STA  $0400,X
        INX
        BNE  LOOP
        RTS
```
It is loaded from BASIC with `POKE` instructions (53040 = `$CF30`) and then recalled:
```basic
10 FOR I=0 TO 19:READ B:POKE 53040+I,B:NEXT
20 DATA 56,233,48,133,251,162,0,189,0,4,24,101,251,157,0,4,232,208,244,96
RUN
@G 3
```

**Things to know**
- Address `$CF30` is **fixed**: it does not change between versions, so your routines remain valid.
- The file loaded from disk contains only the `RTS` in the user area; the rest is uninitialized RAM.
- The area is saved and restored by images created with `@X`, so routines survive them (`@F` does not touch it).
- To restart with your routines already ready, save an image after loading them.

### `@X n` — Bootable image
Saves memory from `$A000` to `$CFFF` (including the program itself, tables, and blocks 0-31) to disk, in the file `IMAGEn.RDXL` (`n` from 0 to 9; higher values give `?OVERFLOW ERROR`). Restored with:
```basic
LOAD "IMAGE0.RDXL",8,1
SYS 49152
```

> **Warning:** the image **does not contain blocks 32-78** (RAM `$D000-$FEFF`). After restoration, the directory would also list files whose data was not saved. To save everything, use `@B`.
> 
> **To verify:** if `IMAGEn.RDXL` already exists, the drive refuses the write (DOS error 63). Delete the old file first or use another index.

### `@B` and `@I` — Full backup and restore
`@B` writes to disk, into the sequential file `RAMDISK.IMG`, **everything**: BAM, chain table, directory, and all 79 blocks (any existing file with the same name is replaced). `@I` re-reads that file (must have been created by `@B`) and restores the state. Disk errors: `?LOAD ERROR`. The operation is slow on a real 1541, because data passes one byte at a time.

## 6. File Types
| Abbr | Type | Created by | Content |
|---|---|---|---|
| `BAS` | BASIC program | `@S` | Program text |
| `SCR` | Screen | `@P` | Characters + color (2000 bytes, 8 blocks) |
| `ASM` | Assembly | `@A` | Code + entry point |
| `BYT` | Memory | `@U` | Memory area |

## 7. Error Messages
The program reuses standard BASIC messages; the only custom text is `FILE EXISTS`.

| Message | When it appears |
|---|---|
| `?SYNTAX ERROR` | Wrong parameters; 4-digit hex number missing; `@R` on a BAS/ASM file; unknown `@` command |
| `?ILLEGAL QUANTITY ERROR` | Invalid range (`end` ≤ `start`, `entry` out of range); index greater than 9 |
| `?OUT OF MEMORY ERROR` | No free directory entries or insufficient blocks; `@S` without program |
| `FILE EXISTS` | A file with the same name already exists |
| `?FILE NOT FOUND ERROR` | Non-existent name in `@L`/`@R`; empty entry in `@E` |
| `?ILLEGAL DIRECT ERROR` | Direct-only command used inside a program |
| `?LOAD ERROR` | Disk problem in `@X`, `@B`, `@I` |
| `?OVERFLOW ERROR` | `@X` index greater than 9 |

## 8. Examples

### 8.1 First session
```basic
SYS 49152
@P "TITLE"           ← saves the current screen
@S "GAME"            ← saves the BASIC program in memory
@D                   ← listing
NEW
@L "GAME"            ← reloads it
RUN
```

### 8.2 Saving and moving a memory area
```basic
@U $0400 $0500 "MAP"        ← saves $0400-$04FF
@R $2000 "MAP"              ← reloads it starting from $2000
```

### 8.3 Assembly program
```basic
@A $9000 $9100 $9000 "ROUTINE"
@L "ROUTINE"                ← reloads and runs it
```

### 8.4 Auto-boot disk
1. Format with `@F` and save the programs you need.
2. Save the program to start as ASM with the exact name `AUTOBOOT.ASM`:
   `@A $9000 $9100 $9000 "AUTOBOOT.ASM"`
3. Create the image: `@X 0`
4. Next time you turn it on: `LOAD "IMAGE0.RDXL",8,1` and `SYS 49152`. The `AUTOBOOT.ASM` program starts by itself.

> **Tip:** blocks are assigned starting from the lowest number, so the first ~8 KB of files end up in blocks 0-31, which the image contains. Save `AUTOBOOT.ASM` and its data **first** after a `@F`.

### 8.5 Use from a BASIC program
```basic
10 @P "SCREEN"
20 @L "SCREEN"
```

## 9. Known Limits and Warnings
- **Cartridge (CRT):** the cartridge version is not yet working; for now, the program is used by loading it from disk.
- **BASIC variables** as parameters are not supported by commands with addresses (`@A`, `@U`, `@R`). `@E` and `@X` use the BASIC calculation routine and should accept them, but it has not been verified.
- **Comma before name:** see §4.2.
- **VIC Bank:** for screens, VIC bank 0 (`$0000-$3FFF`) is assumed.
- **Use of RAM under ROMs:** programs that exclude the BASIC or KERNAL ROM and use those areas overwrite ramdisk data.
- **RESTORE key:** during copies, which last a few milliseconds, the KERNAL is temporarily excluded; the non-maskable interrupt generated by RESTORE could freeze the machine. Avoid pressing it while a command is working.
- **`@L` on an empty entry** does not report an error and does not do anything.
- **`@L` of an ASM file** always executes it: load only what you trust.
- **Space:** code and tables end at `$CF20`; the user area (`@G`) starts at `$CF30`, a fixed address. There are about 16 bytes of margin left for source modifications (if the code exceeds them, the assembler signals an error).

## 10. For Developers

### 10.1 Compilation
The source is for the **ACME** assembler. The program is assembled with start address `$C000`; to get a `.prg` loadable with `LOAD "...",8,1` the header with the address is needed:
```bash
acme -f cbm -o ramdisk.prg RAMDisk-Evolved_AI_fixed.asm
```

### 10.2 Directory entry format (24 bytes)
| Offset | Content |
|---|---|
| 0 | Type: 0 = free, 1 = BAS, 2 = SCR, 3 = ASM, 4 = BYT |
| 1-15 | Name (terminated by 0 if shorter) |
| 16-17 | Start address |
| 18-19 | End address |
| 20 | First block |
| 21-22 | Entry point (ASM) |
| 23 | Number of blocks |

### 10.3 BAM and chains
- **BAM:** 79 bytes, one per block. `$FF` = free; otherwise the index of the owning directory entry.
- **Secondary BAM:** 79 bytes; for each block indicates the next block of the file, `$FF` = last.
- **Physical address:** blocks 0-31 → `$A000 + n × 256`; blocks 32-78 → `$D000 + (n − 32) × 256`.

### 10.4 Notes on BASIC integration
The `@` command hooks into vector `$0308`. After each command, the text pointer is brought to the end of the instruction (`$00` or `:`) because the interpreter checks it and would otherwise report `?SYNTAX ERROR`. Color memory (`$D800`), unlike the rest, is read and written only with I/O active, which is why screen copying is done in half-blocks with a memory configuration change.

---
_Document compiled based on the source code and testing performed during development._