# 08 — Files, heap and the command line

Source: [`examples/08-files/wc.asm`](../examples/08-files/wc.asm)

A small but complete utility — a clone of Unix `wc`:

```
> wc.exe wc.asm
lines: 190  words: 742  bytes: 6210  wc.asm
```

It touches the three things almost every application needs: **arguments**,
**files**, and **dynamic memory**.

## The command line

Windows gives a process its command line as **one string**:

```asm
invoke  GetCommandLineA         ; rax -> "C:\course\wc.exe" wc.asm
```

Splitting it into arguments is the program's job (C runtimes do this before
`main`). We do the minimum: skip the program name — which may be quoted — and
any spaces after it. What's left is the filename.

Pointers to the middle of strings are free: `filename` just points *into* the
command line; nothing is copied.

## Handles and files

```asm
invoke  CreateFileA, [filename], GENERIC_READ, FILE_SHARE_READ, NULL, \
                     OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL
cmp     rax, INVALID_HANDLE_VALUE
je      .error_open
```

`CreateFileA` opens (or creates) files, and also devices, pipes and more. It
returns a **handle** — an opaque number identifying an object the kernel keeps
for you. You pass it to `ReadFile`, `WriteFile`, `GetFileSizeEx`, and finally
`CloseHandle`. The console handles from lesson 05 are the same kind of thing.

Seven arguments: four in registers, three on the stack. `invoke` handles it.

### Errors

Most APIs signal failure with a special return value (0, `NULL`,
`INVALID_HANDLE_VALUE` = −1) and stash a reason code you fetch with
`GetLastError`. Always check. Common codes:

| Code | Name |
|------|------|
| 2 | `ERROR_FILE_NOT_FOUND` |
| 3 | `ERROR_PATH_NOT_FOUND` |
| 5 | `ERROR_ACCESS_DENIED` |
| 32 | `ERROR_SHARING_VIOLATION` |

In WinDbg, `!error 2` translates a code to text, and `!gle` shows the current
thread's last error.

## The heap

```asm
invoke  GetProcessHeap
mov     [hheap], rax
invoke  HeapAlloc, [hheap], 0, r8       ; r8 = size
...
invoke  HeapFree, [hheap], 0, [buffer]
```

Every process has a default heap. `HeapAlloc` returns a pointer to a block of
the requested size (or `NULL`). Pass `HEAP_ZERO_MEMORY` (8) as flags to get it
zeroed. For big buffers (megabytes, like the framebuffer in lesson 11)
`VirtualAlloc` gives you whole pages straight from the OS.

## Counting

The counting loop is a little **state machine**: one register (`r10d`) remembers
whether we're inside a word. A word starts at a non-space byte that follows a
space (or the beginning):

```
          non-space: words++ ─┐
 ┌─────────┐ ────────────────►┌─────────┐
 │ outside │                  │ in word │ ◄── non-space
 └─────────┘ ◄────────────────└─────────┘
     ▲  space                       
     └── space
```

No function calls inside the loop, so it uses volatile registers freely.

## Explore in WinDbg

Pass arguments after the exe name:

```bat
cd examples\08-files
fasm wc.asm
windbgx wc.exe wc.asm
```

### Look at the raw command line

```
bp KERNELBASE!GetCommandLineA "gu; da @rax"
g
```

### Follow the file through the kernel

```
bp KERNELBASE!CreateFileA "da @rcx; gc"
bp KERNELBASE!ReadFile
g
```

When ReadFile hits:

```
r rcx, rdx, r8
!handle @rcx f
```

`!handle <h> f` shows what kernel object a handle refers to: type `File`, and
its name — the full NT path, like `\Device\HarddiskVolume3\course\...\wc.asm`.

Then `gu` and dump the buffer: `db <rdx value> L80`. That's your file's
content in memory.

### Inspect the heap block

```
!heap -x <buffer address>
```

shows which heap and block the address belongs to, its size and state. (Heap
extensions need symbols for ntdll — another reason for `.symfix`.)

### Provoke an error

```bat
windbgx wc.exe does_not_exist.txt
```

```
bp KERNELBASE!GetLastError "gu; !error @eax"
g
```

`ERROR_FILE_NOT_FOUND`. Same program, different path through the code — use
`pc`/`p` to watch it take the `je .error_open` branch.

### Unicode exercise in the debugger

Windows is Unicode internally: `CreateFileA` converts your ANSI name and calls
`CreateFileW`. Prove it:

```
bp KERNELBASE!CreateFileW "du @rcx; gc"
g
```

`du` dumps UTF-16 strings.

## Exercises

1. Handle a quoted filename argument (`wc "my file.txt"`).
2. Accept **several** files and print a total line, like the real `wc`.
3. Write `copy.exe src dst`: `CreateFileA` the destination with
   `GENERIC_WRITE`, `CREATE_ALWAYS`, and `WriteFile` the buffer.
4. Write `upper.exe file`: read, convert `a`–`z` to uppercase (`sub al, 32`
   or `and al, 0DFh`), write to stdout.
5. Count the most frequent byte: a 256-entry `dq` table on the stack or heap,
   `inc qword [table + rax*8]` (remember: load the table base into a
   register first).
6. Very large files: instead of reading all at once, read in 64 KB chunks
   in a loop until `ReadFile` returns 0 bytes. Make sure a word split across
   two chunks isn't counted twice.

Next: [09 — Opening a window](09-window.md)
