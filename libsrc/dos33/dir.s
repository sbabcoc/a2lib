;
; DOS 3.3 directories for the cc65 apple2 target (DESIGN.md 5.9)
;
; DIR* __fastcall__ _dos33_opendir (const char* name);
; struct dirent* __fastcall__ _dos33_readdir (DIR* dir);
; int __fastcall__ _dos33_closedir (DIR* dir);
; void __fastcall__ _dos33_rewinddir (DIR* dir);
;
; include/dirent.h maps opendir, readdir, closedir and rewinddir to these.
;
; The File Manager's CATALOG call only prints, so the catalog is read
; directly through RWTS: the VTOC (track 17, sector 0) gives the first
; catalog sector, and each catalog sector links to the next and holds
; seven file entries. As in DOS's own search ("Beneath Apple DOS" ch. 8,
; B1C9), deleted entries ($FF) are skipped and the first never-used entry
; ($00) ends the catalog.
;
; dir_at: open the catalog at fm_slot, fm_drive and fm_volume (used by
; opendir and stat). Returns the DIR* in AX, or NULL with errno set.
;

        .export         __dos33_opendir, __dos33_readdir
        .export         __dos33_closedir, __dos33_rewinddir
        .import         __dos_type
        .import         _malloc, _free

        .macpack        longbranch

        .include        "zeropage.inc"
        .include        "errno.inc"
        .include        "fm.inc"

        .code

; ------------------------------------------------------------------------

__dos33_opendir:
        sta     ptr1
        stx     ptr1+1

        ; Under ProDOS the page 3 vectors aren't DOS 3.3's
        lda     __dos_type
        beq     :+
        lda     #ENOSYS
        jmp     nulldirect

:       lda     ptr1
        ldx     ptr1+1
        jsr     fm_location
        bcc     dir_at
        jmp     nullmapped      ; A = $40 -> EINVAL

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
        jsr     readsector
        bcc     :+
        jsr     rwts_maperr
        jmp     freemapped

        ; Check that it is a DOS 3.3 VTOC: 16 sectors per track, 122 T/S
        ; pairs per list sector, and a first catalog sector on the disk
:       ldy     #DIR::BUF + VTOC_SECTORS
        lda     (ptr1),y
        cmp     #16
        bne     notdos
        ldy     #DIR::BUF + VTOC_TSPAIRS
        lda     (ptr1),y
        cmp     #122
        bne     notdos
        ldy     #DIR::BUF + VTOC_CATTRACK
        lda     (ptr1),y
        beq     notdos
        cmp     #35
        bcs     notdos
        ldy     #DIR::FIRSTT
        sta     (ptr1),y
        ldy     #DIR::BUF + VTOC_CATTRACK + 1
        lda     (ptr1),y
        cmp     #16
        bcs     notdos
        ldy     #DIR::FIRSTS
        sta     (ptr1),y

        jsr     rewind
        lda     ptr1
        ldx     ptr1+1
        rts

notdos: lda     #$52            ; ProDOS "Not a ProDOS volume" -> ENODEV
freemapped:
        pha
        lda     ptr1
        ldx     ptr1+1
        jsr     _free
        pla
nullmapped:
        jsr     ___mappederrno
        jmp     null
nulldirect:
        jsr     ___directerrno
null:   lda     #$00
        tax
        rts

; ------------------------------------------------------------------------

__dos33_readdir:
        sta     ptr1
        stx     ptr1+1

next:   ldy     #DIR::DONE
        lda     (ptr1),y
        jne     null            ; End of the catalog: NULL, errno unchanged

        ; Read the next catalog sector when this one is used up
        ldy     #DIR::INDEX
        lda     (ptr1),y
        cmp     #CAT_PERSECTOR
        bcc     entry
        ldy     #DIR::NEXTT
        lda     (ptr1),y
        jeq     end             ; End of the chain
        pha
        ldy     #DIR::NEXTS
        lda     (ptr1),y
        tax
        pla
        jsr     readsector
        bcc     :+
        jsr     rwts_maperr
        jmp     nullmapped
:       ldy     #DIR::BUF + CAT_NEXT
        lda     (ptr1),y
        ldy     #DIR::NEXTT
        sta     (ptr1),y
        ldy     #DIR::BUF + CAT_NEXT + 1
        lda     (ptr1),y
        ldy     #DIR::NEXTS
        sta     (ptr1),y
        lda     #$00
        ldy     #DIR::INDEX
        sta     (ptr1),y

        ; ptr2 = the entry: BUF + CAT_ENTRIES + INDEX * CAT_ENTRYLEN
