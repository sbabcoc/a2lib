;
; Scott Babcock, 2026-11-20
;
; struct dirent* __fastcall__ readdir (DIR* dir);
;
; Link-time guard (DESIGN.md 2, 4.2): defines the name cc65's <dirent.h>
; gives the function. a2lib's include/dirent.h maps it to _readdir_a2lib,
; for its own struct dirent, and the DOS 3.3 directory modules take the
; place of cc65's in a2lib-dos33.lib. A program compiled with cc65's header
; (without -I include) would reach cc65's ProDOS module in apple2.lib,
; which cl65 links after a2lib-dos33.lib. It fails to link instead, naming
; the symbol below.
;

        .export         _readdir
        .import         readdir_needs_a2lib_dirent_h

_readdir        := readdir_needs_a2lib_dirent_h
