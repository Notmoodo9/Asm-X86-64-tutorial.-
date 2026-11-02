# 00 — Setup: FASM, WinDbg and the workflow

By the end of this page you'll have an assembler, a debugger, and a repeatable
"edit → assemble → run → debug" loop.

## 1. Install FASM (flat assembler)

1. Go to <https://flatassembler.net/download.php> and download
   **flat assembler 1.73.xx for Windows** (a `.zip`).
2. Extract it to `C:\fasm` so that you have `C:\fasm\FASM.EXE`,
   `C:\fasm\FASMW.EXE` and the folder `C:\fasm\INCLUDE`.
3. Tell Windows where it is. In a **Command Prompt**:

   ```bat
   setx PATH "%PATH%;C:\fasm"
   setx INCLUDE "C:\fasm\INCLUDE"
   ```

   Close and reopen the prompt (`setx` only affects *new* windows). Check:

   ```bat
   fasm
   ```

   You should see `flat assembler  version 1.73.xx` and a usage message.

### Why the `INCLUDE` variable?

From lesson 03 onward our sources start with `include 'win64a.inc'`. That file
lives in `C:\fasm\INCLUDE` and pulls in:

* **macros** — `invoke`, `proc`, `struct`, `library`/`import`, ...
* **equates** — names for Windows constants (`WM_PAINT`, `MB_OK`, ...)
* **structures** — `WNDCLASSEX`, `MSG`, `RECT`, ...
* **API lists** — `include 'api\kernel32.inc'` declares every KERNEL32 export

The `a` in `win64a` means **ANSI** (8-bit) strings. There's also `win64w.inc`
for UTF-16. We use ANSI throughout to keep strings simple.

> **FASMW.EXE** is a small IDE bundled with FASM. Open a `.asm` file, press
> **Ctrl+F9** to assemble, **F9** to assemble and run. It reads include paths
> from `FASMW.INI` (add a `[Environment]` section with
> `Include=C:\fasm\INCLUDE`). Any editor works though — VS Code with an
> "x86 and x86_64 Assembly" extension is pleasant.

## 2. Install WinDbg

WinDbg is Microsoft's debugger — the same one used to debug Windows itself.
Install the modern version (sometimes called "WinDbg Preview"):

```bat
winget install Microsoft.WinDbg
```

or get it from the Microsoft Store (search "WinDbg"), or from
<https://aka.ms/windbg/download>.

The executable is `WinDbgX.exe` and it's on your PATH as `windbgx`.

### Configure symbols (once)

Our programs have no debug symbols (FASM doesn't produce PDB files), but
**Windows' DLLs do**, and Microsoft serves them for free. With them WinDbg
shows names like `KERNELBASE!WriteFile` instead of raw addresses.

Start WinDbg, then in the command box at the bottom type:

```
.symfix c:\symbols
.reload
```

`.symfix` points the symbol path at Microsoft's symbol server with a local
cache in `c:\symbols`. The modern WinDbg remembers this setting. (Equivalent:
set the environment variable
`_NT_SYMBOL_PATH=srv*c:\symbols*https://msdl.microsoft.com/download/symbols`.)

## 3. The workflow

Everything in this course follows this loop:

```
 ┌──────────┐   fasm prog.asm   ┌──────────┐   run / windbgx   ┌──────────┐
 │ prog.asm │ ────────────────► │ prog.exe │ ─────────────────► │ observe  │
 └──────────┘                   └──────────┘                    └────┬─────┘
       ▲                                                             │
       └─────────────────────── change something ◄───────────────────┘
```

### Assemble

```bat
cd examples\01-exit
fasm exit.asm
```

FASM prints how many passes it took and the output size:

```
flat assembler  version 1.73.32  (1048576 kilobytes memory)
2 passes, 1536 bytes.
```

`exit.exe` now exists. There is no linker step: FASM writes a complete
Windows PE executable itself.

### Run

```bat
exit.exe
echo %ERRORLEVEL%
```

(In PowerShell use `$LASTEXITCODE` instead of `%ERRORLEVEL%`.)

### Debug

```bat
windbgx exit.exe
```

or in WinDbg: **File → Start debugging → Launch executable**.

You can also pass startup commands:

```bat
windbgx -c "bp $exentry; g" exit.exe
```

which means "set a breakpoint at the program's entry point, then go".

## 4. A tour of the WinDbg window

The modern WinDbg has a ribbon at the top and dockable windows. The ones you
want open (**View** tab):

| Window | Use |
|--------|-----|
| **Command** | Where you type commands. This is 90% of WinDbg. |
| **Disassembly** | Live disassembly around the current instruction |
| **Registers** | All registers; changed ones are highlighted |
| **Memory** | A hex view of any address |
| **Stack** | The call stack (`k`) |

Arrange them side by side: Disassembly + Registers on top, Command at the
bottom. The keyboard shortcuts you'll use constantly:

| Key | Command | Meaning |
|-----|---------|---------|
| F5 | `g` | Go (run until a breakpoint/exception/exit) |
| F11 | `t` | Trace: execute one instruction, *entering* calls |
| F10 | `p` | Step: execute one instruction, *stepping over* calls |
| Shift+F11 | `gu` | Go up: run until the current function returns |
| F9 | `bp` | Toggle breakpoint on the current line |
| Ctrl+Break | – | Break in to a running program |

> Tip: the Disassembly window is nice, but get used to `u` (unassemble) and `r`
> (registers) in the command window — they're precise, scriptable and you can
> scroll back through history.

## 5. Things that will confuse you (so they don't)

* **The first stop isn't your code.** When WinDbg launches a program, it
  stops inside `ntdll` *before* your program's code runs (the "initial
  breakpoint"). Type `g` to go, or `bp $exentry` first to stop at your entry
  point.
* **`int3` in your code is a breakpoint.** We'll sprinkle `int3` instructions
  in the examples as checkpoints. Under WinDbg they stop the program. **Outside
  a debugger, they crash it** ("has stopped working"). That's expected — remove
  them (or run under WinDbg) when you want a normal run.
* **Addresses are stable.** FASM produces executables without relocation info,
  so Windows always loads them at their preferred address `0x400000`. Code is
  usually at `0x401000`, the next section at `0x402000`, and so on. This makes
  debugging by address easy.
* **No symbols for your code.** WinDbg will show `exit+0x1000` or just raw
  addresses for your program. You'll find your way using `$exentry`,
  disassembly, and register values. The [WinDbg cheat-sheet](windbg-cheatsheet.md)
  has more tricks.
* **Antivirus may flag tiny hand-made executables.** Unusual PE files with no
  C runtime sometimes trigger heuristic detections. If an example disappears
  after assembling, add an exclusion for your course folder.

## 6. Checklist

- [ ] `fasm` prints its version
- [ ] `echo %INCLUDE%` shows `C:\fasm\INCLUDE`
- [ ] `windbgx` opens WinDbg
- [ ] `.symfix` done
- [ ] You've cloned/downloaded this repository

Next: [01 — Your first program](01-first-program.md)
