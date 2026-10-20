# AGENTS.md

This repository is `loup-cmd-bare-shell`, an interactive shell on the
serial port of a bare-metal machine, in the loup-cmd series of Loup example
applications. It is `freestanding` Loup (`.lpfree`): no operating system,
no heap, no exceptions. It is built for two boards (x86-64 on QEMU `pc`,
AArch64 on QEMU `virt`) and tested by typing scripted sessions into QEMU.

## Skills

| Skill | Location | Use it when |
|-------|----------|-------------|
| `loup-programmer` | [skills/loup-programmer/SKILL.md](skills/loup-programmer/SKILL.md) | Writing, reviewing, debugging or explaining Loup code: `.lpscr`, `.loup`, `.lphc`, `.lpweb` or `.lpfree` source files, `.lppkg` manifests, `@mode(...)` directives, or the `loup` / `loup-bootstrap` commands. |

Read `skills/loup-programmer/SKILL.md` and
`skills/loup-programmer/references/freestanding.md` before writing or
changing any Loup code in this repository. Load the other references only as
needed.

## Code layout

```text
.
├── package.lppkg                # x86_64 board: [build] entry/mode/arch/panic, [linker], [freestanding]
├── boards/aarch64/package.lppkg # aarch64 board: the same keys; paths relative to its directory
├── linker/                      # x86_64.ld (1 MiB, boot headers first), aarch64.ld (0x40080000)
├── source/                      # all Loup code; modules import each other by path from here
│   ├── main_x86_64.lpfree       # x86_64 entry file: boot headers, _start, COM1, TSC, isa-debug-exit, @panic_handler
│   ├── main_aarch64.lpfree      # aarch64 entry file: _start, PL011, CNTVCT, semihosting exit, @panic_handler
│   ├── appinfo.lpfree           # APP_NAME, APP_VERSION, STATUS_*
│   ├── platform/
│   │   ├── board.lpfree         # struct Board: names, memory window, ticks and exit functions
│   │   └── console.lpfree       # attach(put, get), getByte, putByte, puts, putDec, putHex, putAddr
│   ├── cli/
│   │   ├── line.lpfree          # readLine(): the line editor
│   │   ├── args.lpfree          # splitWords, wordIs, parseNumber -> Result[uint64, ArgError], expectArgs
│   │   ├── usage.lpfree         # banner, help, usage lines
│   │   └── app.lpfree           # run(board): the shell loop, dispatch, error reports
│   └── commands/
│       ├── echo.lpfree          # echo
│       ├── memory.lpfree        # peek, poke, hexdump, checkRange
│       ├── ticks.lpfree         # ticks
│       ├── sha256.lpfree        # SHA-256 over memory (masked uint64 words)
│       ├── hash.lpfree          # the sha256 command
│       └── system.lpfree        # panic, halt
├── scripts/qemu.sh              # the QEMU command line for each board
├── tests/
│   ├── boot.sh                  # types the sessions into QEMU, compares transcripts and exit statuses
│   ├── sessions/                # input: one command per line; \b, \x15, \x03 for the editing keys
│   └── expected/                # transcripts (cat -v; the ticks value as N)
├── specs/bare-shell/            # requirements.md, design.md, tasks.md
├── skills/loup-programmer/      # the Loup skill and its references
├── .github/workflows/ci.yml     # installs lld, QEMU and Loup, runs `make ci`, uploads the images
└── build/                       # build output (git-ignored)
```

## Build, run and test

Prerequisites: Linux x86-64, Loup 1.26.0 (`loup` and `loup-bootstrap` on
`PATH`), `make`, `clang`, `ld.lld`, `qemu-system-x86_64` and
`qemu-system-aarch64`.

| Task | Command | Notes |
|------|---------|-------|
| Type-check | `make check` | `loup-bootstrap check` at the root and in `boards/aarch64` |
| Build | `make build` | `build/shell-x86_64.elf`, `build/shell-aarch64.elf` |
| Build one board | `make build/shell-aarch64.elf` | `loup build --target freestanding --arch aarch64 -o ... boards/aarch64` |
| Boot tests | `make boot` | `tests/boot.sh`: four sessions, transcripts and exit statuses compared |
| Refresh expected transcripts | `UPDATE=1 bash tests/boot.sh` | then read `git diff tests/expected` before committing |
| Use the shell | `make run` / `make run ARCH=aarch64` | Ctrl-C goes to the shell; type `halt` to leave |
| Everything CI runs | `make ci` | check, build, boot |
| Clean | `make clean` | removes `build/` and `.temp/` |

Run `make ci` before reporting a change as done. `loup-bootstrap check`
accepts things the freestanding back ends reject or miscompile, so only a
boot proves a change.

Do not call `loup check` on Linux x86-64 (the self-hosted driver refuses it);
use `loup-bootstrap check`. `loup-bootstrap test --freestanding` does not work
for this project in 1.26.0; test through `tests/sessions/` instead.

## Making a change

1. Update the spec in `specs/bare-shell/`.
2. Change the code under `source/`.
3. Add the new behaviour to `tests/sessions/x86_64.txt` and `aarch64.txt`.
4. Run `make build`, then `UPDATE=1 bash tests/boot.sh`, read the diff of
   `tests/expected/`, then `make ci`.
5. Tick the finished tasks in `specs/bare-shell/tasks.md`.

## Conventions

- Every source file is `@mode(freestanding)` with the `.lpfree` extension.
  Each board's entry file has the single `@entry` (`_start`), which calls
  `kernelMain`.
- Code that differs per CPU lives only in the two `main_*.lpfree` files.
  Everything else must build for both boards.
- Modules import each other by path from `source/`:
  `from cli.args import (parseNumber);`. No relative imports.
- No heap, no exceptions, no `list`/`dict`, no string building: use
  `buffer[T, N]`, module-level variables, `Result` and `match`. Commands
  return `Result[int, ArgError]` and use `?`.
- Sized integers (`uint8` ... `uint32`) do not wrap in 1.26.0 freestanding
  builds. When wrap-around matters, compute in `uint64` and mask.
- Do not name a local that holds a function value like a builtin (`exit`,
  `read`): the call links to the C symbol. Use `stop`, `readClock`.
- Leave the 16550's FIFO control register alone; enabling or clearing the
  FIFOs drops input that QEMU has already delivered.
- Output ends lines with `\n` only; QEMU's stdio adds the carriage return.
- Keep `APP_VERSION` in `source/appinfo.lpfree` equal to `version` in both
  manifests.
- The skill documents toolchain 1.25.1; this repository targets 1.26.0. When
  they disagree, trust the toolchain's behaviour.
