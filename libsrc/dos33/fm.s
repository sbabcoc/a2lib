;
; Scott Babcock, 2026-11-12
;
; DOS 3.3 File Manager glue for the cc65 apple2 target
;
; On entry to the routines below, ctlblock points to the open file's
; control block (FCB). fm_begin sets fm_parmlist to the File Manager
; parameter list.
;

        .include        "zeropage.inc"
        .include        "filedes.inc"
        .include        "fm.inc"

; Shared storage
call_type       = tmp1          ; byte: FMC_READ or FMC_WRITE (fm_rangeio)

        .code

; ------------------------------------------------------------------------
; fm_fdfcb: ctlblock = the control block of fdtab slot Y. Preserves X and Y;
; returns Z set if the slot has none (the console).
; fm_fdbegin: the same, then fm_begin (falls into it).

fm_fdfcb:
        lda     fdtab + FD::BUFFER,y
        sta     ctlblock
        lda     fdtab + FD::BUFFER+1,y
        sta     ctlblock+1
        rts

fm_fdbegin:
        jsr     fm_fdfcb        ; Falls into fm_begin

; fm_begin: locate the parameter list (fm_parmlist) and point its buffer
; fields at the control block in ctlblock: its work area, and the T/S list and data
; buffers below it. Must precede every series of File Manager calls,
; because DOS owns the parameter list between calls.

fm_begin:
        jsr     FM_LOCATE       ; Y = low, A = high
        sty     fm_parmlist
        sta     fm_parmlist+1

        .assert FM_TSL = FM_WORK + 2, error
        .assert FM_DATA = FM_TSL + 2, error
        .assert FCB_TSL = $100 && FCB_DATA = $200, error
        ldx     ctlblock+1
        ldy     #FM_WORK
:       lda     ctlblock        ; Each buffer a page below the last
        sta     (fm_parmlist),y
        iny
        txa
        sta     (fm_parmlist),y
        iny
        dex
        cpy     #FM_DATA + 2
        bne     :-
        rts

; ------------------------------------------------------------------------
; fm_simple: call type in A, no other parameters (CLOSE; or DELETE after
; fm_name has set the name fields).
; fm_op: the same, with X as for fm_call.

fm_simple:
        ldx     #$01
fm_op:  ldy     #FM_CALL
        sta     (fm_parmlist),y
        jmp     fm_call         ; fm_call is in another segment

; ------------------------------------------------------------------------
; fm_open: OPEN the file the name fields name (fm_name), with variable-
; length records; A is the type for a new file. X as for fm_call.

fm_open:
        ldy     #FM_TYPE
        sta     (fm_parmlist),y
        lda     #$00
        ldy     #FM_RECORD
        sta     (fm_parmlist),y
        iny
        sta     (fm_parmlist),y
        lda     #FMC_OPEN
        bne     fm_op           ; Branch always

; ------------------------------------------------------------------------
; fm_call: call the File Manager. X = 0 allocates the file on OPEN if it
; isn't found; X <> 0 doesn't. Returns the File Manager's return code in A,
; with carry set if it is nonzero.
;
; cc65 leaves Language Card bank 2 enabled for reading. Switch ROM in
; around the call, as rdkey.s does around the monitor's RDKEY.

        .segment        "LOWCODE"

fm_call:
        bit     LC_ROM_RO
        jsr     FM_ENTRY
        bit     LC_BANK2_RO
        ldy     #FM_RC
        lda     (fm_parmlist),y
        cmp     #$01            ; C = (return code <> 0)
        rts

        .code

; ------------------------------------------------------------------------
; fm_position: POSITION to the absolute byte offset in AX (record 0).
; Returns as fm_call.

fm_position:
        ldy     #FM_OFFSET
        sta     (fm_parmlist),y
        iny
        txa
        sta     (fm_parmlist),y
        lda     #$00
        ldy     #FM_RECORD
        sta     (fm_parmlist),y
        iny
        sta     (fm_parmlist),y
        lda     #FMC_POSITION
        bne     fm_simple       ; Branch always

; ------------------------------------------------------------------------
; fm_readbyte: read one byte. Returns carry clear with the byte in A, or
; carry set with the return code in A.

fm_readbyte:
        ldy     #FM_CALL
        lda     #FMC_READ
        sta     (fm_parmlist),y
        iny
        lda     #FMS_ONE
        sta     (fm_parmlist),y
        ldx     #$01
        jsr     fm_call
        bcs     :+
        ldy     #FM_BYTE
        lda     (fm_parmlist),y
        clc
:       rts

; ------------------------------------------------------------------------
; fm_writebyte: write the byte in A. Returns as fm_call.

fm_writebyte:
        ldy     #FM_BYTE
        sta     (fm_parmlist),y
        ldy     #FM_CALL
        lda     #FMC_WRITE
        sta     (fm_parmlist),y
        iny
        lda     #FMS_ONE
        sta     (fm_parmlist),y
        ldx     #$01
        jmp     fm_call

; ------------------------------------------------------------------------
; fm_rangeio: READ or WRITE (call type in A) fm_rio_count bytes at
; fm_rio_addr. The count must not be zero. Returns as fm_call.
; Uses call_type.

fm_rangeio:
        sta     call_type
        ldy     #FM_CALL
        sta     (fm_parmlist),y
        iny
        lda     #FMS_RANGE
        sta     (fm_parmlist),y

        ; Range length; a WRITE takes the count minus FM_WRITE_ADJUST
        lda     fm_rio_count
        ldx     fm_rio_count+1
        ldy     call_type
        cpy     #FMC_WRITE
        bne     :+
        sec
        sbc     #FM_WRITE_ADJUST
        bcs     :+
        dex
:       ldy     #FM_RANGE
        sta     (fm_parmlist),y
        iny
        txa
        sta     (fm_parmlist),y

        ; Range address
        ldy     #FM_ADDR
        lda     fm_rio_addr
        sta     (fm_parmlist),y
        iny
        lda     fm_rio_addr+1
        sta     (fm_parmlist),y

        ldx     #$01
        jmp     fm_call

; ------------------------------------------------------------------------
; fm_incpos: increment the control block's logical position.

fm_incpos:
        ldy     #FCB::POS
        lda     (ctlblock),y
        clc
        adc     #$01
        sta     (ctlblock),y
        iny
        lda     (ctlblock),y
        adc     #$00
        sta     (ctlblock),y
        rts

; ------------------------------------------------------------------------
; fm_maperr: translate a File Manager return code (A) into the
; __oserror value. The File Manager's codes are DOS 3.3's own error
; numbers (fm.inc), so they pass through; anything else is an I/O error.

fm_maperr:
        cmp     #DOSERR_LOCKED + 1
        bcc     :+
        lda     #DOSERR_IO      ; Unknown: treat as I/O error
:       rts

        .bss

fm_rio_addr:    .res    2
fm_rio_count:   .res    2
