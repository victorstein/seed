# YubiKey-backed passphrase for `gpg-key.enc`

Date: 2026-06-08
Status: Approved (revised after independent review), ready for implementation plan

## Goal

Replace the human-memorable symmetric passphrase that currently protects
`gpg-key.enc` with the high-entropy static string stored on the user's
YubiKey static-password slot. This raises the brute-force cost of the
authentication gate in `bootstrap.sh` from "guess a memorized passphrase"
to "guess a long random string", without disturbing the GPG keypair or
`pass` entries.

## Scope

In scope:

- One-time re-encryption of `gpg-key.enc` with the YubiKey static string.
- A small `bootstrap.sh` change: add `-r` to the `read` that captures the
  passphrase, so a literal backslash in the static string is preserved
  (see "bootstrap.sh changes" below).
- `.gitignore` change: ignore `*.bak` so a stray `git add -A` cannot
  commit `gpg-key.enc.bak` (the prior, weakly-encrypted blob).
- `README.md` UX update: "touch your YubiKey when prompted for the
  encryption password."
- A `pass` entry that records where the offline recovery copy of the
  static string lives (NOT the README — see "Recovery story").
- A throwaway local helper script that performs the re-encryption
  safely (NOT committed to the repo).

Out of scope:

- Any change to the GPG keypair (`E84B48EB778BF9E6`), the existing
  `*.gpg` entries, the `pass` workflow, or the trust model.
- Moving the GPG private key onto a YubiKey OpenPGP smart card (a
  meaningfully stronger but more invasive change, considered and
  declined for now).
- FIDO2 / PIV / age-plugin-yubikey wrapping schemes.

## Threat model

What this change strengthens:

- **Passphrase entropy.** The current passphrase is human-memorable;
  the YubiKey static string is long and random. Offline brute force on
  a captured `gpg-key.enc` becomes infeasible.

What this change does NOT strengthen — and what the user must accept:

- **Physical possession of the YubiKey.** Anyone holding the key can
  touch it into a terminal sitting in this repo and decrypt everything.
  The static slot has no PIN and no touch-to-confirm beyond the single
  tap; whichever window has focus at the moment of touch receives the
  keystrokes. A focus-stealing app at that moment captures the secret.
- **Static-secret leakage.** The string is, by definition, static. If
  it leaks (screen share, paste buffer, shoulder-surf, printed copy
  lost, terminal session recorder such as `script(1)` or `asciinema`,
  keylogger on a compromised bootstrap machine), rotation cost is high:
  re-flash the YubiKey, re-run the re-encryption procedure, re-publish,
  and replace the offline vault copy. Unlike a memorable passphrase,
  the user has no intuition that it leaked. Implication: only bootstrap
  on machines the user controls and trusts.
- **`__SEED_AUTH_PASSWORD` re-exec window.** On the Debian sudo-install
  path (`bootstrap.sh:177-178`), the captured passphrase is exported as
  `__SEED_AUTH_PASSWORD` for the re-execed child. While `--unset` runs
  shortly after (line 426), the value briefly lives in
  `/proc/<pid>/environ`. With a memorable passphrase, that exposure is
  recoverable (user re-encrypts with a new one); with the static slot
  it is not without reflashing.
- **Plaintext-on-disk window.** The plaintext GPG private key briefly
  exists in a `mktemp` file during re-encryption and during bootstrap.
  Mitigated with `shred -u`; on SSDs `shred` is best-effort due to
  wear leveling.

## Design

### What changes in the repo

- `gpg-key.enc`: re-encrypted with the YubiKey static string as the
  symmetric passphrase, using AES-256 and high-iteration S2K. Verified
  with `gpg --list-packets gpg-key.enc` (see "Verification checklist").
- `bootstrap.sh`: change `read -s AUTH_PASSWORD < /dev/tty` (line 131)
  to `read -s -r AUTH_PASSWORD < /dev/tty`. Without `-r`, a backslash
  in the static string is consumed as an escape, producing a different
  passphrase from what the YubiKey actually typed. No other lines in
  `bootstrap.sh` need to change.
- `.gitignore`: add `*.bak`. Belt and suspenders against accidentally
  committing `gpg-key.enc.bak` during the procedure. (Note: the
  existing `!*.enc` exception does not catch `gpg-key.enc.bak` because
  the suffix is `.bak`, not `.enc` — but no positive ignore catches it
  either, so the file lands as untracked and a `git add -A` would
  commit it. Hence the new rule.)
- `README.md`: "Requirements" line changes from "Your GPG encryption
  password" to "Your YubiKey programmed with the static-password slot
  used for this repo." No reference to *where* the recovery copy lives
  — a public README pointing at "1Password / Recovery / ..." tells an
  adversary which password manager to phish.
