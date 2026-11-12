;
; DOS 3.3 file I/O for the cc65 apple2 target
;
; int __fastcall__ stat (const char* pathname, struct stat* statbuf);
;
; Replaces libsrc/apple2/stat.s from cc65. Opens the file with this
; library's open() and takes the size from lseek(fd, 0, SEEK_END), so the
; size follows the same rules as reads and seeks (DESIGN.md 5.8):
;
;   st_dev      slot | (drive - 1) << 3, the encoding stock stat derives
;               from ProDOS's unit number
;   st_mode     S_IFREG (DOS 3.3 has no directories)
;   st_size     T: bytes before the first $00; A, I, B: the header's
;               length; others: bytes up to the end of the data
;   st_access   $01 (read only) if locked, else $C3 (cc65's default for
;               new ProDOS files)
;   st_type     ProDOS equivalent: T $04, B $06, A $FC, I $FA, R $FE;
;               others $00
;   st_auxtype  B: load address; others 0
;
; Everything else is 0: DOS 3.3 keeps no dates, and the sector count is
; only in the catalog, which this module doesn't read.
;

        .export         _stat
        .import         _open, _close, _lseek
        .import         popax, pushax, pusha0

        .include        "zeropage.inc"
        .include        "errno.inc"
        .include        "fcntl.inc"
        .include        "filedes.inc"
        .include        "stat.inc"
        .include        "fm.inc"

        .code

_stat:
        sta     stbuf
        stx     stbuf+1

        ; Clear statbuf
        sta     ptr1
        stx     ptr1+1
        lda     #$00
        ldy     #.sizeof(stat) - 1
:       sta     (ptr1),y
        dey
        bpl     :-

        ; fd = open (pathname, O_RDONLY)
        jsr     popax
        jsr     pushax
        lda     #O_RDONLY
        jsr     pusha0
        ldy     #4
        jsr     _open
        cpx     #$FF
        bne     :+
        rts                     ; -1, errno set by open
:       sta     fd

        ; Fields from the control block and the parsed name
        ldy     fd
        tya
        asl
        asl
        tay
        lda     fdtab + FD::BUFFER,y
        sta     ptr4
        lda     fdtab + FD::BUFFER+1,y
        sta     ptr4+1
        lda     stbuf
        sta     ptr1
        lda     stbuf+1
        sta     ptr1+1

        ; st_dev
        lda     fm_drive
        sec
        sbc     #1
        asl
        asl
        asl
        ora     fm_slot
        ldy     #stat::st_dev
        sta     (ptr1),y

        ; st_mode
        lda     #S_IFREG
        ldy     #stat::st_mode
        sta     (ptr1),y

        ; st_access
        ldy     #FCB::TYPE
        lda     (ptr4),y
        sta     type
        ldx     #$C3
        asl                     ; Lock bit into C
        bcc     :+
        ldx     #$01
:       txa
        ldy     #stat::st_access
        sta     (ptr1),y

        ; st_type
        lda     type
        and     #$7F
        ldx     #NTYPES - 1
:       cmp     ftypes,x
        beq     :+
        dex
        bpl     :-
        lda     #$00
        beq     settype         ; Branch always
:       lda     ptypes,x
settype:
        ldy     #stat::st_type
        sta     (ptr1),y

        ; st_auxtype: B files only (ADDR is 0 otherwise)
        ldy     #FCB::ADDR
        lda     (ptr4),y
        ldy     #stat::st_auxtype
        sta     (ptr1),y
        ldy     #FCB::ADDR+1
        lda     (ptr4),y
        ldy     #stat::st_auxtype+1
        sta     (ptr1),y

        ; st_size = lseek (fd, 0L, SEEK_END)
        lda     fd
        jsr     pusha0
        lda     #$00
        tax
        jsr     pushax          ; High word of offset
        jsr     pushax          ; Low word
        lda     #1              ; SEEK_END
        ldx     #$00
        jsr     _lseek
        sta     tmp1
        stx     tmp2
        lda     sreg            ; -1 has sreg = $FFFF; sizes are below $10000
        bne     fail
        lda     stbuf           ; lseek changed ptr1
        sta     ptr1
        lda     stbuf+1
        sta     ptr1+1
        ldy     #stat::st_size
        lda     tmp1
        sta     (ptr1),y
        iny
        lda     tmp2
        sta     (ptr1),y

        ; close (fd); return 0
        lda     fd
        ldx     #$00
        jsr     _close
        lda     #$00
        tax
        rts

        ; Close, keeping lseek's errno, and return -1
fail:   lda     ___errno
        pha
        lda     fd
        ldx     #$00
        jsr     _close
        pla
        sta     ___errno
        lda     #$FF
        tax
        rts

        .rodata

; File Manager type (lock bit cleared) -> ProDOS type
ftypes: .byte   FMT_TEXT, FMT_BINARY, FMT_APPLESOFT, FMT_INTEGER, FMT_RELOC
NTYPES = * - ftypes
ptypes: .byte   $04,      $06,        $FC,           $FA,         $FE

        .bss

stbuf:  .res    2
fd:     .res    1
type:   .res    1
