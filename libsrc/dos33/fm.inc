;
; DOS 3.3 File Manager interface for the cc65 apple2 target
;
; Parameter list layout and call codes are from "Beneath Apple DOS",
; chapter 6 ("Calling the DOS File Manager"). See DESIGN.md, section 4.4.
;

; ------------------------------------------------------------------------
; Page 3 vectors

FM_LOCATE       := $03DC        ; Returns parameter list address in Y (lo), A (hi)
FM_ENTRY        := $03D6        ; File Manager entry; X=0 allocates on OPEN

; Last-used slot and drive kept by 48K DOS 3.3 ("Beneath Apple DOS" ch. 8,
; keyword value table at $AA66). S and D persist between commands; V is
; reset to 0 by every command, so it is not read from here.
DOS_DRIVE       := $AA68        ; 2 bytes
DOS_SLOT        := $AA6A        ; 2 bytes

; RWTS ("Beneath Apple DOS" ch. 6): JSR $3E3 returns DOS's IOB address in
; Y (lo), A (hi); JSR $3D9 calls RWTS with the IOB address in Y and A.

RWTS_LOCATE     := $03E3
RWTS_ENTRY      := $03D9

IOB_TYPE        = $00           ; Table type, must be $01
IOB_SLOT        = $01           ; Slot * 16
IOB_DRIVE       = $02           ; Drive (1 or 2)
IOB_VOLUME      = $03           ; Volume expected (0 = any)
IOB_TRACK       = $04
IOB_SECTOR      = $05
IOB_BUF         = $08           ; Address of 256-byte buffer (2)
IOB_COUNT       = $0B           ; Byte count ($00 = 256)
IOB_CMD         = $0C           ; Command ($01 = READ)
IOB_RC          = $0D           ; Return code

; DOS 3.3 disk layout ("Beneath Apple DOS" ch. 4)
VTOC_TRACK      = $11           ; VTOC: track 17, sector 0
VTOC_CATTRACK   = $01           ; First catalog sector: track, sector
VTOC_TSPAIRS    = $27           ; T/S pairs per T/S list sector (122)
VTOC_SECTORS    = $35           ; Sectors per track (16)
CAT_NEXT        = $01           ; Catalog sector: next track, sector
CAT_ENTRIES     = $0B           ; Catalog sector: first file entry
CAT_ENTRYLEN    = 35            ; Bytes per file entry
CAT_PERSECTOR   = 7             ; File entries per catalog sector
ENT_TRACK       = $00           ; Entry: T/S list track ($00 unused, $FF deleted)
ENT_SECTOR      = $01
ENT_TYPE        = $02           ; Type in catalog coding; bit 7 = locked
ENT_NAME        = $03           ; 30 bytes
ENT_LENGTH      = $21           ; Length in sectors (2)

; ------------------------------------------------------------------------
; Parameter list offsets

FM_CALL         = $00           ; Call type
FM_SUB          = $01           ; Sub-call type for READ / WRITE
FM_RECORD       = $02           ; OPEN: record length; RW: record number (2)
FM_NEWNAME      = $02           ; RENAME: address of new name (2)
FM_VOLUME       = $04           ; OPEN: volume number (0 = any)
FM_OFFSET       = $04           ; RW: byte offset (2)
FM_DRIVE        = $05           ; OPEN: drive (1-2)
FM_SLOT         = $06           ; OPEN: slot (1-7)
FM_RANGE        = $06           ; RW: range length (2)
FM_TYPE         = $07           ; OPEN: file type in (new files) and out
FM_NAME         = $08           ; OPEN: address of 30-byte name (2)
FM_ADDR         = $08           ; RW: range address (2)
FM_BYTE         = $08           ; RW one byte: byte read or to write
FM_RC           = $0A           ; Return code
FM_WORK         = $0C           ; Address of 45-byte work area (2)
FM_TSL          = $0E           ; Address of 256-byte T/S list buffer (2)
FM_DATA         = $10           ; Address of 256-byte data buffer (2)

