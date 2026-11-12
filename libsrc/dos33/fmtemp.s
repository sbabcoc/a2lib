;
; DOS 3.3 file I/O for the cc65 apple2 target
;
; Temporary control block for File Manager calls made without an open
; file (DELETE, RENAME): they need the work area and buffers as OPEN does.
;
; fm_tempfcb: allocate one into ptr4. Returns carry clear, or carry set
;             with A = $25 (maps to ENOMEM; the ProDOS table has no closer
;             code, since stock cc65 allocates nothing for these calls).
; fm_freefcb: free the one in ptr4. Preserves A.
;

        .import         _malloc, _free

        .include        "zeropage.inc"
        .include        "fm.inc"

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
:       lda     #$25
        sec
        rts

fm_freefcb:
        pha
        lda     ptr4
        ldx     ptr4+1
        jsr     _free
        pla
        rts
