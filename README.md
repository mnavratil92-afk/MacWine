# MacWine

Experimentální prostředí pro Windows aplikace na Apple Silicon: Wine ze zdrojů CrossOveru 26.3.0, DXVK (větev CodeWeavers 1.10.3) a MoltenVK. Aktuální vývoj probíhá na M1 Pro s macOS 27. Unixová část Wine je x86_64 a běží přes Rosettu; WoW64 zajišťuje 32bitové Windows aplikace.

## Stav

Podle předání od Clauda uživatel při ručním testu 11. října 2026 potvrdil GTA V Legacy při limitu 60 FPS, zatížení GPU přibližně 60–70 % a bez zamrzání během testu. Fungující konfigurace kombinuje GCC 13.4, upravené výchozí hodnoty MoltenVK, údaj SDK 15.1 v binárkách a okno bez okrajů. Délka testu nebyla zaznamenána a vliv jednotlivých změn nebyl ověřen odděleně. Steam a Rockstar Launcher se vykreslují. Projekt není hotová náhrada všech funkcí CrossOveru.

## Předpoklady

- Apple Silicon, Rosetta a plný Xcode; skript MoltenVK standardně používá `/Applications/Xcode.app/Contents/Developer` (lze změnit `DEVELOPER_DIR`).
- Homebrew v `/opt/homebrew`. Skripty používají zejména CMake, Ninja, Meson, pkg-config, autoconf/automake/libtool, Bison, Flex, LLVM/LLD a knihovny GMP, MPFR, MPC, ISL. Nativní nástroje Wine potřebují také dostupný FreeType. Toto je seznam požadavků současných skriptů, nikoli ověřený instalátor pro čistý Mac.
- Internet pro stažení překladačů a dalších závislostí; dostatek místa pro zdroje a několik souběžných sestavení.
- MoltenVK sestavte před Wine podle postupu níže: konfigurace Wine ji pak najde v `$MACWINE_DEST/lib/libMoltenVK.dylib`. Cestu lze přepsat přes `MOLTENVK_DYLIB`.

## Příprava zdrojů

Příkazy spouštějte z této složky `macwine`. Zvolte **nový, dosud neexistující** adresář s existujícím rodičem. Následující příklad používá oddělený build i runtime:

```bash
export MACWINE_BUILD="$HOME/macwine-build-fresh"
export MACWINE_HOME="$HOME/MacWine-fresh"
export MACWINE_DEST="$MACWINE_HOME/runtime"
./prepare-sources.sh "$MACWINE_BUILD"
```

Případně použijte již stažený archiv:

```bash
./prepare-sources.sh "$MACWINE_BUILD" \
  "$HOME/macwine-build/crossover-sources-26.3.0.tar.gz"
```

Jde o dvě alternativy; druhý příkaz nespouštějte do cíle vytvořeného prvním. Skript odmítá každý existující cíl, ověřuje SHA-256 archivu a aplikuje všechny `patches/*.patch` v abecedním pořadí bez fuzzy shody. Předpona názvu vybírá kořen `sources/wine`, `sources/dxvk` nebo `sources/moltenvk`; neznámá předpona je chyba. Neúspěšná příprava uklidí pracovní data, může ponechat prázdný cílový adresář.

Archiv zůstane v kořeni build adresáře, protože jej znovu čte `build-moltenvk.sh`. Soubor `prepare-sources.manifest` zaznamenává otisk archivu a aplikovaných patchů. Použitý SHA-256 je otisk lokálního archivu použitého při vývoji, nikoli podpis vydavatele. Příprava zdrojů je opakovatelná; celý výsledný build zatím není garantován jako bitově reprodukovatelný.

## Sestavení

Doporučené pořadí připraví vlastní MoltenVK ještě před konfigurací Wine:

```bash
./build-toolchain.sh
./build-deps.sh
./build-moltenvk.sh
./build-wine.sh
./build-dxvk.sh
./package-runtime.sh
```

Pokud konfigurační knihovna MoltenVK chybí, `build-wine.sh` má záložní cestu do `~/Applications/CrossOver.app/Contents/SharedSupport/CrossOver/lib64/`; při doporučeném postupu není potřeba.

Význam jednotlivých kroků:

