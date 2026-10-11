# utv-runtime

Manual (apktool + smali, no patch frameworks) ad removal for the YouTube Android TV app,
personal use. Every finding, patch and its version-proof fingerprint lives in `PATCHES.md`.

## Structure
- `./utv-runtime`: the CLI. No command = guided flow (doctor, connect, pull, name prompt, decode, patch,
  build, install). Subcommands run single steps. Flags: `--ip`, `--name`, `--version`, `--yes`.
- `lib/common.sh`: constants (PACKAGE, NEW_PACKAGE, paths), prompts (`ask`, `confirm`,
  `confirm_destructive`), config (`.utv-runtime.conf`), version/APK resolution.
- `lib/steps/<step>.sh`: one `step_<name>` function per step. `utv-runtime` sources them all.
- `patches/`: patch payloads (`adblock.js`, `AdBlockObserver.smali` template, Perl helpers).
  `lib/steps/patch.sh` applies them.

## Data
Top level holds only `utv-runtime`, `logs/`, `.utv-runtime.conf`, source (`lib/`, `patches/`) and docs.
Everything generated lives under `workspace/` (gitignored):
- `workspace/original/<versionName>/`: untouched APKs pulled from the TV. Never modify or overwrite.
- `workspace/work/<apk name>/`: apktool decodes, plus `workspace/work/.version`. Disposable (all patches are scripted);
  `decode` needs `--force` to replace it, and `patch`/`build` refuse a decode of another version.
- `workspace/build/`: intermediates, **wiped by every build**. `workspace/out/`: signed APKs. `logs/`: logcat captures.
- `workspace/keys/atv.keystore` + `workspace/keys/password.txt`: the one signing key, created on first build. Never
  regenerate. Gitignored, back it up.
- `.utv-runtime.conf`: remembered DEVICE_IP, APP_LABEL, VERSION. Gitignored (`utv-runtime.conf.example` committed).

## Invariants
- Stock YouTube is a Google-signed system app (`/product/app/YouTubeLeanback`). A re-signed APK can't
  replace it without root, so the patched build uses the fixed package `.adfree` and installs beside
  it. Only the label is user-chosen, so every run updates the same app and keeps its login.
  Never uninstall stock. `install` may uninstall only `.adfree`, and only via `confirm_destructive`.
- The APK set is `base.apk` plus whatever `split_*.apk` were pulled; never hardcode split names.
  All splits share the package name and signing key. `extractNativeLibs=false`: `.so` files stay
  stored and page aligned (`zipalign -p 4`).
- The app is Cobalt (Chromium-based web runtime). UI and ads are JS from youtube.com/tv; smali only
  hosts the shell. Ads are removed by injecting JS, not by `return-void` patches.
- Patches never hardcode obfuscated names. They locate files by string anchors or unobfuscated names
  (`dev.cobalt.*`, `GEN_JNI` stubs, JNI-called methods) and resolve obfuscated ones structurally.
  Every patch writes `# PATCH <id>` and is a no-op when re-run.
- apktool 3 takes `-q` after the subcommand (`apktool d -q`), not before.
- Cobalt drops console output from injected scripts; don't rely on it for verification.
- Ask before any uninstall on the device. No em-dashes in user-facing text.
