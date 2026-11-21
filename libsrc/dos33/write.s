;
; Oliver Schmidt, 12.01.2005
; Scott Babcock, 2026-11-12
;
; int __fastcall__ write (int fd, const void* buf, unsigned count);
;
; DOS 3.3 version of libsrc/apple2/write.s from cc65. The O_APPEND path,
; which issued ProDOS MLI calls, is gone: rwfile.s moves to the end of the
; file (seekend.s). The device path leaves its count in rw_count
; (rwcommon.s), not in ProDOS's parameter block, and counts its passes
; through the low byte first: stock's loop wrote 256 characters too many
; for a count that is a nonzero multiple of 256 (DESIGN.md 10.28).
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

