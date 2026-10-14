# Tested games and launchers

This list contains only what has been tested by hand. For everything else, see the community ratings in the app (open a game → **Community rating**) or the [Compatibility discussions](https://github.com/mnavratil92-afk/MacWine/discussions/categories/compatibility).

Tested on a MacBook Pro M1 Pro, macOS 27, MacWine 0.9.x.

## Games

| Game | Store | Status | Notes |
| --- | --- | --- | --- |
| Grand Theft Auto V Legacy | Steam | ✅ Plays well | Story mode at a steady 60 FPS (GPU about 60–70 %). Use *Windowed Borderless* and a 60 FPS limit – exclusive fullscreen can freeze. Online modes protected by BattlEye are not supported. |
| The Forest | Steam | ✅ Runs | Starts and renders correctly; longer play not tested yet. |
| Human Resource Machine | Epic | ✅ Plays well | Downloaded directly from Epic (no launcher). DirectX 9. Turn on *Better sound for older games* (choppy sound otherwise); 60 FPS limit recommended. |
| FlatOut | GOG | ⚠️ Playable, slow | Downloaded directly from GOG (no GOG Galaxy). DirectX 9: 40 FPS in menus, 13–25 FPS in races (limited by Rosetta). Turn on *Better sound for older games* – sound is clean then. |
| Medal of Honor: Airborne | Steam | ❌ Not playable | Starts and menus work (55–60 FPS), but gameplay runs at 2–11 FPS (DirectX 9, CPU-bound under Rosetta). Turn on *Better sound for older games* (metallic sound otherwise). |
| The Elder Scrolls IV: Oblivion GOTY Deluxe | GOG | ⚠️ Playable, slow | Downloaded directly from GOG; MacWine applies GOG's registry setup and starts xOBSE when it is installed. Needs windowed mode (e.g. 1280×800 in `Documents/My Games/Oblivion/Oblivion.ini`) – fullscreen at the default resolution crashes. FPS varies a lot outdoors. Turn on *Better sound for older games*. |
| Hidden and Dangerous Deluxe | Own bottle (installer) | ✅ Runs | Installed with its Windows installer into a custom bottle; MacWine finds the installed program automatically. Turn on *Better sound for older games*. |

## Launchers and stores

| Launcher / store | Status | Notes |
| --- | --- | --- |
| Steam | ✅ Works | Sign-in, store pages, library, downloads. |
| Rockstar Games Launcher | ✅ Works | Needed for GTA V; uses Wine's built-in Direct3D. |
| Ubisoft Connect | ✅ Works | Sign-in and library; MacWine reads the library from Ubisoft Connect. |
| Epic Games | ✅ Works | Sign-in inside MacWine, full library, direct game downloads (Legendary). |
| GOG | ✅ Works | Sign-in inside MacWine, full library, direct game downloads (gogdl). |

## Known limitations

- **Anti-cheat** (BattlEye, Easy Anti-Cheat, Vanguard, …) usually blocks Wine – online games that rely on it will not run.
- **DirectX 12** needs Apple's D3DMetal, which MacWine cannot ship (experimental import of your own copy).
- **In-game videos** in some games may not play yet.
- **Older games with DirectSound audio** can sound metallic or choppy – turn on *Better sound for older games* for that game.
- **EA app** games (e.g. The Sims 4 from Epic) are not supported yet.
