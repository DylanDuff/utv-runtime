# utv-runtime

Hand-made ad-free build of the YouTube Android TV app (`com.google.android.youtube.tv`), using
apktool and smali edits only. Personal use on my own TV.

The patched app installs **beside** stock YouTube under the fixed package
`com.google.android.youtube.tv.adfree`, with a launcher name you choose. Stock YouTube and its
login aren't touched.

- [PATCHES.md](PATCHES.md): findings, every patch, and the string anchors and fingerprints
  needed to redo them after an update.
- [CLAUDE.md](CLAUDE.md): layout, invariants and conventions.

## Requirements

macOS with Android Studio (SDK build-tools, platform-tools, bundled JDK), `apktool`, `ripgrep`,
`perl`, and network debugging enabled on the TV. `jadx` is optional (for investigating new
versions). `./utv-runtime doctor` checks all of these and offers to install apktool/jadx with Homebrew.

## Usage

```sh
./utv-runtime
```

The guided flow:

1. Checks tools.
2. Asks for the TV's IP and connects (accept the debugging prompt on the TV the first time).
3. Pulls the installed stock YouTube into `workspace/original/<version>/`, unless already there.
4. Asks for the application name.
5. Decodes, renames, and applies all patches.
6. Builds, signs, installs over the previous patched build, and compiles it.

Answers are remembered in `.utv-runtime.conf` and offered as defaults next time. Everything generated
(originals, decodes, builds, signed APKs, the signing key) lives under `workspace/`; logs go to
`logs/`.

Single steps, for iterating:

```sh
./utv-runtime doctor                 # check tools
./utv-runtime pull                   # pull stock APKs into workspace/original/<version>/
./utv-runtime decode --force         # fresh decode into workspace/work/ + package rename
./utv-runtime patch                  # apply patches (safe to re-run; re-applies the name)
./utv-runtime build                  # rebuild, zipalign, sign into workspace/out/
./utv-runtime install                # install over the patched app, AOT compile
./utv-runtime logcat [--raw|--all]   # stream logs, saved to logs/
```

Options: `--ip <address>`, `--name <label>`, `--version <ver>`, `--yes` (accept defaults; destructive
prompts still ask). Example, rename only: `./utv-runtime patch --name "YouTube" && ./utv-runtime build && ./utv-runtime install`.

The first build creates `workspace/keys/atv.keystore`. Back up `workspace/keys/`: losing it means the installed app
can't be updated without uninstalling it (and signing in again). If that happens, `install`
offers to uninstall the patched app (never stock).

## After a YouTube update

1. Let the TV update stock YouTube, then run `./utv-runtime`. It pulls the new version into its own
   `workspace/original/<version>/` folder and rebuilds.
2. If a patch stops with "anchor not found" or "shape changed", follow its fingerprint in
   `PATCHES.md` to find the new location in `jadx` output, then update `lib/steps/patch.sh`.
3. If ads come back but nothing fails, YouTube changed its ad fields: edit `patches/adblock.js`
   and run `./utv-runtime patch && ./utv-runtime build && ./utv-runtime install`.
4. Record the new version and results in `PATCHES.md`.
