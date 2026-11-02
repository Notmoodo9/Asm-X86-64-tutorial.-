# 01 — Your first program (and your first debugging session)

Source: [`examples/01-exit/exit.asm`](../examples/01-exit/exit.asm)

## The program

Here's the whole thing, minus comments:

```asm
format PE64 console
entry start

section '.text' code readable executable
start:
        sub     rsp, 40
        mov     ecx, 42
        call    [ExitProcess]

section '.idata' import data readable writeable
        dd      0, 0, 0, RVA kernel_name, RVA kernel_table
        dd      0, 0, 0, 0, 0
kernel_table:
        ExitProcess     dq RVA _ExitProcess
                        dq 0
kernel_name     db 'KERNEL32.DLL', 0
        align 2
_ExitProcess    dw 0
                db 'ExitProcess', 0
```

Assemble and run it:

```bat
cd examples\01-exit
fasm exit.asm
exit.exe
echo %ERRORLEVEL%
```

Output: `42`. You just wrote a Windows program with no compiler, no linker and
no runtime library. Let's understand every line.

## Line by line

### `format PE64 console`

FASM is unusual: it's an assembler *and* a linker. This directive says "the
output file is a 64-bit **P**ortable **E**xecutable" — the `.exe` format
Windows uses. `console` sets the *subsystem*: Windows will give the program a
console window. (Later we'll use `GUI` for windowed programs.)

### `entry start`

Which address the program starts executing at. `start` is a **label** — a
name for an address, defined further down with `start:`.

### `section '.text' code readable executable`

A PE file is split into sections; each is loaded into memory with its own
permissions. The name `.text` is traditional for code. The flags say: this
contains code, and the memory may be read and executed (but not written).

### The three instructions

```asm
sub     rsp, 40         ; rsp = rsp - 40
mov     ecx, 42         ; ecx = 42
call    [ExitProcess]   ; call the function whose address is stored at ExitProcess
```

* `rsp` is the **stack pointer**. Subtracting from it reserves stack space.
  Windows functions require the caller to reserve some — lesson 05 covers the
  rules. For now: before calling a Windows function, do this.
* `ecx` is the low 32 bits of the register `rcx`. In the Windows x64 calling
  convention, **the first argument is passed in `rcx`**. `ExitProcess` takes
  one argument: the exit code. (Writing `ecx` also zeroes the top half of
  `rcx` — more on that in lesson 02.)
* `call [ExitProcess]` — note the brackets. `ExitProcess` is a label in our
  import table where Windows has stored the real address of the function.
  Brackets mean "the value **at** that address". So this is an *indirect*
  call: read 8 bytes at `ExitProcess`, jump there.

### The import table

Your program can't know where `KERNEL32.DLL` will be in memory, so it asks the
Windows loader to fill in addresses. The `.idata` section is that request:

```
Import descriptor ──► Name: "KERNEL32.DLL"
                  └─► FirstThunk (IAT): kernel_table
                                        ├─ ExitProcess: RVA of {hint 0, "ExitProcess"}
                                        └─ 0 (end)
```

* `RVA x` = *relative virtual address*: the offset of `x` from the start of
  the loaded image. PE files use RVAs everywhere.
* At load time Windows walks the descriptor, loads KERNEL32.DLL, looks up
  `"ExitProcess"` and **overwrites** the qword at label `ExitProcess` with the
  function's real address.

From lesson 03 on, FASM's `library`/`import` macros write this table for us.
Now you know what they generate.

## Your first WinDbg session

```bat
windbgx exit.exe
```

WinDbg launches the program and stops almost immediately. The Command window
shows something like:

```
ModLoad: 00000000`00400000 00000000`00404000   exit.exe
ModLoad: 00007ffb`8e5b0000 00007ffb`8e7c8000   ntdll.dll
...
(1a2c.2f10): Break instruction exception - code 80000003 (first chance)
ntdll!LdrpDoDebuggerBreak+0x30:
00007ffb`8e68b8a4 cc              int     3
```

This is the **initial breakpoint**: the loader stops *before* your code runs
so you can set things up. Notice `exit.exe` loaded at `0x400000`.

### 1. Break at your entry point

```
bp $exentry
g
```

`$exentry` is a WinDbg pseudo-register holding the entry point address.
`bp` sets a breakpoint, `g` goes. You stop at:

```
Breakpoint 0 hit
exit+0x1000:
00000000`00401000 4883ec28        sub     rsp,28h
```

Read that line: address `0x401000`, raw bytes `48 83 ec 28`, instruction
`sub rsp,28h` (WinDbg shows hex — `28h` = 40).

### 2. Look at the code

```
u $exentry L3
```

`u` = unassemble, `L3` = three instructions:

```
00000000`00401000 4883ec28        sub     rsp,28h
00000000`00401004 b92a000000      mov     ecx,2Ah
00000000`00401009 ff1519100000    call    qword ptr [exit+0x2028 (00000000`00402028)]
```

The call reads its target from `0x402028` — our `ExitProcess` slot in the
import table. (The `.idata` section starts at `0x402000`; the IAT comes after
the two 20-byte import descriptors, i.e. at offset `0x28`.) What's there now?

```
dq 402028 L1
ln poi(402028)
```

* `dq` dumps quadwords (8-byte values). You'll see an address like
  `00007ffb`8d2b5e70`, not the small RVA we wrote — the loader already
  patched it.
* `poi(x)` reads the pointer at x. `ln` ("list nearest") names the symbol at
  an address: `KERNEL32!ExitProcessImplementation`. That's the import table
  doing its job.

### 3. Step and watch registers

```
r rsp
p
r rsp
```

`r` prints registers (`r rsp` just that one). `p` executes one instruction.
`rsp` dropped by `0x28`. Step again and check `rcx`:

```
p
r rcx
```

`rcx=000000000000002a`. 0x2a = 42. Convert numbers anytime with `?`:

```
? 2a
```

```
Evaluate expression: 42 = 00000000`0000002a
```

### 4. Change the future

Before the `call` executes, change the exit code:

```
r rcx=7
g
```

The process exits. WinDbg prints the exit code in the command window
(`ExitProcess` ... `exit code 7` / `Process exited`). You just patched a running
program's state. Close WinDbg, run `exit.exe` normally again, and it's back to
42 — nothing on disk changed.

### 5. Look at the file's structure

Run `windbgx exit.exe` again, and at the initial breakpoint:

```
lm
!dh exit
```

* `lm` lists loaded modules (exe + DLLs) and their address ranges.
* `!dh` dumps PE headers: you'll find the entry point RVA (`1000`), the
  sections `.text` and `.idata`, and the "Import Address Table Directory".
  Match these against the source.

## Exercises

1. Change the exit code to `-1`. What does `%ERRORLEVEL%` print? Why does
   `mov ecx, -1` give `rcx = 00000000ffffffff` in WinDbg?
2. Remove the `sub rsp, 40` and run it. It *probably* still works — but it's
   now breaking the rules, and lesson 05 will show you a case where it crashes.
3. Add a second import: `GetTickCount` from KERNEL32 (no arguments, returns a
   32-bit number in `eax`). Call it, then `mov ecx, eax` before
   `ExitProcess`. Hint: add a new `dq RVA _GetTickCount` line *before* the
   terminating `dq 0`, and a new hint/name entry. Run it a few times — the exit
   code changes.
4. In WinDbg, set a breakpoint directly on the Windows function:
   `bp kernel32!ExitProcess` then `g`. When it hits, type `k` to see the call
   stack — your program's address is in there.

Next: [02 — Registers, arithmetic and flags](02-registers.md)
