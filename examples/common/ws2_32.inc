; =============================================================================
; ws2_32.inc - Winsock 2 imports and constants (lesson 12)
;
; FASM's include package has no api file for WS2_32.DLL, so we write the
; import list ourselves. Include this file in your IMPORT section, after a
; 'library' line that names ws2_32:
;
;     section '.idata' import data readable writeable
;         library kernel32, 'KERNEL32.DLL', \
;                 ws2_32,   'WS2_32.DLL'
;         include 'api\kernel32.inc'
;         include '..\common\ws2_32.inc'
;
; As with the api\*.inc files, only functions you use are imported.
; =============================================================================

AF_UNSPEC       = 0
AF_INET         = 2
AF_INET6        = 23
SOCK_STREAM     = 1
SOCK_DGRAM      = 2
IPPROTO_TCP     = 6
IPPROTO_UDP     = 17
INVALID_SOCKET  = -1
SOCKET_ERROR    = -1
SD_SEND         = 1
SD_BOTH         = 2
SOL_SOCKET      = 0FFFFh
SO_REUSEADDR    = 4

; useful error codes (WSAGetLastError)
WSAECONNRESET   = 10054
WSAETIMEDOUT    = 10060
WSAECONNREFUSED = 10061
WSAEADDRINUSE   = 10048

; struct sockaddr_in (16 bytes):
;   +0  dw  sin_family     (AF_INET)
;   +2  dw  sin_port       (BIG-endian: network byte order)
;   +4  dd  sin_addr       (4 address bytes, in order)
;   +8  rb 8 sin_zero
;
; struct addrinfo (48 bytes on x64):
;   +0  dd ai_flags      +4  dd ai_family    +8  dd ai_socktype
;   +12 dd ai_protocol   +16 dq ai_addrlen   +24 dq ai_canonname
;   +32 dq ai_addr       +40 dq ai_next
;
; WSADATA is 408 bytes on x64 - reserve rb 512 to be safe.

        import  ws2_32, \
                WSAStartup,      'WSAStartup', \
                WSACleanup,      'WSACleanup', \
                WSAGetLastError, 'WSAGetLastError', \
                socket,          'socket', \
                bind,            'bind', \
                listen,          'listen', \
                accept,          'accept', \
                connect,         'connect', \
                send,            'send', \
                recv,            'recv', \
                shutdown,        'shutdown', \
                closesocket,     'closesocket', \
                setsockopt,      'setsockopt', \
                htons,           'htons', \
                ntohs,           'ntohs', \
                inet_ntop,       'inet_ntop', \
                getaddrinfo,     'getaddrinfo', \
                freeaddrinfo,    'freeaddrinfo'
