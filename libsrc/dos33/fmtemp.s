;
; DOS 3.3 file I/O for the cc65 apple2 target
;
; Temporary control block for File Manager calls made without an open
; file (DELETE, RENAME): they need the work area and buffers as OPEN does.
;
; fm_tempfcb: allocate one into ptr4. Returns carry clear, or carry set
;             with A = DOSERR_NOBUFS (DOS's NO BUFFERS AVAILABLE, ENOMEM).
; fm_freefcb: free the one in ptr4. Preserves A.
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

        .import         _malloc, _free

        .include        "zeropage.inc"
        .include        "fm.inc"
        .include        "filedes.inc"

; File Manager work area ("Beneath Apple DOS", ch. 6): the bytes that
; identify a file. The first T/S list's track and sector are unique on a
; disk; slot and drive say which disk.
WA_TSL          = $00           ; Track, sector of the first T/S list
WA_SLOT         = $26           ; Slot * 16
WA_DRIVE        = $27           ; Drive

        .code

fm_tempfcb:
        lda     #<.sizeof(FCB)
        ldx     #>.sizeof(FCB)
        jsr     _malloc
        sta     ptr4
        stx     ptr4+1
        ora     ptr4+1
        beq     :+
        clc
        rts
:       lda     #DOSERR_NOBUFS
        sec
        rts

fm_freefcb:
        pha
        lda     ptr4
        ldx     ptr4+1
        jsr     _free
        pla
        rts

fm_isopen:
        lda     #$00
        ldy     #FM_RECORD
        sta     (ptr3),y
        iny
        sta     (ptr3),y
        ldy     #FM_CALL
        lda     #FMC_OPEN
        sta     (ptr3),y
        ldx     #$01            ; Don't allocate
        jsr     fm_call
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
