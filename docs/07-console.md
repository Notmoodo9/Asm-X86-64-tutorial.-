# 07 — A console toolkit: strings, numbers, input

Sources:
[`examples/common/console.inc`](../examples/common/console.inc),
[`examples/07-console/calc.asm`](../examples/07-console/calc.asm)

Real programs are built from reusable pieces. In this lesson you get your
first library — `console.inc` — and use it to build an interactive
calculator:

```
asm calc - enter e.g.  12 * 34   (empty line quits)
> 12 * 34
= 408   hex 0000000000000198
> -100 / 7
= -14   hex FFFFFFFFFFFFFFF2
> 7 % 0
division by zero
>
```

## Structuring a program with include files

```asm
section '.text' code readable executable
start:
        ...
        include '..\common\console.inc'
```

`include` pastes another file's text in at that point. Because the procs in
`console.inc` are wrapped in `if used`, programs that only use `print_z` don't
carry `print_hex` around. Paths are resolved relative to the including file
first, then the `INCLUDE` environment variable.

`console.inc` keeps its read-only constants (`console_crlf`, the hex digits)
inside the code section so the include is self-contained. Code sections are
readable, just not writeable.

## Text is bytes

Windows has two flavours of text API: `...A` (ANSI — one byte per character,
the current code page) and `...W` (UTF-16 — two bytes per character). With
ANSI, the string `'12'` in memory is the bytes `31h 32h` — the ASCII codes.
The digit `'0'` is `30h`, so:

```
digit value = character - '0'
character   = digit value + '0'
```

## Number → text (`print_u64`)

Repeatedly divide by 10; each remainder is the next digit **from the right**:

```
1234 / 10 = 123 rem 4
 123 / 10 =  12 rem 3
  12 / 10 =   1 rem 2
   1 / 10 =   0 rem 1     → "1234"
```

So we fill a buffer backwards:

```asm
        lea     rdi, [digits + 31]
.next:
        xor     edx, edx
        div     rbx                     ; rbx = 10
        add     dl, '0'
        mov     [rdi], dl
        dec     rdi
        inc     rsi                     ; digit count
        test    rax, rax
        jnz     .next
```

`print_i64` prints `-` and negates first. `print_hex` does the same with a
divisor of 16 — but since 16 is a power of two, it uses `and 0Fh` and
`shr 4`, and looks digits up in a table `'0123456789ABCDEF'`.

## Text → number (`parse_u64`)

The reverse: for each digit, `value = value * 10 + digit`:

```asm
.next:
        movzx   edx, byte [rcx]
        sub     edx, '0'
        cmp     edx, 9
        ja      .done                   ; not a digit
        imul    rax, rax, 10
        add     rax, rdx
        inc     rcx
        jmp     .next
```

The `sub` + unsigned `cmp ..., 9` + `ja` trick tests "is it between `'0'` and
`'9'`" in one comparison: characters below `'0'` wrap around to huge unsigned
values.

`parse_u64` returns **two** values: the number in `rax` and "where I stopped"
in `rdx`. The convention only defines `rax` as a return register, but your own
functions can document extra outputs — the caller uses `rdx` to continue
parsing the operator.

`parse_u64` and `skip_spaces` are **leaf functions**: they call nothing and
only touch volatile registers, so they need no prologue, no stack frame, and
no alignment. `parse_i64` *does* call something, so it does `sub rsp, 40`
first.

## Reading input

```asm
invoke  ReadFile, rbx, [pbuf], [maxlen], addr nread, 0
```

The console's input handle works with `ReadFile`. It blocks until the user
presses Enter and returns the line **including** `CR LF` (`13, 10`). `read_line`
strips them and zero-terminates. Note the buffer must have room for
`maxlen + 1` bytes — always think about the terminator.

## Signed division

```asm
        cqo                 ; rdx = all 1s if rax negative, else 0
        idiv    rcx
```

`idiv` divides the 128-bit `rdx:rax`. `cqo` (convert quad to octo) fills `rdx`
with copies of `rax`'s sign bit. Forgetting it is the #1 `idiv` bug — and
dividing by zero raises an exception, so `calc` checks first.

## Explore in WinDbg

```bat
cd examples\07-console
fasm calc.asm
windbgx calc.exe
```

The program runs in its own console window. Type `g`, then enter a
calculation.

### Breakpoint on input arrival

Catch `ReadFile`, remember the buffer pointer, and let it return:

```
bp KERNELBASE!ReadFile
g
```

Type `5 + 6` in the program's console and press Enter... nothing happens
yet — WinDbg stopped at the *start* of `ReadFile`, before your typing was
read. Now:

```
r $t1 = @rdx       ; 2nd argument: the buffer
gu                 ; run until ReadFile returns (it consumes your line)
da @$t1
db @$t1 L10
```

There's your text, read straight out of the program's buffer. The `db` view
shows the trailing CR LF bytes (`0d 0a`).

### Watch the parser work

Find `parse_u64` (it's the first instruction after the procs — look for
`movzx edx,byte ptr [rcx]` with `u`), then:

```
bp <parse_u64 address>
g
da @rcx            ; what is it about to parse?
pt                 ; step to its ret
r rax, rdx
da @rdx            ; where it stopped
```

### Edit the input before it's parsed

At that same breakpoint, rewrite the user's input in memory:

```
ea @rcx "999"
g
```

The calculator now computes with 999. Debuggers can change *any* state.

### The overflow case

Type `9223372036854775807 + 1` (the largest signed 64-bit value, plus one).
The result is negative: signed overflow. `imul`/`add` don't trap — check `OF`
yourself with `jo` if you care. Add a `jo .overflow` after the `add` as an
exercise.

## Exercises

1. Add a `^` operator (power) using a loop of `imul`.
2. Detect overflow on `+ - *` with `jo` and print `overflow`.
3. Add `print_bin` to `console.inc` (binary with 64 digits, or skip leading
   zeros). Show it in the calculator output.
4. Support hex input: if a number starts with `0x`, parse hex digits
   (`0-9`, `a-f`, `A-F`).
5. Keep a running total: if the line starts with an operator (`+ 5`), apply it
   to the previous result.
6. Write `str_eq(a, b) -> rax` and make the calculator quit on `quit` too.

Next: [08 — Files, heap and the command line](08-files.md)
