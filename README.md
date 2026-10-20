# loup-cmd-bare-shell

A command-line program with no operating system: an interactive shell on
the serial port of a bare-metal [Loup](https://code-craft.ai/references/loup)
image, with line editing and commands to inspect memory, read the clock and
hash memory with SHA-256. It boots under QEMU on x86-64 and AArch64.

Part of the **loup-cmd** series of example applications: classic Linux and
Windows commands, and projects for each Loup execution mode, each in its own
repository under [myronccai](https://github.com/myronccai?tab=repositories&q=loup-cmd).
This one is `freestanding` Loup (`.lpfree`), and it has the same shape as
the series' host commands (`cli/` parses, `commands/` act, errors are
`NAME: message`), running on bare metal.

## What this example shows

| Feature | Where |
|---|---|
| Reading from a UART: COM1 with `in`/`out` port I/O, the PL011 through `Volatile` | `com1Get`/`com1Put` in [`source/main_x86_64.lpfree`](source/main_x86_64.lpfree), `pl011Get`/`pl011Put` in [`source/main_aarch64.lpfree`](source/main_aarch64.lpfree) |
| A line editor in a fixed `buffer[uint8, 80]`: echo, Backspace, Ctrl-U, Ctrl-C, CR/LF | [`source/cli/line.lpfree`](source/cli/line.lpfree) |
| Parsing without strings: words as (start, length) pairs into the line buffer, numbers parsed to `Result[uint64, ArgError]` | [`source/cli/args.lpfree`](source/cli/args.lpfree) |
| Commands that return `Result` and propagate with `?`; one place that reports errors | [`source/cli/app.lpfree`](source/cli/app.lpfree), [`source/commands/`](source/commands) |
| Raw memory access: `Volatile[uint8].at(addr)` for peek/poke/hexdump, `bufGetU8` for hashing | [`source/commands/memory.lpfree`](source/commands/memory.lpfree), [`source/commands/sha256.lpfree`](source/commands/sha256.lpfree) |
| SHA-256 in the freestanding subset: module-level buffers, 32-bit words in `uint64` with masking | [`source/commands/sha256.lpfree`](source/commands/sha256.lpfree) |
| Reading counters with `asm`: `rdtsc`, `mrs cntvct_el0` | `readTsc`, `readCounter` |
| Function values in a struct: the board hands the shell its clock and its exit | [`source/platform/board.lpfree`](source/platform/board.lpfree) |
| `@panic_handler` with `panic = "custom"`, reached by `unreachable` | `kernelPanic`, [`source/commands/system.lpfree`](source/commands/system.lpfree) |
| Driving an interactive program in CI: a scripted session typed into QEMU's serial port | [`tests/boot.sh`](tests/boot.sh), [`tests/sessions/`](tests/sessions) |

The boot code (Multiboot2 header, PVH note, long-mode trampoline) is the
same as in [loup-cmd-bare-hello](https://github.com/myronccai/loup-cmd-bare-hello),
which explains it.

## Requirements

- Linux x86-64 (freestanding images are built on Linux only).
- [Loup Lite](https://github.com/code-craft-ai-company/loup-releases) 1.26.0
  or later; see [Installing Loup Lite](#installing-loup-lite).
- `make`, `clang`, `ld.lld` and QEMU for both architectures. On Ubuntu:

  ```sh
  sudo apt-get install clang lld qemu-system-x86 qemu-system-arm
  ```

## Installing Loup Lite

This example is built and tested with **Loup Lite**, the free public build of
the Loup toolchain from [Code Craft AI](https://code-craft.ai), meant for
education and training. Code Craft AI publishes the official builds,
installers and signed checksums at
**<https://github.com/code-craft-ai-company/loup-releases>**, for Linux
(x86-64, arm64), macOS (Apple silicon, Intel) and Windows (x86-64).

Linux and macOS:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.sh | sh
```

Windows (PowerShell):

```powershell
irm https://github.com/code-craft-ai-company/loup-releases/releases/latest/download/loup-install.ps1 | iex
```

The installer picks the archive for your machine, checks it against the
release's `SHA256SUMS`, unpacks it into `~/.loup`
(`%LOCALAPPDATA%\Programs\Loup` on Windows) and puts its `bin` directory on
your `PATH`; it needs no administrator rights. You get `loup`, the Stage0
compiler `loup-bootstrap` and the Wasm runtime `loup-launcher`. Open a new
shell and check:

```sh
loup --version             # loup 1.26.0 or later
```

CI installs the exact version it tests with, 1.26.0. To do the same:

```sh
curl -fsSL https://github.com/code-craft-ai-company/loup-releases/releases/download/v1.26.0/loup-install.sh | sh -s -- --version 1.26.0
```

To install by hand, download your platform's archive from the
[releases page](https://github.com/code-craft-ai-company/loup-releases/releases),
check it against `SHA256SUMS`, unpack it anywhere and add its `bin` directory to
`PATH`. The [loup-releases README](https://github.com/code-craft-ai-company/loup-releases#verify-a-download)
explains how to verify the Sigstore signature on `SHA256SUMS`.

Loup Lite leaves out Loup's cryptography library and the full set of Loup
packages; this example needs neither. The full release is at
<https://code-craft.ai/loup/download>, and commercial use of Loup needs a
license: <https://code-craft.ai/loup/license>.

## Build and run

```sh
make check               # type-check both boards (loup-bootstrap check)
make build               # build/shell-x86_64.elf and build/shell-aarch64.elf
make boot                # type the sessions in tests/sessions/ into both and compare
make ci                  # check, build, boot
make run                 # the x86_64 shell on this terminal; type halt to leave
make run ARCH=aarch64    # the same for aarch64
```

`make run` uses [`scripts/qemu.sh`](scripts/qemu.sh), which connects the
guest's serial port to the terminal with `-chardev stdio,signal=off`, so
Ctrl-C reaches the shell instead of stopping QEMU.

## Usage

```text
$ scripts/qemu.sh x86_64 build/shell-x86_64.elf
loup-cmd-bare-shell 0.1.0 on x86_64, console 16550 UART at I/O port 0x3f8
type help for the commands
> help
commands:
  help              this list
  echo [WORD]...    print the words
  peek ADDR         read the byte at ADDR
  poke ADDR VALUE   write the byte VALUE at ADDR
  hexdump ADDR LEN  show LEN bytes from ADDR
  ticks             TSC count since boot
  sha256 ADDR LEN   SHA-256 of LEN bytes from ADDR
  panic             stop through the panic handler
  halt              stop and exit QEMU
numbers are decimal or 0x hex; memory is 0x0-0x3fffffff, free RAM from 0x200000
keys: Backspace, Ctrl-U erases the line, Ctrl-C cancels it
> echo hello,   bare   metal
hello, bare metal
> hexdump 0x100000 24
00100000  d6 50 52 e8 00 00 00 00  18 00 00 00 12 af ad 17  |.PR.............|
00100010  00 00 00 00 08 00 00 00                           |........|
> poke 0x200000 0x61
0x200000: 0x00 -> 0x61
> poke 0x200001 0x62
0x200001: 0x00 -> 0x62
> poke 0x200002 0x63
0x200002: 0x00 -> 0x63
> sha256 0x200000 3
ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
> ticks
ticks: 73309960 TSC counts since boot
> peek 0x40000000
peek: 0x40000000+1 is outside memory 0x0-0x3fffffff
> hexdump 0x200000 zz
hexdump: not a number: zz
> halt
halting
```

QEMU then exits with status 33. The first 24 bytes at `0x100000` are the
image's own Multiboot2 header (magic `0xe85250d6`, little-endian). The
digest is SHA-256 of `abc`.

A panic ends the run through the panic handler (QEMU exits with 37):

```text
> panic
panicking on purpose
PANIC: reached an `unreachable` expression at commands/system.lpfree:21
```

On AArch64 the memory is the virt machine's RAM, `0x40000000`-`0x4fffffff`,
the free RAM starts at `0x44000000`, `ticks` reads the virtual counter, and
QEMU exits with 0 after `halt` and 2 after a panic:

```text
$ scripts/qemu.sh aarch64 build/shell-aarch64.elf
loup-cmd-bare-shell 0.1.0 on aarch64, console PL011 UART at MMIO 0x9000000
type help for the commands
> poke 0x44000000 0x61
0x44000000: 0x00 -> 0x61
> sha256 0x44000000 1
ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb
> ticks
ticks: 1294929 CNTVCT counts since boot
> halt
halting
```

### Commands

| Command | Does |
|---|---|
| `help` | lists the commands, the number syntax, the memory range and the keys |
| `echo [WORD]...` | prints the words separated by single spaces |
| `peek ADDR` | prints the byte at ADDR |
| `poke ADDR VALUE` | writes the byte VALUE at ADDR, printing old and new value |
| `hexdump ADDR LEN` | LEN bytes from ADDR, in the format of `hexdump -C` |
| `ticks` | the free-running counter (TSC, or CNTVCT on AArch64) since the shell started |
| `sha256 ADDR LEN` | the SHA-256 digest of LEN bytes from ADDR |
| `panic` | stops through the panic handler |
| `halt` | stops and exits QEMU |

Numbers are decimal or hex with `0x`. Memory commands refuse addresses
outside the board's mapped memory instead of faulting.

Editing keys: Backspace or Delete erases a character, Ctrl-U the whole line,
Ctrl-C abandons the line; Enter is CR or LF. A line holds up to 80
characters and 16 words.

Errors are reported as `COMMAND: message` and the shell carries on:
`missing argument; usage: ...`, `too many arguments; usage: ...`,
`not a number: WORD`, `0xADDR+LEN is outside memory START-END`,
`0xVALUE does not fit in a byte`, and
`unknown command: WORD (type help for the commands)`.

### Exit statuses

| Event | Status | QEMU exit status, x86-64 | QEMU exit status, AArch64 |
|---|---|---|---|
| `halt` | 0 | 33 | 0 |
| panic | 2 | 37 | 2 |

## Differences from the roadmap

- `peek` and `poke` work on single bytes (no word sizes).
- `ticks` reads the CPU's free-running counter rather than counting timer
  interrupts; interrupts are the subject of
  [loup-cmd-bare-timer](https://github.com/myronccai/loup-cmd-bare-timer).
- The aarch64 version, optional in the roadmap, is included and tested.
- The SHA-256 core keeps 32-bit words in `uint64` and masks them: in Loup
  1.26.0 freestanding builds `uint32` arithmetic does not wrap.
- There are no separate unit tests: `loup-bootstrap test --freestanding`
  (1.26.0) cannot import project modules or compile code with
  `buffer[uint8, N]`. The scripted sessions check every command, error
  message and editing key, and SHA-256 against known digests.

## Layout

```text
package.lppkg                 # x86_64 board: manifest (the default image)
boards/aarch64/package.lppkg  # aarch64 board: manifest
linker/                       # x86_64.ld (1 MiB), aarch64.ld (0x40080000)
source/main_x86_64.lpfree     # x86_64 entry, COM1, TSC, isa-debug-exit, panic handler
source/main_aarch64.lpfree    # aarch64 entry, PL011, CNTVCT, semihosting exit, panic handler
source/appinfo.lpfree         # name, version, statuses
source/platform/              # Board, console
source/cli/                   # line editor, words and numbers, usage, the shell loop
source/commands/              # echo, memory, ticks, sha256, hash, system
scripts/qemu.sh               # the QEMU command line for each board
tests/boot.sh                 # boot tests (make boot)
tests/sessions/               # what the tests type
tests/expected/               # the transcripts they expect
specs/bare-shell/             # requirements, design, tasks
```

[AGENTS.md](AGENTS.md) has every build and test command and the conventions
for changing the code.

## License

[MIT](LICENSE), copyright 2026 Code Craft AI LLC. The Loup skill in
[`skills/loup-programmer/`](skills/loup-programmer/) is copied from the Loup
project and is not covered by this license; it keeps the Loup project's terms.
