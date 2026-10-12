# TABS Hit Replay

By **Andrew**. An unofficial hit replay add-on for Teardown's TABS Vehicle Framework.

![Preview](tabs-hit-replay/preview.jpg)

**Subscribing to TABS or installing this add-on alone is not sufficient: the matching bridge patch is required.**

[Download v0.1.0](https://github.com/swaggyp7/tabs-hit-replay/releases/tag/v0.1.0) · [Original TABS](https://steamcommunity.com/sharedfiles/filedetails/?id=3148138736) · [Optional TABS Crew](https://steamcommunity.com/sharedfiles/filedetails/?id=3561237115)

## Downloads

- `TABS-Hit-Replay-v0.1.0.zip`: the standalone replay mod.
- `TABS-Hit-Replay-Bridge-v0.1.0.zip`: all required TABS replacement files, plus installation instructions and a compatibility manifest.
- `SHA256SUMS.txt`: SHA-256 checksums for both archives.

## Installation

1. Subscribe to [TABS Vehicle Framework](https://steamcommunity.com/sharedfiles/filedetails/?id=3148138736) and its required Workshop items.
2. Extract `TABS-Hit-Replay-v0.1.0.zip` into `Documents/Teardown/mods`. The resulting path must be `mods/tabs-hit-replay/info.txt`. Do not enable duplicate local and Workshop copies of this add-on.
3. Close Teardown. Locate `<SteamLibrary>/steamapps/workshop/content/1167630/3148138736/` in the Steam library holding Teardown.
4. Compare SHA-256 hashes of `main.lua` and `TABS/scripts/ballistics.lua` against `original_sha256` in `compatibility.json`. If they already match `replacement_sha256`, this bridge version is installed. Stop on any other hashes: your TABS version or another patch may be incompatible.
5. Back up both original files outside the Workshop folder, retaining their relative paths. Never overwrite an original backup with patched files.
6. Extract `TABS-Hit-Replay-Bridge-v0.1.0.zip`. Copy the **contents** of its `replacement` folder into `3148138736`, merging directories and replacing exactly the two files shown below. Do not copy the outer `replacement` folder itself. Verify the resulting hashes against `replacement_sha256`.
7. Start Teardown, enable TABS and TABS Hit Replay, and reload the level. Hit a TABS vehicle with a vehicle-mounted weapon to check the replay. TABS Crew is optional and requires no patch.

### Replacement paths and verification

Use the Steam library where Teardown is installed; it may be on a different drive. The destination is the TABS **framework** Workshop directory, not the Teardown game directory, the vehicle pack, or the Hit Replay add-on directory.

```text
<SteamLibrary>/steamapps/workshop/content/1167630/3148138736/
|-- main.lua
`-- TABS/
    `-- scripts/
        `-- ballistics.lua
```

For example, run these PowerShell commands after adjusting the drive and library path:

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath 'D:/SteamLibrary/steamapps/workshop/content/1167630/3148138736/main.lua'
Get-FileHash -Algorithm SHA256 -LiteralPath 'D:/SteamLibrary/steamapps/workshop/content/1167630/3148138736/TABS/scripts/ballistics.lua'
```

Before installation, both hashes must match `original_sha256` in `compatibility.json`. After installation, both must match `replacement_sha256`. The bridge ZIP's README and compatibility manifest are reference documents; they do not need to be copied into TABS. Use `SHA256SUMS.txt` to check the downloaded archives separately.

### Updating, conflicts, and uninstalling

TABS updates can remove the bridge. Check compatibility before reapplying; never overwrite a newer unknown version with this package. Other patches editing the same files need manual integration. To uninstall, close the game and restore your matching original backups only if the current files still match this release's patched hashes. If TABS has updated, obtain a clean current framework instead of restoring stale backups. Disable/remove the replay add-on separately.

## Features and controls

- Recent 3-second hit window with animated projectile and fragment paths; F9 replays the saved window.
- Fixed vehicle framing, internal module status colors, and optional detailed Crew outlines (green alive / red dead).
- F8: toggle replay; F9: replay; F10: switch own-vehicle / nearby-vehicle target mode. Nearby mode has no distance filter, but only simulated hits reaching the bridge can be recorded.
- Vehicle-mounted small-caliber rounds are supported. Standalone handheld weapon shots are **not** currently recorded.
- This is a wireframe replay overlay. Cover artwork is promotional and is not an exact in-game screenshot of the overlay.
- Capture is bounded; very dense fire can reach capacity limits. Crew status uses observed damage/connection state, not an exact per-limb death event.

## Bridge scope and compatibility

The bridge appends recording code to TABS `main.lua` and adds six guarded hook sites in `TABS/scripts/ballistics.lua` for impact, penetration and fragment association. It does not intentionally change native damage formulas or handheld weapon scripts. It requires the exact original file hashes in `compatibility.json`; no universal compatibility is claimed. This release has local scripted verification, not exhaustive compatibility testing on other installations.

## Credits and third-party files

Replay add-on author: **Andrew**. TABS Vehicle Framework belongs to its original creators; see the linked Workshop page for credits. Optional TABS Crew belongs to its respective creators. This is an unofficial project and does not claim endorsement.

The bridge replacement ZIP contains modified TABS source files, which remain third-party material. No blanket license or redistribution permission for TABS is granted by this repository. The TABS page states “DO NOT REUPLOAD WITHOUT PERMISSION”; this README does not represent proof of permission. Crew assets are not included.
