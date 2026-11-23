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
        sta     dirptr
        stx     dirptr+1
        ; Fall through

; rewind_dir: start the DIR at dirptr again at the first catalog sector
; (read on the next readdir). Used by opendir too.

rewind_dir:
        ldy     #DIR::FIRSTT
        lda     (dirptr),y
        ldy     #DIR::NEXTT
        sta     (dirptr),y
        ldy     #DIR::FIRSTS
        lda     (dirptr),y
        ldy     #DIR::NEXTS
        sta     (dirptr),y
        lda     #CAT_PERSECTOR
        ldy     #DIR::INDEX
        sta     (dirptr),y
        lda     #$00
        ldy     #DIR::DONE
        sta     (dirptr),y
        rts
