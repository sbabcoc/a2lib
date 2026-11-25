/*
** soft70.h: the Soft-70 display (a2lib)
**
** With lib/a2lib-soft70.o and lib/a2lib-soft70.lib, a program sees an
** 80 x 24 screen. On a VideoTerm it is shown whole; without one, Soft-70
** shows 70 of its 80 columns as text drawn on hi-res page 1, with upper
** and lowercase. By default the view follows the cursor, panning between
** columns 0-69 and 10-79, when a character is written or the cursor is
** about to be shown.
** On the VideoTerm these functions do nothing (s70_left and s70_active
** return 0), so programs need no conditionals.
**
** Link with --start-addr 0x4000, so that the program sits above the
** hi-res page:
**   cl65 -t apple2 --start-addr 0x4000 -I include -o prog prog.c \
**        lib/a2lib-soft70.o lib/a2lib-soft70.lib lib/a2lib-dos33.lib
**
** Soft-70 is drawn for monochrome monitors; on a colour monitor its text
** shows colour fringes, as hi-res text did on a real II+. While it runs, a
** marker before its 80 x 24 buffer lets emulators copy the screen's text
** (see section 3.9 of DESIGN). For details, see section 3.8 of DESIGN.
**
** Copyright (c) 2026 Scott Babcock. zlib license; see LICENSE.
*/

#ifndef _SOFT70_H
#define _SOFT70_H

/* Show columns left to left + 69 (left is limited to 0-10), and stop
** following the cursor. */
void __fastcall__ s70_pan (unsigned char left);

/* Follow the cursor again, panning to it now if needed. */
void s70_follow (void);

/* The leftmost visible column. */
unsigned char s70_left (void);

/* Nonzero if Soft-70 is in use (no VideoTerm). */
unsigned char s70_active (void);

/* Replace the font with a 768-byte character set in the period format
** used by Soft Seventy, Flex Type (".70" sets) and the DOS Tool Kit: 96
** characters ($20-$7F) of 8 bytes, one per scanline, top first, bit 0 the
** leftmost pixel. A 70-column glyph uses bits 0-3; with nibble nonzero,
** bits 4-7 are used instead, for files holding two sets. The screen is
** redrawn with it. The set is copied, so its memory can be reused; the
** space ($20) is always blank, since blank cells are not drawn. */
void __fastcall__ s70_font (const void* set, unsigned char nibble);

#endif
