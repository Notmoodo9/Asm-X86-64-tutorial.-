# WinDbg cheat-sheet

Numbers are **hex by default**. Use `0n` for decimal (`0n100`), `0x` is
optional for hex. Registers in expressions need `@` (`@rax`) — it's faster and
unambiguous.

## Starting

| Command | Meaning |
|---------|---------|
| `windbgx prog.exe args` | launch under the debugger |
| `windbgx -c "bp $exentry; g" prog.exe` | launch and run to the entry point |
| `windbgx -pn prog.exe` | attach to a running process by name |
| `.restart` | restart the target |
| `q` / `qd` | quit (kill) / quit and detach (leave it running) |
| `.symfix c:\symbols` then `.reload` | use Microsoft's symbol server |

## Execution

| Command | Key | Meaning |
|---------|-----|---------|
| `g` | F5 | go |
| `g <addr>` | | go until address |
| `p` | F10 | step over one instruction |
| `t` | F11 | trace into one instruction |
| `p 5` / `t 5` | | five steps |
| `gu` | Shift+F11 | go up: run until current function returns |
| `pc` / `tc` | | step / trace to next `call` |
| `pt` / `tt` | | step / trace to next `ret` |
| `pa <addr>` | | step until address, printing each step |
| `wt` | | trace and summarise all calls made by the current function |
| Ctrl+Break | | break in to a running program |

## Breakpoints

| Command | Meaning |
|---------|---------|
| `bp <addr>` | software breakpoint |
| `bp $exentry` | at the program's entry point |
| `bp kernelbase!WriteFile` | at an API |
| `bu module!func` | "unresolved": set even before the DLL is loaded |
| `bm user32!*Message*` | breakpoints on all matching symbols |
| `bp <addr> "cmds"` | run commands when hit (`gc` at the end = keep going) |
| `bp <addr> ".if (@rcx == 3) {} .else {gc}"` | conditional breakpoint |
| `bp <addr> 5` | stop on the 5th hit |
| `~1 bp <addr>` | only for thread 1 |
| `ba w8 <addr>` | hardware: break when 8 bytes at addr are **written** |
| `ba r4 <addr>` | hardware: read **or** write of 4 bytes |
| `ba e1 <addr>` | hardware: execution |
| `bl` / `bc <n>` / `bc *` | list / clear one / clear all |
| `bd <n>` / `be <n>` | disable / enable |
| `sxe ld:ws2_32` | break when a DLL loads |
| `sxe av` / `sxd av` | break on / ignore first-chance access violations |

Don't put `g`/`gu`/`p` in the *middle* of a breakpoint command string —
commands after them won't run as you'd expect. Put `gc` last, or step by hand.

## Registers

| Command | Meaning |
|---------|---------|
| `r` | all registers |
| `r rax, rcx` | some registers |
| `r rax=5` | set |
| `r efl` / `r zf` | flags register / one flag |
| `r $t0 = 1234` | scratch pseudo-registers `$t0`..`$t19` |
| `r xmm0` / `r xmm0:uq` | SSE register, as a whole / as 2 qwords |

Pseudo-registers: `$ip` (instruction pointer), `$exentry`, `$retreg` (rax),
`$csp` (stack pointer), `$peb`, `$teb`, `$tid`, `$tpid`, `$ra` (return
address of the current function).

Flag letters in `r` output: `ov/nv` OF, `dn/up` DF, `ng/pl` SF, `zr/nz` ZF,
`ac/na` AF, `pe/po` PF, `cy/nc` CF.

## Memory

| Command | Meaning |
|---------|---------|
| `db <addr>` / `dw` / `dd` / `dq` | bytes / words / dwords / qwords |
| `dd <addr> L10` | 0x10 items |
| `dd <addr> L?0n1000` | more than the default size limit |
| `da` / `du` | ASCII / UTF-16 string |
| `dps <addr>` | pointers, with symbols (great for stacks) |
| `dq @rsp L8` | top of the stack |
| `poi(<addr>)` | read the pointer at addr (in expressions) |
| `dwo()`, `by()`, `wo()` | read dword / byte / word in expressions |
| `eb/ew/ed/eq <addr> <values>` | write memory |
| `ea <addr> "text"` / `eza` | write ASCII (zero-terminated with `eza`) |
| `f <addr> L<n> <bytes>` | fill |
| `s -a <addr> L<n> "text"` | search for a string |
| `s -b <addr> L<n> 90 90` | search for bytes |
| `!address <addr>` | what region is this (stack/heap/image), protection |
| `!address -summary` | memory usage overview |
| `.writemem file <addr> L<n>` | dump memory to a file |

## Code

| Command | Meaning |
|---------|---------|
| `u` / `u <addr>` / `u <addr> L20` | disassemble |
| `ub <addr>` | disassemble backwards (what led here) |
| `uf <addr>` | whole function (needs symbols or clear boundaries) |
| `a <addr>` | assemble instructions into memory |
| `ln <addr>` | nearest symbol |
| `x kernel32!*File*` | search symbols |
| `lm` | loaded modules |
| `!dh <module>` | PE headers |

## Stack and threads

| Command | Meaning |
|---------|---------|
| `k` / `kn` / `kv` / `kf` | call stack / numbered / with args / with frame sizes |
| `.frame <n>` | switch to frame n |
| `~` | list threads |
| `~3s` | switch to thread 3 |
| `~*k` | stacks of all threads |
| `~3 f` / `~3 u` | freeze / unfreeze thread 3 |
| `!teb` / `!peb` | thread / process environment block |

## Expressions & output

| Command | Meaning |
|---------|---------|
| `? <expr>` | evaluate (`? @rsp + 0x28`) |
| `.formats <value>` | value as hex/dec/binary/chars/time... |
| `.printf "x=%d %p %ma\n", @ecx, @rdx, @r8` | formatted output (`%ma` = ASCII string at address, `%mu` UTF-16) |
| `.echo text` | print |
| `.if (...) {...} .else {...}` / `.while` / `.for` | scripting |
| `.logopen c:\log.txt` / `.logclose` | log the session |
| `.cls` | clear the command window |
| `.hh <command>` | help |

## Errors and handles

| Command | Meaning |
|---------|---------|
| `!error <code>` | Win32 / Winsock / NTSTATUS code → text |
| `!gle` | current thread's GetLastError |
| `!handle` | all handles |
| `!handle <h> f` | details of one handle (file name, type...) |
| `.lastevent` | why the debugger last stopped |
| `!analyze -v` | automatic crash analysis |

## Time travel (TTD)

After recording a trace (*Start debugging → Launch executable (advanced) →
Record with TTD*):

| Command | Meaning |
|---------|---------|
| `g-` / `p-` / `t-` | run / step / trace **backwards** |
| `!tt 0` / `!tt 100` | go to start / end of the trace |
| `ba w8 <addr>` then `g-` | find the last write to a variable |
| `dx @$cursession.TTD.Calls("kernelbase!WriteFile")` | every call to a function in the trace |
