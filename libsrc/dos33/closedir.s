;
; Scott Babcock, 2026-11-20
;
; int __fastcall__ _closedir_a2lib (DIR* dir);
;
; DOS 3.3 directories (DESIGN.md 5.9; opendir.s). The DIR holds no open
; file, so closing it frees it; returns 0.
;

        .export         __closedir_a2lib
        .import         _free, return0

__closedir_a2lib:
        jsr     _free
        jmp     return0
