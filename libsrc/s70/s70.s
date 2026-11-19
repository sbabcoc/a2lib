;
; Soft-70 display for the shared 80 x 24 model (DESIGN.md 3.8)
;
; Shows columns s80_left to s80_left + 69 of the model (libsrc/s80) on
; hi-res page 1, in cells 4 pixels wide and 8 scanlines tall: 280 / 4 = 70
; columns. Glyphs come from a 768-byte font in the period format (96
; characters x 8 scanlines, bit 0 leftmost, bits 0-3 used), copied at
; startup from the default font (font.s) and replaceable with s70_font.
; Every byte written has bit 7 clear.
;
; Drawing: cell c starts at pixel 4c, in byte 4c / 7 at bit 4c mod 7, so a
; cell at bit 0-3 lies in one byte and a cell at bit 4-6 spans two. For
; each bit offset, lotab and hitab give a glyph row's bits in the first
; and second byte, so a scanline costs two lookups and a masked store per
; byte, with no shifting.
;
; Scrolling copies 8 scanlines per text row with an unrolled loop, and
; only the bytes that can hold text: sext[r] is one more than the
; rightmost byte written on screen row r since it was last cleared.
;
; Position gauge (DESIGN.md 6.3): a bar on the bottom scanline, dotted
; across the full width with a solid thumb over the 70 visible columns,
; drawn and removed with EOR, so it needs nothing restored. Drawing on row
; 23 while it is shown keeps the bar in the cells drawn.
;
; Cursor (cgetc.s, rdkey.s): the cell at the cursor drawn in inverse,
; blinking with a periodic timer when a slot is free.
;
; Programs using Soft-70 are linked with --start-addr 0x4000, so that the
; hi-res page ($2000-$3FFF) isn't part of the program; the buffer and the
; font are in LOWBSS, below the hi-res page (DESIGN.md 3.8).
;
; Uses BASL and BAS2L ($28-$2B) as pointers, set on every use, and no
; other zero page, except s70_font, a C function, which uses ptr1 and
; ptr2. Self-modifying: the drawing loops' operands are set per cell.
;

        .export         _s70_font
        .macpack        longbranch
        .export         s70_curshow, s70_curhide
        .import         HOME, uppercasemask, popax
        .import         s70_deffont, _a2_timer_stop
        .import         __MAIN_START__, __LOW_LAST__

        .include        "apple2.inc"
        .include        "zeropage.inc"
        .include        "s80.inc"
        .include        "display.inc"
        .include        "vt.inc"
        .include        "timer.inc"

        .assert __MAIN_START__ >= $4000, lderror, "Soft-70: link with --start-addr 0x4000 (DESIGN.md 3.8)"
        .assert __LOW_LAST__ <= $2000, lderror, "Soft-70: LOWBSS overlaps the hi-res page"

HGR             = $2000         ; Hi-res page 1
SCANLINE        = $0400         ; From one scanline of a text row to the next
ROW23           = HGR + $03D0   ; Row 23, scanline 0
BARLINE         = ROW23 + 7 * SCANLINE ; Row 23, scanline 7
BLINK_TICKS     = MS_TICKS(250)

        .segment        "ONCE"

disp_init:
        ldx     #$00
:       lda     s70_deffont,x
        sta     font,x
        lda     s70_deffont+$100,x
        sta     font+$100,x
        lda     s70_deffont+$200,x
        sta     font+$200,x
        inx
        bne     :-
        lda     #$FF            ; The font has lowercase
        sta     uppercasemask
        jsr     hclear          ; Clear before showing
        bit     HIRES
        bit     LOWSCR
        bit     MIXCLR
        bit     TXTCLR
        rts

        .code

disp_done:
        bit     TXTSET
        jmp     HOME

; ------------------------------------------------------------------------
; disp_cell: show screen code A at screen column X, row Y.

disp_cell:
        sty     crow
        tay
        lda     #$00
        cpy     #$80
        bcs     :+
        lda     #$0F            ; Inverse: complement the cell
:       sta     inv1+1
        sta     inv2+1

        ; Glyph: (code & $7F) - $20, controls ($00-$1F) as their letters
        tya
        and     #$7F
        cmp     #$20
        bcs     :+
        adc     #$40
