;
; Scott Babcock, 2026-11-19
;
; chdir() for DOS 3.3. The current directory is DOS's last-used slot and
; drive: chdir() sets them, so they stay set after the program exits, as
; ProDOS's prefix does. A directory is "/6/2", "2" or ".", each optionally
; ending in "/". "/" and "/6" aren't directories, and fail with EINVAL like
; any other path. As with DOS's own ",D2", the drive isn't read until a file
; on it is. For details, see section 5.5 of DESIGN.
;

        .export         __syschdir
        .import         initcwd

        .include        "fm.inc"

        .code

;-----------------------------------------------------------------------------
; Change the current directory, for chdir().
;
; Signature:    unsigned char __fastcall__ _syschdir (const char* name)
; Overrides:    cc65's _syschdir()
; Input:        X:A           char*     "/S/D", "D" or ".", each optionally
;                                       ending in "/"
; Output:       A             byte      0, or DOSERR_SYNTAX (EINVAL) for any
;                                       other path
; Changes:      Y and ptr1 (fm_location). On success: DOS_SLOT and DOS_DRIVE,
;               which outlast the program, and __cwd (initcwd).
; Note:         X isn't set: the only caller, cc65's chdir(),
;               ends in ___mappederrno, which sets it.

__syschdir:
        jsr     fm_location     ; From AX
        bcs     done            ; A = DOSERR_SYNTAX

        lda     fm_slot
        sta     DOS_SLOT
        lda     fm_drive
        sta     DOS_DRIVE
        lda     #$00
        sta     DOS_SLOT+1
        sta     DOS_DRIVE+1
        jsr     initcwd         ; __cwd = "/S/D"
        lda     #$00
done:   rts
