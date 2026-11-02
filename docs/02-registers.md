# 02 — Registers, arithmetic and flags

Source: [`examples/02-registers/registers.asm`](../examples/02-registers/registers.asm)

## The register file

The CPU's working storage is a handful of **registers** — tiny, very fast
variables built into the processor. x86-64 has 16 general-purpose 64-bit
registers:

| 64-bit | low 32 | low 16 | low 8 | Traditional role / Windows ABI role |
|--------|--------|--------|-------|-------------------------------------|
| `rax` | `eax` | `ax` | `al` | accumulator; **return value** |
| `rbx` | `ebx` | `bx` | `bl` | general; *preserved* across calls |
| `rcx` | `ecx` | `cx` | `cl` | counter; **1st argument** |
| `rdx` | `edx` | `dx` | `dl` | data; **2nd argument**; high half of mul/div |
| `rsi` | `esi` | `si` | `sil` | source index; *preserved* |
| `rdi` | `edi` | `di` | `dil` | destination index; *preserved* |
| `rbp` | `ebp` | `bp` | `bpl` | frame/base pointer; *preserved* |
| `rsp` | `esp` | `sp` | `spl` | **stack pointer** — don't use for anything else |
| `r8`  | `r8d` | `r8w` | `r8b` | **3rd argument** |
| `r9`  | `r9d` | `r9w` | `r9b` | **4th argument** |
| `r10`–`r11` | `r10d`… | | | scratch |
| `r12`–`r15` | `r12d`… | | | *preserved* |

Plus:

* `rip` — instruction pointer: address of the next instruction. You can't
  `mov` to it; jumps and calls change it.
* `rflags` — status flags set by arithmetic (zero? negative? carry?).
* `xmm0`–`xmm15` — 128-bit SIMD/floating-point registers (we barely need them).

There's also `ah`, `bh`, `ch`, `dh` (bits 8–15 of the old 16-bit registers) —
legacy; you'll see them in old code.

```
 63                               31               15       7      0
 ┌────────────────────────────────┬────────────────┬────────┬──────┐
 │                               rax                                │
 └────────────────────────────────┼────────────────────────────────┤
                                  │              eax                │
                                  └────────────────┼────────────────┤
                                                   │       ax       │
                                                   └────────┼───────┤
                                                            │  al   │
```

### The rule that bites everyone

* Writing a **32-bit** register (`mov eax, ...`) **zeroes the upper 32 bits**
  of the 64-bit register.
* Writing an **8- or 16-bit** register (`mov al, ...`, `mov ax, ...`) **leaves
  the other bits alone**.

That's why `xor eax, eax` is the standard way to zero all of `rax` (and it's a
shorter instruction than `xor rax, rax`).

## Instructions in this lesson

| Instruction | Meaning |
|-------------|---------|
| `mov dst, src` | copy |
| `add dst, src` / `sub dst, src` | `dst += src` / `dst -= src` |
| `inc x` / `dec x` | `x += 1` / `x -= 1` |
| `neg x` | `x = -x` |
| `imul dst, src` / `imul dst, src, imm` | signed multiply (result truncated to dst size) |
| `mul r` / `div r` | unsigned `rdx:rax = rax * r` / `rax = rdx:rax / r, rdx = remainder` |
| `idiv r` | signed divide (use `cqo` first to sign-extend `rax` into `rdx`) |
| `and` `or` `xor` `not` | bitwise logic |
| `shl` `shr` `sar` | shift left, shift right logical, shift right arithmetic |
| `movzx` / `movsx` / `movsxd` | widen with zeros / with sign |
| `xchg a, b` | swap |

Note FASM number syntax: `42` decimal, `2Ah` or `0x2A` hex (a hex number must
start with a digit: `0FFh`, not `FFh`), `101010b` binary.

## Run it in WinDbg

```bat
cd examples\02-registers
fasm registers.asm
windbgx registers.exe
```

At the initial breakpoint, type `g`. You'll stop at checkpoint 1:

