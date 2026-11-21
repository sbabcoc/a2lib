;
; void cout_count_start (void);
; unsigned cout_count_stop (void);
;
; For test/filetest.c: count the characters console output sends through
; CSW ($36), the output hook the monitor's COUT jumps through, without
; showing them. cout_count_start points CSW at the counter; cout_count_stop
; puts the previous hook back and returns the count.
;

        .export         _cout_count_start, _cout_count_stop

        .code

_cout_count_start:
        lda     #$00
        sta     count
        sta     count+1
        lda     $36
        sta     saved
        lda     $37
        sta     saved+1
        lda     #<counter
        sta     $36
        lda     #>counter
        sta     $37
        rts

_cout_count_stop:
        lda     saved
        sta     $36
        lda     saved+1
        sta     $37
        lda     count
        ldx     count+1
        rts

; The hook: count the character; A, X and Y are left alone
counter:
        inc     count
        bne     :+
        inc     count+1
:       rts

        .bss

count:  .res    2
saved:  .res    2
