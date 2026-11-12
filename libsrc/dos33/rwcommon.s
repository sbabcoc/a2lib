;
; DOS 3.3 file I/O for the cc65 apple2 target
;
; Replaces libsrc/apple2/rwcommon.s from cc65 and exports the same symbols.
; read.s and write.s call rwcommon with:
;   A     REF_NUM of the file (see open.s)
;   Y     READ_CALL or WRITE_CALL
;   ptr1  buffer
;   ptr2  count
; and expect the number of bytes transferred in AX (via rwepilog, which
; write.s also uses for device output).
;
; T files (DESIGN.md 5.1):
;   write: rejects the whole request with EINVAL if any byte is $80-$FF;
;          otherwise swaps $0A/$0D and sets bit 7
;   read:  the first $00 on disk ends the file; clears bit 7 and swaps
;          $0A/$0D back, so every byte written reads back unchanged
;          (including $00, stored as $80)
; Header files (A, I, B; DESIGN.md 5.3): the header is hidden; reads stop
; at the length it records, and writes extend it (rewritten on close).
; Other files are transferred raw.
;

        .export         rwprolog, rwcommon, rwepilog
        .import         popax, popptr1

        .macpack        longbranch

        .include        "zeropage.inc"
        .include        "errno.inc"
        .include        "fcntl.inc"
        .include        "mli.inc"
        .include        "filedes.inc"
        .include        "fm.inc"

COUNT = mliparam + MLI::RW::TRANS_COUNT ; Bytes transferred, for rwepilog

        .code

rwprolog:
        ; Save count
        sta     ptr2
        stx     ptr2+1

        ; Get and save buf
        jsr     popptr1

        ; Get and process fd
        jsr     popax
        jmp     getfd           ; Returns A, Y and C

rwcommon:
        ; Find the control block from REF_NUM
        and     #$3F
        tax
        lda     fdtab + FD::BUFFER,x
        sta     ptr4
        lda     fdtab + FD::BUFFER+1,x
        sta     ptr4+1
        sty     op

        lda     #$00
        sta     COUNT
        sta     COUNT+1
        lda     ptr2
        ora     ptr2+1
        jeq     ok              ; Nothing to do

        jsr     fm_begin
        ldy     #FCB::KIND
        lda     (ptr4),y
        jmi     text
        ldy     #FCB::HDRLEN
        lda     (ptr4),y
        jne     header

; ------------------------------------------------------------------------
; Raw files

        lda     op
        cmp     #WRITE_CALL
        bne     rawrd
        jsr     whole
        lda     #FMC_WRITE
        jsr     fm_rangeio
        jcs     fmerr
        jcc     setall          ; Branch always

        ; Read byte by byte: a range READ that runs into the end of the
        ; data doesn't say how many bytes it transferred
rawrd:  jsr     fm_readbyte
        jcs     rdend
        jsr     putbyte
        bne     rawrd
        jeq     ok              ; Branch always

; ------------------------------------------------------------------------
; Header files

header: lda     op
        cmp     #WRITE_CALL
        jeq     hwrite

        ; Read at most LEN - POS bytes
        ldy     #FCB::LEN
        lda     (ptr4),y
        ldy     #FCB::POS
        sec
        sbc     (ptr4),y
        sta     tmp1
        ldy     #FCB::LEN+1
        lda     (ptr4),y
        ldy     #FCB::POS+1
        sbc     (ptr4),y
        sta     tmp2
        jcc     ok              ; Past the end
        ora     tmp1
        jeq     ok              ; At the end
        lda     ptr2            ; Count < remaining?
        cmp     tmp1
        lda     ptr2+1
        sbc     tmp2
        bcs     :+
        lda     ptr2
        sta     tmp1
        lda     ptr2+1
        sta     tmp2
:       lda     ptr1
        sta     fm_rio_addr
        lda     ptr1+1
        sta     fm_rio_addr+1
        lda     tmp1
        sta     fm_rio_count
        lda     tmp2
        sta     fm_rio_count+1
        lda     #FMC_READ
        jsr     fm_rangeio      ; Uses tmp1
        jcs     fmerr

        ; COUNT = bytes read; POS += COUNT
        lda     fm_rio_count
        sta     COUNT
        lda     fm_rio_count+1
        sta     COUNT+1
        ldy     #FCB::POS
        lda     (ptr4),y
        clc
        adc     COUNT
        sta     (ptr4),y
        iny
        lda     (ptr4),y
        adc     COUNT+1
        sta     (ptr4),y
        jmp     ok

        ; The new position must fit the header's 16-bit length
