;
; Scott Babcock, 2026-11-12
;
; Reading a disk sector through RWTS, with DOS's own IOB ($3E3), so that the
; device characteristics table and last-access fields DOS keeps stay valid
; ("Beneath Apple DOS" ch. 6). The catalog routines use it.
;

        .include        "zeropage.inc"
        .include        "fm.inc"

; Shared storage
iob             = ptr3          ; byte*: DOS's IOB

        .code

;-----------------------------------------------------------------------------
; Read one sector through RWTS.
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
        jsr     RWTS_LOCATE     ; A:Y
        sty     iob
        sta     iob+1

        ldy     #IOB::TYPE
        lda     #IOB_TABLE
        sta     (iob),y
        iny                     ; IOB::SLOT
        lda     rwts_slot
        asl
        asl
        asl
        asl
        sta     (iob),y
        .assert IOB::DRIVE = IOB::SLOT + 1, error
        .assert IOB::VOLUME = IOB::DRIVE + 1, error
        .assert IOB::TRACK = IOB::VOLUME + 1, error
        .assert IOB::SECTOR = IOB::TRACK + 1, error
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
        ldy     #IOB::BUF
        lda     rwts_buf
        sta     (iob),y
        iny
        lda     rwts_buf+1
        sta     (iob),y
        ldy     #IOB::COUNT
        lda     #$00            ; 256 bytes
        sta     (iob),y
        ldy     #IOB::CMD
        lda     #IOB_READ
        sta     (iob),y

        ldy     iob
        lda     iob+1
        jmp     call

        .segment        "LOWCODE"

;-----------------------------------------------------------------------------
; Call RWTS. cc65 leaves Language Card bank 2 enabled for reading, so ROM is
; switched in around the call, as fm_call does.
;
; Input:        A:Y           byte*     the IOB
;               iob           byte*     the IOB, set up for the call
; Output:       C             flag      as rwts_read
;               A             byte      as rwts_read
; Changes:      X and Y.

call:   bit     LC_ROM_RO
        jsr     RWTS_ENTRY
        bit     LC_BANK2_RO
        ldy     #IOB::RC
        lda     (iob),y
        cmp     #$01            ; C = (return code <> 0)
        rts

        .code

;-----------------------------------------------------------------------------
; Translate an RWTS return code into the DOS 3.3 error number that DOS itself
; reports for it, as fm_maperr does for the File Manager.
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
