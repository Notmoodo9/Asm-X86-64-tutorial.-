# FASM cheat-sheet

Targets FASM 1.73 with the `win64a.inc` package.

## File skeleton

```asm
format PE64 console             ; or: format PE64 GUI 5.0   /   format PE64 DLL
entry start
include 'win64a.inc'

section '.text' code readable executable
start:
        sub     rsp, 8          ; align the stack once
        ...
        invoke  ExitProcess, 0

section '.data' data readable writeable
        ...

section '.idata' import data readable writeable
        library kernel32, 'KERNEL32.DLL', user32, 'USER32.DLL'
        include 'api\kernel32.inc'
        include 'api\user32.inc'
```

Command line: `fasm prog.asm` → `prog.exe`. Options: `fasm prog.asm out.exe`,
`-d NAME=value` (define a constant), `-s prog.fas` (symbol file for the
`LISTING`/`PREPSRC` tools), `-m 262144` (more memory).

## Numbers and strings

| Syntax | Meaning |
|--------|---------|
| `123` | decimal |
| `7Bh`, `0x7B`, `$7B` | hex (with `h`, must start with a digit: `0FFh`) |
| `1111011b` | binary |
| `173o` | octal |
| `'A'`, `'text'` | character / string (single or double quotes) |
| `1.5` | float (in `dd`/`dq` data) |

## Data

| Directive | Size | Reserve |
|-----------|------|---------|
| `db` | 1 | `rb n` |
| `dw` | 2 | `rw n` |
| `du` | 2 per char (UTF-16 string) | |
| `dd` | 4 | `rd n` |
| `dq` | 8 | `rq n` |
| `dt` | 10 | `rt n` |

```asm
msg     db 'Hello', 13, 10, 0
len     = $ - msg                ; $ = current address
table   dd 1, 2, 3
        times 16 db 0            ; repeat
        align 8                  ; pad to multiple of 8
        file 'image.bin'         ; include a binary file
```

## Labels and constants

```asm
name:                ; label (no size)
name    dq 0         ; label with size (qword)
label   name qword at rsp+8      ; label at an arbitrary address/expression
.local:              ; local to the previous global label (full name: name.local)
@@:                  ; anonymous; jump with @b (back) / @f (forward)
X = 10               ; numeric constant (can be redefined, forward-referenced)
Y equ rax            ; symbolic constant (text substitution)
```

## Size overrides

```asm
mov     al, byte [x]
mov     word [x], 5
inc     dword [rbx]
mov     qword [rsp + 32], 0
```

Needed whenever the size can't be inferred from a register or a sized label.

## Addressing

```asm
[rax]  [rax + 8]  [rax + rcx*4]  [rax + rcx*8 + 16]  [label]
```

`[label]` is RIP-relative in 64-bit code. `[label + rcx*4]` is *not*
possible RIP-relative — use `lea rdx, [label]` then `[rdx + rcx*4]`.

## Conditional assembly and repetition

```asm
if DEBUG
        int3
else if VERBOSE > 1
        ...
end if

if defined NAME          ; / if used NAME / if ~ defined NAME
repeat 8
        db %             ; % = 1..8
end repeat
```

## Macros

```asm
macro checkpoint {
        int3
}

macro print_twice text {         ; parameters
        fastcall print_z, text
        fastcall print_z, text
}

macro push_all [reg] {           ; [ ] = variable number of args
  forward
        push reg
}
```

Inside a macro `local name` makes a unique label per expansion. `struc` is like
`macro` but invoked with a label: `point POINT`.

## Structures (`win64a.inc`'s `struct`)

```asm
struct VEC3
  x dd ?
  y dd ?
  z dd ?
ends

pos     VEC3 1, 2, 3                 ; instance in data
        mov     eax, [pos.y]
        mov     eax, [rbx + VEC3.y]   ; field offset (4)
        mov     ecx, sizeof.VEC3      ; 12
```

## Windows macros

| Macro | Meaning |
|-------|---------|
| `invoke f, a, b, ...` | `fastcall [f], ...` — call an imported function |
| `fastcall f, a, b, ...` | call `f` directly with the x64 convention |
| `addr x` | pass the address of a local (`lea`) |
| `proc name uses rbx rsi, p1, p2` ... `endp` | function with prologue/epilogue |
| `locals` ... `endl` / `local x:QWORD` | stack locals inside a proc |
| `ret` (inside proc) | epilogue + return |
| `frame` ... `endf` | allocate shadow space once for several calls |
| `library dll, 'NAME.DLL', ...` | import descriptors |
| `import dll, label, 'Name', ...` | import entries |
| `api\*.inc` | ready-made import lists (kernel32, user32, gdi32, advapi32, comctl32, comdlg32, shell32, wsock32) |

Remember:
* args 1–4 are loaded into `rcx, rdx, r8, r9` **in order** — don't pass
  `rdx` as arg 1 and `rcx` as arg 2.
* avoid `rax` as argument 5+ (may be used as a temporary).
* proc parameters 1–4 are **not** auto-stored: `mov [p1], rcx`.

## Common errors

| Message | Usual cause |
|---------|-------------|
| `undefined symbol 'X'` | typo, missing include, or the constant isn't in FASM's equates — define it yourself (`X = value`, look it up on Microsoft Learn) |
| `operand sizes do not match` | e.g. `mov al, [qword_var]` — add `byte` |
| `operand size not specified` | e.g. `mov [rbx], 5` — add `qword`/`dword`... |
| `invalid address` / `value out of range` | addressing form not encodable (RIP-relative + index), or immediate too large (only `mov reg, imm64` takes 64-bit immediates) |
| `symbol already defined` | duplicate label; use local `.labels` |
| `file not found` | `INCLUDE` environment variable not set, or wrong relative path |
| `illegal instruction` | misspelt mnemonic, or a macro used without including `win64a.inc` |
