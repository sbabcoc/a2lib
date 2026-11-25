;
; Scott Babcock, 2026-11-20
;
; closedir() for DOS 3.3 disks. For details, see section 5.9 of DESIGN.
;

        .export         __closedir_a2lib
        .import         _free, return0

;-----------------------------------------------------------------------------
; Close a directory: it holds no open file, so its DIR is freed.
;
; Signature:    int __fastcall__ _closedir_a2lib (DIR* dir)
; Overrides:    closedir(), as a2lib's dirent.h defines it
; Prepare:      opendir()
; Input:        X:A           DIR*      directory object pointer
; Output:       X:A           int       0
; Changes:      Y and what free changes. dir is freed.

__closedir_a2lib:
        jsr     _free
        jmp     return0
