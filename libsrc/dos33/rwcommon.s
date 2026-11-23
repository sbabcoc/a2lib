;
; Scott Babcock, 2026-11-12
;
; Replaces libsrc/apple2/rwcommon.s from cc65 and exports the same symbols,
; for the stock read.s and for write.s:
;   rwprolog  pop fd and buf, save count (count) and buf (ptr1), getfd
;   rwcommon  transfer to or from a file: a JMP to rwfile (rwfile.s), set
;             by its constructor when a program opens files; a program
;             that doesn't has no file to pass here
;   rwepilog  return rw_count, the bytes transferred, with __oserror = A
;             (0)
;

        .export         rwprolog, rwcommon, rwepilog, rw_count
        .import         popax, popptr1

        .include        "zeropage.inc"
        .include        "errno.inc"
        .include        "filedes.inc"

; Shared storage
count           = ptr2          ; unsigned: the bytes asked for

        .code

rwprolog:
        ; Save count
        sta     count
        stx     count+1

        ; Get and save buf
        jsr     popptr1

        ; Get and process fd
        jsr     popax
        jmp     getfd           ; Returns A, Y and C

rwepilog:
        ; Return success
        sta     ___oserror      ; A = 0
        lda     rw_count
        ldx     rw_count+1
        rts

nofile: lda     #EINVAL
        jmp     ___directerrno

        .data

rwcommon:
        jmp     nofile          ; Patched to rwfile

        .bss

rw_count:
        .res    2
