# YubiKey-backed passphrase for `gpg-key.enc`

Date: 2026-06-08
Status: Approved, ready for implementation plan

## Goal

Replace the human-memorable symmetric passphrase that currently protects
`gpg-key.enc` with the high-entropy static string stored on the user's
YubiKey static-password slot. This raises the brute-force cost of the
authentication gate in `bootstrap.sh` from "guess a memorized passphrase"
to "guess a long random string", without changing the bootstrap flow,
GPG keypair, or `pass` entries.

## Scope

In scope:

- One-time re-encryption of `gpg-key.enc` with the YubiKey static string.
- `README.md` update to describe the new "touch your YubiKey" UX.
- A throwaway local script that performs the re-encryption safely (NOT
  committed to the repo).

Out of scope:

- Any change to `bootstrap.sh`. Because the YubiKey static slot emulates
  keyboard input, the existing `read -s AUTH_PASSWORD < /dev/tty` prompt
  accepts the keystrokes with no code change.
- Any change to the GPG keypair (`E84B48EB778BF9E6`), the existing
  `*.gpg` entries, the `pass` workflow, or the trust model.
- Moving the GPG private key onto a YubiKey OpenPGP smart card (a
  meaningfully stronger but more invasive change considered and
  declined for now).
- FIDO2 / PIV / age-plugin-yubikey wrapping schemes.

## Threat model

What this change strengthens:

- **Passphrase entropy.** The current passphrase is human-memorable;
  the YubiKey static string is long and random. Offline brute force on
  a captured `gpg-key.enc` becomes infeasible.

What this change does NOT strengthen:

- **Physical possession.** Anyone holding the YubiKey can touch it
  into a terminal sitting in this repo and decrypt everything. The
  YubiKey is now a load-bearing physical token; treat it accordingly.
- **Static-secret leakage.** The static string is, by definition,
  static. If it leaks (screen share, paste buffer, shoulder-surf,
  printed copy lost), rotating it requires re-flashing the YubiKey
  AND re-running the re-encryption procedure.
- **Plaintext-on-disk window.** The plaintext GPG private key briefly
  exists in a `mktemp` file during re-encryption. This is the same
  exposure window `bootstrap.sh` already accepts and the procedure
  mitigates it with `shred -u`. On SSDs `shred` is best-effort due
  to wear leveling.

## Design

### What changes in the repo

- `gpg-key.enc`: re-encrypted with the YubiKey static string as the
  symmetric passphrase, using AES-256 and high-iteration S2K
  (parameters in the procedure below).
- `README.md`: the "Requirements" section changes from "Your GPG
  encryption password" to "Your YubiKey (touch when prompted for the
  encryption password)", with a one-line pointer to where the offline
  vault copy of the static string lives.

### What does NOT change

- `bootstrap.sh`. The `read -s AUTH_PASSWORD < /dev/tty` prompt works
  identically whether the user types or the YubiKey types. If the
  YubiKey's slot is configured with "Append CR", the CR terminates
  `read` automatically; otherwise the user presses Enter.
- Every `*.gpg` file in the repo. They remain encrypted to the GPG
  public key `E84B48EB778BF9E6`, unaffected by the symmetric
  passphrase change.
- The `pass` workflow, dotfiles symlinks, and the `gpg-id` file.

### Recovery story

Chosen: **print / vault the static string.**

- Before the prior `gpg-key.enc.bak` is deleted, the user must store a
  copy of the static string in an offline vault (paper in a safe /
  safe deposit box / a separate password manager). YubiKey static
  slots support up to 38 characters; the exact length depends on how
  the slot is programmed.
- `README.md` will record *where* the recovery copy lives (e.g.
  "1Password vault: Personal / Recovery / seed-yubikey-static"), so
  future-you doesn't have to remember. The actual location is the
  user's choice and will be filled in during implementation.
- No secondary YubiKey is provisioned and no memorable-passphrase
  fallback is wrapped into the file. Single decryption path: the
  static string.

### One-time re-encryption procedure

Implemented as a local helper script (NOT committed). The script is
intended to be sourced/run from a tmpfs or `/private/tmp` directory and
deleted after use.

1. Read the old passphrase from the user (`read -s -r OLD_PASS`).
2. Decrypt the current `gpg-key.enc` to a `mktemp` file with
   `chmod 600`. Abort if decryption fails.
3. Prompt: "Touch your YubiKey now." Capture into `YUBI_PASS` via
   `read -s -r`. `read` strips the terminating CR/newline, so the
   captured value is the literal static string regardless of whether
   the YubiKey appends CR.
4. Re-encrypt the plaintext file to `gpg-key.enc.new` with:

   ```
   gpg --batch --yes --symmetric \
       --cipher-algo AES256 \
       --s2k-mode 3 \
       --s2k-count 65011712 \
       --s2k-digest-algo SHA512 \
       --passphrase-fd <fd reading YUBI_PASS> \
       --output gpg-key.enc.new \
       <plaintext temp file>
   ```

5. **Round-trip verification gate.** Decrypt `gpg-key.enc.new` using
   `YUBI_PASS` to a second temp file, byte-compare with the original
   plaintext (`cmp -s`). If mismatch: shred everything and abort
   without touching `gpg-key.enc`.
6. **Second-touch test.** Prompt the user to touch the YubiKey again,
   capture into `YUBI_PASS_2`, decrypt `gpg-key.enc.new` with it,
   byte-compare again. This catches inconsistencies between touches
   (e.g. accidental long-touch hitting slot 2, "Append CR" producing
   different terminators) before the old file is overwritten.
7. On success:
   - `mv gpg-key.enc gpg-key.enc.bak` (gitignored).
   - `mv gpg-key.enc.new gpg-key.enc`.
   - `shred -u` the two plaintext temp files; `unset` the passphrase
     vars.
   - Print a reminder: "Stash the static string in your offline vault,
     then delete `gpg-key.enc.bak`."
8. Stage and commit `gpg-key.enc` + the README update. Do NOT commit
   `gpg-key.enc.bak` or the helper script.

### Verification checklist (post-procedure)

- `gpg --list-packets gpg-key.enc` shows AES-256 + the chosen S2K
  parameters.
- A fresh `bootstrap.sh --dry-run` is not affected (dry-run skips
  decryption).
- A real `bootstrap.sh` run on a scratch VM / container, touching the
  YubiKey at the prompt, completes step 5 ("GPG Key Import") without
  the "Authentication failed. Wrong password." error.
- `gpg-key.enc.bak` is deleted only after the offline vault copy of
  the static string is confirmed in place.

## Open questions to resolve during implementation

- Exact location of the offline vault copy (so the README entry is
  concrete, not "somewhere safe").
- Whether the helper script lives in `/private/tmp` for the session
  or in a user-controlled scratch directory.