; Call types
FMC_OPEN        = $01
FMC_CLOSE       = $02
FMC_READ        = $03
FMC_WRITE       = $04
FMC_DELETE      = $05
FMC_RENAME      = $09
FMC_POSITION    = $0A

; Sub-call types for READ / WRITE
FMS_ONE         = $01           ; One byte
FMS_RANGE       = $02           ; Range of bytes
FMS_POSRANGE    = $04           ; POSITION, then range

; "Beneath Apple DOS" ch. 6: for a range WRITE, the length passed must be
; one less than the number of bytes to write. Kept in one place so the
; adjustment can be changed if testing on real DOS shows otherwise.
FM_WRITE_ADJUST = 1

; Return codes used by this layer
FMR_ENDDATA     = $05           ; End of data
FMR_NOTFOUND    = $06           ; File not found (allocated if X=0)

; File types in the File Manager's coding (OPEN byte 07). These differ
; from catalog entry codes for R and S files; see DESIGN.md 4.4.
FMT_TEXT        = $00
FMT_INTEGER     = $01
FMT_APPLESOFT   = $02
FMT_BINARY      = $04
FMT_RELOC       = $08

; ------------------------------------------------------------------------
; Per-file control block, allocated with malloc() by open() and kept in
; fdtab[fd].BUFFER. The File Manager's three buffers live inside it, so
; the layer doesn't use DOS's MAXFILES buffer chain (DESIGN.md 4.4).

.struct FCB
        KIND    .byte           ; Bit 7 set: T file (text codec)
        HDRLEN  .byte           ; Hidden header length: 0, 2 (A/I) or 4 (B)
        LENOFS  .byte           ; Offset of the length word in the header
        STATE   .byte           ; See FCBS_* below
        LEN     .word           ; Header files: logical length (from header)
        POS     .word           ; Logical position (bytes after the header)
        TYPE    .byte           ; OPEN's type byte, including the lock bit
        ADDR    .word           ; B files: load address (from the header)
        WORK    .res 45         ; File Manager work area
        TSL     .res 256        ; File Manager T/S list buffer
        DATA    .res 256        ; File Manager data sector buffer
.endstruct

FCBS_EOF        = $80           ; T file: end of data was read
FCBS_DIRTY      = $40           ; Header file: length changed, rewrite on close

FCB_TEXT        = $80           ; FCB::KIND value for T files

; ------------------------------------------------------------------------
; Shared routines (fm.s, fmname.s)

        .global         fm_begin, fm_call, fm_simple, fm_maperr
        .global         fm_position, fm_readbyte, fm_writebyte
        .global         fm_rangeio, fm_rio_addr, fm_rio_count
        .global         fm_incpos
        .global         fm_name, fm_location, fm_namebuf
        .global         fm_slot, fm_drive, fm_volume
        .global         dir_at
        .global         rwts_read, rwts_maperr
        .global         rwts_slot, rwts_drive, rwts_volume
        .global         rwts_track, rwts_sector, rwts_buf
        .global         fm_tempfcb, fm_freefcb

; ------------------------------------------------------------------------
; Directories. DIRENT must match struct dirent in include/dirent.h.

.struct DIRENT
        NAME    .res 31         ; 30 characters + NUL
        INO     .word           ; T/S list track * 256 + sector
        BLOCKS  .word           ; 512-byte blocks
        TYPE    .byte           ; ProDOS-equivalent type
        ACCESS  .byte           ; $01 locked, $C3 otherwise
        SECTORS .word           ; Length in sectors
        DOSTYPE .byte           ; Catalog type without the lock bit
.endstruct

.struct DIR
        SLOT    .byte           ; Location from opendir
        DRIVE   .byte
        VOLUME  .byte
        FIRSTT  .byte           ; First catalog sector (from the VTOC)
        FIRSTS  .byte
        NEXTT   .byte           ; Next catalog sector to read
        NEXTS   .byte
        INDEX   .byte           ; Next entry in BUF; CAT_PERSECTOR = read next
        DONE    .byte           ; End of the catalog reached
        ENT     .tag DIRENT     ; Entry returned by readdir
        BUF     .res 256        ; VTOC, then the current catalog sector
.endstruct
