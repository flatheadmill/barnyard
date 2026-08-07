# Barnyard

Barnyard is configuration management for the machines that live outside your orchestrator — the foundational VMs, the services Kubernetes deliberately does not cover. It is written in Zsh and shipped as a single executable: you install it by copying one file to `/usr/local/bin/barnyard`. It is inspired by aviary.sh, and it is diff-based — you describe the state a machine should be in, each operator checks for drift and converges toward it.

This README is also where Barnyard's decisions are written down and kept. A decision recorded here is settled — we build on it rather than relitigate it. If this outgrows a README, it becomes a Markdown book; until then, it lives here.

## Install

`barnyard control prepare ubuntu --destination <ssh-destination>` pipes a bootstrap script to the box over SSH as `sudo bash`: it installs the dependencies, installs zshctl, and writes the single-file `barnyard` to `/usr/local/bin/barnyard`.

Dependencies on a prepared machine: `zsh`, `gnupg2` (gpg), `git`, `age`, `rsync`, and — for JSON configuration — `jo` and `jq`. Ubuntu is what we run; another distribution is only the package step, so `barnyard control prepare fedora` installs the same set with `dnf` and copies the same one file. The binary does not change; only the package manager does.

To deploy a new Barnyard, copy the local file up. There is no upgrade dance and no version negotiation between a client and a server — the file you built is the file the machine runs.

## Commands

- `barnyard version` — the version.
- `barnyard completions` — shell completions.
- `barnyard extend` — the zshctl extension mechanism.
- `barnyard control <cmd>` — the operator side: `prepare`, `bootstrap`, `commit`, `configure`, `generate`.
- `barnyard agent <cmd>` — the machine side: `clone`, `commit`, `gpg`, `prepare`, `ssh`, `apply`, `always`. `apply` and `always` are run by hand on the box; the rest are reached in by `control` over SSH.
- `barnyard <operator> <...>` — a user operator. Any top-level word that is not one of the five reserved above.

## Design

**Barnyard is one executable.** Not a tarball, not a `.deb`, not an `.rpm` — a single file. zshctl lets the whole program live in one file: the functions are declared in one place and the help is heredocs, so there is nothing to package and nothing to unpack. Every other simplicity here follows from this one.

**One program, five reserved words.** There is one program, `barnyard`, and it reserves exactly five top-level words — `control`, `agent`, `version`, `extend`, `completions`. Every other word expressible in Unicode belongs to the user for their operators. The five are frozen: when Barnyard needs a new base command it nests under a word it already owns (`barnyard control <new-thing>`); it never claims a sixth top-level word. That is the whole contract — these five are Barnyard's forever, the rest are yours — and it stays honest only because it is never grown.

**`control` and `agent`, not client and server.** `control` is the operator side, run where you sit. `agent` is the machine side, run on the box — some commands by hand (`apply`, `always`), some reached in over SSH by `control` (`control bootstrap` calls `agent gpg trust`). It is not client and server, because the machine side does not serve requests; it acts. `control` directs; the `agent` does the work.

**User operators are top-level commands.** A user's operator is a top-level word — `barnyard postgresql hba apply`. This is exactly why the reserved set is kept to five: every word Barnyard keeps is a word an operator can never be named.

**Barnyard operates a program; it is not extended into.** A user writes one zshctl program of their own — their operators, their namespace — and Barnyard operates it, because it knows the zshctl shape. The user does not extend two bases and inherit their collisions; Barnyard composes over the user's program. (Open: this rests on zshctl offering a way to *drive* a program rather than only `extend` it into a shared namespace — confirm the mechanism before leaning on it.)

**Configuration is canonical JSON.** Per-machine configuration is canonical JSON, built with `jo` and canonicalized with `jq -S`, so a one-field change is a one-line diff. The data was always structured name/value and name/list pairs; JSON is its native shape, and `jq`'s array-merge is the same operation as composing operators that each append to a list.

**The farm stays in the prose.** The metaphor — the barnyard, the chores, the hand — is welcome in the man pages, the comments, and the help text, where it costs nothing and warms the reading. It stays out of the executables and command names, which are plain, because a name a stranger has to decode is a name that failed. `control` and `agent`, never `farmer` and `farmhand`.

## Recipes

**Apply on a machine.** `barnyard agent apply` converges the machine, run by hand on the box; `barnyard agent always` is the always-run pass. A single operator is applied through its own command, `barnyard <operator> apply`.

**Prepare another distribution.** The one file is portable; the distribution is only the package step. `barnyard control prepare fedora` installs `gpg`, `zsh`, `jo`, `jq` with `dnf`, then copies `barnyard` to `/usr/local/bin/` — off to the races.

## See also

- `notes.md` — the legacy `modules/` directory and machine config-file format.
- `args.md` — the zshctl argument-parsing forms.
