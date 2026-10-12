# TABS Hit Replay

![Preview](tabs-hit-replay/preview.jpg)

**Subscribe to TABS Hit Replay on Steam Workshop, then manually install the TABS bridge patch below.**

[Download v0.1.0](https://github.com/swaggyp7/tabs-hit-replay/releases/tag/v0.1.0) · [Original TABS](https://steamcommunity.com/sharedfiles/filedetails/?id=3148138736) · [Optional TABS Crew](https://steamcommunity.com/sharedfiles/filedetails/?id=3815951830)

## What to download

**Get TABS Hit Replay from the Steam Workshop. This Release only provides the patch for TABS Vehicle Framework.**

Download **[TABS-Hit-Replay-Bridge-v0.1.0.zip](https://github.com/swaggyp7/tabs-hit-replay/releases/download/v0.1.0/TABS-Hit-Replay-Bridge-v0.1.0.zip)**. You do not need to download or install the replay mod from GitHub.

## Manual installation

### 1. Subscribe on Steam

Subscribe to **TABS Hit Replay** in the Steam Workshop, and to [TABS Vehicle Framework](https://steamcommunity.com/sharedfiles/filedetails/?id=3148138736) with its required items. Wait for Steam to finish downloading them, then **close Teardown**.

### 2. Open the TABS folder

In Steam, right-click **Teardown > Manage > Browse local files**. This opens a folder like:

```text
D:/SteamLibrary/steamapps/common/Teardown
```

Go up two folders to **steamapps**, then open:

```text
workshop/content/1167630/3148138736
```

This is the TABS Vehicle Framework folder. Your drive or Steam library name may differ. Leave this window open.

### 3. Back up the original files

Copy these two files from the TABS folder to a safe place, such as a new folder on your Desktop:

- `main.lua` (directly inside `3148138736`)
- `ballistics.lua` (inside `3148138736/TABS/scripts`)

Keep these originals so you can undo the patch. If you already patched TABS, do not overwrite your original backups.

### 4. Replace the two files

Extract the downloaded bridge ZIP. Open its **replacement** folder.

Copy each file to the matching destination below, choosing **Replace the file in the destination** when Windows asks:

| File from the extracted ZIP | Destination inside the TABS folder |
|---|---|
| `replacement/main.lua` | `3148138736/main.lua` |
| `replacement/TABS/scripts/ballistics.lua` | `3148138736/TABS/scripts/ballistics.lua` |

That is all you need to copy. Do not put these files in the Hit Replay mod folder or in `Documents/Teardown/mods`. Do not copy the outer `replacement` folder itself.

### 5. Play

Start Teardown. Enable **TABS Vehicle Framework** and **TABS Hit Replay** in Mod Manager, then load a level. Hit a TABS vehicle with a vehicle-mounted weapon to see the replay. Press **F9** to replay the saved hits.

[Enhanced TABS Crew](https://steamcommunity.com/sharedfiles/filedetails/?id=3815951830) is optional. Subscribe to it if you want crew outlines; no Crew files need replacing.

## Updates and uninstalling

This patch targets a specific TABS version. A TABS update may remove the patch or make these replacement files incompatible. Do not overwrite an unknown newer version with old files. Other patches that replace these same files can conflict.

To undo this patch, close Teardown and restore the two original files you backed up. Only use backups from the same TABS version; if TABS has updated since the backup, obtain a clean current TABS installation instead. Unsubscribe from or disable Hit Replay separately if you no longer want it.

<details>
<summary>Advanced: check the supported TABS version and file hashes</summary>

The ZIP includes `compatibility.json`. Its `original_sha256` values identify the supported unmodified TABS files; `replacement_sha256` identifies the installed patch. If the files match neither set, stop and check compatibility before replacing them.

In PowerShell, adjust the paths to your Steam library:

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath 'D:/SteamLibrary/steamapps/workshop/content/1167630/3148138736/main.lua'
Get-FileHash -Algorithm SHA256 -LiteralPath 'D:/SteamLibrary/steamapps/workshop/content/1167630/3148138736/TABS/scripts/ballistics.lua'
```

`SHA256SUMS.txt` verifies the downloaded bridge ZIP. The README and compatibility manifest are documentation; they do not need to be copied into TABS.

</details>

## Features and controls

- Recent 3-second hit window with animated projectile and fragment paths; F9 replays the saved window.
- Fixed vehicle framing, internal module status colors, and optional detailed Crew outlines (green alive / red dead).
- F8: toggle replay; F9: replay; F10: switch own-vehicle / nearby-vehicle target mode. Nearby mode has no distance filter, but only simulated hits reaching the bridge can be recorded.
- Vehicle-mounted small-caliber rounds are supported. Standalone handheld weapon shots are **not** currently recorded.
- This is a wireframe replay overlay. Cover artwork is promotional and is not an exact in-game screenshot of the overlay.
- Capture is bounded; very dense fire can reach capacity limits. Crew status uses observed damage/connection state, not an exact per-limb death event.

## Bridge scope and compatibility

The bridge appends recording code to TABS `main.lua` and adds six guarded hook sites in `TABS/scripts/ballistics.lua` for impact, penetration and fragment association. It does not intentionally change native damage formulas or handheld weapon scripts. It requires the exact original file hashes in `compatibility.json`; no universal compatibility is claimed. This release has local scripted verification, not exhaustive compatibility testing on other installations.
