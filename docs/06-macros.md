# 06 — FASM macros: `invoke`, `proc`, `import`

Source: [`examples/06-macros/hello_macros.asm`](../examples/06-macros/hello_macros.asm)

You now know how to call any Windows function by hand. It's also tedious and
error-prone. FASM ships macros (in `C:\fasm\INCLUDE\MACRO\`) that do the
mechanical parts. This lesson introduces them **and shows what they generate**,
so you can always drop back to the raw form — or debug the expansion.

## `library` and `import`

```asm
section '.idata' import data readable writeable
        library kernel32, 'KERNEL32.DLL', \
                user32,   'USER32.DLL'
        include 'api\kernel32.inc'
        include 'api\user32.inc'
```

`library` writes the import descriptors; `import` writes each DLL's address
table and hint/name entries — exactly what you typed by hand in lesson 01. The
`api\*.inc` files contain one giant `import` for every function in that DLL;
the macro wraps each in `if used ...`, so **only functions you actually
reference end up in the import table**.

They also define convenience aliases: with `win64a.inc`, `MessageBox` means
`MessageBoxA`. This course uses the explicit `A` names so that what you type
matches what you set breakpoints on in WinDbg (`bp user32!MessageBoxA`).

For DLLs FASM doesn't have an `api` file for, you write the `import` yourself
— we'll do this for Winsock in lesson 12:

```asm
        import  ws2_32, \
                WSAStartup, 'WSAStartup', \
                socket,     'socket'
```

The `\` at the end of a line continues it on the next line.

## `invoke` and `fastcall`

```asm
invoke   WriteFile, [hstdout], message, message_len, written, 0   ; call [WriteFile]
fastcall greet, name1, 3                                        ; call greet
```

`invoke f, args` = `fastcall [f], args`. Use `invoke` for imported functions
(called *through* the import table) and `fastcall` for your own labels.

Outside a `proc`, roughly what the first line expands to:

```asm
        sub     rsp, 48                 ; 32 shadow + 2 stack args, rounded to 16
        mov     rcx, [hstdout]
        mov     rdx, message            ; address of message
        mov     r8, message_len
        mov     r9, written             ; address of written
        mov     qword [rsp+32], 0
        call    [WriteFile]
        add     rsp, 48
```

So `invoke` handles shadow space and argument placement **but not your
initial alignment**: you still need the `sub rsp, 8` at the top of `start`
to go from "8 mod 16" to "0 mod 16". Inside a `proc`, the prologue does it.

### Argument forms

| You write | Means |
|-----------|-------|
| `123`, `MB_OK`, `message` | constant / address of a label |
| `[hstdout]` | the value stored at `hstdout` |
| `rax` | a register |
| `addr local_var` | `lea reg, [local_var]` — address of a stack local |

Two traps:

* **Order of evaluation.** Arguments are loaded **into `rcx`, `rdx`, `r8`,
  `r9` in that order.** `fastcall f, rdx, rcx` does `mov rcx, rdx` then
  `mov rdx, rcx` — both end up equal to the original `rdx`! If your arguments
  live in argument registers, shuffle them through other registers first.
  Similarly, avoid passing `rax` as a 5th+ argument — `rax` may be used as a
  temporary to put values on the stack.
* **Size.** Give qword-sized memory arguments (`dq` variables). Passing
  `[some_dword]` may not load what you expect — copy it into a register with
  `mov eax, [some_dword]` first, then pass `rax`.

## `proc` / `endp`

```asm
proc greet uses rbx rsi, pname, times
  locals
        len     dq ?
  endl
        mov     [pname], rcx
        mov     [times], rdx
        ...
        ret
endp
```

* `uses rbx rsi` — pushed in the prologue and popped by every `ret`.
* `pname, times` — names for the **shadow-space slots** `[rbp+16]`,
  `[rbp+24]` (then `[rbp+32]`, `[rbp+40]`). Arguments 5+ are at `[rbp+48]`
  onward, where the caller put them, so their names work immediately. But
  **the first four arrive in `rcx/rdx/r8/r9` and are not stored automatically**
  — `mov [pname], rcx` if you want to use the name.
* `locals ... endl` — stack variables, addressed relative to `rbp`. (A
  single one: `local len:QWORD`.)
* `ret` inside a proc is a macro that emits the epilogue (`pop`s, `leave`,
  `ret`). You may have several `ret`s.
* Local labels (`.strlen`) belong to the proc's name.
* A `proc` is only assembled if something references it (`if used`). Handy
  for libraries; confusing when you expect to see an unused one in WinDbg.

The generated prologue is the same shape as lesson 05's `print_number`:

```asm
        push    rbp
        mov     rbp, rsp
        sub     rsp, <locals, rounded up to keep alignment>
        push    rbx
        push    rsi
```

## See the expansion in WinDbg

Macros are text; the CPU only sees instructions. Look:

```bat
cd examples\06-macros
fasm hello_macros.asm
windbgx hello_macros.exe
```

```
bp $exentry
g
u @rip L20
```

Find the `sub rsp,30h ... call qword ptr [...] ... add rsp,30h` sandwich around
each call. Then find `greet` (the target of a direct `call` instruction):

```
u <greet address> L12
```

You'll see `push rbp / mov rbp,rsp / sub rsp,... / push rbx / push rsi`, then
our `mov qword ptr [rbp+10h],rcx`. At the end of the function, the `ret`
macro's `pop rsi / pop rbx / leave / ret`.

Check the frame while inside `greet`:

```
bp <greet address>
g
p 4            ; step through the prologue
dq @rbp L6     ; saved rbp, return address, then pname/times slots
da poi(@rbp+10)
```

## Optional: seeing the expansion at assemble time

FASM can print the processed source. Run `fasm hello_macros.asm -s
hello_macros.fas`, then use `PREPSRC` from FASM's `TOOLS` folder (assemble
`TOOLS\WIN32\PREPSRC.ASM` once to get `prepsrc.exe`):

```bat
prepsrc hello_macros.fas hello_macros.prep.txt
```

The `LISTING` tool in the same folder produces an address/bytes/source
listing — very useful next to WinDbg.

## Exercises

1. Rewrite lesson 05's `print_number` as a `proc` with `locals` for the digit
   buffer. Use `addr` to pass the local `written` to `WriteFile`.
2. Demonstrate the order-of-evaluation trap: write `proc show2, a, b` that
   prints both numbers, then call `fastcall show2, rdx, rcx` after setting
   `rcx=1, rdx=2`. Predict, run, then fix it.
3. Add a third parameter `times` style arg beyond four: write a proc with 6
   parameters and verify in WinDbg that params 5 and 6 are at `[rbp+30h]` and
   `[rbp+38h]`.
4. Read `C:\fasm\INCLUDE\MACRO\PROC64.INC`. It's dense, but find `macro
   fastcall` and identify where it computes the stack space. You don't need to
   understand all of it — just get a feeling that there's no magic.

Next: [07 — A console toolkit](07-console.md)
