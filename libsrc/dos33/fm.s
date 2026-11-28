;
; Scott Babcock, 2026-11-12
;
; Calls into DOS 3.3's File Manager ("Beneath Apple DOS" ch. 6 and 8):
; locating the parameter list, OPEN, POSITION, byte and range READ and WRITE,
; and mapping its return codes to __oserror values. Each open file's buffers
; are a control block (FCB). For details, see section 4.4 of DESIGN.
;

        .include        "zeropage.inc"
        .include        "filedes.inc"
        .include        "fm.inc"

; Shared storage
call_type       = tmp1          ; byte: FMC_READ or FMC_WRITE (fm_rangeio)

        .code

;-----------------------------------------------------------------------------
; Find the control block of an fdtab slot.
;
; Prepare:      open()
; Input:        Y             byte      the fdtab slot's offset (fd *
;                                       .sizeof(FD))
; Output:       ctlblock      FCB*      the slot's control block; 0 for the
;                                       console
;               A             byte      ctlblock's high byte
;               Z             flag      set: the slot has no control block
;                                       (the console)
; Changes:      N set from A. X and Y are unchanged.

fm_fdfcb:
        lda     fdtab + FD::BUFFER,y
        sta     ctlblock
        lda     fdtab + FD::BUFFER+1,y
        sta     ctlblock+1
        rts

;-----------------------------------------------------------------------------
; Find the control block of an fdtab slot and begin File Manager calls on it:
; fm_fdfcb, then fm_begin (falls into it).
;
; Prepare:      open()
; Input:        Y             byte      the fdtab slot's offset, of an open
;                                       file
; Output:       ctlblock      FCB*      the slot's control block
;               fm_parmlist   byte*     as fm_begin sets it
; Changes:      A, X and Y.

fm_fdbegin:
        jsr     fm_fdfcb        ; Falls into fm_begin

;-----------------------------------------------------------------------------
; Begin a series of File Manager calls: locate the parameter list and point
; its buffer fields at the control block's work area and the T/S list and data
; buffers below it. Needed before each series, because DOS owns the parameter
; list between calls.
;
; Prepare:      fm_getfcb or fm_fdfcb
; Input:        ctlblock      FCB*      the control block
; Output:       fm_parmlist   byte*     the parameter list, with
;                                       FMPARMS::WORK, FMPARMS::TSL and
;                                       FMPARMS::DATA set
; Changes:      A, X and Y.

fm_begin:
        jsr     FM_LOCATE       ; A:Y
        sty     fm_parmlist
        sta     fm_parmlist+1

        .assert FMPARMS::TSL = FMPARMS::WORK + 2, error
        .assert FMPARMS::DATA = FMPARMS::TSL + 2, error
        .assert FCB_TSL = $100 && FCB_DATA = $200, error
        ldx     ctlblock+1
        ldy     #FMPARMS::WORK
:       lda     ctlblock        ; Each buffer a page below the last
        sta     (fm_parmlist),y
        iny
        txa
        sta     (fm_parmlist),y
        iny
        dex
        cpy     #FMPARMS::DATA + 2
        bne     :-
        rts

;-----------------------------------------------------------------------------
; Make a File Manager call that takes no parameters but the call type (CLOSE,
; or DELETE once fm_name has set the name fields). Falls into fm_op.
;
; Prepare:      fm_begin
; Input:        A             byte      the call type (FMC_*)
;               fm_parmlist   byte*     the parameter list
; Output:       C             flag      as fm_call
;               A             byte      as fm_call
; Changes:      X (FMX_NOALLOC) and Y.

fm_simple:
        ldx     #FMX_NOALLOC    ; Falls into fm_op

;-----------------------------------------------------------------------------
; Make a File Manager call of the given type, its other parameters already
; set.
;
; Prepare:      fm_begin
; Input:        A             byte      the call type (FMC_*)
;               X             byte      as fm_call
;               fm_parmlist   byte*     the parameter list
; Output:       C             flag      as fm_call
;               A             byte      as fm_call
; Changes:      Y.

fm_op:  ldy     #FMPARMS::CALL
        sta     (fm_parmlist),y
        jmp     fm_call         ; fm_call is in another segment

;-----------------------------------------------------------------------------
; OPEN the file that the name fields name, with variable-length records.
;
; Prepare:      fm_begin, fm_name
; Input:        A             byte      the type for a new file (FMT_*);
;                                       ignored for one that exists
;               X             byte      0: create the file if it isn't found;
;                                       else don't (fm_call)
;               fm_parmlist   byte*     the parameter list
; Output:       C             flag      as fm_call
;               A             byte      as fm_call
;               fm_parmlist   byte*     if C clear: FMPARMS::TYPE is the
;                                       file's type, with its lock bit
; Changes:      Y.

fm_open:
        ldy     #FMPARMS::TYPE
        sta     (fm_parmlist),y
        lda     #$00
        ldy     #FMPARMS::RECLEN
        sta     (fm_parmlist),y
        iny
        sta     (fm_parmlist),y
        lda     #FMC_OPEN
        bne     fm_op           ; Branch always

        .segment        "LOWCODE"

