;
; Apple II and DOS 3.3 addresses and values the library uses, beside cc65's
; apple2.inc, which its modules also include. The File Manager's definitions
; include it, so every file module has them.
;

.ifndef MACHINE_INC
MACHINE_INC = 1

; Language card soft switches ("Apple II Reference Manual"), each named for
; what it does to reads and to writes. cc65 runs with bank 2 enabled for
; reading; the File Manager, RWTS and the monitor need ROM. A switch that
; write-enables RAM must be read twice. These take the place of
; apple2.inc's ROMIN and LCBANK2, whose names don't say that both
; write-enable RAM.
LC_BANK2_RO     := $C080        ; Read bank 2 RAM; RAM write-protected
LC_ROM_WRAM     := $C081        ; Read ROM; write bank 2 RAM (read twice)
LC_ROM_RO       := $C082        ; Read ROM; RAM write-protected
LC_BANK2_RW     := $C083        ; Read and write bank 2 RAM (read twice)

; Monitor and DOS entry points
MON_COUT        := $FDED        ; COUT: through CSW, so through DOS's intercept
MON_RDKEY       := $FD0C        ; RDKEY: through KSW, so through DOS's intercept
DOS_CONNECT     := $03EA        ; Reconnect DOS's I/O intercepts (page 3 vector)

; Applesoft's pointers for BLTU2, the block move crt0 copies the LC
; segment with
HIGHDS          := $94          ; One past the destination's last byte
HIGHTR          := $96          ; One past the source's last byte
LOWTR           := $9B          ; The source's first byte

; Pages exec() uses after the C library has shut down
STACK_PAGE      := $0100        ; Hardware stack page: exec()'s saved cmdline
BASIC_BUF       := $0200        ; GETLN's buffer: where DOS collects a command

; Characters as the monitor and DOS use them: high bit set
HI_CTRL_D       = $84           ; Starts a DOS command in output
HI_BS           = $88           ; Backspace
HI_LF           = $8A           ; Line feed
HI_CR           = $8D           ; Carriage return
HI_SPACE        = $A0           ; Space; DOS pads names with it
HIBIT_OFF       = $7F           ; AND mask: high-bit character to plain ASCII

.endif
