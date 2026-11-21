;
; Scott Babcock, 2026-11-20
;
; void __fastcall__ _rewinddir_a2lib (DIR* dir);
;
; DOS 3.3 directories (DESIGN.md 5.9; opendir.s).
;

        .export         __rewinddir_a2lib

        .include        "zeropage.inc"
        .include        "fm.inc"
        .include        "dir.inc"

        .code

__rewinddir_a2lib:
        sta     ptr1
        stx     ptr1+1
        ; Fall through

; rewinddir_ptr1: start the DIR at ptr1 again at the first catalog sector
; (read on the next readdir). Used by opendir too.

rewinddir_ptr1:
        ldy     #DIR::FIRSTT
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
