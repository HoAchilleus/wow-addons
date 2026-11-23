# wow-addons

World of Warcraft addons, one folder each under `addons/`, sharing their
tooling: linting, tests, CI and releases.

| Addon                                         | What it does                                  |
| --------------------------------------------- | --------------------------------------------- |
| [TwoColumnStats](addons/TwoColumnStats)       | Character sheet stats in two columns (Forever) |

## Layout

```
addons/<Name>/          one addon: <Name>.toc, its Lua files, README, CHANGELOG
addons/<Name>/spec/     its tests (busted), not shipped
spec/helpers/           shared test helpers: a WoW API mock and an addon loader
tools/release.py        checks, packages and uploads releases
tools/tests/            tests for the release tooling (pytest)
tools/docker/           the lint and test image, used locally and in CI
scripts/                check.ps1 / check.sh (lint and test), link-addon.ps1
.github/workflows/      CI on every push and PR; releases on tags
```

## Developing

Link an addon into the game, so edits here show up after `/reload`:

```powershell
./scripts/link-addon.ps1 TwoColumnStats
```

It defaults to the Forever AddOns folder; pass `-AddOnsPath` for another
install. `-Force` moves an existing copy of the addon to a backup first.

Lint and test everything (needs Docker running; the same image CI uses):

```powershell
./scripts/check.ps1
```

That runs luacheck, the busted tests in each `addons/*/spec`, the release
tooling's tests, and `tools/release.py check` on every addon.

### Writing tests

Tests use [busted](https://lunarmodules.github.io/busted/). Two shared helpers:

- `require("addon")("Name")` loads `addons/Name` the way the game does: it
  reads the `.toc` and runs each file with `(addonName, namespace)`. Pass a
  list of files to load only some, e.g. pure modules.
- `require("wow")` is a small in-memory WoW API. Call `wow.reset()` in
  `before_each`, then `wow.fire(event, ...)`, `wow.runTimers()` and
  `wow.printed`. Regions take explicit screen rectangles with `_SetRect`.
  Extend it as addons need more of the API.

Keep game-independent logic (maths, rules) in its own module so it can be
tested without mocks; see `addons/TwoColumnStats/Layout.lua`.

## Adding an addon

1. Create `addons/<Name>/<Name>.toc` with `## Interface`, `## Title` and
   `## Version` (like `1.0.0`), listing its Lua files.
2. Add a `CHANGELOG.md` with a `## [1.0.0]` section, and a `README.md`.
3. Add any new WoW globals it uses to `.luacheckrc`, and tests under `spec/`.
4. Run `./scripts/check.ps1`.

## Releasing

Releases are per addon and start from a tag named `<Name>/v<version>`:

1. Bump `## Version` in the `.toc` and add a matching section to `CHANGELOG.md`.
2. Commit, then tag and push:

   ```powershell
   git tag TwoColumnStats/v1.0.0
   git push origin main TwoColumnStats/v1.0.0
   ```

The release workflow checks that the tag matches the `.toc`, runs every check,
builds `<Name>-<version>.zip` (the `.toc`, its files, README, CHANGELOG and
LICENSE, without tests), and creates a GitHub release with that version's
changelog. A version with a suffix, like `1.1.0-beta.1`, becomes a
pre-release (and a beta on CurseForge).

### CurseForge

Uploading is optional, per addon, and turns on once all of these are set up:

1. Create the project on CurseForge (by hand, once per addon) and add its
   project ID to the `.toc`: `## X-Curse-Project-ID: 123456`.
2. Create an API token at <https://legacy.curseforge.com/account/api-tokens>
   and add it to the GitHub repo as the secret `CF_API_TOKEN`.
3. Find the game version ID(s) to list the file under. The IDs come from
   CurseForge's API, which names versions by number, so filter
   by the game's version (WoW: Forever is `1.60.1`, ID 17053):

   ```powershell
   $env:CF_API_TOKEN = Read-Host "CurseForge API token"
   python tools/release.py curseforge-versions 1.60
   ```

   and add them, comma-separated, as the repo variable
   `CURSEFORGE_GAME_VERSIONS`.

Without these, releases still go to GitHub; the CurseForge step is skipped.
