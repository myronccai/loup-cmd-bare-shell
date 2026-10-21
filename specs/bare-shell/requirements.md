# Requirements: bare-shell

## Introduction

`bare-shell` is a command-line program with no operating system: an
interactive shell on the serial port of a bare-metal Loup image. It has the
shape of the other loup-cmd repositories (argument parsing in `cli/`,
commands in `commands/`, errors reported as `NAME: message`), but it reads
its own keystrokes, edits its own line and touches memory directly. It runs
on two boards: x86-64 (QEMU `pc`) and AArch64 (QEMU `virt`).

## Requirements

### Requirement 1: Boot and prompt

**User Story:** As a user at a serial terminal, I want a banner and a prompt
when the machine starts so that I know the shell is ready.

#### Acceptance Criteria

1. WHEN the image boots, THE shell SHALL print
   `loup-cmd-bare-shell 0.1.0 on ARCH, console UART`, then
   `type help for the commands`, then the prompt `> `.
2. THE x86_64 image SHALL use the 16550 UART at I/O port `0x3F8` (COM1) for
   input and output; THE aarch64 image SHALL use the PL011 UART at
   `0x0900_0000`.
3. THE shell SHALL use no heap and no exceptions.

### Requirement 2: Line editing

**User Story:** As a user, I want to correct my typing so that a mistake
does not run the wrong command.

#### Acceptance Criteria

1. WHEN a printable character is typed and the line has fewer than 80
   characters, THE shell SHALL add it to the line and echo it; otherwise THE
   shell SHALL ring the bell (BEL).
2. WHEN Backspace (BS) or Delete (DEL) is typed and the line is not empty,
   THE shell SHALL remove the last character and erase it on screen
   (BS, space, BS).
3. WHEN Ctrl-U is typed, THE shell SHALL remove and erase the whole line.
4. WHEN Ctrl-C is typed, THE shell SHALL print `^C`, abandon the line and
   prompt again.
5. WHEN CR or LF is typed, THE shell SHALL end the line; a LF that directly
   follows a CR SHALL be ignored. Other control characters SHALL be ignored.
6. THE shell SHALL split the line into words at spaces; an empty line SHALL
   just prompt again, and a line of more than 16 words SHALL be refused.

### Requirement 3: Commands

**User Story:** As a developer on a new board, I want to inspect and change
memory and check data so that I can explore the machine without a debugger.

#### Acceptance Criteria

1. `help` SHALL list the commands, the number syntax, the memory range, the
   free RAM address and the editing keys.
2. `echo [WORD]...` SHALL print the words separated by single spaces.
3. `peek ADDR` SHALL print `0xADDR: 0xVV`, the byte at ADDR.
4. `poke ADDR VALUE` SHALL write the byte VALUE at ADDR and print
   `0xADDR: 0xOLD -> 0xNEW`.
5. `hexdump ADDR LEN` SHALL print LEN bytes from ADDR in the format of
   `hexdump -C`: 8 hex digits of address, 16 bytes in hex in two groups of
   8, and the printable characters between `|` bars.
6. `ticks` SHALL print `ticks: N CLOCK counts since boot`, where CLOCK is the
   board's free-running counter (the TSC on x86_64, CNTVCT on aarch64).
7. `sha256 ADDR LEN` SHALL print the SHA-256 digest of LEN bytes from ADDR
   in lower-case hex, computed in the freestanding subset with 32-bit words
   kept in `uint64` and masked.
8. `panic` SHALL stop the machine through the panic handler.
9. `halt` SHALL print `halting` and end the run with status 0.
10. Memory commands SHALL access memory one byte at a time through
    `Volatile`.
11. Every line with words SHALL be recorded before it runs; `history`
    SHALL print the recorded lines oldest first, each as its number
    right-aligned in 5 columns, two spaces and the line. WHEN the record
    store (4 KiB of text, 1024 lines) is full, THE shell SHALL empty it and
    keep numbering from where it was.

### Requirement 4: Errors

**User Story:** As a user, I want clear messages for mistakes so that I can
fix the command instead of crashing the machine.

#### Acceptance Criteria

1. THE shell SHALL accept numbers in decimal or as hex with a `0x` prefix;
   WHEN a word is not such a number or does not fit in 64 bits, THE shell
   SHALL print `CMD: not a number: WORD`.
2. WHEN a command has too few or too many arguments, THE shell SHALL print
   `CMD: missing argument; usage: USAGE` or
   `CMD: too many arguments; usage: USAGE`.
3. WHEN an address range is not inside the board's mapped memory (x86_64
   `0x0`-`0x3fffffff`, aarch64 `0x40000000`-`0x4fffffff`), THE shell SHALL
   print `CMD: 0xADDR+LEN is outside memory START-END` and not touch it.
4. WHEN a poke value is above 255, THE shell SHALL print
   `poke: 0xVALUE does not fit in a byte`.
5. WHEN the first word is not a command, THE shell SHALL print
   `unknown command: WORD (type help for the commands)`.
6. Command errors SHALL be `Result` values; none SHALL stop the shell.

### Requirement 5: Stopping

**User Story:** As a CI pipeline, I want the run to end with a status so
that a scripted session can be checked without parsing for a hang.

#### Acceptance Criteria

1. WHEN `halt` runs, THE x86_64 image SHALL write `0x10` to `isa-debug-exit`
   (QEMU exits with 33) and THE aarch64 image SHALL call semihosting
   `SYS_EXIT` with 0.
2. WHEN a panic happens, THE panic handler SHALL mask interrupts, print
   `PANIC: MESSAGE at FILE:LINE` and exit with status 2 (QEMU exits with 37 on
   x86_64, 2 on aarch64).

### Requirement 6: Build and test

**User Story:** As a maintainer, I want one command that checks, builds and
drives both images so that CI and local runs agree.

#### Acceptance Criteria

1. `make check` SHALL type-check both boards with `loup-bootstrap check`.
2. `make build` SHALL build `build/shell-x86_64.elf` and
   `build/shell-aarch64.elf` with `loup build --target freestanding`.
3. `make boot` SHALL type each session in `tests/sessions/` into the serial
   port of an image under QEMU, with a time limit, and compare the
   transcript and QEMU's exit status with `tests/expected/`.
4. `make ci` SHALL run `check`, `build` and `boot`.
