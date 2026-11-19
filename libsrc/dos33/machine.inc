;
; Apple II and DOS 3.3 addresses and values used by a2lib's modules,
; beside cc65's apple2.inc (which they also include). Included by fm.inc,
; so every File Manager module has them.
;

.ifndef MACHINE_INC
MACHINE_INC = 1

; Language card soft switches ("Apple II Reference Manual"). cc65 runs with
; bank 2 enabled for reading; the File Manager, RWTS and the monitor need
; ROM. apple2.inc names $C081 (ROMIN) and $C083 (LCBANK2), not these.
LC_ROM_RO       := $C082        ; Read ROM; RAM write-protected
LC_BANK2_RO     := $C080        ; Read bank 2 RAM; write-protected

; Monitor and DOS entry points
MON_COUT        := $FDED        ; COUT: through CSW, so through DOS's intercept
DOS_CONNECT     := $03EA        ; Reconnect DOS's I/O intercepts (page 3 vector)

; Pages exec() uses after the C library has shut down
STACK_PAGE      := $0100        ; Hardware stack page: exec()'s saved cmdline
BASIC_BUF       := $0200        ; GETLN's buffer: where DOS collects a command

; Characters as the monitor and DOS use them: high bit set
HI_CTRL_D       = $84           ; Starts a DOS command in output
HI_BS           = $88           ; Backspace
HI_CR           = $8D           ; Carriage return
HI_SPACE        = $A0           ; Space; DOS pads names with it
HIBIT_OFF       = $7F           ; AND mask: high-bit character to plain ASCII

.endif
