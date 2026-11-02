# 05 — The Windows x64 calling convention

Source: [`examples/05-calling-convention/hello_raw.asm`](../examples/05-calling-convention/hello_raw.asm)

To use anything Windows offers — console, files, windows, graphics, sockets —
you call functions in system DLLs. They all follow **one** set of rules: the
Microsoft x64 calling convention. Get it right and every API is available to
you. Get it wrong and you get crashes that look random. This lesson is the
foundation for everything after it.

## The rules

### 1. Arguments

| Argument | Integer/pointer | Floating point |
|----------|-----------------|----------------|
| 1st | `rcx` | `xmm0` |
| 2nd | `rdx` | `xmm1` |
| 3rd | `r8` | `xmm2` |
| 4th | `r9` | `xmm3` |
| 5th, 6th, ... | stack: `[rsp+32]`, `[rsp+40]`, ... (at the moment of the `call`) | same |

Each argument uses one slot, whatever its type (an `int` still takes a full
8-byte stack slot). Structs larger than 8 bytes are passed **by pointer**.

### 2. Return value

`rax` (or `xmm0` for float/double). A 32-bit `BOOL`/`int`/`DWORD` comes back
in `eax` — the upper half of `rax` is **not** guaranteed to be meaningful.

### 3. Shadow space

The caller **must reserve 32 bytes** at `[rsp] .. [rsp+31]` before every call,
even if the function takes fewer than four arguments. The callee may use it to
spill `rcx/rdx/r8/r9`. That's why the 5th argument is at `[rsp+32]`, not
`[rsp]`.

### 4. Stack alignment

**At the moment of a `call`, `rsp` must be a multiple of 16.**

Since `call` pushes an 8-byte return address, every function *starts* with
`rsp ≡ 8 (mod 16)`. Your entry point is no exception (the OS `call`ed it).
So the classic prologue arithmetic is:

```
rsp at entry          ≡ 8   (mod 16)
+ each push           += 8
+ sub rsp, N          += N
------------------------------
must be               ≡ 0   (mod 16) before any call
```

For `start` in this lesson: `8 + 56 = 64` ✓. For lesson 01: `8 + 40 = 48` ✓.

Why does it matter? Windows functions use SSE instructions like `movaps` that
**fault** on misaligned memory. Many APIs happen not to — which is why bugs
here are so confusing. `MessageBoxA` is a reliable crasher with a misaligned
stack; try it in the exercises.

### 5. Register preservation

| Volatile (caller-saved): callee may destroy | Non-volatile (callee-saved): callee must restore |
|---|---|
| `rax rcx rdx r8 r9 r10 r11`, `xmm0–xmm5` | `rbx rbp rdi rsi rsp r12 r13 r14 r15`, `xmm6–xmm15` |

So after `call [WriteFile]`, assume `rcx`, `rdx`, `r8`... are garbage. Keep
values you need in non-volatile registers or in memory.

### 6. Direction flag

DF must be clear (`cld`) on call and return. It always is unless you `std`.

## A call, slot by slot

`WriteFile` has five parameters:

```c
BOOL WriteFile(HANDLE hFile, LPCVOID lpBuffer, DWORD nNumberOfBytesToWrite,
               LPDWORD lpNumberOfBytesWritten, LPOVERLAPPED lpOverlapped);
```

```asm
        sub     rsp, 56                 ; done once at the start of 'start'
        ...
        mov     rcx, rax                ; hFile
        lea     rdx, [message]          ; lpBuffer
        mov     r8d, message_len        ; nNumberOfBytesToWrite
        lea     r9, [rsp + 40]          ; lpNumberOfBytesWritten -> our local
        mov     qword [rsp + 32], 0     ; lpOverlapped (5th) -> stack
        call    [WriteFile]
```

The stack at the moment of the `call`:

```
          ┌──────────────────────────┐
 rsp+56   │ return address (to OS)   │ ◄─ rsp at entry
          ├──────────────────────────┤
 rsp+48   │ padding                  │
 rsp+40   │ 'written' (our local)    │ ◄─ r9 points here
 rsp+32   │ 5th arg: 0               │
 rsp+24   │                          │
 rsp+16   │ shadow space (32 bytes)  │
 rsp+8    │ owned by WriteFile       │
 rsp+0    │                          │ ◄─ rsp at the call (16-aligned)
          └──────────────────────────┘
```

When `WriteFile` starts, the `call` has pushed one more qword, so inside it
the shadow space is at `[rsp+8]` and the 5th argument at `[rsp+40]`. Remember
**`+0x28` at function entry** — you'll use it in WinDbg constantly.

## Writing your own well-behaved function

