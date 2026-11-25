;
; Scott Babcock, 2026-11-20
;
; closedir() for DOS 3.3 disks. For details, see section 5.9 of DESIGN.
;

        .export         __closedir_a2lib
        .import         _free, return0

;-----------------------------------------------------------------------------
; Close a directory by freeing its directory object. Reading a DOS 3.3
; directory leaves no file open, so there is nothing else to close.
;
; Signature:    int __fastcall__ _closedir_a2lib (DIR* dir)
; Overrides:    closedir(), as a2lib's dirent.h defines it
; Prepare:      opendir()
; Input:        X:A           DIR*      directory object pointer
; Output:       X:A           int       0
; Changes:      Y and what free changes.

__closedir_a2lib:
        jsr     _free
        jmp     return0
