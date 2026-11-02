# 12 — TCP networking with Winsock

Sources:
[`examples/common/ws2_32.inc`](../examples/common/ws2_32.inc),
[`examples/12-sockets/echo_server.asm`](../examples/12-sockets/echo_server.asm),
[`examples/12-sockets/echo_client.asm`](../examples/12-sockets/echo_client.asm)

Two programs talk to each other over TCP: a server that echoes back whatever
it receives, and a client that sends what you type.

```
 echo_client                                   echo_server
 ───────────                                   ───────────
 WSAStartup                                    WSAStartup
 socket                                        socket
                                               bind  (0.0.0.0:5000)
                                               listen
 connect (127.0.0.1:5000) ───── handshake ───► accept   → new socket
 send "hello"            ─────── bytes ──────► recv
 recv                    ◄────── bytes ─────── send "hello"
 closesocket             ─────── FIN ────────► recv returns 0 → closesocket
```

## Winsock in a nutshell

Winsock (`WS2_32.DLL`) is Windows' implementation of the BSD sockets API —
the same `socket/bind/listen/accept/connect/send/recv` you'd use in C on
Linux, plus `WSAStartup`/`WSACleanup` around it.

FASM has no `api\ws2_32.inc`, so we wrote our own (`common/ws2_32.inc`): an
`import` list plus the constants. That's a skill in itself — any DLL is usable
from assembly once you know its function names and calling convention, and
the C headers (`winsock2.h`, `ws2def.h`) tell you the numbers.

### Return values to check

| Function | Success | Failure |
|----------|---------|---------|
| `WSAStartup` | 0 | error code |
| `socket`, `accept` | a `SOCKET` (64-bit!) | `INVALID_SOCKET` (−1) |
| `bind`, `listen`, `connect` | 0 | `SOCKET_ERROR` (−1) |
| `send`, `recv` | bytes transferred (`int`) | −1; `recv` returns **0** when the peer closed |

On failure, `WSAGetLastError()` tells you why. The common ones:

| Code | Meaning |
|------|---------|
| 10048 `WSAEADDRINUSE` | someone's already listening on that port (a second server?) |
| 10054 `WSAECONNRESET` | the other side vanished |
| 10060 `WSAETIMEDOUT` | no answer (wrong IP, firewall) |
| 10061 `WSAECONNREFUSED` | nobody listening on that port (server not running) |

`SOCKET` is a pointer-sized handle, so compare all of `rax`:
`cmp rax, INVALID_SOCKET`. `recv` returns an `int` in `eax` — compare `eax`,
then `mov eax, eax` to get a clean 64-bit count.

## Addresses: byte order matters

An IPv4 socket address is a 16-byte `sockaddr_in`:

```asm
server_addr     dw AF_INET                      ; family (little-endian, normal)
                db PORT shr 8, PORT and 0FFh    ; port: BIG-endian!
                db 127, 0, 0, 1                 ; IP address bytes, in order
                rb 8                            ; padding
```

Network protocols put multi-byte numbers **most significant byte first**
("network byte order", big-endian) — the opposite of x86. Port 5000 is
`1388h`, so the bytes must be `13h 88h`. Writing `dw 5000` would produce
`88h 13h` = port 34835. We sidestep the conversion by writing the bytes
explicitly. In code, you'd call `htons` ("host to network short") or use the
`xchg al, ah` / `rol ax, 8` / `bswap` instructions.

`0.0.0.0` (`INADDR_ANY`) in `bind` means "all of this machine's network
interfaces". `127.0.0.1` is "this machine" (loopback).

## TCP is a stream, not messages

This is the most important networking concept in the lesson. If the client
sends 100 bytes in one `send`, the server's `recv` may return 100 bytes — or 60
and then 40, or (with several sends) 250 bytes at once. TCP guarantees **order
and delivery of bytes**, not message boundaries.

On loopback with short lines, you'll almost always get everything at once,
which hides bugs. The client handles it properly anyway: it keeps calling
`recv` until it has as many bytes as it sent:

```asm
.more:
        lea     rdx, [reply]
        add     rdx, [got]              ; where to continue
        mov     r8, [line_len]
        sub     r8, [got]               ; how much is still missing
        invoke  recv, [sock], rdx, r8, 0
        cmp     eax, 0
        jle     server_gone
        mov     eax, eax
        add     [got], rax
        mov     rax, [got]
        cmp     rax, [line_len]
        jb      .more
```

