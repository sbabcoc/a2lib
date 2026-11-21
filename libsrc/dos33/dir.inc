;
; DOS 3.3 directories: the catalog's layout, and the DIR that opendir
; allocates (DESIGN.md 5.9). Include after fm.inc, for NAME_LEN.
;

; DOS 3.3 disk layout ("Beneath Apple DOS" ch. 4)
VTOC_TRACK      = $11           ; VTOC: track 17, sector 0
VTOC_CATTRACK   = $01           ; First catalog sector: track, sector
VTOC_TSPAIRS    = $27           ; T/S pairs per T/S list sector (122)
VTOC_SECTORS    = $35           ; Sectors per track (16)

DOS_SECTORS     = 16            ; Sectors per track
DOS_TSPAIRS     = 122           ; T/S pairs per T/S list sector
DOS_TRACKS      = 35            ; Tracks on a disk
CAT_NEXT        = $01           ; Catalog sector: next track, sector
CAT_ENTRIES     = $0B           ; Catalog sector: first file entry
CAT_ENTRYLEN    = 35            ; Bytes per file entry
CAT_PERSECTOR   = 7             ; File entries per catalog sector
ENT_TRACK       = $00           ; Entry: T/S list track ($00 unused, $FF deleted)
ENT_SECTOR      = $01
ENT_TYPE        = $02           ; Type in catalog coding; bit 7 = locked
ENT_NAME        = $03           ; 30 bytes
ENT_LENGTH      = $21           ; Length in sectors (2)

; DIRENT must match struct dirent in include/dirent.h.

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

; dir_at: open the catalog at fm_slot, fm_drive and fm_volume, for opendir
; and stat (opendir.s). read_dir_sector_ptr1: read track A, sector X of
; ptr1's DIR's disk into its BUF (opendir.s). rewinddir_ptr1: start
; ptr1's DIR again at the first catalog sector (rewinddir.s).

        .global         dir_at, read_dir_sector_ptr1, rewinddir_ptr1