:       sec
        sbc     #$20
        tay
        and     #$1F            ; Offset in its page: (glyph & 31) * 8
        asl
        asl
        asl
        sta     fidx
        tya                     ; Page: glyph / 32
        lsr
        lsr
        lsr
        lsr
        lsr
        clc
        adc     #>font
        sta     fnt1+2
        sta     fnt2+2

        ; Row and column
        ldy     crow
        lda     rowlo,y
        sta     BAS2L
        lda     rowhi,y
        sta     BAS2L+1
        lda     bytetab,x
        sta     b1+1
        sta     b2+1
        sta     cbyte
        tay
        lda     shtab,x
        tax
        stx     csh
        lda     m1tab,x
        eor     #$7F
        sta     k1+1
        sta     k2a+1
        lda     lotabl,x
        sta     lt1+1
        sta     lt2+1
        lda     lotabh,x
        sta     lt1+2
        sta     lt2+2

        ; Extent of the row
        iny                     ; Byte + 1
        cpx     #4
        bcc     :+
        iny                     ; Byte + 2
:       tya
        ldy     crow
        cmp     sext,y
        bcc     :+
        sta     sext,y
:       lda     fidx            ; End of the glyph's 8 bytes
        clc
        adc     #8
        sta     end1+1
        sta     end2+1
        cpx     #4
        bcs     two

        ; One byte per scanline
        ldx     fidx
one:
fnt1:   lda     font,x
inv1:   eor     #$00
        tay
lt1:    lda     lotab,y
        sta     o1+1
b1:     ldy     #$00
        lda     (BAS2L),y
k1:     and     #$00
o1:     ora     #$00
        sta     (BAS2L),y
        lda     BAS2L+1
        clc
        adc     #>SCANLINE
        sta     BAS2L+1
        inx
end1:   cpx     #$00
        bne     one
        beq     bar             ; Branch always

        ; Two bytes per scanline
two:    lda     m2tab,x
        eor     #$7F
        sta     k2b+1
        lda     hitabl-4,x
        sta     lh2+1
        lda     hitabh-4,x
        sta     lh2+2
        ldx     fidx
twol:
fnt2:   lda     font,x
inv2:   eor     #$00
        tay
lt2:    lda     lotab,y
        sta     o2+1
lh2:    lda     hitab,y
        sta     o3+1
b2:     ldy     #$00
        lda     (BAS2L),y
k2a:    and     #$00
o2:     ora     #$00
        sta     (BAS2L),y
        iny
        lda     (BAS2L),y
k2b:    and     #$00
o3:     ora     #$00
        sta     (BAS2L),y
        lda     BAS2L+1
        clc
        adc     #>SCANLINE
        sta     BAS2L+1
        inx
end2:   cpx     #$00
        bne     twol

        ; On row 23 with the gauge shown, put the bar back in the cell
bar:    bit     baron
        bpl     :+
        lda     crow
        cmp     #S80_ROWS-1
        bne     :+
        ldx     csh
        ldy     cbyte
        lda     barpat,y
        and     m1tab,x
        eor     BARLINE,y
        sta     BARLINE,y
        lda     m2tab,x
        beq     :+
        iny
        and     barpat,y
        eor     BARLINE,y
        sta     BARLINE,y
:       rts

; ------------------------------------------------------------------------
; disp_redraw: clear the page and draw the window's nonblank cells.

disp_redraw:
        jsr     hclear
        lda     #$00
        sta     rrow
row:    lda     rrow
        jsr     s80_setbuf      ; BAS2L = buffer row
        clc
        lda     BAS2L
        adc     s80_left
        sta     BASL
        lda     BAS2L+1
        adc     #$00
        sta     BASL+1
        lda     #$00
        sta     rcol
@col:   ldy     rcol
        lda     (BASL),y
        beq     @next           ; Blank
        eor     #S80_BUF_XOR
        ldx     rcol
        ldy     rrow
        jsr     disp_cell       ; Leaves BASL alone
@next:  inc     rcol
        lda     rcol
        cmp     #S80_VIEW
        bne     @col
        inc     rrow
        lda     rrow
        cmp     #S80_ROWS
        bne     row
        rts

; disp_clear / hclear: clear the page; the gauge goes with it.

disp_clear:
hclear: lda     #$00
        tay
