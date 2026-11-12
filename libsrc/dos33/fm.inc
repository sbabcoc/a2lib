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
        .global         fm_name, fm_namebuf, fm_slot, fm_drive
        .global         fm_tempfcb, fm_freefcb
