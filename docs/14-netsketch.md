# 14 — Capstone: NetSketch, a networked whiteboard

Source: [`examples/14-netsketch/netsketch.asm`](../examples/14-netsketch/netsketch.asm)

Everything comes together: a window, your own framebuffer and line algorithm,
TCP networking — and one new ingredient, **threads**. Start NetSketch twice;
what you draw in one window appears in the other.

```bat
cd examples\14-netsketch
fasm netsketch.asm
start netsketch.exe
start netsketch.exe
```

The first instance finds nobody to connect to and becomes the **host**
("waiting for a peer..."). The second connects to it. Draw in either window.

To use two computers, change `PEER_IP` near the top of the source to the
host's IPv4 address (`ipconfig` on the host), rebuild on the *connecting*
machine, and let the host through Windows Firewall (it asks the first time).

## Design first

Before writing assembly for anything this size, decide on the pieces and how
they talk. This is the design from the comment at the top of the file:

```
   GUI thread                                network thread (net_thread)
   ──────────                                ───────────────────────────
   message loop                              connect()  or  listen()+accept()
   WM_MOUSEMOVE: draw_line locally,          loop:
                 send 16-byte packet ─────►      recv_all 16 bytes
   WM_NETLINE:   draw_line from packet ◄────     PostMessageA(WM_NETLINE)
   WM_NETSTATUS: SetWindowTextA        ◄────     PostMessageA(WM_NETSTATUS)
```

### Why a second thread?

`recv` blocks until data arrives. If the GUI thread called it, the window
would freeze — no painting, no mouse — until the peer drew something. So a
**network thread** does nothing but wait for packets, and the **GUI thread**
does nothing but handle messages. Each blocks on its own thing.

```asm
invoke  CreateThread, NULL, 0, net_thread, NULL, 0, NULL
```

A thread is just a function the OS starts running in parallel, with its own
registers and its own stack. `net_thread` is an ordinary `proc` that takes one
parameter; when it returns, the thread ends.

### Rule: only the GUI thread touches the window and the framebuffer

Two threads writing the same memory at the same time is a **data race**. The
cleanest way to avoid races is to not share: the network thread never draws.
It hands each packet to the GUI thread **as a message**:

```asm
invoke  PostMessageA, [main_hwnd], WM_NETLINE, [in_packet], [in_packet + 8]
```

`PostMessageA` puts a message in the window's queue — it's thread-safe and
returns immediately. The GUI thread's `GetMessageA` picks it up and dispatches
it to `WindowProc` like any mouse click. `WM_APP` (`8000h`) and above are
message numbers reserved for applications, so we define our own:

```asm
WM_NETLINE   = 8000h + 1
WM_NETSTATUS = 8000h + 2
```

The packet is 16 bytes and a message carries two 8-byte parameters — so the
**whole packet travels inside the message**. No shared buffers, no locks.

The one piece of shared state is the `connected` flag (and `sock`), written
by the network thread and read by the GUI thread. An aligned 8-byte `mov` is
atomic on x64, and `sock` is written *before* `connected` is set to 1, so the
GUI never sees `connected = 1` with a stale socket. (For anything more
complex you'd use `InterlockedExchange`-style `lock` instructions, critical
sections, or more messages.)

### The protocol

```
 offset  size  field
 +0      2     x0   (signed 16-bit)
 +2      2     y0
 +4      2     x1
 +6      2     y1
 +8      8     colour (0x00RRGGBB)
```

Fixed-size packets solve the stream-framing problem from lesson 12: the
receiver always reads exactly 16 bytes with `recv_all`, which loops until it
has them all:

```asm
proc recv_all uses rbx rsi rdi, s, pbuf, count
        mov     rbx, rcx
        mov     rsi, rdx
        mov     rdi, r8
  .more:
        test    rdi, rdi
        jz      .ok
        invoke  recv, rbx, rsi, rdi, 0
        cmp     eax, 0
        jle     .fail
        mov     eax, eax
        add     rsi, rax
        sub     rdi, rax
        jmp     .more
  ...
```

Both ends are x86, so we send our numbers little-endian as they are. A
"proper" protocol would define a byte order (usually big-endian) and convert —
an exercise.