1. **toolchain**: binutils 2.41, GCC 13.4.0 a mingw-w64 11.0.1 pro x86_64 a i686; CRT `msvcrt`, vlákna POSIX. Skript používá systémovou zlib a samostatný sysroot pro každý cíl. Podle zjištění při vývoji používá CodeWeavers GCC 13.2.0; zde byla zvolena 13.4.0 kvůli problému se sestavením 13.2.0 s libc++ z Xcode 27.
2. **deps**: x86_64 FreeType, GMP, Nettle a GnuTLS. Nettle 3.10 se stahuje samostatně, protože zdrojový balík CodeWeavers postrádá potřebný `Makefile.in`.
3. **moltenvk**: používá SPIRV-Cross z archivu CodeWeavers; další závislosti řeší `fetchDependencies`. Skript upravuje cílovou verzi macOS v projektech pro Xcode 27.
4. **wine**: nejdříve nativní nástroje ARM64, potom x86_64 Wine s 32/64bitovým WoW64. Windows část používá `-std=gnu17` a vlastní GCC 13.
5. **dxvk**: sestaví obě architektury, odstraní ladicí symboly a instaluje D3D9–11 DLL. `dxgi.dll` se používá z Wine.
6. **package-runtime**: zkopíruje podpůrné knihovny do runtime, upraví jejich odkazy a lokálně je podepíše. Navíc pomocí `xcrun vtool` nastavuje údaj SDK na 15.1 u Wine loaderu, wineserveru, unixových `.so` a MoltenVK a znovu je lokálně podepisuje. Minimální verzi macOS zachovává; nejde o nové přeložení proti SDK 15.1. Cílem této změny je sladění chování kompatibility macOS se sestavením CrossOveru při vykreslování; samostatný přínos nebyl izolovaným testem potvrzen. Nevytváří samo o sobě instalační balíček ani aplikaci `.app`.

Skripty uchovávají konfiguraci a značky dokončených kroků v `obj/`. Změna překladače či konfiguračních voleb se proto nemusí projevit při pouhém opakovaném spuštění. Pro čisté ověření použijte nový build adresář. Do právě běžícího sestavení nezasahujte.

## Spouštěč

Na vývojovém Macu je runtime fyzicky v `~/Applications/MacWine.app/Contents/MacOS/runtime` a `~/MacWine/runtime` je symbolický odkaz na něj. Balíček `MacWine.app` byl vytvořen ručně; obsahuje `Info.plist` a spouštěcí skript `Contents/MacOS/MacWine`, který volá `macwine steam gta`. Umístění runtime v balíčku slouží k přiřazení procesů Wine k aplikaci v systému. Sestavovací skripty tento balíček nezakládají.

Spouštěč očekává runtime v `$MACWINE_HOME/runtime`; výchozí `MACWINE_HOME` je `~/MacWine`. `MACWINE_DEST` ovlivňuje sestavovací skripty, nikoli umístění runtime ve spouštěči. Při vlastním umístění musí obě hodnoty odpovídat.

```bash
./macwine create hry
./macwine steam hry
./macwine run hry "/absolutni/cesta/program.exe"
```

Bottle je samostatné prostředí Windows uložené v `$MACWINE_HOME/bottles/<název>`. Používejte jednoduché názvy bez lomítek.

| Příkaz | Účel |
| --- | --- |
| `create <bottle>` | Vytvoří Windows 10 bottle, zkopíruje DXVK a zapíše kompatibilitu. |
| `run <bottle> <program.exe> [argumenty…]` | Spustí program; doporučena absolutní cesta. |
| `steam <bottle>` | Při prvním použití stáhne a nainstaluje Steam, pak jej spustí. |
| `cfg <bottle>` | Otevře winecfg. |
| `kill <bottle>` | Ukončí všechny Wine procesy daného bottlu. |
| `fps <bottle> <n>` | Uloží trvalý limit FPS do `<bottle>/macwine-fps`; `0` ruší tento limit. Platí při dalším spuštění hry. |
| `list` | Vypíše existující bottles. |
| `dxvk <bottle>` | Znovu zkopíruje DXVK DLL do bottlu a nastaví registry. |
| `compat <bottle>` | Znovu zapíše pravidla kompatibility. |

Při `run` a `steam` spouštěč porovnává 64bitovou `d3d11.dll` s vybraným zdrojem DXVK. Při rozdílu provede aktualizaci bottlu a obnoví DXVK automaticky, takže po běžné aktualizaci runtime není nutné ručně volat `./macwine dxvk hry`. Tento příkaz zůstává dostupný pro vynucené obnovení všech DXVK DLL. Změněná pravidla registru se aplikují přes `./macwine compat hry`. Před těmito změnami ukončete programy daného bottlu.

## Nastavení a diagnostika

