# Modular robotics installer

- **[BEHAVIOR.md](./BEHAVIOR.md)** — Ordered phases, flags, idempotency, and TUI behavior (contract for contributors).
- **`bootstrap.sh`** — Intended for `curl | bash`: downloads this directory from GitHub raw (pinned ref) into a temp dir and runs `main.sh`.
- **`main.sh`** — Entrypoint when you already have the repo cloned; sources `lib/*.sh` in order.
- **`lib/08-phase-verify.sh`** — After each phase, quick smoke checks (see [BEHAVIOR.md](./BEHAVIOR.md)).
- **TTY** — If stdout is a terminal *before* logging is wired through `tee`, `ROBOTICS_CLI_TTY=1` and each phase prints an extra banner plus bullet “plan” lines.

## Verify downloads (optional)

After updating any script, regenerate checksums from the repo root:

```bash
cd install && sha256sum bootstrap.sh main.sh lib/*.sh | sort -k2 > SHA256SUMS
```

To audit before running bootstrap:

```bash
curl -fsSL "https://raw.githubusercontent.com/2vyy/robotics-docs/main/install/bootstrap.sh" -o bootstrap.sh
# Compare the printed checksum with the matching line in SHA256SUMS on the same commit.
sha256sum bootstrap.sh
```

## Local run

```bash
chmod +x install/main.sh
./install/main.sh --help
./install/main.sh --dry-run --no-ros --no-gazebo --no-px4 --no-pip
```

## History

The pre-modular single-file `robotics-setup.sh` remains in **git history** if you need to diff behavior; the live entrypoint is `install/main.sh` (or `./robotics-setup.sh` at repo root).
