;
; Scott Babcock, 2026-11-20
;
; struct dirent* __fastcall__ _readdir_a2lib (DIR* dir);
;
; DOS 3.3 directories (DESIGN.md 5.9; opendir.s). As in DOS's own search
; ("Beneath Apple DOS" ch. 8, B1C9), deleted entries ($FF) are skipped and
; the first never-used entry ($00) ends the catalog.
;

        .export         __readdir_a2lib
        .import         return0

        .macpack        longbranch

        .include        "zeropage.inc"
        .include        "errno.inc"
        .include        "fm.inc"
        .include        "dir.inc"

        .code

__readdir_a2lib:
        sta     ptr1
        stx     ptr1+1

next:   ldy     #DIR::DONE
        lda     (ptr1),y
        jne     return0         ; End of the catalog: NULL, errno unchanged

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
        jsr     read_dir_sector_ptr1
        bcc     :+
        jsr     rwts_maperr
        jsr     ___mappederrno
        jmp     return0
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

        ; d_name: 30 characters, bit 7 cleared, trailing blanks removed.
        ; ptr3 = &d_name - ENT_NAME, so that one Y indexes both names.
        clc
        lda     ptr1
        adc     #<(DIR::ENT + DIRENT::NAME - ENT_NAME)
        sta     ptr3
        lda     ptr1+1
        adc     #>(DIR::ENT + DIRENT::NAME - ENT_NAME)
        sta     ptr3+1
        ldy     #ENT_NAME
:       lda     (ptr2),y
        and     #HIBIT_OFF
        sta     (ptr3),y
        iny
        cpy     #ENT_NAME + NAME_LEN
        bne     :-
        lda     #$00
        sta     (ptr3),y
:       dey
        lda     (ptr3),y
        cmp     #' '
        bne     :+
        lda     #$00
        sta     (ptr3),y
        cpy     #ENT_NAME
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

        ; d_access (the lock bit) and d_type (the catalog's type, as is)
        ldy     #ENT_TYPE
        lda     (ptr2),y
        pha
        and     #FMT_LOCKED
        ldy     #DIR::ENT + DIRENT::ACCESS
        sta     (ptr1),y
        pla
        and     #FMT_TYPE_MASK
        ldy     #DIR::ENT + DIRENT::TYPE
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
        jmp     return0

        .rodata

entryofs:
        .repeat CAT_PERSECTOR, i
        .byte   i * CAT_ENTRYLEN
        .endrepeat
