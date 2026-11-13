;
; void __fastcall__ mon_cout (char c);
; unsigned csw (void);          Current output hook ($36)
; unsigned dos_csw (void);      DOS 3.3's saved true output hook ($AA53)
;
; For test/cswtest.c: write a character through the monitor's COUT
; ($FDED), which goes through CSW, unlike cc65's own console output.
;

        .export         _mon_cout, _csw, _dos_csw

        .segment        "LOWCODE"

_mon_cout:
        ora     #$80
        bit     $C082           ; ROM
        jsr     $FDED           ; COUT, through CSW
        bit     $C080           ; LC bank 2, read only
        rts

        .code

_csw:   lda     $36
        ldx     $37
        rts

_dos_csw:
        lda     $AA53
        ldx     $AA54
        rts
