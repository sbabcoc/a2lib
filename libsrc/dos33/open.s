;
; Scott Babcock, 2026-11-12
;
; open() for DOS 3.3 files, closing files for cc65's close() and at exit, with
; the symbols cc65's own read(), close() and descriptor table expect, so those
; work unchanged. A file's fdtab slot holds:
;
;   REF_NUM  the slot's offset ORed with #$40: nonzero and below $80, so
;            read(), write() and close() treat it as a file, and the slot
;            can be found again from it
;   BUFFER   the file's control block, a DOS buffer; 0 for the console
;
; Each file is classified by type when it opens: text, a hidden header (A, I
; and B files), or raw. For details, see sections 4 and 5 of DESIGN.
;

        .export         _open, closedirect, freebuffer
        .export         __filetype, __auxtype, __datetime
        .destructor     closeallfiles, 5

        .import         addysp, popax
        .forceimport    rwfile          ; Reads and writes these files

        .macpack        longbranch

        .include        "zeropage.inc"
        .include        "errno.inc"
        .include        "fcntl.inc"
        .include        "filedes.inc"
        .include        "fm.inc"

REF_FLAG = $40

        .code

;-----------------------------------------------------------------------------
; Open a file. A new file gets the type in _filetype, and a new B file the
; load address in _auxtype. With O_CREAT and a _filetype that the File Manager
; can't create, a file that exists is opened, and one that doesn't fails with
; EINVAL.
;
; Signature:    int open (const char* name, int flags, ...)
; Overrides:    cc65's open()
; Input:        C stack       char*     path name
;               C stack       int       O_RDONLY, O_WRONLY or O_RDWR, with
;                                       O_CREAT, O_EXCL, O_TRUNC and O_APPEND
;               C stack       ...       mode, ignored
;               Y             byte      the number of argument bytes on the C
;                                       stack (variadic)
;               __filetype    byte      O_CREAT: the type for a new file
;                                       (FMT_*)
;               __auxtype     unsigned  O_CREAT: a new B file's load address
; Output:       X:A           int       the file descriptor, or -1
;               errno         int       if -1: EMFILE (no fdtab slot), ENOMEM
;                                       (no free DOS buffer), EINVAL (a bad
;                                       path, or a _filetype that can't be
;                                       created), ENOENT, EEXIST, or as
;                                       __oserror maps
;               __oserror     byte      0, or the DOS 3.3 or library error
;                                       (DOSERR_*, LIBERR_*)
; Changes:      Y; ptr1 (fm_name), fm_parmlist, ctlblock and tmp1
;               (fm_rangeio). Pops the arguments. On success, takes an fdtab
;               slot and a DOS buffer, and may create the file or empty it
;               (O_TRUNC).

_open:
        ; Throw away all parameters except name and flags
        ; occupying together 4 bytes
        dey
        dey
        dey
        dey
        jsr     addysp

        ; Get and save flags and name
        jsr     popax
        sta     flags
        jsr     popax
        sta     name
        stx     name+1

        ; Find a free fdtab slot
        ldy     #$00
:       lda     fdtab + FD::REF_NUM,y
        beq     found
        .assert .sizeof(FD) = 4, error
        iny                     ; Next descriptor: 4 bytes on
        iny
        iny
        iny
        cpy     #MAX_FDS * .sizeof(FD)
        bcc     :-
        lda     #EMFILE
        jmp     ___directerrno

found:  sty     slot

        ; Reserve a control block
        jsr     fm_getfcb
        bcc     :+
        jmp     ___mappederrno  ; A = DOSERR_NOBUFS -> ENOMEM

:       ldy     slot
        lda     ctlblock
        sta     fdtab + FD::BUFFER,y
        lda     ctlblock+1
        sta     fdtab + FD::BUFFER+1,y
        lda     #$00
        sta     created

        jsr     fm_begin
        jsr     setname
        bcc     :+
        jmp     errfree

:
        ; The type for a new file: _filetype, if it's one the File Manager
        ; creates
        lda     flags
        and     #O_CREAT
        beq     old
        lda     __filetype
        ldx     #NTYPES - 1
:       cmp     ctypes,x
        beq     :+
        dex
        bpl     :-
        ; Not a type the File Manager creates: open the file only if it
        ; exists, since O_CREAT matters only when it doesn't (POSIX)
        ldx     #FMX_NOALLOC
        jsr     fmopen
        bcc     exists
        cmp     #DOSERR_NOTFOUND
        bne     jerrfreefm
        lda     #EINVAL         ; Can't create it
        jmp     errfreedirect