Any real protocol needs **framing**: either fixed-size messages (lesson 14),
a length prefix, or a delimiter (like HTTP's `\r\n` — lesson 13).

## Blocking

`accept`, `connect` and `recv` **block**: the thread sleeps until something
happens. That's fine for a console tool. In a GUI program it would freeze the
window — lesson 14 moves the network into its own thread.

The server handles one client at a time. While it's echoing for client A,
client B's `connect` succeeds (the OS completes the handshake, up to the
`listen` backlog of 5), but nobody serves B until A disconnects. Try it with
two clients.

## Try it

```bat
cd examples\12-sockets
fasm echo_server.asm
fasm echo_client.asm
start echo_server.exe
echo_client.exe
```

Windows Firewall may ask whether to allow the server — for loopback testing you
can cancel; to test from another computer, allow it on private networks (and
change `127, 0, 0, 1` in the client to the server's IP — see `ipconfig`).

Other clients work too, since it's plain TCP: `telnet localhost 5000` (enable
"Telnet Client" in Windows Features) or `ncat localhost 5000` from Nmap.
PowerShell can do it:

```powershell
$c = New-Object Net.Sockets.TcpClient('127.0.0.1', 5000)
$s = $c.GetStream(); $b = [Text.Encoding]::ASCII.GetBytes("hi from PS")
$s.Write($b, 0, $b.Length); Start-Sleep -m 200
$r = New-Object byte[] 100; $n = $s.Read($r, 0, 100); [Text.Encoding]::ASCII.GetString($r, 0, $n)
```

`netstat -ano | findstr 5000` shows the listening socket and connections.

## Explore in WinDbg

### Watch the server wait

```bat
windbgx echo_server.exe
```

`g`. The server prints "listening" and blocks in `accept`. Break in with
Ctrl+Break and look at the main thread:

```
~0s
k
```

`~0s` switches to thread 0 (break-in happens on a new debugger thread). The
stack shows `ws2_32!accept` → `mswsock` → `ntdll!NtWaitForSingleObject` (or
similar). That's what "blocking" looks like: the thread is parked in the
kernel waiting for an event.

### Read network traffic as it arrives

```
bp ws2_32!recv
g
```

Connect with the client and send a line. At the breakpoint:

```
r $t1 = @rdx
gu
r eax
db @$t1 L@eax
```

You see the bytes exactly as they came off the network. (`L@eax` uses the
return value as the length.)

### Tamper with a reply

At `ws2_32!send` in the server, change the data before it leaves:

```
bp ws2_32!send
g
ea @rdx "HACKED"
g
```

The client receives `HACKED` (followed by the rest of the original line, since
the length `r8` didn't change). Debuggers see — and can change — everything a
program sends or receives, before any encryption would happen. Remember that
when you think about security.

### Decode errors

Stop the server and run the client alone. It prints `socket error 10061`.

```
!error 0n10061
```

WinDbg knows Winsock error codes too.

### Inspect the socket

At any breakpoint where you have a socket in a register:

```
!handle <socket value> f
```

A socket is a kernel handle to the AFD driver (`\Device\Afd`) — the part of
Windows that implements sockets.

## Exercises

1. Make the server **uppercase** the reply (`and al, 0DFh` on `a`–`z`).
2. Print the client's address in the server: pass a 16-byte buffer and a
   pointer to a dword `16` as `accept`'s 2nd and 3rd arguments, then print the
   four address bytes and the port (swap the bytes!).
3. A **time server**: on connect, send `GetLocalTime`'s hours/minutes/seconds
   as text and close the connection.
4. Make the port configurable from the command line (reuse lesson 08's
   argument parsing and lesson 07's `parse_u64`, then `htons`).
5. UDP: write a sender and receiver with `SOCK_DGRAM` / `IPPROTO_UDP`,
   `sendto` and `recvfrom` (add them to `ws2_32.inc`). UDP *does* preserve
   message boundaries — but may lose or reorder messages.
6. Serve several clients by moving each accepted socket into its own thread
   with `CreateThread` (see lesson 14 for threads).

Next: [13 — DNS and HTTP](13-http.md)