- A new `pass` entry, e.g. `recovery/seed-gpg-key-enc-static`, that
  contains the static string (so the user's own decrypted password
  store records both the secret and the recovery location). This is
  itself encrypted to the GPG public key, so it costs nothing to keep.

### What does NOT change

- Every `*.gpg` file in the repo. They remain encrypted to the GPG
  public key `E84B48EB778BF9E6`, unaffected by the symmetric passphrase
  change.
- The `pass` workflow, dotfiles symlinks, and the `.gpg-id` file.
- The bootstrap step sequence, dry-run behaviour, or any other
  `bootstrap.sh` logic beyond the single `-r` flag.

### Preconditions on the YubiKey static slot

Before running the procedure, the YubiKey static-password slot MUST be
configured as follows. Any deviation lands the user in a different-bytes-
on-different-machines failure mode.

- **Programmed and populated.** Verify with `ykman otp info` (or the
  YubiKey Manager GUI). An empty slot will silently re-encrypt with an
  empty passphrase.
- **Slot choice documented.** If using slot 2 (long-touch), every
  bootstrap from now on requires a long touch; a short touch fires slot
  1 (often the factory Yubico OTP) and produces the wrong bytes. Record
  the chosen slot in the `pass` recovery entry.
- **Terminator: "Append CR" ON, "Append TAB" OFF.** A trailing CR makes
  `read` return immediately on touch. A TAB would not terminate `read`
  and would also be included in the captured bytes — different from
  what the user typed during re-encryption.
- **Character set: ASCII letters and digits only — no backslash.**
  Avoids the `read -s` vs `read -s -r` quoting hazard entirely on any
  consumer that forgets `-r`, and sidesteps NUL/control-byte concerns.
- **Keyboard layout pinned to "US keyboard."** The static slot emits
  HID scancodes, not Unicode. A slot programmed against US layout will
  emit different bytes on a Linux VM with, say, a Spanish layout. The
  procedure assumes US layout on every bootstrap target. Document this
  in the recovery `pass` entry.

If any of these are not already true, fix them before running the
procedure. A reference `ykman` invocation (run by the user, not the
helper) for programming a fresh slot 2 with a 38-char random ASCII
string is in the implementation plan, not this spec.

### Recovery story

Chosen: **print / vault the static string.** Single decryption path.

- Before deleting `gpg-key.enc.bak`, the user stores a copy of the
  static string in an offline vault (paper in a safe / safe deposit
  box / a separate password manager). YubiKey static slots support up
  to 38 ASCII characters; the exact length depends on how the slot is
  programmed.
- The *location* of that vault copy is recorded in a new `pass` entry
  (`recovery/seed-gpg-key-enc-static`), not in the public README. The
  entry holds the static string itself plus a one-line note about the
  offline location and the slot/layout assumptions above.
- No secondary YubiKey is provisioned. No memorable-passphrase fallback
  is wrapped into the file.

### One-time re-encryption procedure

Implemented as a local helper script (NOT committed). Runs from
`mktemp -d` on whichever platform. The spec previously called this
"tmpfs" — that was sloppy: `/private/tmp` on macOS is APFS-backed, not
tmpfs. On Linux the user MAY prefer `/dev/shm` for the temp directory;
on macOS, accept the SSD wear-leveling caveat already noted above.

**Step 0 — working directory.** `cd ~/.password-store`. All file paths
in steps 6–8 are relative to this directory; if the helper is invoked
from elsewhere, it must `cd` here first or use absolute paths derived
from `$HOME`.

**Step 1 — capture old passphrase.** `read -s -r OLD_PASS`. Decrypt
`gpg-key.enc` to `PLAIN_OLD=$(mktemp)` with `chmod 600`. Abort if
decryption fails.

**Step 2 — capture YubiKey static string.** Prompt "Touch your YubiKey
now." Capture into `YUBI_PASS` via `read -s -r`. `read` strips one
terminating newline; if the slot is configured "Append CR" the CR
arrives, terminates `read`, and is also stripped.

**Step 3 — sanity-check captured bytes.** Print only `printf '%s'
"$YUBI_PASS" | wc -c` (the length) and the SHA-256 of the captured
bytes:

```
printf '%s' "$YUBI_PASS" | shasum -a 256
```

Do NOT print the string itself (terminal scrollback). Ask the user to
confirm the length matches what `ykman otp info` reports the slot was
programmed with. This is the cheapest defense against an empty slot or
a wrong-slot capture. The full `xxd` dump is available on demand if the
user wants to inspect for stray `\r` / `\t` bytes — recommended at
least once during initial implementation.

