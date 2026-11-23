;
; Scott Babcock, 2026-11-19
;
; unsigned char __fastcall__ _syschdir (const char* name);
;
; Replaces libsrc/apple2/syschdir.s from cc65. chdir() passes the result to
; ___mappederrno, so it returns 0 or an __oserror value (DESIGN.md 5.6).
;
; The current directory is DOS's last-used slot and drive (DESIGN.md 5.5):
; chdir() sets them, so they stay set after the program exits, as
; ProDOS's prefix does. name is a directory as for opendir(): "/6/2",
; "2", "." (each optionally ending in "/"). "/" and "/6" aren't
; directories, and fail with EINVAL like any other path. As with DOS's
; own ",D2", the drive isn't read until a file on it is.
;

        .export         __syschdir
        .import         initcwd

        .include        "fm.inc"

        .code

;-----------------------------------------------------------------------------
; __syschdir: Change the current directory, for chdir(): unsigned char
; __fastcall__ _syschdir (const char* name).
;
; Input:        AX            char*     name: "/S/D", "D" or ".", each
;                                       optionally ending in "/"
; Output:       A             byte      0, or DOSERR_SYNTAX (EINVAL) for any
;                                       other path
;               X             byte      unchanged (name's high byte), not 0:
;                                       cc65's chdir reads only A
; Changes:      Y and ptr1 (fm_location). On success: DOS_SLOT and DOS_DRIVE,
;               which outlast the program, and __cwd (initcwd).

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