```
(2c4.1f8): Break instruction exception - code 80000003 (first chance)
registers+0x1042:
00000000`00401042 cc              int     3
```

### Checkpoint 1 — widths

```
r rax, rbx, rcx, rdx, r8, r9
```

```
rax=1122334455667788 rbx=1122334455667788 rcx=00000000ffffffff
rdx=0000000000000005 r8=ffffffffffff0005 r9=ffffffffffffff05
```

Compare `rdx` (written via `edx`: upper half zeroed) with `r8` and `r9`
(written via `r8w`/`r9b`: upper bits kept). This is the rule above, live.

Try a few things:

```
r ax
r al
r r8w
```

WinDbg understands sub-register names. You can also change values: `r rax=0`.

### Checkpoint 2 — add/sub/neg

```
g
r eax, ebx
? @ebx
```

`ebx = ffffff88`. Is that -120? `?` evaluates expressions in 64-bit, so it
prints `4294967176`. Ask for signed 32-bit interpretation with `.formats`:

```
.formats @ebx
```

`.formats` shows a value as hex, decimal, octal, binary, chars, float, time...
Look for the `Decimal:` line, then compute `? 0n-120` — `0n` is WinDbg's
decimal prefix (WinDbg's default number base is **hex**: typing `10` means 16!).

### Checkpoint 3 — multiply/divide

```
g
r rax, rdx, rcx
```

`rax = 0x8e` (142), `rdx = 6` → 1000 = 142 × 7 + 6. `ecx = 0x1f8` (504).

**Experiment:** what if you forget `xor edx, edx` before `div`? `div` divides
the 128-bit number `rdx:rax`. If `rdx` holds garbage, the quotient may not fit
in 64 bits and the CPU raises a **divide error** — the program crashes. You
don't need to edit the source to see this; use the debugger. Restart with
`.restart`, `g` to checkpoint 2, then:

```
u @rip L10        ; find the address of the 'div rbx' instruction
bp <that address>
g                 ; stops right before div executes
r rdx=1234
p
```

WinDbg reports `Integer overflow - code c0000095` (or `Integer divide-by-zero`
if the divisor is 0). That's what a crash looks like from inside a debugger:
the faulting instruction, its address, and all the registers at that moment.
`.restart` to start over.

### Checkpoint 4 — bits

```
g
r eax, ebx, ecx, edx, r8
.formats @eax
```

Check each against the comments in the source. `sar ecx,2` on -64 gives -16
(`fffffff0`); `shr edx,2` gives `3ffffff0`. Same bits in, different
interpretation — **signedness is a property of the instruction, not the data**.

### Checkpoints 5–8 — flags

Look at the bottom of `r`'s output:

```
r
```

```
... iopl=0         nv up ei pl zr na pe nc
```

Those two-letter codes are the flags:

| Flag | Set (1) | Clear (0) | Set when |
|------|---------|-----------|----------|
| OF overflow | `ov` | `nv` | signed result didn't fit |
| DF direction | `dn` | `up` | (string instructions go backwards) |
| IF interrupts | `ei` | `di` | (OS stuff — always `ei` for us) |
| SF sign | `ng` | `pl` | result's top bit is 1 (negative) |
| ZF zero | `zr` | `nz` | result was zero |
| AF aux carry | `ac` | `na` | carry out of bit 3 (BCD — ignore) |
| PF parity | `pe` | `po` | low byte has even number of 1 bits |
| CF carry | `cy` | `nc` | unsigned result didn't fit (carry/borrow) |

Individual flags: `r zf`, `r cf`, `r sf`, `r of`. Whole register: `r efl`.

Walk through each checkpoint and predict the flags *before* you look:

| CP | Operation | ZF | SF | CF | OF |
|----|-----------|----|----|----|----|
| 5 | 5 − 5 | 1 | 0 | 0 | 0 |
| 6 | 3 − 5 | 0 | 1 | 1 (borrow) | 0 |
| 7 | 255 + 1 (8-bit) | 1 | 0 | 1 | 0 |
| 8 | 127 + 1 (8-bit) | 0 | 1 | 0 | 1 |

CF is about **unsigned** overflow, OF about **signed** overflow. The CPU
computes both every time and lets *you* pick which one matters — that's exactly
how `jb` (unsigned) and `jl` (signed) work in lesson 04.

### Checkpoint 9 — extension

```
g
r al, ebx, ecx, rdx, r8, r9
```

## Exercises

1. **Trace mode.** Restart, `bp $exentry`, `g`, then press `t` repeatedly
   (or F11) and watch the Registers window highlight changes. Do the entire
   program one instruction at a time.
2. **Predict, then check.** Add after checkpoint 9:
   ```asm
   mov rax, 0FFFFFFFFh
   add eax, 1
   int3
   ```
   What's in `rax`? What are ZF and CF? (Answer: `rax = 0`, ZF=1, CF=1.)
3. Compute `(17 * 23 + 5) / 4` and leave the quotient in `rcx` before
   `ExitProcess`, so it's the exit code. Run without WinDbg (remove the
   `int3`s or comment them with `;`) and check `%ERRORLEVEL%`.
4. Signed division: compute −100 / 7 with `idiv`. You need `cqo` (sign-extend
   `rax` into `rdx`) instead of `xor edx, edx`. What's the remainder's sign?
5. Use WinDbg's `a` (assemble) command to write instructions straight into
   memory: at a checkpoint, `a @rip` then type `mov eax, 1234` Enter, empty
   line to finish, then `u @rip L1` and `p`. You can experiment with
   instructions without re-assembling.

Next: [03 — Memory, addressing and the stack](03-memory.md)