;-----------------------------------------------------------------------------
; Call the File Manager. cc65 leaves Language Card bank 2 enabled for reading,
; so ROM is switched in around the call, as cc65's RDKEY does around the
; monitor's.
;
; Prepare:      fm_begin
; Input:        X             byte      FMX_ALLOC or FMX_NOALLOC, for OPEN;
;                                       FMX_NOALLOC for every other call
;               fm_parmlist   byte*     the parameter list, with the call's
;                                       fields set
; Output:       C             flag      clear: the call succeeded; set: it
;                                       failed
;               A             byte      the File Manager's return code: 0, or
;                                       a DOS 3.3 error number (DOSERR_*)
; Changes:      X and Y; DOS's own state and zero page. Language Card bank 2
;               is enabled for reading on return.

fm_call:
        bit     LC_ROM_RO
        jsr     FM_ENTRY
        bit     LC_BANK2_RO
        ldy     #FMPARMS::RC
        lda     (fm_parmlist),y
        cmp     #$01            ; C = (return code <> 0)
        rts

        .code

;-----------------------------------------------------------------------------
; POSITION an open file to a byte offset from its start (record 0).
;
; Prepare:      fm_begin
; Input:        X:A           unsigned  the byte offset
;               fm_parmlist   byte*     the parameter list
; Output:       C             flag      as fm_call
;               A             byte      as fm_call
; Changes:      X and Y.

fm_position:
        ldy     #FMPARMS::OFFSET
        sta     (fm_parmlist),y
        iny
        txa
        sta     (fm_parmlist),y
        lda     #$00
        ldy     #FMPARMS::RECORD
        sta     (fm_parmlist),y
        iny
        sta     (fm_parmlist),y
        lda     #FMC_POSITION
        bne     fm_simple       ; Branch always

;-----------------------------------------------------------------------------
; READ one byte from an open file.
;
; Prepare:      fm_begin
; Input:        fm_parmlist   byte*     the parameter list
; Output:       C             flag      clear: read; set: failed
;                                       (DOSERR_ENDDATA at the file's end)
;               A             byte      if C clear: the byte; if C set: the
;                                       return code (DOSERR_*)
; Changes:      X and Y.

fm_readbyte:
        ldy     #FMPARMS::CALL
        lda     #FMC_READ
        sta     (fm_parmlist),y
        iny
        lda     #FMS_ONE
        sta     (fm_parmlist),y
        ldx     #FMX_NOALLOC
        jsr     fm_call
        bcs     :+
        ldy     #FMPARMS::BYTE
        lda     (fm_parmlist),y
        clc
:       rts

;-----------------------------------------------------------------------------
; WRITE one byte to an open file.
;
; Prepare:      fm_begin
; Input:        A             byte      the byte
;               fm_parmlist   byte*     the parameter list
; Output:       C             flag      as fm_call
;               A             byte      as fm_call
; Changes:      X and Y.

fm_writebyte:
        ldy     #FMPARMS::BYTE
        sta     (fm_parmlist),y
        ldy     #FMPARMS::CALL
        lda     #FMC_WRITE
        sta     (fm_parmlist),y
        iny
        lda     #FMS_ONE
        sta     (fm_parmlist),y
        ldx     #FMX_NOALLOC
        jmp     fm_call

;-----------------------------------------------------------------------------
; READ or WRITE a range of bytes of an open file. A WRITE passes the File
; Manager the count less FM_WRITE_ADJUST, as "Beneath Apple DOS" ch. 6 says a
; range WRITE takes.
;
; Prepare:      fm_begin
; Input:        A             byte      FMC_READ or FMC_WRITE
;               fm_rio_addr   byte*     the buffer
;               fm_rio_count  unsigned  the number of bytes; not 0
;               fm_parmlist   byte*     the parameter list
; Output:       C             flag      as fm_call
;               A             byte      as fm_call
; Changes:      X, Y and call_type.

fm_rangeio:
        sta     call_type
        ldy     #FMPARMS::CALL
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
:       ldy     #FMPARMS::RANGE
        sta     (fm_parmlist),y
        iny
        txa
        sta     (fm_parmlist),y

        ; Range address
        ldy     #FMPARMS::ADDR
        lda     fm_rio_addr
        sta     (fm_parmlist),y
        iny
        lda     fm_rio_addr+1
        sta     (fm_parmlist),y

        ldx     #FMX_NOALLOC
        jmp     fm_call

;-----------------------------------------------------------------------------
; Add 1 to the control block's logical position.
;
; Prepare:      fm_begin
; Input:        ctlblock      FCB*      the control block
; Output:       ctlblock      FCB*      FCB::POS one higher, modulo 65536
; Changes:      A and Y; C set if POS wrapped to 0. X is unchanged.

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

;-----------------------------------------------------------------------------
; Translate a File Manager return code into an __oserror value. The File
; Manager's codes are DOS 3.3's own error numbers, so they pass
; through; anything else is an I/O error.
;
; Input:        A             byte      the return code, not 0
; Output:       A             byte      the __oserror value (DOSERR_*)
; Changes:      C, N and Z. X and Y are unchanged.

fm_maperr:
        cmp     #DOSERR_LOCKED + 1
        bcc     :+
        lda     #DOSERR_IO      ; Unknown: treat as I/O error
:       rts

        .bss

fm_rio_addr:    .res    2       ; byte*: fm_rangeio's buffer
fm_rio_count:   .res    2       ; unsigned: fm_rangeio's byte count
