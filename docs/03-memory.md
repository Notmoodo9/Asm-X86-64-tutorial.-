# 03 — Memory, addressing and the stack

Source: [`examples/03-memory/memory.asm`](../examples/03-memory/memory.asm)

Registers are few. Everything else — arrays, strings, structures, the stack —
lives in **memory**: one enormous array of bytes, indexed by 64-bit addresses.

## Defining data in FASM

```asm
section '.data' data readable writeable

magic     dq 1122334455667788h   ; define quadword (8 bytes)
numbers   dd 5, 12, -3, 40, 7, 19 ; define doublewords (4 bytes each)
greeting  db 'Hello, memory!', 0  ; define bytes; strings are just bytes
counter   dq 0
buffer    rb 64                   ; reserve 64 bytes (uninitialised = zero)
```

| Define | Reserve | Size |
|--------|---------|------|
| `db` | `rb` | byte (1) |
| `dw` | `rw` | word (2) |
| `dd` | `rd` | dword (4) |
| `dq` | `rq` | qword (8) |

A label created this way (e.g. `numbers`) remembers its **size**. So
`mov eax, [numbers]` is fine, but `mov al, [magic]` is an error — FASM
refuses to guess. You must write `mov al, byte [magic]`.

`$` means "the current address", so `NUM_COUNT = ($ - numbers) / 4` computes
how many dwords were defined. `=` defines an **assemble-time constant** — it
takes no space in the program.

## Address vs. value: the brackets

This is the single most important thing in this lesson:

```asm
lea rsi, [numbers]   ; rsi = the ADDRESS of numbers   (e.g. 0x402008)
mov eax, [numbers]   ; eax = the VALUE stored there   (5)
```

* **Brackets** mean "memory at this address".
* `mov` with brackets **reads memory**.
* `lea` ("load effective address") computes the address inside the brackets
  and **does not touch memory**.

## Addressing modes

The general form of a memory operand is

```
[ base + index*scale + displacement ]
```

where `base` and `index` are registers, `scale` is 1, 2, 4 or 8 and
`displacement` is a constant. Any part may be omitted.

| Operand | Typical use |
|---------|-------------|
| `[rsi]` | pointer |
| `[rsi + 8]` | struct field |
| `[rsi + rcx*4]` | `array[i]` with 4-byte elements |
| `[rsi + rcx*8 + 16]` | `obj->items[i]` |
| `[label]` | global variable (FASM makes this **RIP-relative**) |

