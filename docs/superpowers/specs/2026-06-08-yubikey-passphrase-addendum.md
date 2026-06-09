# Addendum to the YubiKey passphrase work

Date: 2026-06-08 (same day, after execution)
Status: Closes out the work begun in `2026-06-08-yubikey-passphrase-design.md`.

## Why this addendum exists

The original spec and plan are kept as-is — they record what we set out
to do. This document records what we actually did, what we discovered
mid-execution that the original spec missed, and the final on-disk state.
Future-you should read this alongside the original spec to understand
the system as it stands.

## What changed vs. the original spec

### 1. Layer A vs. Layer B was an unstated assumption

The original spec talked about "re-encrypting `gpg-key.enc` with the
YubiKey static." It implicitly assumed that `gpg-key.enc` had a single
passphrase. In reality there are two:

- **Layer A** — the symmetric wrapper protecting the file at rest.
- **Layer B** — the GPG private key's own passphrase, embedded in the
  exported secret-key blob inside the wrapper.

A fresh bootstrap needs *both* to be the YubiKey static for the "single
touch unlocks everything" UX to actually work end-to-end. The original
spec only fixed Layer A.

### 2. Local GPG key state diverged from `gpg-key.enc`

At some earlier session (the user remembers but the git log doesn't),
the local GPG private key's passphrase was rotated to the YubiKey static
on the **encryption subkey only** (`D8E8489DBD5CDEC2`). The **primary
key** (`E84B48EB778BF9E6`) was left on the older memorable passphrase.

`pass show` decryption uses the encryption subkey, so daily life worked
fine and hid the divergence. `gpg --export-secret-keys` touches both,
which is how we surfaced it.

`gpg-key.enc` itself was a frozen export from key-creation time
(2024-09-25), so it contained both primary and subkey at their original
passphrases — not the YubiKey static.

### 3. The recovery `pass` entry was circular

The original spec compromised on "don't put the recovery location in
the public README; put it in a `pass` entry instead." That entry was
encrypted to the same GPG public key whose private key it was meant to
recover — so in the actual recovery scenario (lost YubiKey on a fresh
machine), it would be undecryptable. The offline vault copy is the only
real recovery path. The entry was deleted in `1e25c6e`.

## What we actually shipped

Two commits on `origin/main`, both on `2026-06-08`:

### `4f18879` — Layer A re-encryption

- `bootstrap.sh`: added `-r` to the `read -s` at line 131 so a backslash
  in the static string would be preserved.
- `.gitignore`: added `*.bak` rule.
- `README.md`: rewrote Requirements section for YubiKey.
- `gpg-key.enc`: re-encrypted symmetric wrapper to YubiKey static.
- `recovery/seed-gpg-key-enc-static.gpg`: new `pass` entry (deleted in
  the next commit — see below).

This commit was made via the first helper `/tmp/seed-reencrypt.sh`,
which decrypted the existing `gpg-key.enc` with the old memorable
passphrase, then re-encrypted the same plaintext with the YubiKey
static. The plaintext (the embedded GPG private key) was untouched, so
Layer B was still the original.

### `1e25c6e` — Layer B re-export + recovery entry deletion

After 4f18879 was pushed and an isolated GNUPGHOME diagnostic revealed
that the private key inside `gpg-key.enc` still carried the original
memorable passphrase (not the YubiKey static), this commit fixed it:

- The user ran `gpg --edit-key E84B48EB778BF9E6 passwd` to rotate the
  **primary key**'s passphrase to YubiKey static (the encryption subkey
  was already on it, as noted above).
- The second helper `/tmp/seed-reexport.sh` then exported the now-fully-
  YubiKey-passphrased private key via `gpg --pinentry-mode loopback
  --passphrase-file <file>` and re-encrypted as `gpg-key.enc`.
- `recovery/seed-gpg-key-enc-static.gpg` deleted as part of the same
  commit.

The second helper performs an inline isolation test before swapping:
import the new blob into a fresh `GNUPGHOME`, encrypt a tiny message
to the key, decrypt with the YubiKey static. Passing this catches the
"exported the wrong-passphrase blob" failure mode.

## Verification status

- **Layer A on a fresh VM**: ✅ verified on a clean OrbStack Ubuntu VM.
  Bootstrap step 5 ("GPG Key Import") prints `Authentication
  successful!` after a YubiKey touch at the encryption-password prompt.
- **Layer B on a fresh GNUPGHOME**: ✅ verified inline by the second
  helper. Functionally equivalent to a fresh-machine bootstrap importing
  the key and using it to decrypt.
- **Layer B on a fresh VM end-to-end (step 8 onward)**: ❌ not verified.
  OrbStack's Ubuntu 24.04 ships `sudo-rs 0.2.13` which does not honor
  `/etc/sudoers.d/` drop-ins despite reporting `parsed OK` to `visudo
  -c`. Even after swapping for classic `sudo 1.9.17p2`, the `stein`
  user's passwordless sudo never engaged. We chose to stop fighting the
  VM rather than expand the scope further — the Layer A + isolated
  GNUPGHOME tests together provide adequate evidence the bytes will work
  on a real fresh machine. Keymap-portability is the only thing that
  remains theoretically unverified, and it's a low-risk failure mode
  given the slot uses ASCII-only HID scancodes on a US layout.

## On-disk state at end of work

- `~/.gnupg/`: primary key + encryption subkey both unlock with YubiKey
  static.
- `~/.password-store/gpg-key.enc`: AES-256 / S2K mode 3 / SHA-512 /
  iter ≥65011712. Layer A = YubiKey static. Embedded private key's
  Layer B = YubiKey static.
- `~/.password-store/gpg-key.enc.bak`: **deleted**. The original
  memorable-passphrase blob is preserved in git history (commit
  `d97ed90 Add encrypted GPG key`) if you ever need it.
- `~/.password-store/recovery/`: deleted.
- `/tmp/seed-reencrypt.sh` and `/tmp/seed-reexport.sh`: shredded after
  use.

## Lessons for the next rotation

1. **Re-exporting is part of the rotation.** Changing the local GPG
   key's passphrase does NOT propagate to `gpg-key.enc`. After any
   `gpg --edit-key passwd`, also re-export and re-encrypt.

2. **Primary and subkeys can drift.** `gpg --edit-key … passwd` is
   supposed to update both at once, but in practice (especially through
   pinentry-mac quirks or partial sessions) only one may end up rotated.
   Use `gpg --batch --pinentry-mode loopback --passphrase-file …
   --export-secret-keys …` as a forcing function: if any keygrip refuses
   the passphrase, the export fails loudly.

3. **The recovery pass entry was a bad idea.** Anything encrypted to
   the key it's meant to recover is not recovery. The README's "private
   offline vault" wording captures the only real recovery path.

4. **OrbStack Ubuntu 24.04 is not a clean bootstrap target right now.**
   `sudo-rs` makes the bootstrap's `sudo -v < /dev/tty` call refuse to
   pass. If you ever need to re-verify on a VM, prefer Ubuntu 22.04,
   Debian, or any image with classic `sudo` as the default — or accept
   running as root for step-5-only verification.

5. **Helper scripts should include the isolated-GNUPGHOME Layer B test
   as a gate before swapping `gpg-key.enc`.** The first helper didn't
   and we shipped a commit that broke step 8 silently. The second helper
   does, and we caught the wrong-passphrase blob before swapping.