:       .repeat $20, i
        sta     HGR + i * $100,y
        .endrepeat
        iny
        bne     :-
        ldx     #S80_ROWS-1
:       sta     sext,x
        dex
        bpl     :-
        sta     baron
        rts

; ------------------------------------------------------------------------
; disp_scroll: move screen rows 1-23 up and clear row 23. Each row copies
; the bytes that can hold text in it or in the row moving into it.

disp_scroll:
        bit     baron           ; Take the bar off row 23 first
        bpl     :+
        jsr     barxor
:       ldx     #$00
srow:   lda     sext,x
        cmp     sext+1,x
        bcs     :+
        lda     sext+1,x
:       tay
        jeq     snext           ; Both blank
        stx     savex

        ; Point the loads at row X + 1 and the stores at row X
        lda     rowlo+1,x
        .repeat 8, k
        sta     .ident(.sprintf("src%d", k))+1
        .endrepeat
        lda     rowlo,x
        .repeat 8, k
        sta     .ident(.sprintf("dst%d", k))+1
        .endrepeat
        lda     rowhi+1,x
        .repeat 8, k
        sta     .ident(.sprintf("src%d", k))+2
        .if k < 7
        clc
        adc     #>SCANLINE
        .endif
        .endrepeat
        lda     rowhi,x
        .repeat 8, k
        sta     .ident(.sprintf("dst%d", k))+2
        .if k < 7
        clc
        adc     #>SCANLINE
        .endif
        .endrepeat

        dey
copy:   .repeat 8, k
.ident(.sprintf("src%d", k)):
        lda     HGR,y
.ident(.sprintf("dst%d", k)):
        sta     HGR,y
        .endrepeat
        dey
        bpl     copy
        ldx     savex
snext:  lda     sext+1,x
        sta     sext,x
        inx
        cpx     #S80_ROWS-1
        jne     srow

        ; Clear row 23
        ldy     sext+S80_ROWS-1
        beq     @bar
        dey
        lda     #$00
@clear: .repeat 8, k
        sta     ROW23 + k * SCANLINE,y
        .endrepeat
        dey
        bpl     @clear
        sta     sext+S80_ROWS-1
@bar:   bit     baron
        bpl     :+
        jsr     barxor
:       rts

; ------------------------------------------------------------------------
; Position gauge

; disp_gauge_draw: the thumb covers 35 of the 40 bytes (70 of 80 columns),
; from byte s80_left / 2.

disp_gauge_draw:
        bit     baron           ; Remove the bar shown, if any
        bpl     :+
        jsr     barxor
:       lda     s80_left
        lsr
        sta     tstart
        clc
        adc     #35
        sta     tend
        ldy     #39
gbyte:  cpy     tstart
        bcc     @track
        cpy     tend
        bcs     @track
        lda     #$7F            ; Thumb
        bne     @store          ; Branch always
@track: tya                     ; Track: alternate pixels
        and     #$01
        tax
        lda     track,x
@store: sta     barpat,y
        dey
        bpl     gbyte
        jsr     barxor
        lda     #$80
        sta     baron
        rts

disp_gauge_erase:
        bit     baron
        bpl     :+
        jsr     barxor
        lda     #$00
        sta     baron
:       rts

barxor: ldy     #39
:       lda     BARLINE,y
        eor     barpat,y
        sta     BARLINE,y
        dey
        bpl     :-
        rts

; ------------------------------------------------------------------------
; Cursor

; s70_curshow: show the cursor, panning to it if following; carry set if
; it isn't visible. s70_curhide: remove it.

s70_curshow:
        jsr     s80_show
        jsr     s80_cursorcol
        bcs     :+
        sta     ccol
        lda     s80_y
        sta     ccrow
        lda     #<BLINK_TICKS
        sta     tmr_ticks
        lda     #>BLINK_TICKS
        sta     tmr_ticks+1
        lda     #<blink
        sta     tmr_fn
        lda     #>blink
        sta     tmr_fn+1
        lda     #$01            ; Periodic
        sta     tmr_per
        jsr     a2_timer_arm    ; $FF if no slot: a steady cursor
        sta     cslot
        lda     #$80
        sta     cshown
        jsr     curdraw
        clc
:       rts

