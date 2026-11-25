;
; Scott Babcock, 2026-11-20
;
; readdir() for DOS 3.3 disks. As in DOS's own search ("Beneath Apple DOS" ch.
; 8, $B1C9), deleted entries ($FF) are skipped, and the first never-used entry
; ($00) ends the catalog. For details, see section 5.9 of DESIGN.
;

        .export         __readdir_a2lib
        .import         return0

        .macpack        longbranch

        .include        "zeropage.inc"
        .include        "errno.inc"
        .include        "fm.inc"
        .include        "dir.inc"

; Shared storage
catentry        = ptr2          ; byte*: the catalog entry, in the DIR's BUF
name_base       = ptr3          ; byte*: d_name - ENT_NAME, so one Y
                                ; indexes both names
sectors_low     = tmp1          ; unsigned: the entry's length in
sectors_high    = tmp2          ; sectors, then in blocks

        .code

;-----------------------------------------------------------------------------
; Read the next file's entry.
;
; Signature:    struct dirent* __fastcall__ _readdir_a2lib (DIR* dir)
; Overrides:    readdir(), as a2lib's dirent.h defines it
; Prepare:      opendir()
; Input:        AX            DIR*      dir: the directory
; Output:       AX            struct dirent*
;                                       the entry, inside dir and valid until
;                                       the next call; NULL at the end, with
;                                       errno unchanged, or after an error
;               errno         int       if NULL after an error: as rwts_maperr
;                                       maps
; Changes:      Y; dirptr, catentry, name_base, sectors_low, sectors_high and
;               iob (ptr3). A catalog sector may be read.

__readdir_a2lib:
        sta     dirptr
        stx     dirptr+1

next:   ldy     #DIR::DONE
        lda     (dirptr),y
        jne     return0         ; End of the catalog: NULL, errno unchanged

        ; Read the next catalog sector when this one is used up
        ldy     #DIR::INDEX
        lda     (dirptr),y
        cmp     #CAT_PERSECTOR
        bcc     entry
        ldy     #DIR::NEXTT
        lda     (dirptr),y
        jeq     end             ; End of the chain
        pha
        ldy     #DIR::NEXTS
        lda     (dirptr),y
        tax
        pla
        jsr     read_dir_sector
        bcc     :+
        jsr     rwts_maperr
        jsr     ___mappederrno
        jmp     return0
:       ldy     #DIR::BUF + CAT_NEXT
        lda     (dirptr),y
        ldy     #DIR::NEXTT
        sta     (dirptr),y
        ldy     #DIR::BUF + CAT_NEXT + 1
        lda     (dirptr),y
        ldy     #DIR::NEXTS
        sta     (dirptr),y
        lda     #$00
        ldy     #DIR::INDEX
        sta     (dirptr),y

        ; catentry = the entry: BUF + CAT_ENTRIES + INDEX * CAT_ENTRYLEN
entry:  tax
        clc
        adc     #$01
        sta     (dirptr),y      ; Y = DIR::INDEX: advance
        clc
        lda     dirptr
        adc     #<(DIR::BUF + CAT_ENTRIES)
        sta     catentry
        lda     dirptr+1
        adc     #>(DIR::BUF + CAT_ENTRIES)
        sta     catentry+1
        clc
        lda     catentry
        adc     entryofs,x
        sta     catentry
        bcc     :+
        inc     catentry+1

:       ldy     #ENT_TRACK
        lda     (catentry),y
        jeq     end             ; Never used: end of the catalog
        cmp     #$FF
        jeq     next            ; Deleted

        ; d_name: 30 characters, bit 7 cleared, trailing blanks removed.
        ; name_base = &d_name - ENT_NAME, so that one Y indexes both names.
        clc
        lda     dirptr
        adc     #<(DIR::ENT + DIRENT::NAME - ENT_NAME)
        sta     name_base
        lda     dirptr+1
        adc     #>(DIR::ENT + DIRENT::NAME - ENT_NAME)
        sta     name_base+1
        ldy     #ENT_NAME
:       lda     (catentry),y
        and     #HIBIT_OFF
        sta     (name_base),y
        iny
        cpy     #ENT_NAME + NAME_LEN
        bne     :-
        lda     #$00
        sta     (name_base),y
:       dey
        lda     (name_base),y
        cmp     #' '
        bne     :+
        lda     #$00
        sta     (name_base),y
        cpy     #ENT_NAME
        bne     :-

        ; d_ino: T/S list track * 256 + sector
:       ldy     #ENT_SECTOR
        lda     (catentry),y
        ldy     #DIR::ENT + DIRENT::INO
        sta     (dirptr),y
        ldy     #ENT_TRACK
        lda     (catentry),y
        ldy     #DIR::ENT + DIRENT::INO + 1
        sta     (dirptr),y

        ; d_access (the lock bit) and d_type (the catalog's type, as is)
        ldy     #ENT_TYPE
        lda     (catentry),y
        pha
        and     #FMT_LOCKED
        ldy     #DIR::ENT + DIRENT::ACCESS
        sta     (dirptr),y
        pla
        and     #FMT_TYPE_MASK
        ldy     #DIR::ENT + DIRENT::TYPE
        sta     (dirptr),y

        ; d_sectors; d_blocks = (d_sectors + 1) / 2
        ldy     #ENT_LENGTH
        lda     (catentry),y
        sta     sectors_low
        iny
        lda     (catentry),y
        sta     sectors_high
        ldy     #DIR::ENT + DIRENT::SECTORS
        lda     sectors_low
        sta     (dirptr),y
        iny
        lda     sectors_high
        sta     (dirptr),y
        lda     sectors_low
        clc
        adc     #$01
        sta     sectors_low
        lda     sectors_high
        adc     #$00
        ror                     ; 17-bit sum (carry in) / 2
        sta     sectors_high
        ror     sectors_low
        ldy     #DIR::ENT + DIRENT::BLOCKS
        lda     sectors_low
        sta     (dirptr),y
        iny
        lda     sectors_high
        sta     (dirptr),y

        ; Return &dir->ent
        clc
        lda     dirptr
        adc     #<DIR::ENT
        tay
        lda     dirptr+1
        adc     #>DIR::ENT
        tax
        tya
        rts

end:    lda     #$01
        ldy     #DIR::DONE
        sta     (dirptr),y
        jmp     return0

        .rodata

entryofs:                       ; byte[7]: each entry's offset in a sector
        .repeat CAT_PERSECTOR, i
        .byte   i * CAT_ENTRYLEN
        .endrepeat
