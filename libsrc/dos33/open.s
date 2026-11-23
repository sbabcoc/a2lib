;
; Scott Babcock, 2026-11-12
;
; int open (const char* name, int flags, ...);
;
; Replaces libsrc/apple2/open.s from cc65 and exports the same symbols, so
; the stock close.s, read.s and filedes.s work unchanged. See DESIGN.md,
; sections 4 and 5.
;
; fdtab usage:
;   REF_NUM  fdtab offset of the slot ORed with $40: nonzero and below $80,
;            so read.s/write.s/close.s treat it as a file, and rwcommon can
;            find the slot again from it
;   BUFFER   the file's control block (FCB): a DOS buffer (fmbuf.s); 0 for
;            the console
;

        .export         _open, closedirect, freebuffer
        .export         __filetype, __auxtype, __datetime
        .destructor     closeallfiles, 5

        .import         addysp, popax
        .forceimport    rwfile          ; Files opened here are read and written there

        .macpack        longbranch

        .include        "zeropage.inc"
        .include        "errno.inc"
        .include        "fcntl.inc"
        .include        "filedes.inc"
        .include        "fm.inc"

REF_FLAG = $40

        .code

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
        iny
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
        ldx     #$01            ; Don't allocate
        jsr     fmopen
        bcc     exists
        cmp     #DOSERR_NOTFOUND
        bne     jerrfreefm
        lda     #EINVAL         ; Can't create it
        jmp     errfreedirect
:       sta     type
        ldx     #$00            ; Allocate the file if it isn't found
        beq     doopen          ; Branch always
old:    ldx     #$01
doopen: jsr     fmopen
        bcc     exists

        ; "File not found" with X=0 means DOS allocated it, and it's open
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
opened: ldy     #FM_TYPE
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

; ------------------------------------------------------------------------
; truncate: replace an open, existing file with an empty one of the same
; type (the File Manager can't shorten a file). B files keep their load
; address. Returns carry clear with the new file open and positioned at
; the start, or sets errno, frees the slot and returns carry set.

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
        ldx     #$00
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

; ------------------------------------------------------------------------
; fmopen: OPEN with the name fields set, variable-length records and
; "type" as the type for a new file. X as for fm_call.

fmopen: lda     type
        jmp     fm_open

; rewind: POSITION to the start of the file.

rewind: lda     #$00
        tax
        jmp     fm_position

; setname: set the name fields from the saved name.

setname:
        lda     name
        ldx     name+1
        jmp     fm_name

; hdrsize: set up fm_rangeio for the hidden header: its last HDRLEN bytes
; of hdrbuf. Returns Z set if the file has no hidden header.

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

; classify: set KIND, HDRLEN and LENOFS for File Manager type A.
;   T:        text codec, no header
;   B:        4-byte header (load address, length), length at offset 2
;   I, A:     2-byte header (length), length at offset 0
;   others:   raw, no header

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

; ------------------------------------------------------------------------
; closedirect: close the file in fdtab slot Y (A = REF_NUM, unused).
; Rewrites the hidden header's length if it changed. Preserves Y.
; Returns carry clear, or carry set with an __oserror value in A.

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

; freebuffer: release the control block of fdtab slot Y, if it has one
; (the console has none).

freebuffer:
        jsr     fm_fdfcb
        beq     :+
        jmp     fm_freefcb
:       rts

; closeallfiles: close all open files at exit, so that buffered sectors
; and header lengths reach the disk, and release their DOS buffers.

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

CREATED   = 1
TRUNCATED = 2

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

flags:          .res    1
name:           .res    2
slot:           .res    1
type:           .res    1
created:        .res    1
errcode:        .res    1
hdrbuf:         .res    4
cslot:          .res    1
cerr:           .res    1
