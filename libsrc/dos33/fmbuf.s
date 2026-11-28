;
; Scott Babcock, 2026-11-12
;
; Control blocks for open files. Each is one of DOS's own file buffers
; ("Beneath Apple DOS" ch. 6): MAXFILES of them, between HIMEM and DOS,
; chained from DOS_BUFS. A buffer is in use while the first byte of its name
; field is nonzero, as DOS's own commands mark it. Also tells whether a file
; is already open, which DELETE and RENAME need, as DOS doesn't check. For
; details, see section 4.4 of DESIGN.
;

        .include        "zeropage.inc"
        .include        "fm.inc"
        .include        "filedes.inc"

; Shared storage
open_ctlblock   = ptr2          ; FCB*: an open file's (fm_isopen)

; File Manager work area ("Beneath Apple DOS", ch. 6): the bytes that
; identify a file. The first T/S list's track and sector are unique on a
; disk; slot and drive say which disk.
WA_TSL          = $00           ; Track, sector of the first T/S list
WA_SLOT         = $26           ; Slot * 16
WA_DRIVE        = $27           ; Drive

        .assert FCB::BUFS = FCB::INUSE + 30, error  ; The name field's length
        .assert WA_DRIVE = WA_SLOT + 1, error

        .code

;-----------------------------------------------------------------------------
; Reserve a free DOS file buffer as a control block.
;
; Output:       C             flag      clear: reserved; set: every buffer is
;                                       in use
;               A             byte      if C set: DOSERR_NOBUFS, the __oserror
;                                       value of DOS's NO BUFFERS AVAILABLE
;                                       (ENOMEM)
;               ctlblock      FCB*      if C clear: the control block,
;                                       addressed at its work area, with the
;                                       library's fields 0
; Changes:      X and Y. The buffer is marked in use in DOS's chain
;               (FCB::INUSE). If C is set, ctlblock is 0.

fm_getfcb:
        lda     DOS_BUFS
        ldx     DOS_BUFS+1
@buf:   sta     ctlblock        ; A buffer's name field
        stx     ctlblock+1
        ora     ctlblock+1
        beq     @none           ; End of the chain
        ldy     #$00
        lda     (ctlblock),y
        beq     @free
        ldy     #FCB::NEXT - FCB::INUSE + 1
        lda     (ctlblock),y    ; The next one's
        tax
        dey
        lda     (ctlblock),y
        jmp     @buf

@free:  lda     #FCB_INUSE
        sta     (ctlblock),y
        sec                     ; Address the work area
        lda     ctlblock
        sbc     #FCB::INUSE
        sta     ctlblock
        bcs     :+
        dec     ctlblock+1
:       lda     #$00            ; Clear the library's fields
        ldy     #FCB::ADDR + 1
@clear: sta     (ctlblock),y
        dey
        cpy     #FCB::INUSE
        bne     @clear
        clc
        rts

@none:  lda     #DOSERR_NOBUFS
        sec
        rts

;-----------------------------------------------------------------------------
; Release a control block's DOS file buffer.
;
; Prepare:      fm_getfcb
; Input:        ctlblock      FCB*      the control block
; Output:       A             byte      unchanged
; Changes:      Y; N and Z set from A. X and C are unchanged. The buffer is
;               free in DOS's chain (FCB::INUSE = 0).

fm_freefcb:
        pha
        lda     #$00
        ldy     #FCB::INUSE
        sta     (ctlblock),y
        pla
        rts

;-----------------------------------------------------------------------------
; Is the file that the parameter list names already open? Asked before DELETE
; and RENAME. OPENs the file without creating it, CLOSEs it,
; and compares its work area's first T/S list, slot and drive with each open
; file's.
;
; Prepare:      fm_begin, fm_name
; Input:        fm_parmlist   byte*     the parameter list, with the name
;                                       fields set
;               ctlblock      FCB*      a control block to OPEN the file in
; Output:       C             flag      clear: not open; set: open, or the
;                                       OPEN failed
;               A             byte      if C set: LIBERR_OPEN (EINVAL) if
;                                       open, else the OPEN's __oserror value
; Changes:      X, Y and open_ctlblock. The parameter list: set it up again
;               (fm_begin, fm_name) before the next call.

fm_isopen:
        ldx     #FMX_NOALLOC
        jsr     fm_open
        bcc     :+
        jsr     fm_maperr
        sec
        rts
:       lda     #FMC_CLOSE
        jsr     fm_simple

        ; Compare with each open file: REF_NUM $40-$7F
        ldx     #$00
file:   lda     fdtab + FD::REF_NUM,x
        and     #$C0
        cmp     #$40
        bne     next
        lda     fdtab + FD::BUFFER,x
        sta     open_ctlblock
        lda     fdtab + FD::BUFFER+1,x
        sta     open_ctlblock+1
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
        .assert .sizeof(FD) = 4, error
next:   inx
        inx
        inx
        inx
        cpx     #MAX_FDS * .sizeof(FD)
        bcc     file
        clc
        rts

;-----------------------------------------------------------------------------
; Compare one byte of two control blocks.
;
; Input:        Y             byte      the byte's offset in each
;               open_ctlblock FCB*      an open file's control block
;               ctlblock      FCB*      this one
; Output:       Z             flag      set: the bytes are equal
; Changes:      A; N and C set by the comparison. X and Y are unchanged.

same:   lda     (open_ctlblock),y
        cmp     (ctlblock),y
        rts
