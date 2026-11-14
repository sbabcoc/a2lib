/*
** a2reflow.h: word-wrapping stdio console output (a2lib)
**
** reflow_on makes stdio console output (printf, puts, putchar and the like)
** break lines between words; conio output is not affected. It can be
** turned on and off as a program runs, for example for documents but not
** menus, and is linked only into programs that use it. See DESIGN.md
** sections 3.2 and 3.7.
**
** Copyright (c) 2026 Scott Babcock. zlib license; see LICENSE.
*/

#ifndef _A2REFLOW_H
#define _A2REFLOW_H

/* Wrap for a screen width columns wide (2-81), or, with 0, the visible
** width: 40 on the stock screen and in the 40-column window, 80 on the
** VideoTerm. A line holds at most width - 1 characters. Characters appear
** at once; a word that would overflow is moved to the next line, and a
** word longer than a line is broken. The filter counts columns from the
** cursor's position now, so call reflow_on again after moving the cursor
** with conio. */
void __fastcall__ reflow_on (unsigned char width);

/* Stop wrapping. */
void reflow_off (void);

#endif