**Step 4 — re-encrypt to `gpg-key.enc.new`.** Write the passphrase to a
600-permission temp file with `printf '%s'` (no trailing newline), then
pass it via `--passphrase-file`. This is the SAME plumbing
`bootstrap.sh:415-423` uses to feed the passphrase to GPG, so any
trailing-byte handling is identical end to end. Explicitly forbid:
here-strings (`<<<"$YUBI_PASS"` appends `\n`), process substitution
into `--passphrase-fd` (subshell argv hazards), and `echo "$YUBI_PASS"`
(adds `\n` and may interpret backslashes).

```
PASS_TMP=$(mktemp); chmod 600 "$PASS_TMP"
printf '%s' "$YUBI_PASS" > "$PASS_TMP"
gpg --batch --yes --symmetric \
    --cipher-algo AES256 \
    --s2k-mode 3 \
    --s2k-count 65011712 \
    --s2k-digest-algo SHA512 \
    --passphrase-file "$PASS_TMP" \
    --output gpg-key.enc.new \
    "$PLAIN_OLD"
```

Note on S2K: modern GPG autocalibrates `--s2k-count` for `--s2k-mode 3`
and may exceed the requested value. The verification step inspects the
resulting packet to confirm AES-256 + high iteration count, rather than
asserting the literal `65011712`.

**Step 5 — round-trip verification gate.** Decrypt `gpg-key.enc.new`
with the same `$PASS_TMP` to `PLAIN_RT=$(mktemp; chmod 600)`. Compare
with `cmp -s "$PLAIN_OLD" "$PLAIN_RT"`. On mismatch: `shred -u` every
temp file and abort without touching `gpg-key.enc`.

**Step 6 — second-touch test.** Prompt the user to touch the YubiKey
again. Capture into `YUBI_PASS_2` via `read -s -r`. Write to a fresh
`PASS_TMP2`. Decrypt `gpg-key.enc.new` again, `cmp` again. This catches
inconsistencies between touches (accidental long-touch hitting slot 2,
terminator drift, etc.) before the old file is overwritten.

**Step 7 — swap files.** Inside `~/.password-store`:

```
mv gpg-key.enc gpg-key.enc.bak
mv gpg-key.enc.new gpg-key.enc
```

Then `shred -u` `$PLAIN_OLD`, `$PLAIN_RT`, `$PASS_TMP`, `$PASS_TMP2`.
`unset OLD_PASS YUBI_PASS YUBI_PASS_2`.

**Step 8 — packet inspection.** Run `gpg --list-packets gpg-key.enc`
and confirm `cipher: AES-256`, `S2K mode: 3`, `S2K hash: SHA512`, and
an iteration count at or above the requested value. Capture this output
into the implementation plan as the expected baseline.

**Step 9 — commit.** Stage `gpg-key.enc`, the `bootstrap.sh` `-r`
change, the `.gitignore` `*.bak` line, and the `README.md` update.
Commit. Do NOT commit `gpg-key.enc.bak` or the helper script. Verify
with `git status` that `gpg-key.enc.bak` shows untracked but the
`.gitignore` rule keeps it from being staged by `git add -A`.

**Step 10 — recovery copy and `.bak` deletion are NOT part of the
helper.** The helper prints the reminder and exits. Removing
`gpg-key.enc.bak` is a deliberate, manual action gated on the post-
procedure checklist below.

### Verification checklist (post-procedure, before deleting `.bak`)

All must hold before `gpg-key.enc.bak` is deleted:

- `gpg --list-packets gpg-key.enc` matches the baseline captured in
  step 8.
- The static string is stored in `pass recovery/seed-gpg-key-enc-static`
  AND in the chosen offline vault.
- A fresh `bootstrap.sh --dry-run` runs to completion (dry-run skips
  decryption but exercises path-walking).
- A real `bootstrap.sh` run on a scratch VM / container — ideally with
  the same OS family and US keyboard layout the user expects to
  bootstrap on in future — completes step 5 ("GPG Key Import") on a
  YubiKey touch without "Authentication failed. Wrong password." This
  is the only check that proves keymap portability; the helper's
  in-session round-trip cannot.

Only after all four pass: `rm gpg-key.enc.bak`.

## Open questions to resolve during implementation

- The exact offline vault location (filled in to the `pass` recovery
  entry, not the README).
- The chosen YubiKey slot (1 or 2) and whether the existing slot is
  already programmed to the user's satisfaction or needs to be
  reprogrammed with a known-good 38-char random string via `ykman`.
- Which scratch VM / container the user will use for the post-procedure
  real-bootstrap test.
