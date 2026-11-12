;
; DOS 3.3 File Manager glue for the cc65 apple2 target
;
; On entry to the routines below, ptr4 points to the open file's control
; block (FCB). fm_begin sets ptr3 to the File Manager parameter list.
;

        .include        "zeropage.inc"
        .include        "fm.inc"

        .code

; ------------------------------------------------------------------------
; fm_begin: locate the parameter list (ptr3) and point its buffer fields at
; the control block in ptr4. Must precede every series of File Manager
; calls, because DOS owns the parameter list between calls.

fm_begin:
        jsr     FM_LOCATE       ; Y = low, A = high
        sty     ptr3
        sta     ptr3+1

        .assert FM_TSL = FM_WORK + 2, error
        .assert FM_DATA = FM_TSL + 2, error
        ldx     #$00
        ldy     #FM_WORK
:       clc
        lda     ptr4
        adc     bufofs_lo,x
        sta     (ptr3),y
        iny
        lda     ptr4+1
        adc     bufofs_hi,x
        sta     (ptr3),y
        iny
        inx
        cpx     #3
        bne     :-
        rts

bufofs_lo:
        .byte   <FCB::WORK, <FCB::TSL, <FCB::DATA
bufofs_hi:
        .byte   >FCB::WORK, >FCB::TSL, >FCB::DATA

; ------------------------------------------------------------------------
; fm_simple: call type in A, no other parameters (CLOSE; or DELETE after
; fm_name has set the name fields).

fm_simple:
        ldy     #FM_CALL
        sta     (ptr3),y
        ldx     #$01
        jmp     fm_call         ; fm_call is in another segment

; ------------------------------------------------------------------------
; fm_call: call the File Manager. X = 0 allocates the file on OPEN if it
; isn't found; X <> 0 doesn't. Returns the File Manager's return code in A,
; with carry set if it is nonzero.
;
; cc65 leaves Language Card bank 2 enabled for reading. Switch ROM in
; around the call, as rdkey.s does around the monitor's RDKEY.

        .segment        "LOWCODE"

fm_call:
        bit     $C082           ; ROM
        jsr     FM_ENTRY
        bit     $C080           ; LC bank 2, read only
        ldy     #FM_RC
        lda     (ptr3),y
        cmp     #$01            ; C = (return code <> 0)
        rts

        .code

; ------------------------------------------------------------------------
; fm_position: POSITION to the absolute byte offset in AX (record 0).
; Returns as fm_call.

fm_position:
        ldy     #FM_OFFSET
        sta     (ptr3),y
        iny
        txa
        sta     (ptr3),y
        lda     #$00
        ldy     #FM_RECORD
        sta     (ptr3),y
        iny
        sta     (ptr3),y
        lda     #FMC_POSITION
        bne     fm_simple       ; Branch always

; ------------------------------------------------------------------------
; fm_readbyte: read one byte. Returns carry clear with the byte in A, or
; carry set with the return code in A.

fm_readbyte:
        ldy     #FM_CALL
        lda     #FMC_READ
        sta     (ptr3),y
        iny
        lda     #FMS_ONE
        sta     (ptr3),y
        ldx     #$01
        jsr     fm_call
        bcs     :+
        ldy     #FM_BYTE
        lda     (ptr3),y
        clc
:       rts

; ------------------------------------------------------------------------
; fm_writebyte: write the byte in A. Returns as fm_call.

fm_writebyte:
        ldy     #FM_BYTE
        sta     (ptr3),y
        ldy     #FM_CALL
        lda     #FMC_WRITE
        sta     (ptr3),y
        iny
        lda     #FMS_ONE
        sta     (ptr3),y
        ldx     #$01
        jmp     fm_call

; ------------------------------------------------------------------------
; fm_rangeio: READ or WRITE (call type in A) fm_rio_count bytes at
; fm_rio_addr. The count must not be zero. Returns as fm_call.
; Uses tmp1.

fm_rangeio:
        sta     tmp1
        ldy     #FM_CALL
        sta     (ptr3),y
        iny
        lda     #FMS_RANGE
        sta     (ptr3),y

        ; Range length; a WRITE takes the count minus FM_WRITE_ADJUST
        lda     fm_rio_count
        ldx     fm_rio_count+1
        ldy     tmp1
        cpy     #FMC_WRITE
        bne     :+
        sec
        sbc     #FM_WRITE_ADJUST
        bcs     :+
        dex
:       ldy     #FM_RANGE
        sta     (ptr3),y
        iny
        txa
        sta     (ptr3),y

        ; Range address
        ldy     #FM_ADDR
        lda     fm_rio_addr
        sta     (ptr3),y
        iny
        lda     fm_rio_addr+1
        sta     (ptr3),y

        ldx     #$01
        jmp     fm_call

; ------------------------------------------------------------------------
; fm_incpos: increment the control block's logical position.

fm_incpos:
        ldy     #FCB::POS
        lda     (ptr4),y
        clc
        adc     #$01
        sta     (ptr4),y
        iny
        lda     (ptr4),y
        adc     #$00
        sta     (ptr4),y
        rts

; ------------------------------------------------------------------------
; fm_maperr: translate a File Manager return code (A) into the equivalent
; ProDOS 8 error code, so the stock ___mappederrno, ___oserror values and
; _stroserror messages work unchanged and match the ProDOS build.

fm_maperr:
        cmp     #ERRTAB_LEN
        bcc     :+
        lda     #$08            ; Unknown: treat as I/O error
:       tax
        lda     errtab,x
        rts

errtab: .byte   $00             ; 00 No error
        .byte   $01             ; 01 Language not available -> ENOSYS
        .byte   $04             ; 02 Bad call type          -> EINVAL
        .byte   $04             ; 03 Bad sub-call type      -> EINVAL
        .byte   $2B             ; 04 Write protected        -> EACCES
        .byte   $4C             ; 05 End of data            (handled by callers)
        .byte   $46             ; 06 File not found         -> ENOENT
        .byte   $45             ; 07 Volume mismatch        -> ENOENT
        .byte   $27             ; 08 Disk I/O error         -> EIO
        .byte   $48             ; 09 Disk full              -> ENOSPC
        .byte   $4E             ; 0A File locked            -> EACCES
ERRTAB_LEN = * - errtab

        .bss

fm_rio_addr:    .res    2
fm_rio_count:   .res    2