`print_number` in the example is a full by-the-book function:

```asm
print_number:
        push    rbp                     ; save caller's rbp
        mov     rbp, rsp                ; frame pointer: stable reference point
        push    rbx                     ; save non-volatiles we'll use
        push    rdi
        sub     rsp, 80                 ; locals + 32 shadow + 5th-arg slot
        ...                             ; body: locals at [rbp - N]
        lea     rsp, [rbp - 16]         ; free locals (rsp -> saved rdi)
        pop     rdi
        pop     rbx
        pop     rbp
        ret
```

Using `rbp` as a frame pointer means locals have fixed offsets (`[rbp-56]`)
regardless of pushes in the body. The alignment arithmetic is
`8 + 8 (rbp) + 16 (rbx, rdi) + 80 = 112 = 7 × 16` ✓.

Lesson 06's `proc` macro generates exactly this kind of prologue/epilogue for
you.

## Explore in WinDbg

```bat
cd examples\05-calling-convention
fasm hello_raw.asm
windbgx hello_raw.exe
```

### Catch the program calling Windows

At the initial breakpoint:

```
bp KERNELBASE!WriteFile
g
```

(`kernel32!WriteFile` is just a tiny forwarder; the real code is in
KERNELBASE. If you're unsure where something lives: `x *!WriteFile`.)

When it hits, you're at the first instruction of `WriteFile`. **Read the
arguments:**

```
r rcx, rdx, r8, r9
da @rdx
dq @rsp L6
```

* `rcx` — a small number like `0x7c`: the console handle.
* `rdx` — pointer to our text; `da @rdx` shows it.
* `r8` — `0x27` = 39 bytes.
* `r9` — pointer into our stack.
* `dq @rsp L6` — `[rsp]` is the **return address** (into `hello_raw`), then
  four shadow slots, then at `[rsp+0x28]` the 5th argument: `0`.

Prove it's the return address:

```
ln poi(@rsp)
u poi(@rsp)-6 L2
```

You'll see our `call qword ptr [...]` right before the return address.

### See the return value

```
gu
r rax
dd <the r9 address you noted> L1
```

`gu` runs until `WriteFile` returns to us. `rax = 1` (TRUE = success), and the
`written` local now holds `0x27`. The text appeared in the console.

### Watch a non-volatile register being preserved

```
bp KERNELBASE!WriteFile
g          ; second WriteFile: the one inside print_number
r rbx, rdi
gu
r rbx, rdi
```

Same values before and after: `WriteFile` saved and restored them. Meanwhile
`rcx`, `rdx`, `r8`... are trashed after the call.

### Check alignment at every API call

This command string turns a breakpoint into an alignment checker:

```
bp user32!MessageBoxA ".if ((@rsp & 0xf) != 8) { .echo MISALIGNED!; } .else { .echo aligned ok; gc }"
g
```

At function entry `rsp & 0xf` must be `8` (it was 0 at the `call`, then the
return address was pushed).

### Look at the MessageBox arguments

```
bp user32!MessageBoxA
g
da @rdx
da @r8
? @r9
```

`r9 = 0x40` = `MB_OK (0) + MB_ICONINFORMATION (0x40)`.

## Exercises

1. **Make it crash.** Change `sub rsp, 56` to `sub rsp, 48` (now misaligned).
   Run it — probably the console line still prints, then MessageBoxA crashes.
   Run it under WinDbg and read the faulting instruction: very likely a
   `movaps xmmword ptr [rsp+...]` with an `Access violation`. Look at `rsp` —
   it ends in `8`. Now you'll recognise this bug forever.
2. **Use the shadow space.** Inside `print_number`, the caller gave you 32
   bytes at `[rbp+16]..[rbp+47]`. Save `rcx` to `[rbp+16]` at the start and
   read it back later instead of keeping it in `rax`.
3. Change the MessageBox to `MB_YESNO + MB_ICONQUESTION` (4 + 20h). It returns
   `IDYES` (6) or `IDNO` (7) in `eax`. Exit with that value as the exit code.
4. Call `GetTickCount64` (no arguments, returns `rax`) and `print_number` the
   result: milliseconds since boot. Add it to the import list.
5. Call `Beep(750, 300)` from KERNEL32 (2 arguments).
6. Look up `GetSystemTime` on MSDN: it takes one argument, a pointer to a
   16-byte `SYSTEMTIME` struct. Reserve 16 bytes in your stack frame, call it,
   and print the year (`word` at offset 0) with `print_number` (`movzx ecx,
   word [...]`).

Next: [06 — FASM macros: `invoke`, `proc`, `import`](06-macros.md)
