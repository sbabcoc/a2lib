;
; Scott Babcock, 2026-11-20
;
; DIR* __fastcall__ _opendir_a2lib (const char* name);
;
; DOS 3.3 directories for the cc65 apple2 target (DESIGN.md 5.9). The DOS
; 3.3 struct dirent isn't stock's, so include/dirent.h maps opendir,
; readdir, closedir and rewinddir to names only these modules define
; (DESIGN.md 2), and these take the place of stock opendir.s, readdir.s,
; closedir.s and rewinddir.s in a2lib-dos33.lib: the DOS 3.3 header
; without them, or stock's with them, fails to link.
;
; The File Manager's CATALOG call only prints, so the catalog is read
; directly through RWTS: the VTOC (track 17, sector 0) gives the first
; catalog sector, and each catalog sector links to the next and holds
; seven file entries (readdir.s).
;

        .export         __opendir_a2lib
        .import         _malloc, _free, return0

        .include        "zeropage.inc"
        .include        "errno.inc"
        .include        "fm.inc"
        .include        "dir.inc"

        .code

;-----------------------------------------------------------------------------
; __opendir_a2lib: Open a directory: DIR* __fastcall__ _opendir_a2lib (const
; char* name), which dirent.h names opendir().
;
; Input:        AX            char*     name: "", ".", "D" or "/S/D"
;                                       (fm_location)
; Output:       AX            DIR*      the directory, or NULL
;               errno         int       if NULL: EINVAL (not a directory
;                                       path), or as dir_at
; Changes:      Y; dirptr, path (ptr1, fm_location) and what dir_at changes.

__opendir_a2lib:
        jsr     fm_location     ; Takes the name in AX
        bcc     dir_at
        jmp     nullmapped      ; A = DOSERR_SYNTAX -> EINVAL

;-----------------------------------------------------------------------------
; dir_at: Open the catalog of a disk, for opendir() and stat(): read its VTOC
; through RWTS, check that it's a DOS 3.3 disk, and take its first catalog
; sector.
;
; Input:        fm_slot       byte      the slot (1-7)
;               fm_drive      byte      the drive (1-2)
;               fm_volume     byte      the volume, 0 for any
; Output:       AX            DIR*      the directory (malloc), or NULL
;               errno         int       if NULL: ENOMEM, ENODEV (no DOS 3.3
;                                       VTOC), or as rwts_maperr maps
;               __oserror     byte      if NULL, unless ENOMEM: the DOS 3.3 or
;                                       library error
; Changes:      Y; dirptr, iob (ptr3) and what malloc changes. The disk's VTOC
;               is read.

dir_at:
        lda     #<.sizeof(DIR)
        ldx     #>.sizeof(DIR)
        jsr     _malloc
        sta     dirptr
        stx     dirptr+1
        ora     dirptr+1
        bne     :+
        lda     #ENOMEM
        jmp     nulldirect

:       ldy     #DIR::SLOT
        lda     fm_slot
        sta     (dirptr),y
        .assert DIR::DRIVE = DIR::SLOT + 1, error
        .assert DIR::VOLUME = DIR::DRIVE + 1, error
        iny
        lda     fm_drive
        sta     (dirptr),y
        iny
        lda     fm_volume
        sta     (dirptr),y

        ; Read the VTOC
        lda     #VTOC_TRACK
        ldx     #$00
        jsr     read_dir_sector
        bcc     :+
        jsr     rwts_maperr
        jmp     freemapped

        ; Check that it is a DOS 3.3 VTOC: 16 sectors per track, 122 T/S
        ; pairs per list sector, and a first catalog sector on the disk
:       ldy     #DIR::BUF + VTOC_SECTORS
        lda     (dirptr),y
        cmp     #DOS_SECTORS
        bne     notdos
        ldy     #DIR::BUF + VTOC_TSPAIRS
        lda     (dirptr),y
        cmp     #DOS_TSPAIRS
        bne     notdos
        ldy     #DIR::BUF + VTOC_CATTRACK
        lda     (dirptr),y
        beq     notdos
        cmp     #DOS_TRACKS
        bcs     notdos
        ldy     #DIR::FIRSTT
        sta     (dirptr),y
        ldy     #DIR::BUF + VTOC_CATTRACK + 1
        lda     (dirptr),y
        cmp     #DOS_SECTORS
        bcs     notdos
        ldy     #DIR::FIRSTS
        sta     (dirptr),y

        jsr     rewind_dir
        lda     dirptr
        ldx     dirptr+1
        rts

notdos: lda     #LIBERR_NOTDOS  ; -> ENODEV
freemapped:
        pha
        lda     dirptr
        ldx     dirptr+1
        jsr     _free
        pla
nullmapped:
        jsr     ___mappederrno
        jmp     return0
nulldirect:
        jsr     ___directerrno
        jmp     return0

;-----------------------------------------------------------------------------
; read_dir_sector: Read a sector of the directory's disk into its BUF.
;
; Input:        A             byte      the track
;               X             byte      the sector
;               dirptr        DIR*      the directory
; Output:       C             flag      as rwts_read
;               A             byte      as rwts_read
; Changes:      X, Y and iob (ptr3); the rwts_* inputs, set for the sector.

read_dir_sector:
        sta     rwts_track
        stx     rwts_sector
        ldy     #DIR::SLOT
        lda     (dirptr),y
        sta     rwts_slot
        iny
        lda     (dirptr),y
        sta     rwts_drive
        iny
        lda     (dirptr),y
        sta     rwts_volume
        clc
        lda     dirptr
        adc     #<DIR::BUF
        sta     rwts_buf
        lda     dirptr+1
        adc     #>DIR::BUF
        sta     rwts_buf+1
        jmp     rwts_read
