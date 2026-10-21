# Design: bare-shell

## Overview

A board brings the machine up, attaches its UART to the console and calls
`cli.app.run(board)`, which never returns: it prompts, reads a line with the
line editor, splits it into words and runs the command. Commands return
`Result[int, ArgError]`; the dispatcher prints errors in the
`NAME: message` style and prompts again. Only `halt` (through the board's
exit function) and a panic (through the board's `@panic_handler`) end the
run.

```text
QEMU -> _start -> kernelMain (board) -> run(board) (cli.app)
                                          loop: prompt, readLine, splitWords,
                                                dispatch -> cmdX(board)
                                                   Err(e) -> reportError
```

## Boards

| | x86_64 | aarch64 |
|---|---|---|
| Manifest | `package.lppkg` | `boards/aarch64/package.lppkg` |
| Linker script | `linker/x86_64.ld` (1 MiB) | `linker/aarch64.ld` (`0x4008_0000`) |
| Entry file | `source/main_x86_64.lpfree` | `source/main_aarch64.lpfree` |
| UART | 16550 at port `0x3F8`: LSR bit 0 (data ready) and bit 5 (transmit empty), `in`/`out` | PL011 at `0x0900_0000`: FR bit 4 (receive empty) and bit 5 (transmit full), `Volatile` |
| Counter for `ticks` | `rdtsc` | `mrs cntvct_el0` |
| Memory the commands may touch | `0x0`-`0x3fffffff` (the identity map the entry stub builds) | `0x40000000`-`0x4fffffff` (RAM with `-m 256M`) |
| Free RAM (for examples) | `0x200000` | `0x4400_0000` |
| Exit | `isa-debug-exit`, QEMU status `(0x10 \| status) << 1 \| 1` | semihosting `SYS_EXIT`, QEMU status `status` |

The COM1 driver does not touch the FIFO control register: enabling or
clearing the FIFOs discards input QEMU may already have delivered (a
scripted session starts sending at once).

## Modules

| Module | Contents |
|---|---|
| `source/appinfo.lpfree` | name, version, statuses |
| `source/platform/board.lpfree` | `struct Board`: names, memory window, scratch address, `ticks` and `exit` as function values |
| `source/platform/console.lpfree` | `attach(put, get)`, `getByte`, `putByte`, `puts`, `newline`, `putDec` (no buffer), `putHex`, `putAddr` |
| `source/cli/line.lpfree` | the line editor: `readLine()` into `buffer[uint8, 80]` |
| `source/cli/args.lpfree` | `splitWords` (start/length of up to 16 words, no copies), `wordIs`, `parseNumber(w): Result[uint64, ArgError]`, `expectArgs` |
| `source/cli/usage.lpfree` | banner, help, the usage line of each command |
| `source/cli/app.lpfree` | `run(board)`, `dispatch`, `reportError` |
| `source/commands/echo.lpfree` | `cmdEcho`, `putWord` |
| `source/commands/memory.lpfree` | `checkRange`, `cmdPeek`, `cmdPoke`, `cmdHexdump` |
| `source/commands/ticks.lpfree` | `markBoot`, `cmdTicks` |
| `source/commands/sha256.lpfree` | SHA-256 over memory (`sha256(addr, len)`, `digestWord(i)`) |
| `source/commands/hash.lpfree` | `cmdSha256` |
| `source/commands/system.lpfree` | `cmdHalt`, `cmdPanic` |
| `source/commands/history.lpfree` | `historyInit`, `recordLine`, `cmdHistory` over a `debug.recording` `RecordStream` |

## SHA-256 in the freestanding subset

The L20 core rewritten without a heap: the round constants, state and
padded tail are module-level `buffer`s (constants are assigned at the start
of each hash, since buffers have no initializer syntax); the message
schedule is an `onstack` local of `compress` under `@no_zero_locals`, as it
is written in full before it is read. Each 32-bit word is a `uint64` masked
with `0xFFFFFFFF` after every addition and rotation, because 1.26.0
freestanding builds do not wrap `uint32` arithmetic. `compress` takes a
block's address and reads it through a 64-byte `buffer` overlay
(`@unsafe("overlay: ...")`), so full blocks are hashed where they lie in
memory; the remainder, the `0x80` marker and the 64-bit bit length go into
a 128-byte tail (one block, or two when the remainder is 56 bytes or more),
which `compress` reads through the same overlay.

## History

A typed line is an input event, so the history is a `debug.recording`
`RecordStream`: each line's bytes go into the stream's 4 KiB arena
(`rs_arena_reserve`) and one record points at them (`rs_record_arena`,
payload = offset and length). `history` replays the records
(`rs_replay`, `rs_payload_offset`, `rs_payload_len`). The stream never
overwrites, so when the arena or the 1024-record ring is full the shell
rotates it (`rs_rotate`) and keeps the numbering in `firstNumber`.

## Differences from the roadmap

- The memory commands work on bytes; `peek`/`poke` have no width option.
- `ticks` reads the CPU's free-running counter (the TSC, or CNTVCT on
  aarch64), counted from the shell's start; there is no timer interrupt in
  this example (that is `loup-cmd-bare-timer`).
- Both x86-64 and aarch64 are built and tested (aarch64 was optional).
- Addresses outside the mapped memory are refused rather than faulting: the
  image has no exception handlers.

## Error handling

`ArgError` has the variants `Missing`, `TooMany`, `BadNumber(word)`,
`OutOfRange(start, len)` and `NotAByte(value)`. Commands propagate them
with `?`; `reportError` turns them into messages. Panics (the `panic`
command, or a bounds-check failure under `bounds = "trap"`) reach the
board's `@panic_handler` (`panic = "custom"`).

## Testing

`tests/boot.sh` types `tests/sessions/x86_64.txt`, `aarch64.txt` and
`panic.txt` into the serial port of each image, and `history.txt` (62 long
lines, enough to make the history start again) into the x86_64 image,
under `scripts/qemu.sh` with a 60-second limit. The sessions exercise every command, every error, and
the editing keys (`\b`, `\x15`, `\x03` in the files). The transcript, with
control characters shown by `cat -v` and the `ticks` value replaced by `N`,
is compared with `tests/expected/`, and QEMU's exit status with 33/37
(x86_64) or 0/2 (aarch64). The SHA-256 cases cover the empty message,
`abc`, 56 zero bytes (the padding needs a second block) and 200 zero
bytes (three blocks read from memory, then the tail).
