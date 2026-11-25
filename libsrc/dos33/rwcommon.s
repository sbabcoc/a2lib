;
; Scott Babcock, 2026-11-12
;
; Replaces libsrc/apple2/rwcommon.s from cc65 and exports the same symbols,
; for the stock read.s and for write.s. The file code is in rwfile.s, which
; only programs that open files link.
;

        .export         rwprolog, rwcommon, rwepilog, rw_count
        .import         popax, popptr1

        .include        "zeropage.inc"
        .include        "errno.inc"
        .include        "filedes.inc"

; Shared storage
count           = ptr2          ; unsigned: the bytes asked for

        .code

;-----------------------------------------------------------------------------
; rwprolog: Take read()'s or write()'s arguments: int __fastcall__ read (int
; fd, void* buf, unsigned count), and write's.
;
; Prepare:      open(), for a file; the console's descriptors (0-2) are open
;               from the start
; Input:        C stack       int       fd
;               C stack       void*     buf
;               AX            unsigned  count
; Output:       ptr1          byte*     buf (rwfile's buffer)
;               count         unsigned  count
;               C             flag      set: fd isn't open (getfd)
;               A             byte      if C set: the errno code (EBADF); else
;                                       fdtab's REF_NUM
;               Y             byte      if C clear: the fdtab slot's offset
; Changes:      X. Pops fd and buf.

rwprolog:
        ; Save count
        sta     count
        stx     count+1

        ; Get and save buf
        jsr     popptr1

        ; Get and process fd
        jsr     popax
        jmp     getfd           ; Returns A, Y and C

;-----------------------------------------------------------------------------
; rwepilog: Return the number of bytes transferred, from read() or write().
;
; Prepare:      rwprolog, then the transfer (rwfile), which sets rw_count
; Input:        A             byte      the __oserror value (0)
;               rw_count      unsigned  the bytes transferred
; Output:       AX            int       rw_count
;               __oserror     byte      A
; Changes:      Y is unchanged.

rwepilog:
        ; Return success
        sta     ___oserror      ; A = 0
        lda     rw_count
        ldx     rw_count+1
        rts

;-----------------------------------------------------------------------------
; nofile: Fail a transfer that rwcommon got before any file was opened.
;
; Input:        none
; Output:       AX            int       -1
;               errno         int       EINVAL
; Changes:      As ___directerrno.

nofile: lda     #EINVAL
        jmp     ___directerrno

        .data

;-----------------------------------------------------------------------------
; rwcommon: Read or write an open file: a JMP to rwfile (rwfile.s), which
; its constructor sets. A program that opens no file has no file to pass
; here; until then it fails with EINVAL.
;
; Input:        as rwfile
; Output:       as rwfile
; Changes:      as rwfile

rwcommon:
        jmp     nofile          ; Patched to rwfile

        .bss

rw_count:
        .res    2               ; unsigned: bytes transferred (rwepilog)
