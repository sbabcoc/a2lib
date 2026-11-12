;
; DOS 3.3 RWTS access for the cc65 apple2 target
;
; rwts_read: read the sector rwts_track/rwts_sector from slot rwts_slot
; (1-7), drive rwts_drive, volume rwts_volume (0 = any) into the 256-byte
; buffer at rwts_buf. Returns carry clear, or carry set with the RWTS
; return code in A.
;
; Uses DOS's own IOB (from $3E3), so the device characteristics table
; and last-access fields that DOS maintains stay valid ("Beneath Apple
; DOS" ch. 6). Uses ptr3.
;
; rwts_maperr: translate an RWTS return code (A) into the equivalent
; ProDOS 8 error code, as fm_maperr does for the File Manager.
;

        .include        "zeropage.inc"
        .include        "fm.inc"

        .code

rwts_read:
        jsr     RWTS_LOCATE     ; Y = low, A = high
        sty     ptr3
        sta     ptr3+1

        ldy     #IOB_TYPE
        lda     #$01
        sta     (ptr3),y
        iny                     ; IOB_SLOT
        lda     rwts_slot
        asl
        asl
        asl
        asl
        sta     (ptr3),y
        .assert IOB_DRIVE = IOB_SLOT + 1, error
        .assert IOB_VOLUME = IOB_DRIVE + 1, error
        .assert IOB_TRACK = IOB_VOLUME + 1, error
        .assert IOB_SECTOR = IOB_TRACK + 1, error
        iny
        lda     rwts_drive
        sta     (ptr3),y
        iny
        lda     rwts_volume
        sta     (ptr3),y
        iny
        lda     rwts_track
        sta     (ptr3),y
        iny
        lda     rwts_sector
        sta     (ptr3),y
        ldy     #IOB_BUF
        lda     rwts_buf
        sta     (ptr3),y
        iny
        lda     rwts_buf+1
        sta     (ptr3),y
        ldy     #IOB_COUNT
        lda     #$00            ; 256 bytes
        sta     (ptr3),y
        ldy     #IOB_CMD
        lda     #$01            ; READ
        sta     (ptr3),y

        ldy     ptr3
        lda     ptr3+1
        jmp     call

; cc65 leaves Language Card bank 2 enabled for reading; switch ROM in
; around the call, as fm_call does.

        .segment        "LOWCODE"

call:   bit     $C082           ; ROM
        jsr     RWTS_ENTRY
        bit     $C080           ; LC bank 2, read only
        ldy     #IOB_RC
        lda     (ptr3),y
        cmp     #$01            ; C = (return code <> 0)
        rts

        .code

rwts_maperr:
        cmp     #$10
        bne     :+
        lda     #$2B            ; Write protected   -> EACCES
        rts
:       cmp     #$20
        bne     :+
        lda     #$45            ; Volume mismatch   -> ENOENT
        rts
:       lda     #$27            ; Drive, read, init -> EIO
        rts

        .bss

rwts_slot:      .res    1
rwts_drive:     .res    1
rwts_volume:    .res    1
rwts_track:     .res    1
rwts_sector:    .res    1
rwts_buf:       .res    2
