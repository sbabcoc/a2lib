;
; Scott Babcock, 2026-11-12
;
; rwfile: read or write an open file, for rwcommon (rwcommon.s), which
; jumps here once this module's constructor has pointed it here. open.s
; forces this module in, so programs that never open a file don't link it.
; Called as rwcommon is, with:
;   A     REF_NUM of the file (see open.s)
;   Y     READ_CALL or WRITE_CALL
;   buffer  (ptr1) the caller's buffer
;   count   (ptr2) the number of bytes
; and returns the number of bytes transferred in AX, through rwepilog.
;
; O_APPEND: a write first moves to the end of the file (seekend.s).
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
; Zero page: like the stock rwcommon, this may change ptr1-ptr3, but it
; preserves ptr4, which it uses for the control block (ctlblock). cc65's fgets keeps
; its destination pointer in ptr4 across fgetc -> read (DESIGN.md 10.1).
;

        .export         rwfile
        .constructor    initrwfile
        .import         rwcommon, rwepilog, rw_count, seekend

        .macpack        longbranch

        .include        "zeropage.inc"
        .include        "errno.inc"
        .include        "fcntl.inc"
        .include        "mli.inc"
        .include        "filedes.inc"
        .include        "fm.inc"

; Shared storage
buffer          = ptr1          ; byte*: the caller's buffer
count           = ptr2          ; unsigned: the bytes asked for
remaining_low   = tmp1          ; unsigned: bytes left to read or check
remaining_high  = tmp2
newpos_low      = tmp3          ; unsigned: a header file's position
newpos_high     = tmp4          ; after a write
scan_ptr        = sreg          ; byte*: the byte being checked (twrite)

COUNT = rw_count                ; Bytes transferred, for rwepilog

        .segment        "ONCE"

initrwfile:
        lda     #<rwfile
        sta     rwcommon+1
        lda     #>rwfile
        sta     rwcommon+2
        rts

        .code

rwfile:
        ; Save the caller's ptr4
        pha
        lda     ctlblock
        sta     saveptr4
        lda     ctlblock+1
        sta     saveptr4+1
        pla

        ; The fdtab slot from REF_NUM
        and     #$3F
        tax

        ; O_APPEND: a write starts at the end
        cpy     #WRITE_CALL
        bne     :+
        lda     fdtab + FD::FLAGS,x
        and     #O_APPEND
        beq     :+
        txa
        tay
        jsr     seekend         ; Preserves Y
        jcs     oserr
        tya
        tax
        ldy     #WRITE_CALL

        ; Find the control block
:       lda     fdtab + FD::BUFFER,x
        sta     ctlblock
        lda     fdtab + FD::BUFFER+1,x
        sta     ctlblock+1
        sty     op

        lda     #$00
        sta     COUNT
        sta     COUNT+1
        lda     count
        ora     count+1
        jeq     ok              ; Nothing to do

        jsr     fm_begin
        ldy     #FCB::KIND
        lda     (ctlblock),y
        jmi     text
        ldy     #FCB::HDRLEN
        lda     (ctlblock),y
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
        jmp     setall

        ; Read byte by byte: a range READ that runs into the end of the
        ; data doesn't say how many bytes it transferred
rawrd:  jsr     fm_readbyte
        jcs     rdend
        jsr     putbyte
        bne     rawrd
        jmp     ok

; ------------------------------------------------------------------------
; Header files

header: lda     op
        cmp     #WRITE_CALL
        jeq     hwrite

        ; Read at most LEN - POS bytes
        ldy     #FCB::LEN
        lda     (ctlblock),y
        ldy     #FCB::POS
        sec
        sbc     (ctlblock),y
        sta     remaining_low
        ldy     #FCB::LEN+1
        lda     (ctlblock),y
        ldy     #FCB::POS+1
        sbc     (ctlblock),y
        sta     remaining_high
        jcc     ok              ; Past the end
        ora     remaining_low
        jeq     ok              ; At the end
        lda     count           ; Count < remaining?
        cmp     remaining_low
        lda     count+1
        sbc     remaining_high
        bcs     :+
        lda     count
        sta     remaining_low
        lda     count+1
        sta     remaining_high
:       lda     buffer
        sta     fm_rio_addr
        lda     buffer+1
        sta     fm_rio_addr+1
        lda     remaining_low
        sta     fm_rio_count
        lda     remaining_high
        sta     fm_rio_count+1
        lda     #FMC_READ
        jsr     fm_rangeio      ; Uses tmp1 (remaining_low)
        jcs     fmerr

        ; COUNT = bytes read; POS += COUNT
        lda     fm_rio_count
        sta     COUNT
        lda     fm_rio_count+1
        sta     COUNT+1
        ldy     #FCB::POS
        lda     (ctlblock),y
        clc
        adc     COUNT
        sta     (ctlblock),y
        iny
        lda     (ctlblock),y
        adc     COUNT+1
        sta     (ctlblock),y
        jmp     ok

        ; The new position must fit the header's 16-bit length
