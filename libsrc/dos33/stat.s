;
; Scott Babcock, 2026-11-12
;
; stat() for DOS 3.3 files. The size comes from opening the file and seeking
; to its end, so it follows the same rules as reads and seeks:
;
;   st_dev      slot | (drive - 1) << 3, the encoding cc65's stat derives
;               from ProDOS's unit number
;   st_mode     S_IFREG: DOS 3.3 has no directories
;   st_size     T: bytes before the first $00; A, I, B: the header's
;               length; others: bytes up to the end of the data
;   st_access   DOS33_LOCKED ($80) if the file is locked, else 0
;   st_type     DOS 3.3's type, in the catalog's coding (DOS33_T_*)
;   st_auxtype  B: load address; others 0
;   st_blocks   512-byte blocks, (sectors + 1) / 2, from the catalog
;               entry, as readdir() gives in d_blocks
;
; Everything else is 0: DOS 3.3 keeps no dates. For details, see section 5.8
; of DESIGN.
;

        .export         _stat
        .import         _open, _close, _lseek
        .import         __readdir_a2lib, __closedir_a2lib
        .import         popax, pushax, pusha0

        .macpack        longbranch

        .include        "zeropage.inc"
        .include        "errno.inc"
        .include        "fcntl.inc"
        .include        "stat.inc"
        .include        "fm.inc"
        .include        "dir.inc"

; Shared storage
statbuf         = ptr1          ; struct stat*: the caller's
entry           = ptr2          ; struct dirent*: a catalog entry
size_low        = tmp1          ; unsigned: the size, from lseek
size_high       = tmp2
name_char       = tmp1          ; char: one of d_name's characters (cmpname)

        .code

;-----------------------------------------------------------------------------
; Describe a file. Opens it with open() and takes the size from lseek (fd, 0,
; SEEK_END), then finds its catalog entry for st_blocks.
;
; Signature:    int __fastcall__ stat (const char* pathname, struct stat*
;               statbuf)
; Overrides:    cc65's stat()
; Input:        C stack       char*     path name
;               X:A           struct stat*
;                                       where the description goes
; Output:       X:A           int       0, or -1
;               errno         int       if -1: as open(), lseek() or readdir()
;                                       set it; if 0: the caller's, unchanged
;               statbuf       struct stat*
;                                       the fields this file's header lists;
;                                       the rest 0. Cleared even if stat fails
; Changes:      Y; statbuf, entry, size_low, size_high, sreg, fm_parmlist,
;               ctlblock, and what open(), lseek(), close(), readdir() and
;               closedir() change. Pops pathname. Opens and closes the file,
;               reads its disk's catalog, and takes and frees a DIR (malloc).

_stat:
        sta     stbuf
        stx     stbuf+1

        ; Clear statbuf
        sta     statbuf
        stx     statbuf+1
        lda     #$00
        ldy     #.sizeof(stat) - 1
:       sta     (statbuf),y
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
        asl
        asl
        tay
        jsr     fm_fdfcb
        lda     stbuf
        sta     statbuf
        lda     stbuf+1
        sta     statbuf+1

        ; st_dev
        lda     fm_drive
        sec
        sbc     #1
        asl
        asl
        asl
        ora     fm_slot
        ldy     #stat::st_dev
        sta     (statbuf),y

        ; st_mode
        lda     #S_IFREG
        ldy     #stat::st_mode
        sta     (statbuf),y

        ; st_access: the lock bit
        ldy     #FCB::TYPE
        lda     (ctlblock),y
        sta     type
        and     #FMT_LOCKED
        ldy     #stat::st_access
        sta     (statbuf),y

        ; st_type: OPEN's type, as the catalog has it
        lda     type
        and     #FMT_TYPE_MASK
        ldy     #stat::st_type
        sta     (statbuf),y

        ; st_auxtype: B files only (ADDR is 0 otherwise)
        ldy     #FCB::ADDR
        lda     (ctlblock),y
        ldy     #stat::st_auxtype
        sta     (statbuf),y
        ldy     #FCB::ADDR+1
        lda     (ctlblock),y
        ldy     #stat::st_auxtype+1
        sta     (statbuf),y

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
        sta     size_low
        stx     size_high
        lda     sreg            ; -1 has sreg = $FFFF; sizes are below $10000
        jne     fail
        lda     stbuf           ; lseek changed statbuf (ptr1)
        sta     statbuf
        lda     stbuf+1
        sta     statbuf+1
        ldy     #stat::st_size
        lda     size_low
        sta     (statbuf),y
        iny
        lda     size_high
        sta     (statbuf),y

        ; close (fd)
        lda     fd
        ldx     #$00
        jsr     _close

        ; st_blocks: find the file's catalog entry, on the disk open()
        ; used (fm_slot, fm_drive, fm_volume), by the name it parsed
        jsr     dir_at
        cpx     #$00
        bne     :+
        cmp     #$00
        jeq     error           ; errno set by dir_at
:       sta     dirp
        stx     dirp+1
        ; errno 0 tells readdir's end from an error; the caller's errno is
        ; put back on success, since no library function sets it to 0
        ; (ISO C 7.5)
        lda     ___errno
        sta     saverr
        lda     ___errno+1
        sta     saverr+1
        lda     #$00
        sta     ___errno
        sta     ___errno+1
find:   lda     dirp
        ldx     dirp+1
        jsr     __readdir_a2lib
        sta     entry
        stx     entry+1
        ora     entry+1
        beq     notfound

        ; Compare d_name (NUL-terminated) with the 30-byte name buffer
        ; (blank-padded, bit 7 set)
        ldx     #$00            ; Name buffer index
        ldy     #$00            ; d_name index; stays on the NUL
cmpname:
        lda     (entry),y
        beq     blank
        iny
        bne     :+              ; Branch always
blank:  lda     #' '            ; Past the end of d_name: blanks
:       sta     name_char
        lda     fm_namebuf,x
        and     #HIBIT_OFF
        cmp     name_char
        jne     find
        inx
        cpx     #NAME_LEN
        bcc     cmpname

        ; Found: st_blocks = d_blocks
        lda     stbuf
        sta     statbuf
        lda     stbuf+1
        sta     statbuf+1
        ldy     #DIRENT::BLOCKS
        lda     (entry),y
        ldy     #stat::st_blocks
        sta     (statbuf),y
        ldy     #DIRENT::BLOCKS+1
        lda     (entry),y
        ldy     #stat::st_blocks+1
        sta     (statbuf),y

        ; Close the catalog; return 0, or -1 if reading it failed
notfound:
        lda     dirp
        ldx     dirp+1
        jsr     __closedir_a2lib
        lda     ___errno
        bne     error
        lda     saverr          ; Success: the caller's errno again
        sta     ___errno
        lda     saverr+1
        sta     ___errno+1
        lda     #$00
        tax
        rts
error:  lda     #$FF
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

        .bss

stbuf:  .res    2               ; struct stat*: the caller's (statbuf)
fd:     .res    1               ; byte: the file, open for reading
type:   .res    1               ; byte: OPEN's type, with the lock bit
dirp:   .res    2               ; DIR*: the catalog of the file's disk
saverr: .res    2               ; int: the caller's errno, while reading it