hwrite: ldy     #FCB::POS
        lda     (ptr4),y
        clc
        adc     ptr2
        sta     tmp3
        iny
        lda     (ptr4),y
        adc     ptr2+1
        sta     tmp4
        bcc     :+
        lda     #ENOSPC
        jmp     ___directerrno

:       jsr     whole
        lda     #FMC_WRITE
        jsr     fm_rangeio
        jcs     fmerr

        ; POS = new position; if past LEN, LEN = POS and mark for close
        ldy     #FCB::POS
        lda     tmp3
        sta     (ptr4),y
        iny
        lda     tmp4
        sta     (ptr4),y
        ldy     #FCB::LEN
        lda     tmp3
        cmp     (ptr4),y
        iny
        lda     tmp4
        sbc     (ptr4),y
        jcc     setall          ; Within the old length
        lda     tmp4
        sta     (ptr4),y
        dey
        lda     tmp3
        sta     (ptr4),y
        ldy     #FCB::STATE
        lda     (ptr4),y
        ora     #FCBS_DIRTY
        sta     (ptr4),y
        jmp     setall

; ------------------------------------------------------------------------
; T files

text:   lda     op
        cmp     #WRITE_CALL
        jeq     twrite

        ; Nothing more once the end has been read
        ldy     #FCB::STATE
        lda     (ptr4),y
        jmi     ok

trd:    jsr     fm_readbyte
        jcs     trdend
        tax                     ; $00 on disk: end of file
        jeq     teof
        and     #$7F
        jsr     swapnl
        jsr     putbyte
        php
        jsr     fm_incpos
        plp
        bne     trd
        jeq     ok              ; Branch always

trdend: cmp     #FMR_ENDDATA
        jne     fmerr
teof:   ldy     #FCB::STATE
        lda     (ptr4),y
        ora     #FCBS_EOF
        sta     (ptr4),y
        jne     ok              ; Branch always

        ; Reject 8-bit data before writing anything
twrite: lda     ptr1
        sta     sreg
        lda     ptr1+1
        sta     sreg+1
        lda     ptr2
        sta     tmp1
        lda     ptr2+1
        sta     tmp2
        ldy     #$00
scan:   lda     (sreg),y
        jmi     reject
        iny
        bne     :+
        inc     sreg+1
:       lda     tmp1
        bne     :+
        dec     tmp2
:       dec     tmp1
        lda     tmp1
        ora     tmp2
        bne     scan

        ; After reading the end, write over the terminator, not after it
        ldy     #FCB::STATE
        lda     (ptr4),y
        bpl     twr
        and     #<~FCBS_EOF
        sta     (ptr4),y
        ldy     #FCB::POS+1
        lda     (ptr4),y
        tax
        dey
        lda     (ptr4),y
        jsr     fm_position
        jcs     fmerr

twr:    ldy     #$00
        lda     (ptr1),y
        jsr     swapnl
        ora     #$80
        jsr     fm_writebyte
        jcs     fmerr
        jsr     fm_incpos
        jsr     nextbyte
        bne     twr
        jeq     ok              ; Branch always

reject: lda     #EINVAL
        jmp     ___directerrno

; ------------------------------------------------------------------------
; Common exits

rdend:  cmp     #FMR_ENDDATA    ; End of data ends a read
        jeq     ok
fmerr:  jsr     fm_maperr
        jmp     ___mappederrno

setall: lda     ptr2            ; Whole count transferred
        sta     COUNT
        lda     ptr2+1
        sta     COUNT+1
ok:     lda     #$00

rwepilog:
        ; Return success
        sta     ___oserror      ; A = 0
        lda     COUNT
        ldx     COUNT+1
        rts

; ------------------------------------------------------------------------
; Helpers

; whole: set up fm_rangeio for the whole request (ptr1, ptr2).

whole:  lda     ptr1
        sta     fm_rio_addr
        lda     ptr1+1
        sta     fm_rio_addr+1
        lda     ptr2
        sta     fm_rio_count
        lda     ptr2+1
        sta     fm_rio_count+1
        rts

; putbyte: store A at ptr1, then fall into nextbyte.
; nextbyte: advance ptr1 and COUNT. Returns Z set when COUNT = ptr2.

putbyte:
        ldy     #$00
        sta     (ptr1),y
nextbyte:
        inc     ptr1
        bne     :+
        inc     ptr1+1
:       inc     COUNT
        bne     :+
        inc     COUNT+1
:       lda     COUNT
        cmp     ptr2
        bne     :+
        lda     COUNT+1
        cmp     ptr2+1
:       rts

; swapnl: exchange $0A and $0D (DESIGN.md 5.1, newlines).

swapnl: cmp     #$0A
        bne     :+
        lda     #$0D
        rts
:       cmp     #$0D
        bne     :+
        lda     #$0A
:       rts

        .bss

op:     .res    1
