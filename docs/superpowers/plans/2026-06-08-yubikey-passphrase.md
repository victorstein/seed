# YubiKey-backed passphrase for `gpg-key.enc` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-encrypt `gpg-key.enc` with the high-entropy static string stored on the user's YubiKey static-password slot, so the `bootstrap.sh` authentication gate is unlocked by touching the YubiKey instead of typing a memorable passphrase.

**Architecture:** A small `bootstrap.sh` quoting fix, a `.gitignore` belt-and-suspenders rule, a public-facing README update, and a private-to-this-machine helper script that performs the symmetric re-encryption with byte-identical encoding to what `bootstrap.sh` uses to consume the passphrase. The GPG keypair, all `*.gpg` entries, and the `pass` workflow are untouched. Recovery: a `pass` entry plus an offline vault copy of the static string.

**Tech Stack:** bash, GnuPG (symmetric `--cipher-algo AES256 --s2k-mode 3 --s2k-digest-algo SHA512`), `pass`, `ykman` (preconditions verification only — not invoked from helper), `shred`, `cmp`, `shasum`.

**Spec:** `docs/superpowers/specs/2026-06-08-yubikey-passphrase-design.md`

---

## Pre-flight: assumed state of the world

Before Task 1, confirm:

- Working tree is clean: `git status` shows nothing untracked or modified.
- You are on `main` and have just pulled.
- `gpg`, `pass`, `shasum`, `shred`, `ykman` are all on `PATH`. macOS Homebrew installs all of these.
- The GPG secret key `E84B48EB778BF9E6` is imported and trusted on this machine (otherwise you cannot create the recovery `pass` entry in Task 7). Verify: `gpg --list-secret-keys E84B48EB778BF9E6`.
- A YubiKey is plugged in and the user knows the current memorable passphrase for `gpg-key.enc`.

---

### Task 1: Verify YubiKey slot preconditions

This task confirms the YubiKey is programmed exactly as the spec assumes. If anything is off, fix it before continuing — the wrong setup here leads to a locked-out `gpg-key.enc`.

**Files:**
- No code changes. Verification only.

- [ ] **Step 1: Identify the static-password slot.**

Run: `ykman otp info`

Expected output: a table showing `Slot 1` and `Slot 2`, each either `programmed` or `empty`, with the configuration type for programmed slots. Identify which slot holds the static password (typically `Slot 2: programmed (Static password)` if the user kept the factory Yubico OTP on slot 1).

If neither slot reports `Static password`, STOP. Program one with a 38-char random ASCII string before continuing. Reference (run only if you intend to reprogram — this overwrites the slot):

```bash
ykman otp static --generate --length 38 --keyboard-layout US 2
```

Record the chosen slot number. You'll need it for the recovery `pass` entry in Task 7.

- [ ] **Step 2: Confirm slot terminator settings.**

Open the YubiKey Manager GUI (`ykman-gui`) → Applications → OTP → click the static-password slot → Configure.

Verify:
- **Append CR**: ON (checked).
- **Append TAB**: OFF (unchecked).
- **Keyboard layout**: US.

If any are wrong, fix them and re-confirm. Close the GUI without overwriting the slot if everything is already correct.

