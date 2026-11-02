# 13 — DNS and HTTP

Source: [`examples/13-http/http_get.asm`](../examples/13-http/http_get.asm)

Lesson 12's programs only talked to each other. Now we talk to a real server
on the internet, which needs two more things: turning a **name** into an
address (DNS), and speaking a **protocol** the server understands (HTTP).

```
> http_get.exe example.com
resolving example.com
connected, sending request...

HTTP/1.1 200 OK
Content-Type: text/html
...
<!doctype html>
<html>
<head>
    <title>Example Domain</title>
...
--- bytes received: 1591
```

## DNS with `getaddrinfo`

```asm
invoke  getaddrinfo, [host], port_str, hints, ai_list
```

```c
int getaddrinfo(const char *node, const char *service,
                const struct addrinfo *hints, struct addrinfo **res);
```

You give it a host name, a port **as a string** (`'80'`), and *hints* about
what kind of socket you want. It returns a **linked list** of `addrinfo`
structures, one per usable address (a host may have several IPv4 and IPv6
addresses):

```
ai_list ──► ┌──────────────────┐     ┌──────────────────┐
            │ +4  ai_family    │     │ ai_family (v6)   │
            │ +8  ai_socktype  │     │ ...              │
            │ +12 ai_protocol  │     │                  │
            │ +16 ai_addrlen   │     │                  │
            │ +32 ai_addr ─────┼─► sockaddr (filled in for you, port included)
            │ +40 ai_next ─────┼────►│ ai_next = NULL   │
            └──────────────────┘     └──────────────────┘
```

We walk the list, trying each address until a `connect` succeeds:

```asm
        mov     rbx, [ai_list]
.try_next:
        test    rbx, rbx
        jz      fail                    ; end of list
        mov     ecx, [rbx + 4]          ; ai_family
        mov     edx, [rbx + 8]          ; ai_socktype
        mov     r8d, [rbx + 12]         ; ai_protocol
        invoke  socket, rcx, rdx, r8
        ...
        mov     rdx, [rbx + 32]         ; ai_addr
        mov     r8, [rbx + 16]          ; ai_addrlen
        invoke  connect, [sock], rdx, r8
        ...
.advance:
        mov     rbx, [rbx + 40]         ; ai_next
        jmp     .try_next
```

This is how you deal with C structures in assembly: **know the offsets**. The
`addrinfo` layout on x64 has 4-byte fields first, then 8-byte pointers aligned
to 8 — `ai_addrlen` is `size_t` (8 bytes) at +16. Get an offset wrong and you
pass garbage to `connect`. (WinDbg can show you the real layout — see below.)

Notice how the list pointer lives in `rbx`: it must survive the calls to
`socket` and `connect`.

`getaddrinfo` allocated the list, so we give it back with `freeaddrinfo`.

Using `AF_UNSPEC` in the hints and taking family/type/protocol from each
result means the program works over IPv6 too, without any IPv6-specific code.

## HTTP: just text over TCP

HTTP/1.1 requests are lines of text, each ending in `\r\n` (CR LF), terminated
by an empty line:

```
GET / HTTP/1.1\r\n
Host: example.com\r\n
User-Agent: asm-http/1.0\r\n
Connection: close\r\n
\r\n
```

* `GET /` — fetch the root path.
* `Host:` — required; one IP address can serve many sites.
* `Connection: close` — asks the server to close the connection after
  responding. That gives us the simplest possible framing: **read until `recv`
  returns 0**.

We build the request in a buffer with a tiny string-append helper, because the
host name comes from the command line:

```asm
        lea     rdi, [request]
        lea     rsi, [req_part1]
        call    append_z
        mov     rsi, [host]
        call    append_z
        lea     rsi, [req_part2]
        call    append_z
```

`append_z` uses `rsi`/`rdi` as source/destination cursors — a custom
"register calling convention" for a small internal helper. That's allowed;
just document it. It's a leaf function and doesn't touch the stack, so it
doesn't need to align anything.

