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
; dir_at: open the catalog at fm_slot, fm_drive and fm_volume (used by
; opendir and stat). Returns the DIR* in AX, or NULL with errno set.
;

        .export         __opendir_a2lib
        .import         _malloc, _free, return0

        .include        "zeropage.inc"
        .include        "errno.inc"
        .include        "fm.inc"
        .include        "dir.inc"

        .code

__opendir_a2lib:
        jsr     fm_location     ; Takes the name in AX
        bcc     dir_at
        jmp     nullmapped      ; A = DOSERR_SYNTAX -> EINVAL

dir_at:
        lda     #<.sizeof(DIR)
        ldx     #>.sizeof(DIR)
        jsr     _malloc
        sta     ptr1
        stx     ptr1+1
        ora     ptr1+1
        bne     :+
        lda     #ENOMEM
        jmp     nulldirect

:       ldy     #DIR::SLOT
        lda     fm_slot
        sta     (ptr1),y
        .assert DIR::DRIVE = DIR::SLOT + 1, error
        .assert DIR::VOLUME = DIR::DRIVE + 1, error
        iny
        lda     fm_drive
        sta     (ptr1),y
        iny
        lda     fm_volume
        sta     (ptr1),y

        ; Read the VTOC
        lda     #VTOC_TRACK
        ldx     #$00
        jsr     read_dir_sector_ptr1
        bcc     :+
        jsr     rwts_maperr
        jmp     freemapped

        ; Check that it is a DOS 3.3 VTOC: 16 sectors per track, 122 T/S
        ; pairs per list sector, and a first catalog sector on the disk
:       ldy     #DIR::BUF + VTOC_SECTORS
        lda     (ptr1),y
        cmp     #DOS_SECTORS
        bne     notdos
        ldy     #DIR::BUF + VTOC_TSPAIRS
        lda     (ptr1),y
        cmp     #DOS_TSPAIRS
        bne     notdos
        ldy     #DIR::BUF + VTOC_CATTRACK
        lda     (ptr1),y
        beq     notdos
        cmp     #DOS_TRACKS
        bcs     notdos
        ldy     #DIR::FIRSTT
        sta     (ptr1),y
        ldy     #DIR::BUF + VTOC_CATTRACK + 1
        lda     (ptr1),y
        cmp     #DOS_SECTORS
        bcs     notdos
        ldy     #DIR::FIRSTS
        sta     (ptr1),y

        jsr     rewinddir_ptr1
        lda     ptr1
        ldx     ptr1+1
        rts

notdos: lda     #LIBERR_NOTDOS  ; -> ENODEV
freemapped:
        pha
        lda     ptr1
        ldx     ptr1+1
        jsr     _free
        pla
nullmapped:
        jsr     ___mappederrno
        jmp     return0
nulldirect:
        jsr     ___directerrno
        jmp     return0

; ------------------------------------------------------------------------
; read_dir_sector_ptr1: read track A, sector X of the disk of the DIR at
; ptr1 into its BUF. Returns as rwts_read.

read_dir_sector_ptr1:
        sta     rwts_track
        stx     rwts_sector
        ldy     #DIR::SLOT
        lda     (ptr1),y
        sta     rwts_slot
        iny
        lda     (ptr1),y
        sta     rwts_drive
        iny
        lda     (ptr1),y
        sta     rwts_volume
        clc
        lda     ptr1
        adc     #<DIR::BUF
        sta     rwts_buf
        lda     ptr1+1
        adc     #>DIR::BUF
        sta     rwts_buf+1
        jmp     rwts_read
