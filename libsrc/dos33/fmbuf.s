;
; Scott Babcock, 2026-11-12
;
; Control blocks (FCB, fm.inc) are DOS's own file buffers ("Beneath Apple
; DOS" ch. 6, DOS BUFFERS; DESIGN.md 4.4): MAXFILES of them, between
; HIMEM and DOS, chained from DOS_BUFS. A buffer is in use while the first
; byte of its name field is nonzero, as DOS's own commands mark it.
;
; fm_getfcb:  reserve a free one into ptr4, with the library's fields
;             cleared. Returns carry clear, or carry set with A =
;             DOSERR_NOBUFS (DOS's NO BUFFERS AVAILABLE, ENOMEM) if every
;             buffer is in use.
; fm_freefcb: release the one in ptr4. Preserves A.
; fm_isopen:  whether the file named in the parameter list (by fm_name) is
;             open, before DELETE and RENAME (DESIGN.md
;             5.5a). OPENs it in the control block in ptr4 without
;             allocating it, CLOSEs it, and compares the work area's first
;             T/S list, slot and drive with each open file's. Returns carry
;             clear if it isn't open, or carry set with A = an __oserror value:
;             LIBERR_OPEN if it is open (EINVAL), or the OPEN's error.
;             Set up the parameter list again before the next call
;             (fm_begin, fm_name). Uses ptr2.
;

        .include        "zeropage.inc"
        .include        "fm.inc"
        .include        "filedes.inc"

; File Manager work area ("Beneath Apple DOS", ch. 6): the bytes that
; identify a file. The first T/S list's track and sector are unique on a
; disk; slot and drive say which disk.
WA_TSL          = $00           ; Track, sector of the first T/S list
WA_SLOT         = $26           ; Slot * 16
WA_DRIVE        = $27           ; Drive

        .assert FCB::BUFS = FCB::INUSE + 30, error  ; The name field's length

        .code

fm_getfcb:
        lda     DOS_BUFS
        ldx     DOS_BUFS+1
@buf:   sta     ptr4            ; A buffer's name field
        stx     ptr4+1
        ora     ptr4+1
        beq     @none           ; End of the chain
        ldy     #$00
        lda     (ptr4),y
        beq     @free
        ldy     #FCB::NEXT - FCB::INUSE + 1
        lda     (ptr4),y        ; The next one's
        tax
        dey
        lda     (ptr4),y
        jmp     @buf

@free:  lda     #FCB_INUSE
        sta     (ptr4),y
        sec                     ; Address the work area
        lda     ptr4
        sbc     #FCB::INUSE
        sta     ptr4
        bcs     :+
        dec     ptr4+1
:       lda     #$00            ; Clear the library's fields
        ldy     #FCB::ADDR + 1
@clear: sta     (ptr4),y
        dey
        cpy     #FCB::INUSE
        bne     @clear
        clc
        rts

@none:  lda     #DOSERR_NOBUFS
        sec
        rts

fm_freefcb:
        pha
        lda     #$00
        ldy     #FCB::INUSE
        sta     (ptr4),y
        pla
        rts

fm_isopen:
        ldx     #$01            ; Don't allocate
        jsr     fm_open
        bcc     :+
        jsr     fm_maperr
        sec
        rts
:       lda     #FMC_CLOSE
        jsr     fm_simple

        ; Compare with each open file: REF_NUM $40-$7F (open.s)
        ldx     #$00
file:   lda     fdtab + FD::REF_NUM,x
        and     #$C0
        cmp     #$40
        bne     next
        lda     fdtab + FD::BUFFER,x
        sta     ptr2
        lda     fdtab + FD::BUFFER+1,x
        sta     ptr2+1
        ldy     #FCB::WORK + WA_TSL
        jsr     same
        bne     next
        iny                     ; WA_TSL + 1: sector
        jsr     same
        bne     next
        ldy     #FCB::WORK + WA_SLOT
        jsr     same
        bne     next
        iny                     ; WA_DRIVE
        jsr     same
        bne     next
        lda     #LIBERR_OPEN    ; -> EINVAL
        sec
        rts
next:   inx
        inx
        inx
        inx
        cpx     #MAX_FDS * .sizeof(FD)
        bcc     file
        clc
        rts

; same: Z set if byte Y of the open file's control block (ptr2) equals the
; same byte of this one (ptr4).

same:   lda     (ptr2),y
        cmp     (ptr4),y
        rts

        .assert WA_DRIVE = WA_SLOT + 1, error
