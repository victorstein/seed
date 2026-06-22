# Changelog

## 1.0.0 (2026-06-22)


### Features

* add Linux support to bootstrap script ([61c0334](https://github.com/victorstein/seed/commit/61c0334b405d52854a54a62b829bd0a42c162485))
* add oh-my-zsh plugins, nvm node setup, and various fixes ([a09f38a](https://github.com/victorstein/seed/commit/a09f38ad7f190d981fdd9a2339d7f74c6a712a91))
* add progress spinners, oh-my-zsh, nvm, and fix GPG issues ([efe0898](https://github.com/victorstein/seed/commit/efe0898eb548170556c71887e8e2efcf75839cfe))
* add sudo bootstrap for fresh Debian installations ([944fb1c](https://github.com/victorstein/seed/commit/944fb1cca4d0dcd545267c3913c2c38928249425))
* add sudo bootstrap for fresh Debian installations ([1ecc25c](https://github.com/victorstein/seed/commit/1ecc25ce51966f36d6761440933bb1f4c88bb7e6))
* **bootstrap:** symlink pass extensions from dotfiles into store ([4208ff7](https://github.com/victorstein/seed/commit/4208ff78358c89ca936f5f6ac0d3b056cd514b3b))
* exec into zsh at end of script (no logout required) ([1f97d09](https://github.com/victorstein/seed/commit/1f97d09565bc2b461ad43f582e62ee2b9aeaf2b2))
* improve cross-platform support, security, and robustness ([07772a4](https://github.com/victorstein/seed/commit/07772a408faf7867fcf0fe3c398c9bbb3992a36f))
* re-encrypt gpg-key.enc with YubiKey static-password slot ([4f18879](https://github.com/victorstein/seed/commit/4f188790e0753847dd7d296f56da88903fe8a0dc))


### Bug Fixes

* always fix Homebrew permissions on Linux, add chmod ([3c59b09](https://github.com/victorstein/seed/commit/3c59b09393385830cd1b4b36fa7cf91f0c4efbe6))
* auto-heal existing ~/.ssh/config on Linux ([6d98073](https://github.com/victorstein/seed/commit/6d98073b98ba7b7e0d4bddc7ccf28ec90525c691))
* chsh password prompt and Homebrew zsh permissions ([cd28c6f](https://github.com/victorstein/seed/commit/cd28c6f1826bf62714695431e828ff0d0ea55d4f))
* clean up temporary GPG loopback config after import ([af01b5f](https://github.com/victorstein/seed/commit/af01b5f04aff7ba95db2e3d908cb0f8371904bb8))
* comprehensively fix Homebrew directory permissions on Linux ([024fd7b](https://github.com/victorstein/seed/commit/024fd7bbb6ad462fa2d627113afe9063cc4a6f86))
* configure gpg-agent for loopback pinentry before import ([b15c42e](https://github.com/victorstein/seed/commit/b15c42ea936ae546d14fb832f6357b966c1dbdc0))
* detect existing Homebrew before reinstall, decouple PATH from persistence ([8607223](https://github.com/victorstein/seed/commit/8607223da94a493fcfb078342958bb4209ac78a5))
* detect Homebrew gnupg by binary path, not version output ([6804a9a](https://github.com/victorstein/seed/commit/6804a9ab91c684652a65129cd4d08ffcd314b359))
* disable system gpg-agent binary to prevent version conflicts ([dbef951](https://github.com/victorstein/seed/commit/dbef951d763b6cf24e55399339b2e636f1a26f47))
* generically fix all Homebrew linking conflicts ([f046ae1](https://github.com/victorstein/seed/commit/f046ae17e65d426cfdb18b24f3100185c99597d2))
* harden GPG step on Linux against systemd respawn and pinentry tty failure ([018c56f](https://github.com/victorstein/seed/commit/018c56f9f153b2f5ba5028869f3745405a9cd80f))
* ignore macOS-only SSH directives on Linux ([c4fb2c9](https://github.com/victorstein/seed/commit/c4fb2c963389971a025c95b093fdbd5a655039c2))
* more aggressive GPG agent bypass for key import ([b217443](https://github.com/victorstein/seed/commit/b217443557f7424f0f8e985c1279aae4b33b8e60))
* re-export gpg-key.enc with YubiKey-passphrased private key ([1e25c6e](https://github.com/victorstein/seed/commit/1e25c6e49786323965eaf001662372d98c976fd9))
* read password from /dev/tty to support curl | bash ([fab9353](https://github.com/victorstein/seed/commit/fab9353c0d452dda7a0f4c4d5130a39a2a7f4730))
* remove system GPG on Linux to avoid version conflicts ([f3abc19](https://github.com/victorstein/seed/commit/f3abc19d0bd1595705d4f73cbec12c02f6b96540))
* resolve bootstrap issues on fresh macOS installs ([fa17633](https://github.com/victorstein/seed/commit/fa17633d94f33f512e0b8f88125cd5896229409b))
* resolve Homebrew linking conflicts before installing packages ([9d636e5](https://github.com/victorstein/seed/commit/9d636e5e7095ec72edeb91a9afb58a5be7695673))
* rewrite hardcoded SSH home-dir paths to ~/.ssh on extraction ([9947348](https://github.com/victorstein/seed/commit/9947348e266911663dfe954a9916f6ba2c076615))
* skip git check in dry-run mode ([b38c242](https://github.com/victorstein/seed/commit/b38c242dcc9520ff701dd3dc1b451dbdc9170385))
* use loopback pinentry mode for GPG import ([217044d](https://github.com/victorstein/seed/commit/217044d62b913ce3f65782d349da6afe305f836a))


### Performance

* skip already-linked Homebrew formulae ([3b80817](https://github.com/victorstein/seed/commit/3b8081766b30ae092a8457a167b467e6dab06171))


### Documentation

* addendum capturing actual outcome of YubiKey passphrase work ([1cdea35](https://github.com/victorstein/seed/commit/1cdea35ccdf7080d2c767e2fe4902cd198b62844))
* design for YubiKey-backed passphrase on gpg-key.enc ([a9bb50f](https://github.com/victorstein/seed/commit/a9bb50f4768bb105748c6d5d1df1e84a7a5ee097))
* implementation plan for YubiKey-backed gpg-key.enc passphrase ([fd57203](https://github.com/victorstein/seed/commit/fd57203f5e1faadf03c6ad8352b9ffc441f94b9a))
* revise YubiKey passphrase spec after review (10 findings) ([017a0dd](https://github.com/victorstein/seed/commit/017a0dd12a00d2e4bdd6cf31e8bd1dc1cb135f1d))
