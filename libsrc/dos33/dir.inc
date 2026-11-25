;
; DOS 3.3 directories: the catalog's layout, and the DIR that opendir()
; allocates. Include after the File Manager's definitions, for NAME_LEN. For
; details, see section 5.9 of DESIGN.
;

; DOS 3.3 disk layout ("Beneath Apple DOS" ch. 4)

DOS_TRACKS      = 35            ; Tracks on a disk
DOS_SECTORS     = 16            ; Sectors per track
DOS_TSPAIRS     = (256 - $0C) / 2 ; T/S pairs per T/S list sector, after its
                                ; 12-byte header (122)
VTOC_TRACK      = 17            ; The VTOC: track 17, sector 0

.struct VTOC
                .res    1
        CATTRACK  .byte         ; First catalog sector: track
        CATSECTOR .byte         ; and sector
        .org    $27
        TSPAIRS   .byte         ; T/S pairs per T/S list sector
        .org    $35
        SECTORS   .byte         ; Sectors per track
.endstruct

; A catalog file entry
.struct CATENTRY
        TRACK   .byte           ; T/S list track ($00 unused, $FF deleted)
        SECTOR  .byte           ; T/S list sector
        TYPE    .byte           ; Type in catalog coding; bit 7 = locked
        NAME    .res ::NAME_LEN
        LENGTH  .word           ; Length in sectors
.endstruct

; A catalog sector: a link to the next, then as many file entries as fit
.struct CATSECTOR
                .res    1
        NEXT    .res    2       ; Next catalog sector: track, sector
        .org    $0B
        ENTRIES .res    256 - $0B ; The file entries
.endstruct

CAT_PERSECTOR   = .sizeof(CATSECTOR::ENTRIES) / .sizeof(CATENTRY)

.assert .sizeof(CATENTRY) = 35, error, "A catalog entry is 35 bytes"
.assert CAT_PERSECTOR = 7, error, "A catalog sector holds 7 entries"
.assert DOS_TSPAIRS = 122, error, "A T/S list sector holds 122 pairs"

; DIRENT must match struct dirent in a2lib's dirent.h.

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

; The cell that the directory modules keep the DIR in (a text macro, as
; the File Manager's names are)

.define dirptr          ptr1    ; DIR*: the directory

; dir_at: open the catalog at fm_slot, fm_drive and fm_volume, for opendir
; and stat. read_dir_sector: read track A, sector X of dirptr's disk into
; its BUF. rewind_dir: start dirptr's directory again at the first catalog
; sector.

        .global         dir_at, read_dir_sector, rewind_dir
