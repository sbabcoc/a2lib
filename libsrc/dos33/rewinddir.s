;
; Scott Babcock, 2026-11-20
;
; rewinddir() for DOS 3.3 disks. For details, see section 5.9 of DESIGN.
;

        .export         __rewinddir_a2lib

        .include        "zeropage.inc"
        .include        "fm.inc"
        .include        "dir.inc"

        .code

;-----------------------------------------------------------------------------
; Start a directory again from its first entry. Falls into rewind_dir.
;
; Signature:    void __fastcall__ _rewinddir_a2lib (DIR* dir)
; Overrides:    rewinddir(), as a2lib's dirent.h defines it
; Prepare:      opendir()
; Input:        AX            DIR*      dir: the directory
; Changes:      A, Y and dirptr. X is unchanged.

__rewinddir_a2lib:
        sta     dirptr
        stx     dirptr+1        ; Falls into rewind_dir

;-----------------------------------------------------------------------------
; Start the directory again at its first catalog sector, which the next
; readdir reads. Used by opendir too.
;
; Prepare:      dir_at
; Input:        dirptr        DIR*      the directory, FIRSTT and FIRSTS set
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
