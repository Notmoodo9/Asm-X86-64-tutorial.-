# 04 — Control flow and functions

Source: [`examples/04-control-flow/control.asm`](../examples/04-control-flow/control.asm)

Assembly has no `if`, `while` or `for`. It has **compare**, **conditional
jump** and **unconditional jump**, and you build everything from those.

## Compare and jump

```asm
cmp  eax, 10      ; compute eax - 10, set flags, throw the result away
jl   too_small    ; jump if (signed) less
```

`cmp a, b` is a subtraction that only sets flags. `test a, b` is an `and` that
only sets flags — `test eax, eax` is the idiom for "is it zero / negative?".

Then a **conditional jump** reads the flags:

| Meaning | Signed | Unsigned | Flags tested |
|---------|--------|----------|-------|
| `a == b` | `je` / `jz` | `je` / `jz` | ZF=1 |
| `a != b` | `jne` / `jnz` | `jne` / `jnz` | ZF=0 |
| `a < b` | `jl` | `jb` | SF≠OF / CF=1 |
| `a <= b` | `jle` | `jbe` | ZF=1 or SF≠OF / CF=1 or ZF=1 |
| `a > b` | `jg` | `ja` | ZF=0 and SF=OF / CF=0 and ZF=0 |
| `a >= b` | `jge` | `jae` | SF=OF / CF=0 |
| negative / not | `js` / `jns` | | SF |

