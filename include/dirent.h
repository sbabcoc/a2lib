/*
** dirent.h for DOS 3.3 (a2lib)
**
** Shadows cc65's <dirent.h> when a2lib's include directory is passed with
** -I. Use it together with lib/apple2-dos33.lib:
**
**   cl65 -t apple2 -I a2lib/include -o prog prog.c a2lib/lib/apple2-dos33.lib
**
** The directory functions keep their names in C, but map to DOS 3.3
** symbols that exist only in apple2-dos33.lib. Compiling with this header
** and linking without the library fails to link, rather than mixing this
** struct dirent with cc65's ProDOS implementation (DESIGN.md section 2).
**
** opendir() takes a location instead of a path: "" or "." for the
** last-used slot and drive, optionally followed by suffixes as at the DOS
** prompt (",D2", ".,S6,D2", ",V254"). DOS 3.3 has no subdirectories.
**
** Copyright (c) 2026 Scott Babcock. zlib license; see LICENSE.
*/

#ifndef _DIRENT_H
#define _DIRENT_H

#if !defined(__APPLE2__)
#error "a2lib's dirent.h is for the cc65 apple2 target"
#endif

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
                                ** the unit of POSIX and ProDOS */
    unsigned char   d_type;     /* ProDOS-equivalent type: T $04, B $06,
                                ** A $FC, I $FA, R $FE; others $00 */
    unsigned char   d_access;   /* $01 (read only) if locked, else $C3 */
    unsigned        d_sectors;  /* Length in sectors, as CATALOG shows */
    unsigned char   d_dostype;  /* DOS type, catalog coding without the
                                ** lock bit: T $00, I $01, A $02, B $04,
                                ** S $08, R $10, A $20, B $40 */
};

#define _DE_ISREG(t)  (1)
#define _DE_ISDIR(t)  (0)
#define _DE_ISLBL(t)  (0)
#define _DE_ISLNK(t)  (0)

DIR* __fastcall__ _dos33_opendir (const char* name);
struct dirent* __fastcall__ _dos33_readdir (DIR* dir);
int __fastcall__ _dos33_closedir (DIR* dir);
void __fastcall__ _dos33_rewinddir (DIR* dir);

#define opendir     _dos33_opendir
#define readdir     _dos33_readdir
#define closedir    _dos33_closedir
#define rewinddir   _dos33_rewinddir

#endif