hwrite: ldy     #FCB::POS
        lda     (ctlblock),y
        clc
        adc     count
        sta     newpos_low
        iny
        lda     (ctlblock),y
        adc     count+1
        sta     newpos_high
        bcc     :+
        lda     #ENOSPC
        jmp     direrr

:       jsr     whole
        lda     #FMC_WRITE
        jsr     fm_rangeio
        jcs     fmerr

        ; POS = new position; if past LEN, LEN = POS and mark for close
        ldy     #FCB::POS
        lda     newpos_low
        sta     (ctlblock),y
        iny
        lda     newpos_high
        sta     (ctlblock),y
        ldy     #FCB::LEN
        lda     newpos_low
        cmp     (ctlblock),y
        iny
        lda     newpos_high
        sbc     (ctlblock),y
        jcc     setall          ; Within the old length
        lda     newpos_high
        sta     (ctlblock),y
        dey
        lda     newpos_low
        sta     (ctlblock),y
        ldy     #FCB::STATE
        lda     (ctlblock),y
        ora     #FCBS_DIRTY
        sta     (ctlblock),y
        jmp     setall

; ------------------------------------------------------------------------
; T files

text:   lda     op
        cmp     #WRITE_CALL
        jeq     twrite

        ; Nothing more once the end has been read
        ldy     #FCB::STATE
        lda     (ctlblock),y
        jmi     ok

trd:    jsr     fm_readbyte
        jcs     trdend
        tax                     ; $00 on disk: end of file
        jeq     teof
        and     #HIBIT_OFF
        jsr     swapnl
        jsr     putbyte
        php
        jsr     fm_incpos
        plp
        bne     trd
        jmp     ok

trdend: cmp     #DOSERR_ENDDATA
        jne     fmerr
teof:   ldy     #FCB::STATE
        lda     (ctlblock),y
        ora     #FCBS_EOF
        sta     (ctlblock),y
        jmp     ok

        ; Reject 8-bit data before writing anything
twrite: lda     buffer
        sta     scan_ptr
        lda     buffer+1
        sta     scan_ptr+1
        lda     count
        sta     remaining_low
        lda     count+1
        sta     remaining_high
        ldy     #$00
scan:   lda     (scan_ptr),y
        jmi     reject
        iny
        bne     :+
        inc     scan_ptr+1
:       lda     remaining_low
        bne     :+
        dec     remaining_high
:       dec     remaining_low
        lda     remaining_low
        ora     remaining_high
        bne     scan

        ; After reading the end, write over the terminator, not after it
        ldy     #FCB::STATE
        lda     (ctlblock),y
        bpl     twr
        and     #<~FCBS_EOF
        sta     (ctlblock),y
        ldy     #FCB::POS+1
        lda     (ctlblock),y
        tax
        dey
        lda     (ctlblock),y
        jsr     fm_position
        jcs     fmerr

twr:    ldy     #$00
        lda     (buffer),y
        jsr     swapnl
        ora     #$80
        jsr     fm_writebyte
        jcs     fmerr
        jsr     fm_incpos
        jsr     nextbyte
        bne     twr
        jmp     ok

reject: lda     #EINVAL
        jmp     direrr

; ------------------------------------------------------------------------
; Common exits

rdend:  cmp     #DOSERR_ENDDATA ; End of data ends a read
        jeq     ok
fmerr:  jsr     fm_maperr
oserr:  jsr     restore
        jmp     ___mappederrno
direrr: jsr     restore
        jmp     ___directerrno

setall: lda     count           ; Whole count transferred
        sta     COUNT
        lda     count+1
        sta     COUNT+1
ok:     jsr     restore
        lda     #$00
        jmp     rwepilog

; ------------------------------------------------------------------------
; Helpers

; restore: restore the caller's ptr4. Preserves A.

restore:
        pha
        lda     saveptr4
        sta     ctlblock
        lda     saveptr4+1
        sta     ctlblock+1
        pla
        rts

; whole: set up fm_rangeio for the whole request (buffer, count).

whole:  lda     buffer
        sta     fm_rio_addr
        lda     buffer+1
        sta     fm_rio_addr+1
        lda     count
        sta     fm_rio_count
        lda     count+1
        sta     fm_rio_count+1
        rts

; putbyte: store A at buffer, then fall into nextbyte.
; nextbyte: advance ptr1 and COUNT. Returns Z set when COUNT = ptr2.

putbyte:
        ldy     #$00
        sta     (buffer),y
nextbyte:
        inc     buffer
        bne     :+
        inc     buffer+1
:       inc     COUNT
        bne     :+
        inc     COUNT+1
:       lda     COUNT
        cmp     count
        bne     :+
        lda     COUNT+1
        cmp     count+1
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
saveptr4:
        .res    2
