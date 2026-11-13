/*
** c40win.h: panning the 40-column window (a2lib)
**
** With lib/apple2-dos33-vtwin.lib, a program sees an 80 x 24 screen. On a
** VideoTerm it is shown whole; without one, a 40-column window onto it is
** shown on the text screen. By default the window follows the cursor, in
** steps of 20 columns, when a character is written or the cursor is about
** to be shown. These functions control it; on the VideoTerm they do
** nothing (c40_left and c40_active return 0), so programs need no
** conditionals. See DESIGN.md section 3.6.
**
** Copyright (c) 2026 Scott Babcock. zlib license; see LICENSE.
*/

#ifndef _C40WIN_H
#define _C40WIN_H

/* Show columns left to left + 39 (left is limited to 0-40), and stop
** following the cursor. */
void __fastcall__ c40_pan (unsigned char left);

/* Follow the cursor again, panning to it now if needed. */
void c40_follow (void);

/* The leftmost visible column. */
unsigned char c40_left (void);

/* Nonzero if the 40-column window is in use (no VideoTerm). */
unsigned char c40_active (void);

#endif
