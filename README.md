# sourceSPAP

> source™ Single Player Archipelago Plugin

**WARNING: sourceSPAP is in early alpha development and is not currently functional. Any and all programming help is appreciated.**

**sourceSPAP** is a SourceMod plugin for singleplayer games made with the Half-Life 2 engine, designed to facilitate the randomisation of said games through the use of [Archipelago](https://archipelago.gg/). It runs directly within games as an always-on listen server, maintaining a connection to an Archipelago server and modifying the game state accordingly.

## Supported Games

| Game                                                 | Status             |
| ---------------------------------------------------- | ------------------ |
| **[Portal](https://store.steampowered.com/app/400)** | ⏳ Work in progress |

Support for other Source Engine games may be added in the future. Any game not made with the Half-Life 2 engine (e.g. Portal 2) cannot be supported by this plugin.

## Installation

*Optional:* The Windows versions of Source Engine games typically run better than the Linux versions, and are more supported by SourceMod. To switch to the Windows version: in Steam, right-click the game, navigate to `Properties > Compatibility` and check `Force the use of a specific Steam Play compatibility tool`, setting it to `Proton Hotfix`.

To install sourceSPAP:

1. Install the latest stable builds of **[Metamod:Source](https://www.metamodsource.net/downloads.php?branch=stable)** and **[SourceMod 1.12](https://www.sourcemod.net/downloads.php?branch=stable)** by placing them directly in the game's `addons/` folder. If you are using the Windows version of the game, install the Windows versions of Metamod:Source and SourceMod.
2. Move the default `.smx` files in `addons/sourcemod/plugins/` to `addons/sourcemod/plugins/disabled/`. sourceSPAP will not run if any other plugins are present.
3. sourceSPAP requires the latest releases of **[sm-ext-json](https://github.com/ProjectSky/sm-ext-json)** and **[sm-ext-websocket](https://github.com/ProjectSky/sm-ext-websocket)** for SourceMod 1.12 to be installed as well.
4. Place this plugin's compiled `.smx` file in the game's `addons/sourcemod/plugins/` folder. As there are no releases yet, refer to the *Compiling* section for instructions on how to compile the plugin.

## Compiling

It is recommended to use **[SourceMod Studio](https://sarrus1.github.io/sourcepawn-studio/)** when developing sourceSPAP, as it provides facilities for downloading SourceMod 1.12 and compiling the plugin.

In addition, sourceSPAP uses **sm-ext-json** and **sm-ext-websocket** as dependencies and requires their `.inc` files to compile. The `.inc` files can be downloaded from their respective GitHub repositories.

To compile sourceSPAP, provided all dependencies are installed, use the following commands as a guide (Note: These commands only work if you are using the Linux version of the game. If using the Windows version, use SourceMod Studio's `./spcomp` in its installed location instead.):

```bash
# Copy source file to game scripting folder
cp sourcespap.sp /.../steam/steamapps/common/<GAME_NAME>/<GAME_FOLDER>/addons/sourcemod/scripting/
# Move to game scripting folder
cd /.../steam/steamapps/common/<GAME_NAME>/<GAME_FOLDER>/addons/sourcemod/scripting/
# Compile with spcomp to plugins folder
spcomp.exe sourcespap.sp -o ../plugins/sourcespap.smx
```

## Contributing

Discussion of the development of sourceSPAP is currently relegated to the [Portal 1 thread on the Archipelago Discord server](https://discord.com/channels/731205301247803413/1439872289943453789). As there is no assembled team for this project yet, reach out to project lead **Jack5** for any questions, suggestions or requests to become a primary contributor or maintainer of the plugin. Pull requests are also appreciated.