:       sta     type
        ldx     #FMX_ALLOC
        .assert FMX_ALLOC = 0, error
        beq     doopen          ; Branch always
old:    ldx     #FMX_NOALLOC
doopen: jsr     fmopen
        bcc     exists

        ; "File not found" with FMX_ALLOC means DOS allocated it, and it's open
        cmp     #DOSERR_NOTFOUND
        bne     jerrfreefm
        lda     flags
        and     #O_CREAT
        beq     :+
        inc     created
        bne     opened          ; Branch always
:       lda     #DOSERR_NOTFOUND
jerrfreefm:
        jmp     errfreefm

exists: lda     flags
        and     #O_CREAT | O_EXCL
        cmp     #O_CREAT | O_EXCL
        bne     opened
        lda     #LIBERR_EXISTS  ; -> EEXIST
        jmp     errclose

        ; Set up the control block from the type of the file opened
opened: ldy     #FMPARMS::TYPE
        lda     (fm_parmlist),y
        ldy     #FCB::TYPE      ; Keep the lock bit for stat
        sta     (ctlblock),y
        and     #FMT_TYPE_MASK
        sta     type
        jsr     classify

        ; "A call to POSITION should follow every OPEN"
        jsr     rewind
        jcs     errclosefm

        lda     created
        bne     newfile
        lda     flags
        and     #O_TRUNC
        beq     oldfile
        jsr     truncate
        bcc     newfile
        rts                     ; truncate has set errno and cleaned up

        ; Existing file: read the hidden header, if there is one
oldfile:
        jsr     hdrsize
        beq     done
        lda     #FMC_READ
        jsr     fm_rangeio
        bcc     :+
        cmp     #DOSERR_ENDDATA ; Empty file: header written on close
        bne     errclosefm
        lda     #$00            ; No load address
        sta     hdrbuf
        sta     hdrbuf+1
        ldy     #FCB::STATE
        lda     #FCBS_DIRTY
        sta     (ctlblock),y
        bne     done            ; Branch always (LEN stays 0)
:       ldy     #FCB::LEN
        lda     hdrbuf+2
        sta     (ctlblock),y
        iny
        lda     hdrbuf+3
        sta     (ctlblock),y
        jmp     done

        ; New (or truncated) file: write the hidden header, if any
newfile:
        lda     created         ; Truncated files keep their load address
        cmp     #TRUNCATED
        beq     :+
        lda     __auxtype
        sta     hdrbuf
        lda     __auxtype+1
        sta     hdrbuf+1
:       lda     #$00
        sta     hdrbuf+2        ; Length 0
        sta     hdrbuf+3
        jsr     hdrsize
        beq     done
        lda     #FMC_WRITE
        jsr     fm_rangeio
        bcs     errclosefm

        ; B files: keep the load address for stat
done:   ldy     #FCB::HDRLEN
        lda     (ctlblock),y
        cmp     #4
        bne     :+
        ldy     #FCB::ADDR
        lda     hdrbuf
        sta     (ctlblock),y
        iny
        lda     hdrbuf+1
        sta     (ctlblock),y

        ; Fill in the fdtab slot and return the handle
:       ldy     slot
        lda     flags
        sta     fdtab + FD::FLAGS,y
        tya
        ora     #REF_FLAG
        sta     fdtab + FD::REF_NUM,y
        tya
        lsr
        lsr
        ldx     #$00
        stx     ___oserror
        rts

; ------------------------------------------------------------------------
; Error exits

errclosefm:                     ; A = File Manager code, file open
        jsr     fm_maperr
errclose:                       ; A = __oserror value, file open
        sta     errcode
        lda     #FMC_CLOSE
        jsr     fm_simple
        lda     errcode
        bne     errfree         ; Branch always
errfreefm:                      ; A = File Manager code, file not open
        jsr     fm_maperr
errfree:                        ; A = __oserror value, file not open
        pha
        ldy     slot
        jsr     freebuffer
        pla
        jmp     ___mappederrno
errfreedirect:                  ; A = errno code, file not open
        pha
        ldy     slot
        jsr     freebuffer
        pla
        jmp     ___directerrno

;-----------------------------------------------------------------------------
; Replace the open file with an empty one of the same type, as the File
; Manager can't shorten a file. A B file keeps its load address.
;
; Prepare:      fm_begin, fmopen
; Input:        ctlblock      FCB*      the file's control block
;               name          char*     the path
;               type          byte      the file's type
; Output:       C             flag      clear: replaced, open and positioned
;                                       at the start
;               created       byte      TRUNCATED if the old header was read,
;                                       else CREATED
;               hdrbuf        byte[4]   the old header, if it was read
; Changes:      A, X, Y and the parameter list. If it fails, it closes the
;               file, releases the slot's buffer, sets errno and returns -1 to
;               _open's caller, not to _open.