The response is printed raw: status line, headers, blank line, body.

### What about HTTPS?

Almost every site today redirects HTTP to HTTPS (you'll see `301 Moved
Permanently` with a `Location: https://...` header). HTTPS is HTTP inside
**TLS** encryption. Implementing TLS yourself is a research project; on Windows
you'd use the **Schannel** SSPI API (`AcquireCredentialsHandle`,
`InitializeSecurityContext`, `EncryptMessage`...), or the much simpler
**WinHTTP** API (`WinHttpOpen`, `WinHttpConnect`, `WinHttpOpenRequest`,
`WinHttpSendRequest`, `WinHttpReceiveResponse`, `WinHttpReadData`), which does
HTTP and HTTPS for you. Calling WinHTTP from FASM is a great exercise — it's
all just `invoke` (its strings are UTF-16, so use `du` in WinDbg and
`du 'text', 0` in FASM).

## Explore in WinDbg

```bat
cd examples\13-http
fasm http_get.asm
windbgx http_get.exe example.com
```

### Watch DNS resolution

```
bp ws2_32!getaddrinfo
g
da @rcx
da @rdx
r $t1 = @r9         ; where the result pointer will be stored
gu
r eax
dq @$t1 L1          ; the list head
```

### Let WinDbg decode the structures

Windows' public symbols include type information for some structures. Try:

```
dt ws2_32!addrinfo poi(@$t1)
```

If that works, it prints each field with its offset — compare with the table
above. If your symbols don't include it, dump it raw and decode by hand:

```
dd poi(@$t1) L4         ; flags, family, socktype, protocol
dq poi(@$t1)+10 L4      ; addrlen, canonname, addr, next
db poi(poi(@$t1)+20) L10  ; the sockaddr: family, port (big-endian), IP bytes
```

In the `sockaddr_in` dump, bytes 2–3 are `00 50` (port 80, big-endian) and
bytes 4–7 are the server's IPv4 address. Compare with `nslookup example.com`.

### Walk the linked list in the debugger

```
r $t2 = poi(@$t1)
.while (@$t2 != 0) { .printf "family %d at %p\n", dwo(@$t2+4), @$t2; r $t2 = poi(@$t2+0x28) }
```

WinDbg has a small scripting language: `.while`, `.if`, `.for`, `.printf`,
`poi()`, `dwo()` (read dword), `by()` (read byte). You just traversed a C
linked list from a debugger prompt.

### See the request on the wire

```
bp ws2_32!send
g
da @rdx
db @rdx L@r8
```

The `db` view shows the `0d 0a` line endings.

### Count the response chunks

```
r $t3 = 0
bp ws2_32!recv "r $t3 = @$t3 + 1; gc"
g
? @$t3
```

How many `recv` calls did it take? Run it a few times — the number varies with
network conditions. The stream has no message boundaries (lesson 12).

## Exercises

1. **Strip the headers**: find the first `\r\n\r\n` in the received data and
   print only what comes after. (Careful: it could be split across two `recv`
   calls. Easiest fix: accumulate the whole response in a `VirtualAlloc`'d
   buffer first.)
2. **Status code**: parse the number after `HTTP/1.1 ` with `parse_u64` and
   use it as the exit code.
3. **Path support**: accept `http_get.exe host /path` and put the path in the
   request line.
4. **Bounds**: the `request` buffer is 1024 bytes and the host comes from the
   command line. A long enough argument overflows it — a classic buffer
   overflow. Prove it in WinDbg with a 2000-character host name and `ba w8` on
   the variable after `request`. Then fix `append_z` to take a limit.
5. **Save to file**: write the body to `index.html` with `CreateFileA`
   (lesson 08).
6. **A tiny web server**: change lesson 12's echo server to read a request and
   answer every request with
   `HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: N\r\n\r\n<h1>Hello from asm</h1>`.
   Open `http://localhost:5000` in your browser.

Next: [14 — Capstone: NetSketch](14-netsketch.md)