entry:  tax
        clc
        adc     #$01
        sta     (ptr1),y        ; Y = DIR::INDEX: advance
        clc
        lda     ptr1
        adc     #<(DIR::BUF + CAT_ENTRIES)
        sta     ptr2
        lda     ptr1+1
        adc     #>(DIR::BUF + CAT_ENTRIES)
        sta     ptr2+1
        clc
        lda     ptr2
        adc     entryofs,x
        sta     ptr2
        bcc     :+
        inc     ptr2+1

:       ldy     #ENT_TRACK
        lda     (ptr2),y
        jeq     end             ; Never used: end of the catalog
        cmp     #$FF
        jeq     next            ; Deleted

        ; d_name: 30 characters, bit 7 cleared, trailing blanks removed
        ldx     #$00
:       txa
        clc
        adc     #ENT_NAME
        tay
        lda     (ptr2),y
        and     #$7F
        pha
        txa
        clc
        adc     #DIR::ENT + DIRENT::NAME
        tay
        pla
        sta     (ptr1),y
        inx
        cpx     #30
        bne     :-
        lda     #$00
        ldy     #DIR::ENT + DIRENT::NAME + 30
        sta     (ptr1),y
:       dey
        lda     (ptr1),y
        cmp     #' '
        bne     :+
        lda     #$00
        sta     (ptr1),y
        cpy     #DIR::ENT + DIRENT::NAME
        bne     :-

        ; d_ino: T/S list track * 256 + sector
:       ldy     #ENT_SECTOR
        lda     (ptr2),y
        ldy     #DIR::ENT + DIRENT::INO
        sta     (ptr1),y
        ldy     #ENT_TRACK
        lda     (ptr2),y
        ldy     #DIR::ENT + DIRENT::INO + 1
        sta     (ptr1),y

        ; d_access, d_dostype, d_type
        ldy     #ENT_TYPE
        lda     (ptr2),y
        ldx     #$C3
        asl                     ; Lock bit into C
        bcc     :+
        ldx     #$01
:       lsr                     ; Type without the lock bit
        pha
        txa
        ldy     #DIR::ENT + DIRENT::ACCESS
        sta     (ptr1),y
        pla
        ldy     #DIR::ENT + DIRENT::DOSTYPE
        sta     (ptr1),y
        ldx     #NTYPES - 1
:       cmp     ctypes,x
        beq     :+
        dex
        bpl     :-
        lda     #$00
        beq     :++             ; Branch always
:       lda     ptypes,x
:       ldy     #DIR::ENT + DIRENT::TYPE
        sta     (ptr1),y

        ; d_sectors; d_blocks = (d_sectors + 1) / 2
        ldy     #ENT_LENGTH
        lda     (ptr2),y
        sta     tmp1
        iny
        lda     (ptr2),y
        sta     tmp2
        ldy     #DIR::ENT + DIRENT::SECTORS
        lda     tmp1
        sta     (ptr1),y
        iny
        lda     tmp2
        sta     (ptr1),y
        lda     tmp1
        clc
        adc     #$01
        sta     tmp1
        lda     tmp2
        adc     #$00
        ror                     ; 17-bit sum (carry in) / 2
        sta     tmp2
        ror     tmp1
        ldy     #DIR::ENT + DIRENT::BLOCKS
        lda     tmp1
        sta     (ptr1),y
        iny
        lda     tmp2
        sta     (ptr1),y

        ; Return &dir->ent
        clc
        lda     ptr1
        adc     #<DIR::ENT
        tay
        lda     ptr1+1
        adc     #>DIR::ENT
        tax
        tya
        rts

end:    lda     #$01
        ldy     #DIR::DONE
        sta     (ptr1),y
        jmp     null

; ------------------------------------------------------------------------

__dos33_closedir:
        jsr     _free
        lda     #$00
        tax
        rts

__dos33_rewinddir:
        sta     ptr1
        stx     ptr1+1
        ; Fall through

; rewind: start again at the first catalog sector (read on the next
; readdir).

rewind: ldy     #DIR::FIRSTT
        lda     (ptr1),y
        ldy     #DIR::NEXTT
        sta     (ptr1),y
        ldy     #DIR::FIRSTS
        lda     (ptr1),y
        ldy     #DIR::NEXTS
        sta     (ptr1),y
        lda     #CAT_PERSECTOR
        ldy     #DIR::INDEX
        sta     (ptr1),y
        lda     #$00
        ldy     #DIR::DONE
        sta     (ptr1),y
        rts

; ------------------------------------------------------------------------
; readsector: read track A, sector X of the DIR's disk into its BUF.
; Returns as rwts_read.

readsector:
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

        .rodata

entryofs:
        .repeat CAT_PERSECTOR, i
        .byte   i * CAT_ENTRYLEN
        .endrepeat

; Catalog type (lock bit cleared) -> ProDOS type
ctypes: .byte   $00, $04, $02, $01, $10 ; T, B, A, I, R
NTYPES = * - ctypes
ptypes: .byte   $04, $06, $FC, $FA, $FE
