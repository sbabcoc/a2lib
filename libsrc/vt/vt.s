;
; Scott Babcock, 2026-11-12
;
; Videx VideoTerm backend for the cc65 apple2 target (DESIGN.md 3.4)
;
; vt_active:  bit 7 set if the card was found and is in use. The conio
;             modules of a2lib-vt.lib test it and either drive the
;             card or run the stock 40-column code.
; vt_write:   write the character in A through the firmware's Pascal 1.1
;             WRITE entry. Preserves A, X and Y, so it also serves as the
;             COUT hook (CSW).
; vt_goto:    move the cursor to column X, row A (firmware GOTOXY, $1E).
; vt_r10:     set CRTC R10 (cursor start and mode) to A.
; vt_screen:  convert an Apple screen code in A to the character the card
;             shows for it (bit 7 clear; controls as @, A-Z, [ \ ] ^ _).
;
; The output hook, for this backend and the 80 x 24 model's (s80.s): only
; one is in use, so they share these and the hooks they save.
; a2_savehooks:  keep CSW and DOS's saved true output hook, to restore at
;                exit (ONCE).
; a2_hookout:    install the routine in AX as the output hook (ONCE).
;                Under DOS 3.3 with DOS's video intercept in CSW, it
;                becomes DOS's true output routine instead: on every
;                character through its intercepts (stdio input included),
;                DOS copies the true handlers into CSW and KSW and
;                reinstalls its intercepts on the way out ("Beneath Apple
;                DOS" ch. 8, $9ED1 and $A851), which drops a routine
;                stored in CSW directly (DESIGN.md 3.5, 3.6).
; a2_unhookout:  restore the hooks a2_savehooks kept: DOS's saved true
;                hook if a2_hookout installed the routine there;
;                otherwise CSW, and DOS's saved hook too if its reconnect
;                routine ($A851) moved the routine into it.
;
; vtinit (constructor) detects the card, initializes it, hides the cursor
; (conio shows it only while waiting for a key), allows lowercase, and
; hooks COUT. vtdone (destructor) restores the output hooks and the display
; mode at exit.
;
; Everything the constructor sets is in DATA: crt0 clears BSS after the
; constructors run (DESIGN.md 6.1).
;
; Every module of the display libraries imports vt_active, so this module
; is linked whenever one of them is. It requires the display library's
; selector (DESIGN.md 2), which defines a2lib_display_needs_selector_object:
; without the selector, the link fails naming that symbol, instead of the
; program's printf silently writing to the stock 40-column screen.
;

        .constructor    vtinit
        .destructor     vtdone
        .import         uppercasemask
        .forceimport    a2lib_display_needs_selector_object

        .macpack        longbranch

        .include        "vt.inc"

        .segment        "ONCE"

vtinit:
        ; The VideoTerm's Pascal 1.1 signature in slot 3
        bit     CLRROM
        lda     VT_ID0
        cmp     #$38
        jne     none
        lda     VT_ID1
        cmp     #$18
        jne     none
        lda     VT_ID2
        cmp     #$01
        jne     none
        lda     VT_ID3
        cmp     #$82
        jne     none

        ; Was output already going to the card (PR#3 before the program)?
        ; Either CSW points into its slot ROM, or DOS's intercept is in CSW
        ; and DOS's saved true hook does.
        lda     CSWL+1
        cmp     #>VT_ID0
        beq     was80
        lda     DOS_CSW+1
        cmp     #>VT_ID0
        bne     :+
was80:  lda     #$80
        sta     prior80

        ; Keep the hooks to restore at exit
:       jsr     a2_savehooks

        ; Full INIT: clear the power-on marker, which about one power-on in
        ; 32 leaves set, making INIT skip the CRTC setup (DESIGN.md 3.4)
        lda     #$00
        sta     VT_POFF
        bit     CLRROM
        ldx     #>VT_ID0        ; Pascal 1.1: X = $Cn, Y = $n0
        ldy     #$30
        jsr     VT_INIT

        ; Hide the cursor, as on the stock 40-column screen
        lda     #R10_HIDDEN
        jsr     vt_r10

        ; The card displays lowercase
        lda     #$FF
        sta     uppercasemask

        ; COUT to the card
        lda     #<vt_write
        ldx     #>vt_write
        jsr     a2_hookout

        lda     #$80
        sta     vt_active
none:   bit     CLRROM          ; Release the card's $C800 space
        rts

a2_savehooks:
        lda     CSWL
        sta     savecsw
        lda     CSWL+1
        sta     savecsw+1
        lda     DOS_CSW
        sta     savedos
        lda     DOS_CSW+1
        sta     savedos+1
        rts

a2_hookout:
        sta     hooked
        stx     hooked+1
        ldy     CSWL
        cpy     DOS_VINT
        bne     direct
        ldy     CSWL+1
        cpy     DOS_VINT+1
        bne     direct
        sta     DOS_CSW
        stx     DOS_CSW+1
        lda     #$80
        sta     viados
        rts
direct: sta     CSWL
        stx     CSWL+1
        rts

        .code

a2_unhookout:
        bit     viados
        bpl     :+
        lda     savedos
        sta     DOS_CSW
        lda     savedos+1
        sta     DOS_CSW+1
        rts
:       lda     savecsw
        sta     CSWL
        lda     savecsw+1
        sta     CSWL+1
        lda     DOS_CSW
        cmp     hooked
        bne     :+
        lda     DOS_CSW+1
        cmp     hooked+1
        bne     :+
        lda     savedos
        sta     DOS_CSW
        lda     savedos+1
        sta     DOS_CSW+1
:       rts

vtdone:
        bit     vt_active
        bpl     done
        jsr     a2_unhookout

        ; Back to 40 columns, unless output went to the card before
mode:   bit     prior80
        bmi     :+
        sta     VT_AN0OFF
        rts
:       lda     #R10_BLINK      ; Cursor back on for BASIC
        jmp     vt_r10
done:   rts

vt_r10: ldx     #10
        stx     VT_CRTCREG
        sta     VT_CRTCDATA
        rts

vt_goto:
        pha
        txa
        pha
        lda     #$1E            ; GOTOXY: column + 32, then row + 32
        jsr     vt_write
        pla
        clc
        adc     #32
        jsr     vt_write
        pla
        clc
        adc     #32
        jmp     vt_write

vt_screen:
        eor     #$80
        and     #$7F
        cmp     #$20
        bcs     :+
        ora     #$40
:       rts

        .segment        "LOWCODE"

; Called with ROM switched in (as the COUT hook) or LC RAM enabled (from
; conio); the firmware uses neither.

vt_write:
        pha
        txa
        pha
        tya
        pha
        tsx
        lda     $0103,x         ; The character
        bit     CLRROM          ; Other cards' $C800 ROMs off
        ldx     #>VT_ID0        ; Pascal 1.1: X = $Cn, Y = $n0
        ldy     #$30
        jsr     VT_WRITE
        pla
        tay
        pla
        tax
        pla
        rts

        .data

vt_active:      .byte   $00
prior80:        .byte   $00
viados:         .byte   $00     ; Bit 7: installed as DOS's true output routine
savecsw:        .word   $0000
savedos:        .word   $0000
hooked:         .word   $0000   ; The routine a2_hookout installed