(There is no `ykman` CLI subcommand that prints the existing slot's "Append CR" / "Append TAB" flags without reprogramming, so the GUI is the safe inspection path.)

- [ ] **Step 3: Smoke-test the touch.**

In a new terminal window, run:

```bash
printf "Touch your YubiKey now and then press Enter: "
read -s -r SMOKE
echo
printf 'length=%d\n' "$(printf '%s' "$SMOKE" | wc -c | tr -d ' ')"
printf 'sha256='; printf '%s' "$SMOKE" | shasum -a 256
unset SMOKE
```

Expected: a length somewhere between 16 and 38 (depending on how the slot was programmed) and a SHA-256 hash. Record the length and the first 8 hex chars of the SHA-256. You will compare against these in Task 6.

If length is 0, the slot is empty or the touch did not register. STOP and resolve before continuing.

- [ ] **Step 4: Commit nothing.**

This task only verifies state. No git changes.

---

### Task 2: Patch `bootstrap.sh` to use `read -s -r`

The current `read -s` (line 131) strips backslashes from the passphrase. A YubiKey static string with a backslash would decrypt fine in the helper (which uses `-r`) but fail in `bootstrap.sh`. Adding `-r` here closes that gap regardless of whether the slot happens to contain a backslash today.

**Files:**
- Modify: `bootstrap.sh:131`

- [ ] **Step 1: Confirm the current line.**

Run: `grep -n 'read -s AUTH_PASSWORD' bootstrap.sh`

Expected output:

```
131:        read -s AUTH_PASSWORD < /dev/tty
```

If the line number is different, the file has shifted since this plan was written — update Task 2 references accordingly and continue.

- [ ] **Step 2: Apply the edit.**

Change line 131 from:

```bash
        read -s AUTH_PASSWORD < /dev/tty
```

to:

```bash
        read -s -r AUTH_PASSWORD < /dev/tty
```

- [ ] **Step 3: Verify the edit.**

Run: `grep -n 'read -s -r AUTH_PASSWORD' bootstrap.sh`

Expected output:

```
131:        read -s -r AUTH_PASSWORD < /dev/tty
```

Run: `bash -n bootstrap.sh`

Expected: no output (syntax OK).

- [ ] **Step 4: Confirm dry-run still works.**

Run: `./bootstrap.sh --dry-run 2>&1 | head -40`

Expected: the banner, the `DRY-RUN MODE` block, and `[INFO] Skipping authentication in dry-run mode`, exiting cleanly into subsequent dry-run steps. No prompt for a password.

- [ ] **Step 5: Do NOT commit yet.**

The bootstrap change, the gitignore change, the README change, the new `gpg-key.enc`, and the recovery `pass` entry are committed together in Task 8 (after Task 6 succeeds). If the helper fails, leaving an uncommitted `-r` flag in the tree is harmless and easy to revert.

---

### Task 3: Add `*.bak` to `.gitignore`

Belt and suspenders so a stray `git add -A` cannot commit `gpg-key.enc.bak` (the old, weakly-encrypted blob) after Task 6.

**Files:**
- Modify: `.gitignore`

- [ ] **Step 1: Confirm `*.bak` is not already ignored.**

Run: `grep -n '\.bak' .gitignore`

Expected output: no matches.

- [ ] **Step 2: Add the rule.**

Append to `.gitignore`, immediately after the existing `*.gpg diff=gpg` line (or at the end of the file if that's clearer in context). Replace the entire `.gitignore` with:

```gitignore
# Prevent accidental commit of unencrypted secrets
*.asc
*.pem
*.key
*.pub
id_*
!*.gpg
!*.enc

# OS and editor files
.DS_Store
*.swp
*.swo
*~
.vscode/
.idea/

# Temp files
*.tmp
*.temp
/tmp/

# Shell history (in case someone runs commands in this dir)
.bash_history
.zsh_history

# GPG agent files
.gpg-agent-info
*.lock

# `pass` extensions live in the dotfiles repo and are symlinked here per-machine
# by bootstrap.sh. The symlink paths are machine-specific (point into ~/.dotfiles)
# so they must never be committed.
.extensions/

# Backups (e.g. gpg-key.enc.bak during the YubiKey re-encryption procedure).
# These hold the old, weakly-encrypted blob and must never be committed.
*.bak
```

Note: the `.gitattributes` line `*.gpg diff=gpg` lives in `.gitattributes`, NOT `.gitignore`. Do not move it.

- [ ] **Step 3: Verify the rule.**

Run: `grep -n '\*\.bak' .gitignore`

Expected output:

```
<line-number>:*.bak
```

Simulate the ignore rule before any `.bak` file exists:

```bash
git check-ignore -v gpg-key.enc.bak
```

Expected output: `.gitignore:<line>:*.bak	gpg-key.enc.bak`

If `git check-ignore` prints nothing or exits 1, the rule didn't take — re-check the file.

- [ ] **Step 4: Do NOT commit yet.** Bundled into Task 8.

---

### Task 4: Update `README.md`

Reflect the new UX without leaking the recovery location.

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Confirm current README.**

Run: `cat README.md`

Confirm the `## Requirements` section currently reads:

```
- Fresh macOS installation
- Internet connection
- Your GPG encryption password
```

- [ ] **Step 2: Apply the edit.**

Replace `README.md` in its entirety with:

````markdown
# Seed

Bootstrap script for setting up a new Mac.

## Quick Start

**Preview what will happen (dry-run):**
```bash
curl -fsSL https://raw.githubusercontent.com/victorstein/seed/main/bootstrap.sh | bash -s -- --dry-run
```

**Run the setup:**
```bash
curl -fsSL https://raw.githubusercontent.com/victorstein/seed/main/bootstrap.sh | bash
```

## What it does

1. Installs Xcode CLI tools
2. Installs Homebrew
3. Imports GPG key (prompts for password — touch your YubiKey)
4. Restores SSH keys from encrypted storage
5. Clones dotfiles and sets up symlinks
6. Installs all Homebrew packages

## Requirements

- Fresh macOS installation
- Internet connection
- Your YubiKey programmed with the static-password slot used for this repo,
  plugged into the new machine. Touch the key when the script prompts for the
  encryption password — do not type anything.

> **Lost the YubiKey?** Recovery requires the static string stored in your
> private offline vault. Without it, `gpg-key.enc` cannot be decrypted and
> the bootstrap cannot complete.
````

- [ ] **Step 3: Verify.**

Run: `grep -n 'YubiKey' README.md`

Expected: at least three matches — in `## What it does`, in `## Requirements`, and in the recovery note.

Run: `grep -ni '1password\|bitwarden\|vault location\|recovery/seed' README.md`

Expected: no matches. The README must not point at a specific password manager or pass entry.

- [ ] **Step 4: Do NOT commit yet.** Bundled into Task 8.

---

### Task 5: Write the re-encryption helper script

The helper lives **outside the repo**. It is never committed. It is the only piece of code that touches the plaintext GPG private key.

**Files:**
- Create: `/tmp/seed-reencrypt.sh` (do NOT place inside `~/.password-store`)

- [ ] **Step 1: Write the helper.**

Save the following as `/tmp/seed-reencrypt.sh`:

```bash
#!/bin/bash
# One-shot helper: re-encrypt ~/.password-store/gpg-key.enc with the static
# string typed by a YubiKey touch.
#
# This script is intentionally NOT in the repo. After a successful run, delete
# it: `shred -u /tmp/seed-reencrypt.sh` (or `rm` on macOS — shred not standard).
#
# All file paths are absolute. The script does not `cd` for you, but the spec
# requires the swap to happen inside ~/.password-store, which is enforced by
# the absolute paths to gpg-key.enc.

set -euo pipefail

STORE="$HOME/.password-store"
KEY="$STORE/gpg-key.enc"
KEY_NEW="$STORE/gpg-key.enc.new"
KEY_BAK="$STORE/gpg-key.enc.bak"

red()    { printf '\033[0;31m%s\033[0m\n' "$*" >&2; }
green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[1;33m%s\033[0m\n' "$*"; }

cleanup_tmp() {
    # Best-effort secure deletion. macOS lacks `shred`; fall back to overwrite + rm.
    for f in "$@"; do
        [[ -n "${f:-}" && -e "$f" ]] || continue
        if command -v shred &>/dev/null; then
            shred -u "$f" 2>/dev/null || rm -f "$f"
        else
            dd if=/dev/urandom of="$f" bs=1k count=16 conv=notrunc 2>/dev/null || true
            rm -f "$f"
        fi
    done
}

PLAIN_OLD=""
PLAIN_RT=""
PLAIN_RT2=""
PASS_TMP=""
PASS_TMP2=""

abort() {
    red "ABORT: $*"
    cleanup_tmp "$PLAIN_OLD" "$PLAIN_RT" "$PLAIN_RT2" "$PASS_TMP" "$PASS_TMP2"
    # Leave gpg-key.enc untouched if we never got to the rename.
    [[ -e "$KEY_NEW" ]] && cleanup_tmp "$KEY_NEW"
    exit 1
}

trap 'abort "interrupted"' INT TERM

# ── Step 0 ─────────────────────────────────────────────────────────────
[[ -f "$KEY" ]] || abort "$KEY not found"
[[ ! -e "$KEY_NEW" ]] || abort "$KEY_NEW already exists — clean up and rerun"
[[ ! -e "$KEY_BAK" ]] || abort "$KEY_BAK already exists — handle it before rerunning"

green "Working on: $KEY"

# ── Step 1: capture old passphrase, decrypt ────────────────────────────
printf 'Enter the CURRENT (memorable) passphrase for gpg-key.enc: '
read -s -r OLD_PASS
echo
[[ -n "$OLD_PASS" ]] || abort "empty old passphrase"

PLAIN_OLD=$(mktemp); chmod 600 "$PLAIN_OLD"
OLD_TMP=$(mktemp);   chmod 600 "$OLD_TMP"
printf '%s' "$OLD_PASS" > "$OLD_TMP"
unset OLD_PASS

if ! gpg --batch --yes --passphrase-file "$OLD_TMP" --decrypt "$KEY" > "$PLAIN_OLD" 2>/dev/null; then
    cleanup_tmp "$OLD_TMP"
    abort "decryption of $KEY failed — wrong passphrase?"
fi
cleanup_tmp "$OLD_TMP"

[[ -s "$PLAIN_OLD" ]] || abort "decrypted plaintext is empty"
green "Decrypted current gpg-key.enc OK."

# ── Step 2: capture YubiKey static string ──────────────────────────────
printf 'Touch your YubiKey now (and press Enter if Append CR is OFF): '
read -s -r YUBI_PASS
echo
[[ -n "$YUBI_PASS" ]] || abort "empty YubiKey capture — slot empty or touch missed"

# ── Step 3: sanity-check captured bytes ────────────────────────────────
YUBI_LEN=$(printf '%s' "$YUBI_PASS" | wc -c | tr -d ' ')
YUBI_SHA=$(printf '%s' "$YUBI_PASS" | shasum -a 256 | awk '{print $1}')
printf 'YubiKey capture: length=%d, sha256=%s\n' "$YUBI_LEN" "$YUBI_SHA"
yellow "Confirm length matches what \`ykman otp info\` reports for the slot."
printf 'Continue? [y/N]: '
read -r CONFIRM
[[ "$CONFIRM" == "y" || "$CONFIRM" == "Y" ]] || abort "user did not confirm capture"

# ── Step 4: re-encrypt to gpg-key.enc.new ──────────────────────────────
PASS_TMP=$(mktemp); chmod 600 "$PASS_TMP"
printf '%s' "$YUBI_PASS" > "$PASS_TMP"

gpg --batch --yes --symmetric \
    --cipher-algo AES256 \
    --s2k-mode 3 \
    --s2k-count 65011712 \
    --s2k-digest-algo SHA512 \
    --passphrase-file "$PASS_TMP" \
    --output "$KEY_NEW" \
    "$PLAIN_OLD"

[[ -s "$KEY_NEW" ]] || abort "re-encryption produced empty $KEY_NEW"
green "Wrote $KEY_NEW."

# ── Step 5: round-trip verification ────────────────────────────────────
PLAIN_RT=$(mktemp); chmod 600 "$PLAIN_RT"
if ! gpg --batch --yes --passphrase-file "$PASS_TMP" --decrypt "$KEY_NEW" > "$PLAIN_RT" 2>/dev/null; then
    abort "round-trip decrypt of $KEY_NEW failed with the captured passphrase"
fi
if ! cmp -s "$PLAIN_OLD" "$PLAIN_RT"; then
    abort "round-trip plaintext differs from original — refusing to swap"
fi
green "Round-trip verify OK."

# ── Step 6: second-touch test ──────────────────────────────────────────
printf 'Touch your YubiKey AGAIN to confirm consistent capture: '
read -s -r YUBI_PASS_2
echo
[[ -n "$YUBI_PASS_2" ]] || abort "empty second YubiKey capture"

YUBI_LEN_2=$(printf '%s' "$YUBI_PASS_2" | wc -c | tr -d ' ')
YUBI_SHA_2=$(printf '%s' "$YUBI_PASS_2" | shasum -a 256 | awk '{print $1}')
if [[ "$YUBI_LEN" != "$YUBI_LEN_2" || "$YUBI_SHA" != "$YUBI_SHA_2" ]]; then
    abort "second touch produced different bytes (len $YUBI_LEN vs $YUBI_LEN_2, sha $YUBI_SHA vs $YUBI_SHA_2) — slot inconsistent?"
fi

PASS_TMP2=$(mktemp); chmod 600 "$PASS_TMP2"
printf '%s' "$YUBI_PASS_2" > "$PASS_TMP2"
unset YUBI_PASS YUBI_PASS_2

PLAIN_RT2=$(mktemp); chmod 600 "$PLAIN_RT2"
if ! gpg --batch --yes --passphrase-file "$PASS_TMP2" --decrypt "$KEY_NEW" > "$PLAIN_RT2" 2>/dev/null; then
    abort "second-touch decrypt of $KEY_NEW failed"
fi
if ! cmp -s "$PLAIN_OLD" "$PLAIN_RT2"; then
    abort "second-touch plaintext differs from original — refusing to swap"
fi
green "Second-touch verify OK."

# ── Step 7: swap files ─────────────────────────────────────────────────
mv "$KEY"     "$KEY_BAK"
mv "$KEY_NEW" "$KEY"
cleanup_tmp "$PLAIN_OLD" "$PLAIN_RT" "$PLAIN_RT2" "$PASS_TMP" "$PASS_TMP2"
PLAIN_OLD=""; PLAIN_RT=""; PLAIN_RT2=""; PASS_TMP=""; PASS_TMP2=""
green "Swapped: old key at $KEY_BAK (gitignored), new key at $KEY."

# ── Step 8: packet inspection ──────────────────────────────────────────
yellow "── Packet inspection (record this as the baseline) ──"
gpg --list-packets "$KEY" | grep -E 'cipher|S2K|symkey'
yellow "── End packet inspection ──"

# ── Step 9/10: hand back to the human ──────────────────────────────────
green "Done. Next steps (NOT performed by this script):"
echo "  1. Create pass entry: pass insert -m recovery/seed-gpg-key-enc-static"
echo "     (paste the static string + slot # + 'US keyboard layout' note)"
echo "  2. Stash the static string in your offline vault."
echo "  3. Stage and commit: bootstrap.sh, .gitignore, README.md, gpg-key.enc, plus the new pass file under recovery/."
echo "  4. Run a real bootstrap.sh on a scratch VM (US layout) to confirm portability."
echo "  5. Only then: rm $KEY_BAK"
echo "  6. Delete this helper:  rm $0"
```

- [ ] **Step 2: Make it executable.**

```bash
chmod 700 /tmp/seed-reencrypt.sh
```

- [ ] **Step 3: Syntax-check.**

```bash
bash -n /tmp/seed-reencrypt.sh
```

Expected: no output.

- [ ] **Step 4: Do NOT commit.** This file is intentionally outside the repo and never tracked. Confirm with `git status` — it must not appear.

---

### Task 6: Run the helper

This is the only step that actually touches `gpg-key.enc`. Read the printed prompts carefully. If anything looks wrong, the helper aborts cleanly without modifying `gpg-key.enc`.

**Files:**
- Modify: `gpg-key.enc` (via the helper)
- Creates: `gpg-key.enc.bak` (gitignored)

- [ ] **Step 1: Run the helper.**

```bash
/tmp/seed-reencrypt.sh
```

Walk through prompts in order:

1. Old passphrase — type your current memorable one.
2. First YubiKey touch — touch the key, then press Enter if Append CR is OFF.
3. The helper prints `length=N, sha256=…`. Compare `N` against `ykman otp info`'s reported slot length. Compare the first 8 hex chars of the sha256 against the smoke-test value you recorded in Task 1 Step 3. If they match: `y`. If not: `n` and investigate.
4. Second YubiKey touch — touch again. The helper compares length+sha to the first capture; if they differ it aborts.

- [ ] **Step 2: Confirm the swap.**

Expected output near the end:

```
Swapped: old key at /Users/<you>/.password-store/gpg-key.enc.bak (gitignored), new key at /Users/<you>/.password-store/gpg-key.enc.
── Packet inspection (record this as the baseline) ──
:symkey enc packet: version 4, cipher 9, s2k 3, hash 10
        salt …, count <large number>
…
── End packet inspection ──
Done. Next steps (NOT performed by this script):
…
```

`cipher 9` = AES-256. `hash 10` = SHA-512. `s2k 3` = iterated+salted. `count` should be at or above the requested ~65M (GPG may autocalibrate higher).

Save the full `:symkey enc packet:` line — that is the baseline the Task 9 verification compares against.

- [ ] **Step 3: Confirm files on disk.**

```bash
ls -la ~/.password-store/gpg-key.enc ~/.password-store/gpg-key.enc.bak
```

Expected: both files present. `gpg-key.enc` has a recent mtime. `gpg-key.enc.bak` has the old mtime.

```bash
git -C ~/.password-store status --short
```

Expected output includes:

```
 M gpg-key.enc
```

`gpg-key.enc.bak` must NOT appear (covered by the `*.bak` rule from Task 3). If it appears as `??`, Task 3 didn't land — fix `.gitignore` before continuing.

- [ ] **Step 4: Do NOT commit yet.** Recovery `pass` entry (Task 7) must be created first so it's bundled into the same commit as the new `gpg-key.enc`.

---

### Task 7: Create the `recovery/seed-gpg-key-enc-static` pass entry

The static string lives in two places: the YubiKey itself (operational) and the `pass` recovery entry (durable backup, encrypted to your GPG public key, so safe to commit and push). The offline vault copy (paper / safe deposit box / external password manager) is a Task 9 prerequisite, not a Task 7 step.

**Files:**
- Create: `recovery/seed-gpg-key-enc-static.gpg` (created by `pass insert`)

- [ ] **Step 1: Touch the YubiKey one more time into a temp variable so you have the string to paste.**

```bash
printf 'Touch the YubiKey one more time so we can paste it into pass: '
read -s -r RECOVERY_CAPTURE
echo
printf 'length=%d  sha256=' "$(printf '%s' "$RECOVERY_CAPTURE" | wc -c | tr -d ' ')"
printf '%s' "$RECOVERY_CAPTURE" | shasum -a 256 | awk '{print $1}'
```

Confirm the length + sha256 match the values you accepted in Task 6 Step 1. If not, abort — touch again and re-capture.

- [ ] **Step 2: Pipe into `pass insert`.**

`pass insert -m` opens an editor by default, which makes pasting non-trivial. Use a stdin-fed approach instead:

```bash
{
    printf '%s\n' "$RECOVERY_CAPTURE"
    printf '\n'
    printf 'YubiKey slot: <SLOT_NUMBER_FROM_TASK_1>\n'
    printf 'Keyboard layout: US\n'
    printf 'Terminator: Append CR ON, Append TAB OFF\n'
    printf 'Offline vault location: <FILL_IN_BEFORE_TASK_9>\n'
} | pass insert -m -f recovery/seed-gpg-key-enc-static
unset RECOVERY_CAPTURE
```

Replace `<SLOT_NUMBER_FROM_TASK_1>` with the slot you confirmed in Task 1 Step 1 (e.g. `2`). Leave the `<FILL_IN_BEFORE_TASK_9>` placeholder literally — you'll edit it after stashing the offline copy.

`pass insert -m -f` overwrites any existing entry; `-m` reads multi-line input from stdin.

- [ ] **Step 3: Verify the entry.**

```bash
pass ls recovery/
pass show recovery/seed-gpg-key-enc-static | head -1 | wc -c
```

Expected: the entry is listed; the first line's character count (including the trailing newline `wc` counts) equals `length+1` from Step 1.

`pass show recovery/seed-gpg-key-enc-static` works (the first line is the secret, subsequent lines are notes).

- [ ] **Step 4: Confirm the new `.gpg` file is in the repo working tree.**

```bash
git -C ~/.password-store status --short
```

Expected (alongside the modified `gpg-key.enc`):

```
 M gpg-key.enc
?? recovery/
```

- [ ] **Step 5: Do NOT commit yet.** Single bundled commit lands in Task 8.

---

### Task 8: Commit everything

One commit bundling the bootstrap fix, the gitignore rule, the README update, the re-encrypted key, and the recovery pass entry. This keeps the change atomic — a checkout of any commit either has the old setup or the new setup, never a half state.

**Files:**
- All edits from Tasks 2–4, 6, 7.

- [ ] **Step 1: Stage exactly the intended files.**

```bash
cd ~/.password-store
git add bootstrap.sh .gitignore README.md gpg-key.enc recovery/seed-gpg-key-enc-static.gpg
```

- [ ] **Step 2: Confirm the staged set.**

```bash
git status --short
```

Expected:

```
M  .gitignore
M  README.md
M  bootstrap.sh
M  gpg-key.enc
A  recovery/seed-gpg-key-enc-static.gpg
```

There must be NO entry for `gpg-key.enc.bak`. If you see `?? gpg-key.enc.bak`, the `*.bak` ignore from Task 3 didn't land — fix it before proceeding.

- [ ] **Step 3: Commit.**

```bash
git commit -m "$(cat <<'EOF'
feat: re-encrypt gpg-key.enc with YubiKey static-password slot

Replace the human-memorable symmetric passphrase on gpg-key.enc with the
high-entropy static string stored on the YubiKey static-password slot.
Bootstrap UX: touch the YubiKey at the password prompt instead of typing.

- bootstrap.sh: add -r to the AUTH_PASSWORD read so a backslash in the
  static string would be preserved.
- .gitignore: ignore *.bak so a stray git add cannot commit the prior,
  weakly-encrypted gpg-key.enc.bak.
- README.md: document the YubiKey requirement and a generic recovery note.
- recovery/seed-gpg-key-enc-static: pass entry recording the static
  string + slot/layout assumptions, encrypted to E84B48EB778BF9E6.

Spec: docs/superpowers/specs/2026-06-08-yubikey-passphrase-design.md
EOF
)"
```

- [ ] **Step 4: Push.**

```bash
git push origin main
```

- [ ] **Step 5: Confirm the commit lands cleanly.**

```bash
git log -1 --stat
```

Expected: 5 files changed, including `recovery/seed-gpg-key-enc-static.gpg` as a new file. `gpg-key.enc.bak` MUST NOT appear.

---

### Task 9: Post-procedure verification on a scratch VM

This is the only check that proves keymap and slot portability across machines. The helper's in-session round-trip cannot prove this.

**Files:**
- None modified. Verification only.

- [ ] **Step 1: Update the offline vault copy.**

Before running anything else, write the static string into your chosen offline vault (paper in a safe / safe deposit box / external password manager). Then edit the `pass` recovery entry to record where it lives:

```bash
pass edit recovery/seed-gpg-key-enc-static
```

Replace `<FILL_IN_BEFORE_TASK_9>` with the actual location.

Commit + push:

```bash
cd ~/.password-store
git add recovery/seed-gpg-key-enc-static.gpg
git commit -m "chore: record offline vault location in recovery entry"
git push origin main
```

- [ ] **Step 2: Provision a scratch VM.**

Anything fresh works: a UTM macOS VM, an OrbStack Ubuntu container, a fresh `multipass launch` Ubuntu instance. Requirements:
- Networked.
- US keyboard layout (matches the YubiKey slot programming).
- No prior knowledge of your dotfiles or GPG keys.

- [ ] **Step 3: Run the dry-run from the VM.**

Inside the VM:

```bash
curl -fsSL https://raw.githubusercontent.com/victorstein/seed/main/bootstrap.sh | bash -s -- --dry-run
```

Expected: completes cleanly, prints the dry-run banner, never prompts for a password.

- [ ] **Step 4: Run the real bootstrap.**

```bash
curl -fsSL https://raw.githubusercontent.com/victorstein/seed/main/bootstrap.sh | bash
```

At the prompt `Enter encryption password:`, plug in the YubiKey and touch it. Append-CR submits automatically; otherwise press Enter.

Expected: `[INFO] Authentication successful!` followed by `[INFO] GPG key imported and temp files deleted`. The script proceeds past Step 5 ("GPG Key Import").

If you see `[ERROR] Authentication failed. Wrong password. Exiting.`: STOP. Do NOT delete `gpg-key.enc.bak`. Investigate (likely causes: VM keyboard layout differs from US, the wrong slot was touched, `read -r` propagation didn't reach the VM's copy of the script).

- [ ] **Step 5: Tear down the VM.**

It now holds the imported GPG private key and your SSH keys in memory and on its filesystem. Delete it.

---

### Task 10: Delete `gpg-key.enc.bak`

Only after Task 9 succeeded with `[INFO] Authentication successful!` on a fresh machine.

**Files:**
- Delete: `~/.password-store/gpg-key.enc.bak`

- [ ] **Step 1: Confirm the verification gate.**

You should be able to answer yes to all three:

- The `:symkey enc packet:` line from Task 6 Step 2 still matches `gpg --list-packets ~/.password-store/gpg-key.enc | grep symkey`.
- The static string is stored in BOTH `pass show recovery/seed-gpg-key-enc-static` AND your offline vault (with the location recorded in the pass entry).
- A real `bootstrap.sh` run on a scratch VM completed Step 5 ("GPG Key Import") without error.

If any answer is no, STOP and resolve.

- [ ] **Step 2: Securely delete the backup.**

```bash
if command -v shred &>/dev/null; then
    shred -u ~/.password-store/gpg-key.enc.bak
else
    dd if=/dev/urandom of=~/.password-store/gpg-key.enc.bak bs=1k count=16 conv=notrunc 2>/dev/null
    rm -f ~/.password-store/gpg-key.enc.bak
fi
```

- [ ] **Step 3: Delete the helper script.**

```bash
if command -v shred &>/dev/null; then
    shred -u /tmp/seed-reencrypt.sh
else
    rm -f /tmp/seed-reencrypt.sh
fi
```

- [ ] **Step 4: Confirm.**

```bash
ls -la ~/.password-store/gpg-key.enc*
ls /tmp/seed-reencrypt.sh 2>&1
```

Expected: only `gpg-key.enc` (no `.bak`, no `.new`). `ls /tmp/seed-reencrypt.sh` errors with `No such file`.

```bash
git -C ~/.password-store status --short
```

Expected: clean.

- [ ] **Step 5: No commit needed.** `.bak` was never tracked.

---

## Done

After Task 10:

- `gpg-key.enc` is encrypted with the YubiKey's static string (AES-256, S2K mode 3, SHA-512).
- `bootstrap.sh` correctly passes that string through unchanged.
- The recovery story has two backups: the `pass` recovery entry (replicated wherever this repo is cloned + GPG-key-imported) and the offline vault copy.
- The old, weakly-encrypted blob is gone from disk.
- The helper that briefly held plaintext is gone from disk.

Future bootstraps: touch the YubiKey when prompted. Future static-string rotation: re-flash the YubiKey, rerun this plan from Task 1 (the helper assumes no `gpg-key.enc.bak` exists, so Task 10 from the previous run must have completed first).
