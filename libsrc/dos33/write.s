;
; Oliver Schmidt, 12.01.2005
; Scott Babcock, 2026-11-12
;
; write() for files and the console, as cc65's without its ProDOS O_APPEND
; path: a file opened with O_APPEND moves to its end first. The console's loop
; counts the low byte first, so a count that is a nonzero multiple of 256 no
; longer writes 256 characters too many, as cc65's did. For details, see
; record 10.28 of DESIGN.
;

        .export         _write
        .import         rwprolog, rwcommon, rwepilog, rw_count
        .import         COUT
        .ifndef __APPLE2ENH__
        .import         uppercasemask
        .endif

        .include        "zeropage.inc"
        .include        "errno.inc"
        .include        "fcntl.inc"
        .include        "mli.inc"
        .include        "filedes.inc"

;-----------------------------------------------------------------------------
; Write to a file or the console. The console gets each byte through COUT,
; '\n' as CR, uppercase on a II+ (uppercasemask).
;
; Signature:    int __fastcall__ write (int fd, const void* buf, unsigned
;               count)
; Overrides:    cc65's write()
; Prepare:      open(), for a file; the console's descriptors (0-2) are open
;               from the start
; Input:        C stack       int       file descriptor, open for writing
;               C stack       void*     the bytes
;               X:A           unsigned  byte count
; Output:       X:A           int       the number of bytes written, or -1
;               errno         int       if -1: EBADF, EINVAL (fd not open for
;                                       writing), or as rwfile sets it
;               __oserror     byte      0, or as rwfile sets it
; Changes:      Y; ptr1 and ptr2; for a file, as rwfile. Pops fd and buf.

_write:
        ; Get parameters
        jsr     rwprolog
        bcs     errno
        tax                     ; Save fd

        ; Check for write access
        lda     fdtab + FD::FLAGS,y
        and     #O_WRONLY
        beq     einval

        ; Check for device
        txa                     ; Restore fd
        bmi     device

        ; Do write
        lda     fdtab + FD::REF_NUM,y
        ldy     #WRITE_CALL
        jmp     rwcommon

        ; Save count for epilog
device: ldx     ptr2
        lda     ptr2+1
        stx     rw_count
        sta     rw_count+1

        ; Check for zero count
        ora     ptr2
        beq     done

        ; Count passes through the low byte: one more if it's nonzero
        cpx     #$01
        lda     ptr2+1
        adc     #$00
        sta     ptr2+1

        ; Get char from buf
        ldy     #$00
next:   lda     (ptr1),y

        ; Replace '\n' with '\r'
        cmp     #$0A
        bne     :+
        lda     #$0D

        ; Set hi bit and write to device
:       ora     #$80
        .ifndef __APPLE2ENH__
        cmp     #$E0            ; Test for lowercase
        bcc     output
        and     uppercasemask
        .endif
output: jsr     COUT            ; Preserves X and Y

        ; Increment pointer
        iny
        bne     :+
        inc     ptr1+1

        ; Decrement count
:       dex
        bne     next
        dec     ptr2+1
        bne     next

        ; Return success
done:   lda     #$00
        jmp     rwepilog

        ; Load errno code
einval: lda     #EINVAL

        ; Set __errno
errno:  jmp     ___directerrno

