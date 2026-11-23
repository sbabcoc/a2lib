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

;-----------------------------------------------------------------------------
; __rewinddir_a2lib: Start a directory again from its first entry: void
; __fastcall__ _rewinddir_a2lib (DIR* dir), which dirent.h names rewinddir().
; Falls into rewind_dir.
;
; Input:        AX            DIR*      dir: from opendir()
; Output:       none
; Changes:      A, Y and dirptr. X is unchanged.

__rewinddir_a2lib:
        sta     dirptr
        stx     dirptr+1        ; Falls into rewind_dir

;-----------------------------------------------------------------------------
; rewind_dir: Start the directory again at its first catalog sector, which the
; next readdir reads. Used by opendir too.
;
; Input:        dirptr        DIR*      the directory, FIRSTT and FIRSTS set
; Output:       none
; Changes:      A and Y. X is unchanged.

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