| Proměnná | Význam |
| --- | --- |
| `MACWINE_BUILD` | Sestavovací adresář; výchozí `~/macwine-build`. |
| `MACWINE_DEST` | Cílový runtime sestavení; výchozí `~/MacWine/runtime`. |
| `MACWINE_HOME` | Domov spouštěče s runtime, bottles a logy. |
| `MACWINE_LOG=1` | Zapne diagnostiku Wine a DXVK v `$MACWINE_HOME/logs/<bottle>-<čas>/`. |
| `MACWINE_HUD=1` | Zapne DXVK HUD s FPS, časy snímků, zatížením GPU a indikátorem překladu shaderů. |
| `MACWINE_DXVK_DIR` | Alternativní zdroj DLL pro instalaci i automatickou kontrolu při `run`/`steam`; obsahuje `x86_64-windows` a `i386-windows`. |
| `MACWINE_FPS=<n>` | Jednorázový limit FPS, který má přednost před uloženým nastavením bottlu; předává se přes `DXVK_FRAME_RATE`. |
| `MACWINE_MVK_DIR` | Přidá složku s alternativní `libMoltenVK.dylib` na začátek vyhledávací cesty při běhu. |
| `MOLTENVK_DYLIB` | Cesta ke knihovně pro konfiguraci Wine při sestavení. |

```bash
MACWINE_LOG=1 MACWINE_HUD=1 ./macwine steam hry
```

Spouštěč zapíná `WINEMSYNC=1` a standardně `ROSETTA_ADVERTISE_AVX=1`. Bez diagnostického režimu vypíná běžné logy Wine a DXVK. `MACWINE_LOG=1` nejprve vypíše umístění logů na obrazovku a poté přesměruje standardní chybový výstup do `wine.log`.

## Doporučené nastavení GTA V Legacy

Použijte **okno bez okrajů** místo exkluzivního fullscreenu. Podle diagnostiky předané Claudem se zamrzání objevovalo při přepínání režimu displeje v exkluzivním fullscreenu. V testovaném `settings.xml` bylo `Windowed=2`, `VSync=0` a rozlišení 2056×1329; na jiném displeji zvolte jeho odpovídající rozlišení.

```bash
./macwine fps gta 60
MACWINE_LOG=1 MACWINE_HUD=1 ./macwine steam gta
```

Tento příklad předpokládá existující bottle `gta`. Pro jednorázovou změnu použijte například `MACWINE_FPS=60 ./macwine steam gta`. Doporučení vychází z testu GTA V Legacy na tomto Macu, nikoli z ověření všech her.

## Záplaty a kompatibilita

- `wine-macwine-compat.patch` je vlastní otevřená implementace vybraných pravidel pro Steam, Rockstar a GTA, obdobná účelu `cxcompatdb.so`; projekt nepoužívá ani nedistribuuje samotnou databázi CrossOveru. Přidává čtení pravidel z `HKCU\Software\MacWine\Compat`. Spouštěč nastavuje argumenty pro Chromium ve Steam/Rockstar launcherech. Steam dostává `--no-sandbox --in-process-gpu --disable-gpu`, kromě procesu s `--type=crashpad-handler`; SocialClubHelper dostává `--in-process-gpu --use-gl=angle --use-angle=swiftshader`. Rockstar `Launcher.exe` používá vestavěné D3D knihovny Wine. Pro `PlayGTAV.exe` se přidává `-nobattleye`; tento režim není potvrzením funkčnosti GTA Online.
- `dxvk-mingw14.patch` podmiňuje starší náhradní deklarace podle verze mingw-w64; s aktuálním toolchainem mingw 11 zůstávají dostupné. Sestavení DXVK navíc přidává hlavičku `cstdint`.
- `moltenvk-crossover-defaults.patch` mění výchozí hodnoty: synchronous queue submits `0`, large query pools `0`, full image view swizzle `1`, log level `WARNING`, resume lost device `1`, Metal argument buffers `0`, maximize concurrent compilation `1`. Jde o nastavení zvolená při porovnávání s CrossOverem; samostatný vliv těchto hodnot na odstranění zamrzání nebyl izolovaně ověřen.

## Spolupráce na projektu

Codex připravuje `prepare-sources.sh` a tento README. Claude spravuje spouštěč, sestavovací skripty, patche a běžící sestavení. Pracovní zprávy se předávají v lokální `.collab/`, vyloučené přes `.git/info/exclude`; toto vyloučení se nepřenáší do jiného klonu. Soubory samy neprobouzejí nečinného agenta, proto se důležitá předání oznamují také v chatu.
