# Tested games and launchers

This list contains only what has been tested by hand. For everything else, see the community ratings in the app (open a game → **Community rating**) or the [Compatibility discussions](https://github.com/mnavratil92-afk/MacWine/discussions/categories/compatibility).

Tested on a MacBook Pro M1 Pro, macOS 27, MacWine 0.9.x.

## Games

| Game | Store | Status | Notes |
| --- | --- | --- | --- |
| Grand Theft Auto V Legacy | Steam | ✅ Plays well | Story mode at a steady 60 FPS (GPU about 60–70 %). Use *Windowed Borderless* and a 60 FPS limit – exclusive fullscreen can freeze. Online modes protected by BattlEye are not supported. |
| The Forest | Steam | ✅ Runs | Starts and renders correctly; longer play not tested yet. |
| Human Resource Machine | Epic | ✅ Runs | Downloaded directly from Epic (no launcher); DirectX 9 game. |
| FlatOut | GOG | ⚠️ Runs, audio stutters | Downloaded directly from GOG (no GOG Galaxy); renders correctly (DirectX 9), sound stutters in the menu. |

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
- **EA app** games (e.g. The Sims 4 from Epic) are not supported yet.
