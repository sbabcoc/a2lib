;
; Videx VideoTerm backend for the cc65 apple2 target (DESIGN.md 3.4)
;
; Firmware 2.4 facts are from the ROM (CRC32 4DDBE669, identical in code to
; BBE3BB28) and ReplicApple2Plus's HARDWARE-REFERENCE.md section 3. The
; card must be in slot 3 (firmware 2.4).
;

; Slot 3 ROM page: Pascal 1.1 signature and entry points
VT_ID0          := $C305        ; $38
VT_ID1          := $C307        ; $18
VT_ID2          := $C30B        ; $01 (Pascal 1.1 firmware)
VT_ID3          := $C30C        ; $82 (80-column card, VideoTerm)
VT_INIT         := $C311        ; Pascal INIT: JMP $C800
VT_WRITE        := $C31C        ; Pascal WRITE: JSR $C9A7, character in A

; Firmware variables (screen holes, slot 3)
VT_BASEL        := $047B        ; VRAM address of the cursor's line (low)
VT_BASEH        := $04FB        ; ... (high)
VT_CHORZ        := $057B        ; Cursor column (80 = wrap pending)
VT_CVERT        := $05FB        ; Cursor row
VT_POFF         := $077B        ; Power-on marker ($30 in bits 3-7 = set up)

; Card I/O (device select, slot 3)
VT_CRTCREG      := $C0B0        ; CRTC register index; read $C0B0 + 4 * n
                                ; selects VRAM page n into $CC00-$CDFF
VT_CRTCDATA     := $C0B1        ; CRTC register data
VT_WINDOW       := $CC00        ; 512-byte VRAM window
VT_AN0OFF       := $C058        ; Annunciator 0: 40-column display
CLRROM          := $CFFF        ; Turns off all cards' $C800 ROMs

; CRTC R10 (cursor start and mode): bits 6-5 = 01 hidden, 11 blinking
R10_HIDDEN      = $20
R10_BLINK       = $E0           ; The firmware's own setting

VT_COLS         = 80
VT_ROWS         = 24

; Monitor and DOS
CSWL            := $36          ; Output hook
DOS_CSW         := $AA53        ; 48K DOS 3.3: saved true output hook

        .global         vt_active, vt_write, vt_goto, vt_r10, vt_screen
