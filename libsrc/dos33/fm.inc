;
; DOS 3.3 File Manager interface for the cc65 apple2 target
;
; Parameter list layout and call codes are from "Beneath Apple DOS",
; chapter 6 ("Calling the DOS File Manager"). See DESIGN.md, section 4.4.
;

        .include        "machine.inc"

; ------------------------------------------------------------------------
; Page 3 vectors

FM_LOCATE       := $03DC        ; Returns parameter list address in Y (lo), A (hi)
FM_ENTRY        := $03D6        ; File Manager entry; X=0 allocates on OPEN

; Last-used slot and drive kept by 48K DOS 3.3 ("Beneath Apple DOS" ch. 8,
; keyword value table at $AA66). S and D persist between commands; V is
; reset to 0 by every command, so it is not read from here.
DOS_DRIVE       := $AA68        ; 2 bytes
DOS_SLOT        := $AA6A        ; 2 bytes

; DOS's file buffers ("Beneath Apple DOS" ch. 6, DOS BUFFERS): MAXFILES of
; them, chained from the first two bytes of 48K DOS
DOS_BUFS        := $9D00        ; The first buffer's name field

; RWTS ("Beneath Apple DOS" ch. 6): JSR $3E3 returns DOS's IOB address in
; Y (lo), A (hi); JSR $3D9 calls RWTS with the IOB address in Y and A.

RWTS_LOCATE     := $03E3
RWTS_ENTRY      := $03D9

NSLOTS          = 7             ; Slots 1-7
NDRIVES         = 2             ; Drives 1-2

IOB_TYPE        = $00           ; Table type, must be IOB_TABLE
IOB_SLOT        = $01           ; Slot * 16
IOB_DRIVE       = $02           ; Drive (1 or 2)
IOB_VOLUME      = $03           ; Volume expected (0 = any)
IOB_TRACK       = $04
IOB_SECTOR      = $05
IOB_BUF         = $08           ; Address of 256-byte buffer (2)
IOB_COUNT       = $0B           ; Byte count ($00 = 256)
IOB_CMD         = $0C           ; Command ($01 = READ)
IOB_RC          = $0D           ; Return code

IOB_TABLE       = $01           ; IOB_TYPE value
IOB_READ        = $01           ; IOB_CMD value
RWTS_WPROT      = $10           ; IOB_RC: write protected
RWTS_VOLUME     = $20           ; IOB_RC: volume mismatch (others: drive or read error)

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

; __oserror values (DESIGN.md 5.6): DOS 3.3's own error numbers, as ONERR
; reports them and DOS's message table orders them ("Beneath Apple DOS"
; ch. 8, $A971); the File Manager's return codes are the first ten. The
; library's own codes follow, for conditions DOS 3.3 has no number for,
; as Atari's oserror.s does with code 183. oserror.s maps them all.
DOSERR_LANG     = $01           ; Language not available
DOSERR_RANGE    = $02           ; Range error (bad call type)
DOSERR_SUBRANGE = $03           ; Range error (bad sub-call type)
DOSERR_WPROT    = $04           ; Write protected
DOSERR_ENDDATA  = $05           ; End of data (a read past the end)
DOSERR_NOTFOUND = $06           ; File not found (OPEN with X = 0: allocated)
DOSERR_VOLUME   = $07           ; Volume mismatch
DOSERR_IO       = $08           ; I/O error
DOSERR_FULL     = $09           ; Disk full
DOSERR_LOCKED   = $0A           ; File locked
DOSERR_SYNTAX   = $0B           ; Syntax error
DOSERR_NOBUFS   = $0C           ; No buffers available
DOSERR_TYPE     = $0D           ; File type mismatch
DOSERR_TOOLARGE = $0E           ; Program too large
DOSERR_NOTDIRECT = $0F          ; Not direct command
LIBERR_EXISTS   = $10           ; File exists (O_EXCL, rename)
LIBERR_OPEN     = $11           ; File is open (remove, rename)
LIBERR_NOTDOS   = $12           ; Not a DOS 3.3 disk (opendir)
LIBERR_POSITION = $13           ; Position out of range (lseek)
LIBERR_NOEND    = $14           ; File has no recorded end (O_APPEND)

; File types, as OPEN takes and returns them and the catalog stores them:
; one coding (DESIGN.md 4.4), DOS 3.3's own, which C programs see too
; (include/dos33_filetype.h). OPEN copies the type between the parameter
; list and the directory entry unchanged ("Beneath Apple DOS" ch. 8, $ABA6).
FMT_TEXT        = $00
FMT_INTEGER     = $01
FMT_APPLESOFT   = $02
FMT_BINARY      = $04
FMT_SPECIAL     = $08           ; S
FMT_RELOC       = $10           ; R
FMT_LOCKED      = $80           ; OPEN's type byte and catalog entries: locked
FMT_TYPE_MASK   = $7F           ; AND mask: the type without the lock bit

; File names: up to NAME_LEN characters, high bit set, padded with
; HI_SPACE, as DOS's command parser stores them ("Beneath Apple DOS" ch. 8)
NAME_LEN        = 30

; ------------------------------------------------------------------------
; Per-file control block: one of DOS's file buffers (fmbuf.s, DESIGN.md
; 4.4), addressed at its File Manager work area and kept in
; fdtab[fd].BUFFER. The 30-byte name field follows the work area: its first
; byte is nonzero while the buffer is in use, and the library keeps its
; own fields in the rest. The T/S list and data sector buffers are 256 and
; 512 bytes below the work area.

.struct FCB
        WORK    .res 45         ; File Manager work area
        INUSE   .byte           ; First byte of the name field: FCB_INUSE
        KIND    .byte           ; Bit 7 set: T file (text codec)
        HDRLEN  .byte           ; Hidden header length: 0, 2 (A/I) or 4 (B)
        LENOFS  .byte           ; Offset of the length word in the header
        STATE   .byte           ; See FCBS_* below
        LEN     .word           ; Header files: logical length (from header)
        POS     .word           ; Logical position (bytes after the header)
        TYPE    .byte           ; OPEN's type byte, including the lock bit
        ADDR    .word           ; B files: load address (from the header)
                .res 18         ; Rest of the name field
        BUFS    .res 6          ; DOS's pointers to the three buffers
        NEXT    .addr           ; Next buffer's name field; 0 after the last
.endstruct

FCB_TSL         = $100          ; T/S list buffer: work area - FCB_TSL
FCB_DATA        = $200          ; Data sector buffer: work area - FCB_DATA
FCB_INUSE       = $FF           ; Any nonzero value reserves the buffer

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
        .global         fm_getfcb, fm_freefcb, fm_isopen

; ------------------------------------------------------------------------
; Directories. DIRENT must match struct dirent in include/dirent.h.

.struct DIRENT
        NAME    .res ::NAME_LEN + 1 ; NAME_LEN characters + NUL
        INO     .word           ; T/S list track * 256 + sector
        BLOCKS  .word           ; 512-byte blocks
        TYPE    .byte           ; Catalog type without the lock bit
        ACCESS  .byte           ; FMT_LOCKED if locked, else $00
        SECTORS .word           ; Length in sectors
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