In 64-bit code, FASM encodes `[label]` relative to `rip` ("the variable is
0x1234 bytes after this instruction"). WinDbg's disassembly still shows you the
absolute address — very handy, as you'll see.

Because `lea` just does arithmetic, it doubles as a calculator that doesn't
change the flags:

```asm
lea rax, [rcx + rcx*4]   ; rax = rcx * 5
lea rax, [rax*2 + 3]     ; rax = rax * 2 + 3
```

## Little-endian

x86 stores multi-byte values **lowest byte first**. The qword
`1122334455667788h` occupies 8 bytes in memory as:

```
address:  +0 +1 +2 +3 +4 +5 +6 +7
bytes:    88 77 66 55 44 33 22 11
```

That's why `mov al, byte [magic]` gives `88h`: it reads only the first byte.

## The stack

The stack is a region of memory that grows **downward**. `rsp` points at the
most recently pushed item.

```asm
push rax     ; rsp = rsp - 8 ; [rsp] = rax
pop  rbx     ; rbx = [rsp]   ; rsp = rsp + 8
```

```
 higher addresses
 ┌────────────┐
 │    ...     │
 ├────────────┤ ◄─ rsp before
 │  0x1111    │
 ├────────────┤
 │  0x2222    │
 └────────────┘ ◄─ rsp after two pushes  (8 bytes lower each)
 lower addresses
```

`call` pushes the return address; `ret` pops it. Local variables live on the
stack too (lesson 05).

## Explore in WinDbg

```bat
cd examples\03-memory
fasm memory.asm
windbgx memory.exe
```

### Finding your data without symbols

There are no symbols for `magic`, `numbers` etc. But the disassembly reveals
their addresses. Stop at your entry and look:

```
bp $exentry
g
u @rip L8
```

```
00000000`00401000 4883ec28        sub     rsp,28h
00000000`00401004 8a05f60f0000    mov     al,byte ptr [memory+0x2000 (00000000`00402000)]
00000000`0040100a 668b1def0f0000  mov     bx,word ptr [memory+0x2000 (00000000`00402000)]
...
```

So `magic` is at `0x402000`, the start of the `.data` section. Following the
data layout (8-byte magic, then the six dwords...) `numbers` is at
`0x402008`. You can confirm with the `lea rsi,[numbers]` line further down.

> **Tip:** WinDbg lets you name addresses yourself with *aliases* or simply
> with pseudo-registers: `r $t0 = 402008` then `dd @$t0`. You can also
> generate a symbol listing with FASM (`fasm memory.asm -s memory.fas`) and
> turn it into a readable listing with the `LISTING` tool from FASM's
> `TOOLS` folder — it shows every instruction's address next to its source line.

### Checkpoint 1 — little-endian

```
g
r al, bx, ecx, rdx
db 402000 L8
dw 402000 L4
dd 402000 L2
dq 402000 L1
```

`db`/`dw`/`dd`/`dq` display memory as bytes/words/dwords/qwords. `L8` = 8
items. The *same 8 bytes* look different depending on how you group them.
This is little-endian, seen directly.

### Checkpoint 2 — the array

```
g
r eax
dd 402008 L6
```

`eax = 0x50` = 80 = 5+12−3+40+7+19. In the `dd` output you'll see `fffffffd`
for −3. Try `dd /c 1 402008 L6` (one per line), or the signed view:

```
dd 402008 L6
.formats fffffffd
```

### Checkpoint 3 — strings

```
g
da @rdi-0n15
```

`da` dumps ASCII strings. At this point `rdi` has advanced past the copied
string (15 bytes including the zero), so `@rdi-0n15` is where `buffer` starts
(`0n` = decimal). Compare with `da` on `greeting`'s address.

Also try `db` on the same address: the left side is hex, the right side shows
the printable characters.

### Checkpoint 5 — watchpoints (hardware data breakpoints)

This is one of the most powerful debugging tools there is: *stop whenever this
memory changes*. Restart and set it **before** the loop runs:

```
.restart
bp $exentry
g
u @rip L40          ; find the 'inc qword ptr [...]' line; note the address in brackets
ba w8 <counter address>
g
```

`ba w8 addr` = break on access, **w**rite, **8** bytes. Each `g` now stops
right after `counter` is incremented. Watch it count:

```
dq <counter address> L1
g
dq <counter address> L1
```

The CPU itself does this (debug registers `dr0`–`dr3`), so it's free — no
slowdown. You get only four of them. `bl` lists breakpoints, `bc *` clears all.

Other forms: `ba r4 addr` (read or write), `ba e1 addr` (execute).

### Checkpoint 6 — the stack

```
g
r rsp
dq @rsp L4
```

The first qword at `rsp` is `2222` (pushed last), then `1111`. Step over the
two `pop`s with `p` and watch `rsp` increase by 8 each time and `rbx`/`rcx`
receive the values.

Edit the stack and see the effect:

```
eq @rsp 0xdeadbeef
p
r rbx
```

`eq` = **e**nter **q**word. There's also `eb`, `ew`, `ed`, and `ea` (ASCII).

### Checkpoint 7

```
g
r rax, rdx
? 0n73
```

### The memory map

At any checkpoint:

```
!address @rip
!address @rsp
!address 402000
```

`!address` tells you what region an address belongs to and its protection:
code is `PAGE_EXECUTE_READ`, data `PAGE_READWRITE`, the stack is a big
`PAGE_READWRITE` region with a guard page below it. Try writing to the code
section from your program (`mov byte [start], 0`) and see the access violation.

## Exercises

1. Find the **maximum** of `numbers` (signed — use `cmp` + `jle`/`jge`, which
   you'll meet properly next lesson, or just try). Store it in a new variable
   `largest dd ?`.
2. Reverse `greeting` in place. Hint: one pointer at the start, one at the end
   (`lea rdi, [greeting + 13]`), swap and move inward until they meet.
3. Define a 3-element array of "points" (`dd x, y` pairs) and sum all the `y`
   values using `[rsi + rcx*8 + 4]`.
4. What happens if you `push` an odd number of times and then call
   `ExitProcess`? (Spoiler: maybe nothing, maybe a crash — lesson 05.)
5. Use `s` (search memory) in WinDbg: `s -a 402000 L100 "memory"` finds the
   string in the data section.

Next: [04 — Control flow and functions](04-control-flow.md)
