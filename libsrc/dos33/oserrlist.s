;
; DOS 3.3 file I/O for the cc65 apple2 target
;
; Defines the platform specific error list: replaces
; libsrc/apple2/oserrlist.s from cc65 (DESIGN.md 5.6). DOS 3.3's own
; messages for its error numbers ("Beneath Apple DOS" ch. 8, $A971), in
; the sentence case of cc65's other lists; then the library's own codes
; (fm.inc).
;
; The table is built as a list of entries
;
;       .byte   entrylen
;       .byte   errorcode
;       .asciiz errormsg
;
; and terminated by an entry with length zero that is returned if the
; error code could not be found.
;

        .export         __sys_oserrlist

        .include        "fm.inc"

;----------------------------------------------------------------------------
; Macros used to generate the list, as in the stock module

; Regular entry
.macro  sys_oserr_entry         code, msg
        .local  Start, End
Start:  .byte   End - Start
        .byte   code
        .asciiz msg
End:
.endmacro

; Sentinel entry
.macro  sys_oserr_sentinel      msg
        .byte   0                       ; Length is always zero
        .byte   0                       ; Code is unused
        .asciiz msg
.endmacro

;----------------------------------------------------------------------------
; The error message table

.rodata

__sys_oserrlist:
        sys_oserr_entry         DOSERR_LANG,      "Language not available"
        sys_oserr_entry         DOSERR_RANGE,     "Range error"
        sys_oserr_entry         DOSERR_SUBRANGE,  "Range error"
        sys_oserr_entry         DOSERR_WPROT,     "Write protected"
        sys_oserr_entry         DOSERR_ENDDATA,   "End of data"
        sys_oserr_entry         DOSERR_NOTFOUND,  "File not found"
        sys_oserr_entry         DOSERR_VOLUME,    "Volume mismatch"
        sys_oserr_entry         DOSERR_IO,        "I/O error"
        sys_oserr_entry         DOSERR_FULL,      "Disk full"
        sys_oserr_entry         DOSERR_LOCKED,    "File locked"
        sys_oserr_entry         DOSERR_SYNTAX,    "Syntax error"
        sys_oserr_entry         DOSERR_NOBUFS,    "No buffers available"
        sys_oserr_entry         DOSERR_TYPE,      "File type mismatch"
        sys_oserr_entry         DOSERR_TOOLARGE,  "Program too large"
        sys_oserr_entry         DOSERR_NOTDIRECT, "Not direct command"
        sys_oserr_entry         LIBERR_EXISTS,    "File exists"
        sys_oserr_entry         LIBERR_OPEN,      "File is open"
        sys_oserr_entry         LIBERR_NODOS,     "Not running under DOS 3.3"
        sys_oserr_entry         LIBERR_NOTDOS,    "Not a DOS 3.3 disk"
        sys_oserr_entry         LIBERR_POSITION,  "Position out of range"
        sys_oserr_entry         LIBERR_NOEND,     "No recorded end of file"
        sys_oserr_sentinel      "Unknown error"
