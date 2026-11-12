;
; DOS 3.3 file I/O for the cc65 apple2 target
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
;   BUFFER   the file's control block (FCB), from malloc()
;

        .export         _open, closedirect, freebuffer
        .export         __filetype, __auxtype, __datetime
        .destructor     closeallfiles, 5

        .import         __dos_type
        .import         _malloc, _free
        .import         addysp, popax

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

        ; Under ProDOS the page 3 vectors aren't the File Manager
        lda     __dos_type
        beq     :+
        lda     #ENOSYS
        jmp     ___directerrno

        ; Find a free fdtab slot
:       ldy     #$00
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

        ; Allocate the control block
        lda     #<.sizeof(FCB)
        ldx     #>.sizeof(FCB)
        jsr     _malloc
        sta     ptr4
        stx     ptr4+1
        ora     ptr4+1
        bne     :+
        lda     #ENOMEM
        jmp     ___directerrno

:       ldy     slot
        lda     ptr4
        sta     fdtab + FD::BUFFER,y
        lda     ptr4+1
        sta     fdtab + FD::BUFFER+1,y

        ; Clear the control block's own fields (everything before WORK)
        lda     #$00
        sta     created
        ldy     #FCB::WORK - 1
:       sta     (ptr4),y
        dey
        bpl     :-

        jsr     fm_begin
        jsr     setname
        bcc     :+
        jmp     errfree

:
        ; Choose the File Manager type for a new file from _filetype
        lda     flags
        and     #O_CREAT
        beq     old
        ldx     #NTYPES - 1
:       lda     __filetype
        cmp     ptypes,x
        beq     :+
        dex
        bpl     :-
        lda     #EINVAL         ; No DOS 3.3 equivalent
        jmp     errfreedirect
:       lda     ftypes,x
        sta     type
        ldx     #$00            ; Allocate the file if it isn't found
        beq     doopen          ; Branch always
old:    ldx     #$01
doopen: jsr     fmopen
        bcc     exists

        ; "File not found" with X=0 means DOS allocated it, and it's open
        cmp     #FMR_NOTFOUND
        bne     jerrfreefm
        lda     flags
        and     #O_CREAT
        beq     :+
        inc     created
        bne     opened          ; Branch always
:       lda     #FMR_NOTFOUND
jerrfreefm:
        jmp     errfreefm

exists: lda     flags
        and     #O_CREAT | O_EXCL
        cmp     #O_CREAT | O_EXCL
        bne     opened
        lda     #$47            ; ProDOS "Duplicate filename" -> EEXIST
        jmp     errclose

        ; Set up the control block from the type of the file opened
opened: ldy     #FM_TYPE
        lda     (ptr3),y
        ldy     #FCB::TYPE      ; Keep the lock bit for stat
        sta     (ptr4),y
        and     #$7F            ; Lock bit
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
        cmp     #FMR_ENDDATA    ; Empty file: header written on close
        bne     errclosefm
        lda     #$00            ; No load address
        sta     hdrbuf
        sta     hdrbuf+1
        ldy     #FCB::STATE
        lda     #FCBS_DIRTY
        sta     (ptr4),y
        bne     done            ; Branch always (LEN stays 0)
:       ldy     #FCB::LEN
        lda     hdrbuf+2
        sta     (ptr4),y
        iny
        lda     hdrbuf+3
        sta     (ptr4),y
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
        lda     (ptr4),y
        cmp     #4
        bne     :+
        ldy     #FCB::ADDR
        lda     hdrbuf
        sta     (ptr4),y
        iny
        lda     hdrbuf+1
        sta     (ptr4),y

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
errclose:                       ; A = ProDOS code, file open
        sta     errcode
        lda     #FMC_CLOSE
        jsr     fm_simple
        lda     errcode
        bne     errfree         ; Branch always
errfreefm:                      ; A = File Manager code, file not open
        jsr     fm_maperr
errfree:                        ; A = ProDOS code, file not open
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
        cmp     #FMR_NOTFOUND   ; Allocated
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

fmopen: lda     #$00
        ldy     #FM_RECORD
        sta     (ptr3),y
        iny
        sta     (ptr3),y
        ldy     #FM_TYPE
        lda     type
        sta     (ptr3),y
        ldy     #FM_CALL
        lda     #FMC_OPEN
        sta     (ptr3),y
        jmp     fm_call

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
        lda     (ptr4),y
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
        sta     (ptr4),y
        txa
        ldy     #FCB::HDRLEN
        sta     (ptr4),y
        rts
text:   lda     #FCB_TEXT
        ldy     #FCB::KIND
        sta     (ptr4),y
        rts

; ------------------------------------------------------------------------
; closedirect: close the file in fdtab slot Y (A = REF_NUM, unused).
; Rewrites the hidden header's length if it changed. Preserves Y.
; Returns carry clear, or carry set with a ProDOS error code in A.

closedirect:
        sty     cslot
        lda     fdtab + FD::BUFFER,y
        sta     ptr4
        lda     fdtab + FD::BUFFER+1,y
        sta     ptr4+1
        jsr     fm_begin
        lda     #$00
        sta     cerr

        ldy     #FCB::STATE
        lda     (ptr4),y
        and     #FCBS_DIRTY
        beq     cclose
        ldy     #FCB::LENOFS
        lda     (ptr4),y
        ldx     #$00
        jsr     fm_position
        bcs     cfail
        clc
        lda     ptr4
        adc     #<FCB::LEN
        sta     fm_rio_addr
        lda     ptr4+1
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

; freebuffer: free the control block of fdtab slot Y.

freebuffer:
        lda     fdtab + FD::BUFFER,y
        ldx     fdtab + FD::BUFFER+1,y
        jmp     _free

; closeallfiles: close all open files at exit, so that buffered sectors
; and header lengths reach the disk.

closeallfiles:
        ldy     #$00
:       lda     fdtab + FD::REF_NUM,y
        beq     :+
        bmi     :+              ; Device
        jsr     closedirect     ; Preserves Y
:       iny
        iny
        iny
        iny
        cpy     #MAX_FDS * .sizeof(FD)
        bcc     :--
        rts

; ------------------------------------------------------------------------

CREATED   = 1
TRUNCATED = 2

        .rodata

; _filetype (ProDOS codes) -> File Manager type for new files
ptypes: .byte   $04             ; TXT
        .byte   $06             ; BIN
        .byte   $FC             ; BAS
        .byte   $FA             ; INT
        .byte   $FE             ; REL
NTYPES = * - ptypes
ftypes: .byte   FMT_TEXT
        .byte   FMT_BINARY
        .byte   FMT_APPLESOFT
        .byte   FMT_INTEGER
        .byte   FMT_RELOC

        .data

__filetype:
        .byte   $06             ; Default: binary file, as in stock cc65
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