### Host or client?

```asm
        invoke  connect, rbx, peer_addr, 16
        test    eax, eax
        jnz     .become_host
```

Try to connect; if it fails, listen and wait. It's a cute trick for a demo —
no command-line arguments needed — but it has a race: start both at the very
same moment and both may become hosts. Real programs take a `--host` flag.

### Drawing remote lines

```asm
  .netline:
        movsx   rax, word [wparam]          ; x0
        mov     [net_x0], rax
        movsx   rax, word [wparam + 2]      ; y0
        ...
        fastcall draw_line, [net_x0], [net_y0], [net_x1], [net_y1], [lparam]
        invoke  InvalidateRect, [hwnd], NULL, 0
```

`wparam` was stored to the stack by our prologue, so its four 16-bit pieces
are just four memory reads.

## Explore in WinDbg

Debugging multi-threaded and networked programs is where WinDbg really
shines. Start one instance normally, and the second under the debugger:

```bat
start netsketch.exe
windbgx netsketch.exe
```

### Threads

```
g
```

Let it connect, then break in (Ctrl+Break):

```
~
```

lists threads. You'll see the main (GUI) thread, the network thread, and a
few Windows worker threads. Look at each one's stack:

```
~*k
```

Find the one sitting in `ws2_32!recv` → that's `net_thread` waiting for a
packet. The GUI thread is in `win32u!NtUserGetMessage`, waiting for input.
Two threads, both blocked, both waiting for different things — that's the
design working.

Switch to a thread with `~<n>s` and look at its registers and stack. Each has
its own `rsp`, in a different stack region (`!address @rsp`).

### Catch packets on arrival

```
bp ws2_32!recv
g
```

Draw in the *other* window. The breakpoint hits **on the network thread** —
the prompt shows the thread number (e.g. `0:003>`). Then:

```
r $t1 = @rdx
gu
db @$t1 L10
```

You're looking at a live packet: four little-endian 16-bit coordinates and the
colour.

### Thread-specific breakpoints

`bp` stops any thread that hits it. `~<n> bp ...` stops only for thread `n`.
Useful when the same function (like `draw_line`) runs for local *and* remote
strokes — though here both run on the GUI thread. Find out which path a call
came from with `k`: local strokes come via `local_stroke`, remote ones
directly from `WindowProc`'s `WM_NETLINE` handler.

### Freeze a thread

```
~<network thread> f
g
```

`f` freezes a thread. The GUI keeps working, but the remote drawing stops —
packets pile up in the OS's socket buffer. Break in, `~<n> u` to unfreeze,
`g`, and all the queued lines appear at once. You've just *seen* TCP
buffering.

### Watch the shared flag

```
ba w8 <address of connected>
g
```

Close the other instance. The data breakpoint fires on the network thread at
`mov [connected], 0`. `k` shows you exactly where and why.

## Exercises

1. **Sync clear**: when you press `C`, send a special packet (e.g. all
   coordinates `0x7FFF`) that tells the peer to clear too.
2. **Late joiner**: when a peer connects, send it the whole current
   framebuffer first (1.92 MB) so it sees what was already drawn. Use
   `send` in a loop (it may send less than requested) and `recv_all` on the
   other side.
3. **More than two**: make the host accept several clients (a thread per
   client), and relay every packet it receives to all the others.
4. **Brush sizes**: add a width byte to the packet (make the packet 16 bytes
   still: pack colour into 4 bytes) and draw thick lines.
5. **Big-endian protocol**: convert coordinates with `xchg al, ah` (or `rol
   ax, 8`) before sending and after receiving. Verify with WinDbg that the
   bytes on the wire changed.
6. **Command-line role**: `netsketch.exe host` / `netsketch.exe 192.168.1.20`.
   Parse an IPv4 address with `parse_u64` and the dots (or call
   `inet_pton`).
7. **Undo**: keep a list of all strokes (local + remote) in a growable heap
   buffer; on `Ctrl+Z` remove your last stroke and redraw everything from the
   list.

Next: [15 — Where to go next](15-next-steps.md)
