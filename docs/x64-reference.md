# x86-64 on one page

## Registers

```
rax rbx rcx rdx rsi rdi rbp rsp r8 r9 r10 r11 r12 r13 r14 r15   (64-bit)
eax ebx ecx edx esi edi ebp esp r8d ...                    r15d  (32-bit, write zero-extends)
ax  bx  cx  dx  si  di  bp  sp  r8w ...                    r15w  (16-bit)
al  bl  cl  dl  sil dil bpl spl r8b ...                    r15b  (8-bit)
rip  rflags  xmm0-xmm15
```

## Windows x64 calling convention

| | |
|-|-|
| Args 1–4 | `rcx rdx r8 r9` (floats: `xmm0–3`) |
| Args 5+ | `[rsp+32]`, `[rsp+40]`, ... at the call (`[rsp+40]`... at callee entry) |
| Return | `rax` (float: `xmm0`) |
| Shadow space | caller reserves 32 bytes at `[rsp]` before every call |
| Alignment | `rsp` ≡ 0 mod 16 at the `call` (≡ 8 at function entry) |
| Volatile | `rax rcx rdx r8 r9 r10 r11 xmm0–5` |
| Non-volatile | `rbx rbp rdi rsi rsp r12–r15 xmm6–15` |

## Data movement

| | |
|-|-|
| `mov d, s` | copy |
| `movzx` / `movsx` / `movsxd` | widen with zeros / sign |
| `lea d, [addr]` | compute address (no memory access) |
| `xchg a, b` | swap |
| `push s` / `pop d` | stack |
| `cmovCC d, s` | conditional move |
| `bswap r` | reverse byte order |
| `cbw cwde cdqe` / `cwd cdq cqo` | sign-extend al→ax→eax→rax / into dx:ax.. rdx:rax |

## Arithmetic and logic

| | |
|-|-|
| `add sub inc dec neg` | |
| `adc sbb` | with carry (multi-precision) |
| `imul d, s` / `imul d, s, imm` | signed multiply, truncated |
| `mul s` / `imul s` | `rdx:rax = rax * s` |
| `div s` / `idiv s` | `rax = rdx:rax / s`, `rdx = remainder` |
| `and or xor not` | |
| `shl shr sar rol ror` | shifts/rotates (count: imm or `cl`) |
| `bt bts btr` | test / set / reset a bit |
| `popcnt lzcnt tzcnt` | count bits |

## Comparison and jumps

`cmp a, b` (a−b), `test a, b` (a AND b) set flags.

| Condition | Signed | Unsigned |
|-----------|--------|----------|
| = | `je` | `je` |
| ≠ | `jne` | `jne` |
| < | `jl` | `jb` |
| ≤ | `jle` | `jbe` |
| > | `jg` | `ja` |
| ≥ | `jge` | `jae` |

Also `js/jns` (sign), `jo/jno` (overflow), `jc/jnc` (carry), `jz/jnz`.
Same suffixes for `setCC` (set a byte to 0/1) and `cmovCC`.

## Strings (with `rsi`, `rdi`, `rcx`)

| | |
|-|-|
| `rep movsb/movsq` | copy `rcx` bytes/qwords from `[rsi]` to `[rdi]` |
| `rep stosb/stosd/stosq` | fill `rcx` items at `[rdi]` with `al/eax/rax` |
| `repne scasb` | find `al` in `[rdi]` |
| `cld` | clear direction flag (forwards) — required at API calls |

## Functions

| | |
|-|-|
| `call f` | push return address, jump |
| `ret` | pop and jump |
| `push rbp` / `mov rbp, rsp` ... `leave` / `ret` | frame setup / teardown |

## Misc

| | |
|-|-|
| `nop` | nothing |
| `int3` | breakpoint |
| `rdtsc` | CPU timestamp counter → `edx:eax` |
| `cpuid` | CPU identification |
| `pause` | spin-loop hint |
| `lock` prefix | atomic read-modify-write (`lock xadd`, `lock cmpxchg`) |
