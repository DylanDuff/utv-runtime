# utv-runtime

JS patch runtime and development environment for the YouTube Android TV app (apktool + smali
bootloader, no patch frameworks; features are JS patches). Every finding, patch and its
version-proof fingerprint lives in `PATCHES.md`; the JS patch API in `docs/js-patches.md`.

## Structure
- `./utv-runtime`: the CLI. No command = guided flow (doctor, connect, pull, name prompt, decode, patch,
  build, install). Subcommands run single steps. Flags: `--ip`, `--name`, `--version`, `--yes`, `--devtools`.
- `lib/common.sh`: constants (PACKAGE, NEW_PACKAGE, paths), prompts (`ask`, `confirm`,
  `confirm_destructive`), config (`.utv-runtime.conf`), version/APK resolution.
- `lib/steps/<step>.sh`: one `step_<name>` function per step (`eval.sh` also holds the JS wrapper). `utv-runtime` sources them all.
- `patches/smali/`: the bootloader (`RuntimeObserver.smali`, `EvalReceiver.smali` templates, Perl helpers).
- `patches/runtime.js`: JS core (log channel, settings registry, response hook pipeline, `utv.patch`).
- `patches/*.js`: JS patches, bundled after the core in filename order, each in its own scope.
  API and rules: `docs/js-patches.md`. `lib/steps/patch.sh` builds the bundle and applies smali patches.

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
  replace it without root, so the patched build uses the fixed package `com.utv.runtime` (outside Google's namespace) and installs beside
  it. Only the label is user-chosen, so every run updates the same app and keeps its login.
  Never uninstall stock. `install` may uninstall only the patched package, and only via `confirm_destructive`.
- The APK set is `base.apk` plus whatever `split_*.apk` were pulled; never hardcode split names.
  All splits share the package name and signing key. `extractNativeLibs=false`: `.so` files stay
  stored and page aligned (`zipalign -p 4`).
- The app is Cobalt (Chromium-based web runtime). UI and ads are JS from youtube.com/tv; smali only
  hosts the shell. Smali is a bootloader; features are JS patches (`utv.patch`), not `return-void` edits.
- JS patch settings become native YouTube client settings: keys are registered in the app's
  known-settings registry and defaults Map (found by content via `ENABLE_PREVIEWS_WITH_SOUND`).
  The Settings category is only injected after registration succeeds.
- Patches never hardcode obfuscated names. They locate files by string anchors or unobfuscated names
  (`dev.cobalt.*`, `GEN_JNI` stubs, JNI-called methods) and resolve obfuscated ones structurally.
  Every patch writes `# PATCH <id>` and is a no-op when re-run.
- apktool 3 takes `-q` after the subcommand (`apktool d -q`), not before.
- Cobalt drops console output from injected scripts and YouTube swallows uncaught errors. Injected
  JS logs via `utv.report()` (title channel -> `RuntimeObserver.titleWasSet` -> logcat tag `utv-runtime`).
- No Chrome DevTools in this build. `--devtools` adds `EvalReceiver` for `./utv-runtime eval`; it is
  an exported receiver, so never make it the default.
- The page enforces Trusted Types: string `eval` needs a TrustedScript (the eval wrapper creates a
  pass-through policy). Code delivered via `evaluateJavaScript` isn't affected.
- Ask before any uninstall on the device. No em-dashes in user-facing text.