Memory aid: **l**ess/**g**reater are signed, **b**elow/**a**bove are unsigned.

The bits in a register have no type. `0FFFFFFFFh` is −1 to `jl` and
4 294 967 295 to `jb`. The program's first block demonstrates this:

```asm
mov eax, -1
cmp eax, 1
jl  ...        ; taken      (-1 < 1)
cmp eax, 1
jb  ...        ; NOT taken  (4294967295 is not below 1)
```

There are also **conditional moves** — `cmovg rax, rdx` = "if greater, copy" —
which avoid jumps entirely (`max3` uses them).

## Patterns

**if / else**

```asm
        cmp   rcx, 0          ; if (x < 0)
        jge   .else
        neg   rcx             ;     x = -x
        jmp   .end
.else:                        ; else
        ...                   ;     ...
.end:
```

Note that the jump condition is the **opposite** of the `if` condition: you
jump *over* the then-block when it shouldn't run.

**while**

```asm
.loop:
        cmp   rcx, rbx        ; while (i < n)
        jae   .done
        ...                   ;     body
        inc   rcx             ;     i++
        jmp   .loop
.done:
```

**do-while** (one jump per iteration — usually preferred):

```asm
.loop:
        ...                   ; body
        dec   rcx
        jnz   .loop           ; while (--n != 0)
```

**switch** (jump table)

```asm
        cmp   rcx, 6
        ja    .default                 ; unsigned: also rejects negative values
        lea   rax, [.table]
        jmp   qword [rax + rcx*8]
        ...
.table  dq .case0, .case1, ...
```

## Labels: global, local, anonymous

```asm
abs_val:            ; global label
.done:              ; local label: its full name is abs_val.done
@@:                 ; anonymous label
        jmp @b      ; nearest @@ backwards
        jmp @f      ; nearest @@ forwards
```

Local labels (starting with `.`) belong to the last global label, so every
function can have its own `.loop` and `.done` without clashing.

## Functions: `call` and `ret`

```asm
        mov   rcx, -42
        call  abs_val      ; push address of next instruction; jump to abs_val
        mov   [r_abs], rax ; ...execution continues here after ret

abs_val:
        mov   rax, rcx
        ...
        ret                ; pop return address; jump to it
```

That's all a function is at the machine level: a label you `call`, that
eventually `ret`s. *Everything else* — where arguments go, which registers
survive — is a **convention**. We're already following the Windows x64 one:

* arguments in `rcx`, `rdx`, `r8`, `r9`
* return value in `rax`
* a function may freely destroy `rax rcx rdx r8 r9 r10 r11` (**volatile**)
* it must preserve `rbx rbp rdi rsi r12–r15` (**non-volatile**) — if it uses
  them, it saves them first (`push`) and restores them before `ret` (`pop`)

`fib` and `count_primes` call other functions, so they push the
non-volatile registers they use and adjust `rsp` so the stack stays
16-byte aligned. The exact arithmetic is lesson 05; the comments show it.

## Explore in WinDbg

```bat
cd examples\04-control-flow
fasm control.asm
windbgx control.exe
```

### CP1 — signed vs unsigned

```
g
u @rip-0n60 L18
```

Find the `cmp`/`jl`/`jb` lines in the disassembly. WinDbg shows jump targets
as absolute addresses. To find the data, look for `mov qword ptr [...],1` and
read the address, then `dq <addr> L2` → `1` and `0`.

A better way to watch a branch decision: restart, set a breakpoint on the `jb`
instruction, and when it hits:

```
r cf
p
```

You see CF and whether `rip` jumped or fell through.

### Step over vs step into

Restart and stop at the entry. Now walk to the first `call abs_val`:

* `p` (F10) on a `call` runs the whole function and stops after it.
* `t` (F11) on a `call` enters it.
* `gu` (Shift+F11) runs until the current function returns.
* `pc` / `tc` — step/trace to the next `call`. `pt` — step to the next `ret`.

Use `tc` to hop from call to call and look at `rcx`, `rdx`, `r8` right before
each one. That's how you read a program's "dataflow" without symbols.

### CP2 — results

```
g
dq <r_abs address> L5
da poi(<r_kind address>)
```

You should see `2a`, `11`, `375f00`, `262` (hex for 42, 17, 3628800, 610).
`poi(x)` reads the pointer stored at `x`, so `da poi(...)` prints the string
that `day_kind` returned: `weekday`.

### The call stack during recursion

Set a breakpoint on `fib`'s base case and look at the stack:

```
.restart
bp $exentry
g
u <fib address> L4     ; find the 'jb' and its target (.base)
bp <.base address>
g
k
```

`k` shows the call stack — a chain of return addresses. Without symbols it
looks like:

```
 # Child-SP          RetAddr               Call Site
00 00000000`0014fe68 00000000`00401123     control+0x1145
01 00000000`0014fe70 00000000`00401123     control+0x1123
02 00000000`0014fec0 00000000`00401123     control+0x1123
...
```

Each line is one active `fib` call. Count them — it should match the recursion
depth. `kn`, `kv`, `kf` show variations (frame numbers, extra args, frame
sizes). How does WinDbg know where each frame is? Unlike C compilers, FASM
doesn't emit unwind data, so WinDbg is *guessing* by scanning the stack — on
this simple program the guesses are good.

`dps @rsp L20` ("display pointers and symbols") dumps raw stack slots and
names any that look like code addresses. Find the pushed `rbx`/`rsi` values
between the return addresses.

### Conditional breakpoints

Stop only when `fib` is called with `n == 3`:

```
bp <fib address> ".if (@rcx != 3) { gc }"
g
```

`gc` = "go from conditional". The command string runs every time the
breakpoint hits. A counter:

```
r $t0 = 0
bp <fib address> "r $t0 = @$t0 + 1; gc"
bp <address of the mov [r_fib],rax line>
g
? @$t0
```

`$t0`–`$t19` are free scratch pseudo-registers. That's how many times `fib`
ran for `fib(15)`: 1973.

## Exercises

1. Write `gcd(rcx, rdx) -> rax` (Euclid: while b≠0: a, b = b, a mod b).
   Exit with `gcd(1071, 462)` = 21.
2. Turn `fib` into a loop. Time both with WinDbg's call counter trick.
3. Write `strlen(rcx = pointer to zero-terminated string) -> rax`.
   Test it on `str_weekday`.
4. Write `is_sorted(rcx = pointer to dwords, rdx = count) -> rax` (1/0).
5. Set `DEBUG = 0`, assemble, run normally, check `%ERRORLEVEL%` = 25.
   Then disassemble the exe in WinDbg — the `int3`s are gone. Macros and
   conditional assembly happen at **assemble time**.
6. Break the rules on purpose: remove `push rsi`/`pop rsi` from `fib` and see
   how the result goes wrong. Then use `ba w8` on the stack slot or step
   through to find *where*.

Next: [05 — The Windows x64 calling convention](05-calling-convention.md)
