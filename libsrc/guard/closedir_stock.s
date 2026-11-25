;
; Scott Babcock, 2026-11-20
;
; A link-time guard for the name cc65's dirent.h gives closedir(). a2lib's
; dirent.h maps it to _closedir_a2lib(), for a2lib's own struct dirent, and
; a2lib's directory modules take the place of cc65's. A program compiled with
; cc65's dirent.h, without a2lib's include directory, would reach cc65's
; ProDOS version, which cl65 links after a2lib's library. It fails to link
; instead, naming the symbol below. For details, see sections 2 and 4.2 of
; DESIGN.
;

        .export         _closedir
        .import         closedir_needs_a2lib_dirent_h

_closedir       := closedir_needs_a2lib_dirent_h
