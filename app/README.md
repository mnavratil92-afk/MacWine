# MacWine native app

A SwiftUI app for macOS 13 or later. The app itself needs no Python or web server.

## Build and package

From the `macwine` directory:

```bash
swift test --package-path app
swift build -c release --package-path app
```

The executable is `app/.build/release/MacWine`. `package-app.sh` combines it with the CLI and runtime:

- `MacWine.app/Contents/MacOS/MacWine`: app executable
- `MacWine.app/Contents/Resources/macwine`: command-line backend
- `MacWine.app/Contents/Resources/runtime`: runtime and supporting tools

For development, `MACWINE_CLI` overrides the backend path. No developer-specific path is embedded in the app. The bundle must declare EXE/MSI document types to send Finder file-open events to `onOpenURL`. Set `CFBundleDevelopmentRegion` and `CFBundleLocalizations` to English.

## User interface

The interface is in English. The sidebar puts **All Games** and **Stores** first, with **Custom Bottles** separately. Store-linked bottles remain accessible through the store's settings; unlinked bottles appear in Custom Bottles. Users can create bottles and run their own EXE/MSI installers.

Installed games have full-color artwork and **Play**. Owned but uninstalled games have grayscale artwork and **Install**. Search and an installed-only filter work across the library. A game remains uninstalled until the local/backend installation state says otherwise; clicking Install does not mark it installed.

Shortcuts can be saved manually or created automatically for installed games (opt-in). The **Sponsor MacWine** button opens the project's GitHub Sponsors page (derived from `MacWineRepo` in Info.plist), or the HTTPS address in `MacWineDonationURL` when that is set.

Appearance is selectable in **MacWine → Settings…** (⌘,): **System**, **Light**, or **Dark**, and is remembered between launches. Sidebar buttons navigate directly, highlight the active page, and clear search/filter state when changing sections. Secondary shortcut preferences are in **Library Options**.

## Account libraries

The app consumes `accounts --json` and `library <store> --json` from the backend. Ownership and installation are separate states, and the UI only labels a library as an account library after a successful response with the full-library capability.

- **Steam:** sign in in Steam, then optionally enter a Steam Web API key to retrieve owned games. The API also depends on the visibility of the account's game details. The key is entered in a secure field, sent to `set-key steam` via standard input and stored by the backend in macOS Keychain.
- **Epic Games:** the backend returns an Epic sign-in URL. The user signs in in the browser and pastes the one-time authorization code into a secure field. The app sends it via standard input to `connect epic --bottle <name> --code-stdin`. The backend handles Legendary and the account library.
- **GOG and Ubisoft Connect:** this version shows local installations in MacWine; the complete owned library and installation are available in the respective store launcher. Full account-library integration for these two stores is not implemented. The UI states this limitation explicitly.

No account password is requested by MacWine. Keys/codes are not passed in process arguments or added to the repository. The CLI wrapper redacts a supplied secret if it appears in an error. Signing in and successful real-account synchronization still require user interaction and cannot be inferred from mock tests.

Backend protocol details are maintained in the local collaboration documents. Core models support the array library response and a future `{games, complete, message}` envelope. Local manifests provide fallback installations, including additional Steam library folders. Nonstandard GOG installation folders may require manual EXE launch.

Official references: [Steam owned-games API](https://partner.steamgames.com/doc/webapi/IPlayerService?language=english), [Steam API key page](https://steamcommunity.com/dev/apikey), [Legendary](https://github.com/legendary-gl/legendary).

## Verification

The test suite covers Valve KeyValues, Steam library folders, installed state bits, Epic/GOG/Ubisoft local manifests, malformed metadata, drive mapping, shell-free argument passing, large command output, error propagation, owned/local library merging and stdin secret redaction.

Visual checks use a separate UI-test bundle and fake CLI: installed and uninstalled cards, grayscale rendering, store navigation, custom bottles and English error dialogs. Real GTA data is only read; game/store installation and sign-in require separate integration checks with an appropriate test bottle.

## App and runtime updates

Sparkle 2 is resolved through SwiftPM (see Package.resolved). Copy the entire
`app/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework`
to `Contents/Frameworks`, preserving symlinks. The executable includes
`@executable_path/../Frameworks` as an rpath. Sign nested components and the final
app according to Sparkle's packaging requirements.

Release Info.plist must include an HTTPS `SUFeedURL`, a valid base64 32-byte
`SUPublicEDKey`, and `SUEnableAutomaticChecks=true` for the default automatic
check behavior. Without valid feed/key configuration, the app runs normally and
update controls are disabled. **MacWine → Check for Updates…** opens Sparkle;
**Settings…** includes its automatic-check preference. Signing private keys never
belong in source or in the application. Integration follows
[the Sparkle setup guide](https://sparkle-project.org/documentation/programmatic-setup/)
and [configuration guide](https://sparkle-project.org/documentation/customization/).

Startup calls `runtime status --json` before showing the library. If components
are missing/outdated, a setup screen offers Download Components, shows stderr
`progress <0–100>` lines from `runtime install --json`, and supports Retry Download.
100% means download complete; the app waits for successful verification/install
and re-checks runtime status before allowing game actions. Local bundled runtimes
may return `required: null`. Runtime download and extraction remain CLI responsibilities.
