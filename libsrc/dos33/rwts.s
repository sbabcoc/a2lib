;
; Scott Babcock, 2026-11-12
;
; DOS 3.3 RWTS access for the cc65 apple2 target
;
; Reads a sector through DOS's own IOB (from $3E3), so the device
; characteristics table and last-access fields that DOS maintains stay
; valid ("Beneath Apple DOS" ch. 6).
;

        .include        "zeropage.inc"
        .include        "fm.inc"

; Shared storage
iob             = ptr3          ; byte*: DOS's IOB

        .code

;-----------------------------------------------------------------------------
; rwts_read: Read one sector through RWTS.
;
; Input:        rwts_slot     byte      the slot (1-7)
;               rwts_drive    byte      the drive (1-2)
;               rwts_volume   byte      the volume; 0 for any
;               rwts_track    byte      the track
;               rwts_sector   byte      the sector
;               rwts_buf      byte*     256 bytes for the sector
; Output:       C             flag      clear: read; set: failed
;               A             byte      RWTS's return code: 0, or RWTS_*
;                                       (rwts_maperr)
;               rwts_buf      byte*     if C clear: the sector
; Changes:      X, Y and iob; DOS's IOB and its own state. Language Card bank
;               2 is enabled for reading on return.

rwts_read:
        jsr     RWTS_LOCATE     ; Y = low, A = high
        sty     iob
        sta     iob+1

        ldy     #IOB_TYPE
        lda     #IOB_TABLE
        sta     (iob),y
        iny                     ; IOB_SLOT
        lda     rwts_slot
        asl
        asl
        asl
        asl
        sta     (iob),y
        .assert IOB_DRIVE = IOB_SLOT + 1, error
        .assert IOB_VOLUME = IOB_DRIVE + 1, error
        .assert IOB_TRACK = IOB_VOLUME + 1, error
        .assert IOB_SECTOR = IOB_TRACK + 1, error
        iny
        lda     rwts_drive
        sta     (iob),y
        iny
        lda     rwts_volume
        sta     (iob),y
        iny
        lda     rwts_track
        sta     (iob),y
        iny
        lda     rwts_sector
        sta     (iob),y
        ldy     #IOB_BUF
        lda     rwts_buf
        sta     (iob),y
        iny
        lda     rwts_buf+1
        sta     (iob),y
        ldy     #IOB_COUNT
        lda     #$00            ; 256 bytes
        sta     (iob),y
        ldy     #IOB_CMD
        lda     #IOB_READ
        sta     (iob),y

        ldy     iob
        lda     iob+1
        jmp     call

        .segment        "LOWCODE"

;-----------------------------------------------------------------------------
; call: Call RWTS. cc65 leaves Language Card bank 2 enabled for reading, so
; ROM is switched in around the call, as fm_call does.
;
; Input:        Y             byte      the IOB's low byte
;               A             byte      the IOB's high byte
;               iob           byte*     the IOB, set up for the call
; Output:       C             flag      as rwts_read
;               A             byte      as rwts_read
; Changes:      X and Y.

call:   bit     LC_ROM_RO
        jsr     RWTS_ENTRY
        bit     LC_BANK2_RO
        ldy     #IOB_RC
        lda     (iob),y
        cmp     #$01            ; C = (return code <> 0)
        rts

        .code

;-----------------------------------------------------------------------------
; rwts_maperr: Translate an RWTS return code into the DOS 3.3 error number
; that DOS itself reports for it, as fm_maperr does for the File Manager.
;
; Input:        A             byte      RWTS's return code, not 0
; Output:       A             byte      the __oserror value: DOSERR_WPROT
;                                       (EACCES), DOSERR_VOLUME (ENOENT) or
;                                       DOSERR_IO (EIO)
; Changes:      C, N and Z. X and Y are unchanged.

rwts_maperr:
        cmp     #RWTS_WPROT
        bne     :+
        lda     #DOSERR_WPROT   ; Write protected   -> EACCES
        rts
:       cmp     #RWTS_VOLUME
        bne     :+
        lda     #DOSERR_VOLUME  ; Volume mismatch   -> ENOENT
        rts
:       lda     #DOSERR_IO      ; Drive, read, init -> EIO
        rts

        .bss

rwts_slot:      .res    1       ; byte: the slot (1-7)
rwts_drive:     .res    1       ; byte: the drive (1-2)
rwts_volume:    .res    1       ; byte: the volume, 0 for any
rwts_track:     .res    1       ; byte: the track (0-34)
rwts_sector:    .res    1       ; byte: the sector (0-15)
rwts_buf:       .res    2       ; byte*: 256 bytes for the sector