truncate:
        ; Save the old header (B files: load address)
        jsr     hdrsize
        beq     :+
        lda     #FMC_READ
        jsr     fm_rangeio
        bcs     :+              ; Unreadable header: use _auxtype instead
        lda     #TRUNCATED
        sta     created
:       lda     #FMC_CLOSE
        jsr     fm_simple
        bcs     tfreefm

        ; READ reused the name fields, so set them again
        jsr     setname
        bcs     tfree
        lda     #FMC_DELETE
        jsr     fm_simple
        bcs     tfreefm

        ; Allocate a new file of the same type
        ldx     #FMX_ALLOC
        jsr     fmopen
        bcc     :+
        cmp     #DOSERR_NOTFOUND ; Allocated
        bne     tfreefm
:       lda     created
        bne     :+
        lda     #CREATED        ; No old header: use _auxtype
        sta     created
:       jsr     rewind
        bcs     tclosefm
        clc
        rts

tclosefm:
        pla                     ; Return straight to _open's caller
        pla
        jmp     errclosefm
tfreefm:
        pla
        pla
        jmp     errfreefm
tfree:  pla
        pla
        jmp     errfree

;-----------------------------------------------------------------------------
; OPEN the named file, with type as the type for a new file.
;
; Prepare:      fm_begin, setname
; Input:        X             byte      as fm_call
;               type          byte      the type for a new file
; Output:       C             flag      as fm_call
;               A             byte      as fm_call
; Changes:      Y.

fmopen: lda     type
        jmp     fm_open

;-----------------------------------------------------------------------------
; POSITION the open file to its start.
;
; Prepare:      fm_begin
; Output:       C             flag      as fm_call
;               A             byte      as fm_call
; Changes:      X and Y.

rewind: lda     #$00
        tax
        jmp     fm_position

;-----------------------------------------------------------------------------
; Set the parameter list's name fields from open()'s path.
;
; Prepare:      fm_begin
; Input:        name          char*     the path
; Output:       C             flag      as fm_name
;               A             byte      as fm_name
; Changes:      X, Y and ptr1 (fm_name).

setname:
        lda     name
        ldx     name+1
        jmp     fm_name

;-----------------------------------------------------------------------------
; Point fm_rangeio at the hidden header: the last HDRLEN bytes of hdrbuf.
;
; Prepare:      classify
; Input:        ctlblock      FCB*      the file's control block, with HDRLEN
;                                       set
; Output:       Z             flag      set: the file has no hidden header
;               fm_rio_addr   byte*     if Z clear: the header's place in
;                                       hdrbuf
;               fm_rio_count  unsigned  if Z clear: HDRLEN
; Changes:      A, Y and C. X is unchanged.

hdrsize:
        ldy     #FCB::HDRLEN
        lda     (ctlblock),y
        beq     :+
        sta     fm_rio_count
        lda     #$00
        sta     fm_rio_count+1
        sec
        lda     #<(hdrbuf + 4)
        sbc     fm_rio_count
        sta     fm_rio_addr
        lda     #>(hdrbuf + 4)
        sbc     #$00
        sta     fm_rio_addr+1
        lda     fm_rio_count    ; Z clear
:       rts

;-----------------------------------------------------------------------------
; Set the control block's KIND, HDRLEN and LENOFS for the file's type. T: the
; text codec, no header. B: a 4-byte header (load address, length), the length
; at offset 2. I and A: a 2-byte header (length) at offset 0. Others: raw, no
; header.
;
; Prepare:      fm_getfcb
; Input:        A             byte      the type (FMT_*, without the lock bit)
;               ctlblock      FCB*      the control block, its fields 0
; Output:       ctlblock      FCB*      KIND, HDRLEN and LENOFS set
; Changes:      A, X and Y.

classify:
        cmp     #FMT_TEXT
        beq     text
        ldx     #4
        ldy     #2
        cmp     #FMT_BINARY
        beq     hdr
        ldx     #2
        ldy     #0
        cmp     #FMT_INTEGER
        beq     hdr
        cmp     #FMT_APPLESOFT
        beq     hdr
        rts                     ; Raw: fields are already zero
