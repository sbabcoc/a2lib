/*
** dirent.h for DOS 3.3 (a2lib)
**
** Shadows cc65's <dirent.h> when a2lib's include directory is passed with
** -I. Use it together with lib/a2lib-dos33.lib:
**
**   cl65 -t apple2 -I a2lib/include -o prog prog.c a2lib/lib/a2lib-dos33.lib
**
** The directory functions keep their names in C, but map to symbols that
** exist only in a2lib-dos33.lib (_opendir_a2lib and the like), whose
** directory modules take the place of cc65's. This struct dirent isn't
** cc65's, so neither can be used with the other's: this header without
** the library, or the library with cc65's header, fails to link (DESIGN.md
** section 2).
**
** opendir() takes a directory path: "/6/2" (slot 6, drive 2), "2" (drive
** 2 in the current slot), "." or "" (the current directory). DOS 3.3 has
** no subdirectories. See DESIGN.md 5.5.
**
** Copyright (c) 2026 Scott Babcock. zlib license; see LICENSE.
*/

#ifndef _DIRENT_H
#define _DIRENT_H

#if !defined(__APPLE2__)
#error "a2lib's dirent.h is for the cc65 apple2 target"
#endif

#include "dos33_filetype.h"     /* d_type and d_access values */

typedef struct DIR DIR;

/* Fields DOS 3.3 can't supply from the catalog (byte size, dates, aux
** type) are left out, so code that relies on them fails to compile
** instead of reading zeros. Use stat() for a file's exact size and load
** address. See DESIGN.md section 5.9.
*/
struct dirent {
    char            d_name[31]; /* Up to 30 characters; trailing blanks
                                ** removed, bit 7 cleared */
    unsigned        d_ino;      /* T/S list location: track * 256 + sector */
    unsigned        d_blocks;   /* 512-byte blocks, (d_sectors + 1) / 2,
                                ** the unit of POSIX */
    unsigned char   d_type;     /* DOS 3.3's type, as the catalog codes
                                ** it (DOS33_T_*, dos33_filetype.h) */
    unsigned char   d_access;   /* DOS33_LOCKED if locked, else 0 */
    unsigned        d_sectors;  /* Length in sectors, as CATALOG shows */
};

#define _DE_ISREG(t)  (1)
#define _DE_ISDIR(t)  (0)
#define _DE_ISLBL(t)  (0)
#define _DE_ISLNK(t)  (0)

DIR* __fastcall__ _opendir_a2lib (const char* name);
struct dirent* __fastcall__ _readdir_a2lib (DIR* dir);
int __fastcall__ _closedir_a2lib (DIR* dir);
void __fastcall__ _rewinddir_a2lib (DIR* dir);

#define opendir     _opendir_a2lib
#define readdir     _readdir_a2lib
#define closedir    _closedir_a2lib
#define rewinddir   _rewinddir_a2lib

#endif
