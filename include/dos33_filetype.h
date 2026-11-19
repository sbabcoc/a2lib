/*
** DOS 3.3 file types for a2lib (DESIGN.md 5.4)
**
** The type byte of a catalog entry, as CATALOG lists it ("Beneath Apple
** DOS" ch. 4). These are the values of _filetype (for new files), of
** st_type (stat) and of d_type (readdir). DOS 3.3's own codes, not
** ProDOS's: note that PRODOS_T_TXT ($04) is DOS33_T_BIN here.
**
** Copyright (c) 2026 Scott Babcock. zlib license; see LICENSE.
*/

#ifndef _DOS33_FILETYPE_H
#define _DOS33_FILETYPE_H

#define DOS33_T_TXT     0x00    /* T: text */
#define DOS33_T_INT     0x01    /* I: Integer BASIC program */
#define DOS33_T_BAS     0x02    /* A: Applesoft BASIC program */
#define DOS33_T_BIN     0x04    /* B: binary (load address and length) */
#define DOS33_T_S       0x08    /* S: special */
#define DOS33_T_REL     0x10    /* R: relocatable object */
#define DOS33_T_NEWA    0x20    /* "new" A: listed, can't be created */
#define DOS33_T_NEWB    0x40    /* "new" B: listed, can't be created */

/* st_access and d_access: DOS 3.3's only access attribute */
#define DOS33_LOCKED    0x80

#endif