s70_curhide:
        bit     cshown
        bpl     :+
        lda     cslot
        jsr     _a2_timer_stop  ; Ignores $FF
        lda     #$00
        sta     cshown
        jsr     curdraw
:       rts

blink:  lda     cshown
        eor     #$40
        sta     cshown
        ; Fall through

; curdraw: draw the cursor's cell from the buffer, inverted while cshown
; is $80 (shown, in its inverse phase).

curdraw:
        lda     ccrow
        jsr     s80_setbuf
        lda     ccol
        clc
        adc     s80_left
        tay
        lda     (BAS2L),y
        eor     #S80_BUF_XOR    ; Screen code
        ldx     cshown
        cpx     #$80
        bne     :+
        eor     #$80            ; Inverted
:       ldx     ccol
        ldy     ccrow
        jmp     disp_cell

; ------------------------------------------------------------------------
; void __fastcall__ s70_font (const void* set, unsigned char nibble);

_s70_font:
        sta     nibble          ; Nonzero: the high nibble
        jsr     popax
        sta     ptr1
        stx     ptr1+1
        lda     #<font
        sta     ptr2
        lda     #>font
        sta     ptr2+1
        lda     #3              ; 768 bytes
        sta     pages
        ldy     #$00
@byte:  lda     (ptr1),y
        ldx     nibble
        beq     @low
        lsr
        lsr
        lsr
        lsr
@low:   and     #$0F
        sta     (ptr2),y
        iny
        bne     @byte
        inc     ptr1+1
        inc     ptr2+1
        dec     pages
        bne     @byte
        lda     #$00            ; Blank cells are skipped, not drawn
        ldy     #7
:       sta     font,y
        dey
        bpl     :-
        bit     vt_active
        bmi     :+
        jmp     disp_redraw
:       rts

        .rodata

; Hi-res page 1, scanline 0 of text row r: $2000 + (r & 7) * $80 +
; (r >> 3) * $28; scanline k is $400 * k further
rowlo:  .repeat S80_ROWS, r
        .byte   <(HGR + (r .mod 8) * $80 + (r / 8) * $28)
        .endrepeat
rowhi:  .repeat S80_ROWS, r
        .byte   >(HGR + (r .mod 8) * $80 + (r / 8) * $28)
        .endrepeat

; Cell c: byte 4c / 7, bit 4c mod 7
bytetab:.repeat S80_VIEW, c
        .byte   (c * 4) / 7
        .endrepeat
shtab:  .repeat S80_VIEW, c
        .byte   (c * 4) .mod 7
        .endrepeat

; The cell's bits in its first and second byte, for each bit offset
m1tab:  .repeat 7, s
        .byte   ($0F << s) & $7F
        .endrepeat
m2tab:  .repeat 7, s
        .byte   $0F >> (7 - s)
        .endrepeat

; Glyph row g at bit offset s: lotab + 16 * s for the first byte, hitab +
; 16 * (s - 4) for the second
lotab:  .repeat 7, s
        .repeat 16, g
        .byte   (g << s) & $7F
        .endrepeat
        .endrepeat
hitab:  .repeat 3, s
        .repeat 16, g
        .byte   g >> (3 - s)
        .endrepeat
        .endrepeat
lotabl: .repeat 7, s
        .byte   <(lotab + 16 * s)
        .endrepeat
lotabh: .repeat 7, s
        .byte   >(lotab + 16 * s)
        .endrepeat
hitabl: .repeat 3, s
        .byte   <(hitab + 16 * s)
        .endrepeat
hitabh: .repeat 3, s
        .byte   >(hitab + 16 * s)
        .endrepeat

track:  .byte   $55, $2A        ; Even pixels lit, in even and odd bytes

        .data

baron:          .byte   $00     ; Bit 7: the gauge's bar is on the screen
cshown:         .byte   $00     ; $80 cursor inverted, $C0 normal phase
cslot:          .byte   $FF

        .bss

crow:           .res    1
cbyte:          .res    1
csh:            .res    1
fidx:           .res    1
rrow:           .res    1
rcol:           .res    1
savex:          .res    1
tstart:         .res    1
tend:           .res    1
pages:          .res    1
nibble:         .res    1
ccol:           .res    1
ccrow:          .res    1

        .segment        "LOWBSS"

font:           .res    96 * 8
sext:           .res    S80_ROWS
barpat:         .res    40
