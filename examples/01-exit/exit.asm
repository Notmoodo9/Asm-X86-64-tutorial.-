; =============================================================================
; Lesson 01 - the smallest useful Windows x64 program
;
; It does exactly one thing: ends the process with exit code 42.
; No include files, no macros: everything the .exe needs is written here.
;
; Build:   fasm exit.asm
; Run:     exit.exe  &  echo %ERRORLEVEL%      (prints 42)
; Debug:   windbgx exit.exe
; =============================================================================

format PE64 console             ; produce a 64-bit Windows console executable
entry start                     ; execution begins at the label 'start'

; -----------------------------------------------------------------------------
; Code
; -----------------------------------------------------------------------------
section '.text' code readable executable

start:
        sub     rsp, 40         ; reserve stack space for the call below
                                ; (lesson 05 explains why exactly 40)
        mov     ecx, 42         ; 1st argument goes in RCX: the exit code
        call    [ExitProcess]   ; call through the import table -> never returns

; -----------------------------------------------------------------------------
; Import table: tells the Windows loader "this program needs ExitProcess from
; KERNEL32.DLL - please fill in its address before I start".
; -----------------------------------------------------------------------------
section '.idata' import data readable writeable

        ; One IMAGE_IMPORT_DESCRIPTOR (5 dwords) per DLL, then an all-zero one.
        ;   OriginalFirstThunk, TimeDateStamp, ForwarderChain, Name, FirstThunk
        dd      0, 0, 0, RVA kernel_name, RVA kernel_table
        dd      0, 0, 0, 0, 0

kernel_table:                   ; the Import Address Table (IAT) for KERNEL32
        ; Before the program runs, this qword holds the RVA of a hint/name
        ; entry. The loader overwrites it with the real address of the function.
        ExitProcess     dq RVA _ExitProcess
                        dq 0    ; end of this DLL's list

kernel_name     db 'KERNEL32.DLL', 0

        align 2
_ExitProcess    dw 0            ; "hint": an index guess, 0 is fine
                db 'ExitProcess', 0