hdr:    tya
        ldy     #FCB::LENOFS
        sta     (ctlblock),y
        txa
        ldy     #FCB::HDRLEN
        sta     (ctlblock),y
        rts
text:   lda     #FCB_TEXT
        ldy     #FCB::KIND
        sta     (ctlblock),y
        rts

;-----------------------------------------------------------------------------
; Close the file in an fdtab slot, for close() and at exit. Rewrites the
; hidden header's length first if it changed, and closes the file even if that
; fails.
;
; Prepare:      open()
; Input:        Y             byte      the fdtab slot's offset, of an open
;                                       file
;               A             byte      REF_NUM (unused)
; Output:       C             flag      clear: closed; set: an error
;               A             byte      0, or the error's __oserror value
;               Y             byte      unchanged
; Changes:      X; fm_parmlist, ctlblock and tmp1 (fm_rangeio). The slot's DOS
;               buffer stays reserved: freebuffer releases it.

closedirect:
        sty     cslot
        jsr     fm_fdbegin
        lda     #$00
        sta     cerr

        ldy     #FCB::STATE
        lda     (ctlblock),y
        and     #FCBS_DIRTY
        beq     cclose
        ldy     #FCB::LENOFS
        lda     (ctlblock),y
        ldx     #$00
        jsr     fm_position
        bcs     cfail
        clc
        lda     ctlblock
        adc     #<FCB::LEN
        sta     fm_rio_addr
        lda     ctlblock+1
        adc     #>FCB::LEN
        sta     fm_rio_addr+1
        lda     #2
        sta     fm_rio_count
        lda     #$00
        sta     fm_rio_count+1
        lda     #FMC_WRITE
        jsr     fm_rangeio
        bcc     cclose
cfail:  jsr     fm_maperr
        sta     cerr

        ; Close even if the header couldn't be updated
cclose: lda     #FMC_CLOSE
        jsr     fm_simple
        bcc     :+
        jsr     fm_maperr
        sta     cerr
:       ldy     cslot
        lda     cerr
        cmp     #$01            ; C = error
        rts

;-----------------------------------------------------------------------------
; Release the control block of an fdtab slot, if it has one (the console has
; none), for close() and at exit.
;
; Prepare:      open()
; Input:        Y             byte      the fdtab slot's offset
; Changes:      A, Y and ctlblock. X is unchanged.

freebuffer:
        jsr     fm_fdfcb
        beq     :+
        jmp     fm_freefcb
:       rts

;-----------------------------------------------------------------------------
; Close every open file at exit (a destructor), so that buffered sectors and
; header lengths reach the disk, and release their DOS buffers. Errors are
; ignored.
;
; Changes:      A, X, Y; fm_parmlist, ctlblock and tmp1 (fm_rangeio).

closeallfiles:
        ldy     #$00
@slot:  lda     fdtab + FD::REF_NUM,y
        beq     @next
        bmi     @next           ; Device
        jsr     closedirect     ; Sets cslot
        jsr     freebuffer
        ldy     cslot
@next:  iny
        iny
        iny
        iny
        cpy     #MAX_FDS * .sizeof(FD)
        bcc     @slot
        rts

; ------------------------------------------------------------------------

CREATED   = 1                   ; created: the file is new
TRUNCATED = 2                   ; created: replaced, keeping its header

        .rodata

; The types a new file can have.
; Not the "new" A and B ($20, $40): DOS 3.3 lists them, but nothing shows
; that the File Manager creates them.
ctypes: .byte   FMT_TEXT, FMT_INTEGER, FMT_APPLESOFT, FMT_BINARY
        .byte   FMT_SPECIAL, FMT_RELOC
NTYPES = * - ctypes

        .data

__filetype:
        .byte   FMT_BINARY      ; Default: B, as stock cc65 defaults to BIN
__auxtype:
        .word   $0000           ; B files: load address
__datetime:
        .word   $0000           ; Exported for compatibility; DOS 3.3
        .word   $0000           ; has no file dates

        .bss

flags:          .res    1       ; byte: open()'s flags (O_*), low byte
name:           .res    2       ; char*: open()'s path
slot:           .res    1       ; byte: the fdtab slot's offset
type:           .res    1       ; byte: the file's type (FMT_*)
created:        .res    1       ; byte: 0, CREATED or TRUNCATED
errcode:        .res    1       ; byte: the error, while the file closes
hdrbuf:         .res    4       ; The hidden header: load address, length
cslot:          .res    1       ; byte: closedirect's fdtab slot offset
cerr:           .res    1       ; byte: closedirect's __oserror value
