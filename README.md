# P5S ReShade NN Shaders

A [Reloaded-II](https://reloaded-project.github.io/Reloaded-II/) mod for **Persona 5 Strikers** (`game.exe`) that installs [ReShade](https://reshade.me/) with an NN shader preset.

## What it does

When the mod is enabled and the game is launched through Reloaded-II, it copies the bundled ReShade files from the mod's `Files/` folder into the game directory:

- `d3d11.dll` (ReShade 6.7.3.2150, 64-bit)
- `d3dcompiler_47.dll`
- `ReShade.ini` (uses relative paths, works at any install location)
- `ReShadePreset.ini` (enables `CMAA2_beta@CMAA2.fx`)
- `ReShade_shaders/` (FSR, CMAA2, NN-AA and FXAA shaders)

It does nothing else — no hooks, no configuration UI, no native code.

## Install

1. Grab `P5S.ReShade.7z` from the latest [GitHub Release](https://github.com/Internetperson-dev/Persona-5-Strikers-Reshade-NN-Shaders/releases) (or build locally, see below).
2. Drag the `.7z` file onto the Reloaded-II Launcher window and drop it. It installs itself into your `Mods` folder automatically.
3. In the Launcher, go to **Game** → **Persona 5 Strikers**, and enable **P5S ReShade NN Shaders**.
4. Launch the game from the Launcher. The mod copies the ReShade files into the game folder and ReShade loads.

> To remove the mod, disable it in the Launcher and delete the files it deployed (`d3d11.dll`, `d3dcompiler_47.dll`, `ReShade.ini`, `ReShadePreset.ini`, `ReShade_shaders/`, `ReShade_cache/`) from your game folder. Disabling the mod alone does not delete them.

## Building locally

Requires the .NET 7 SDK.

```powershell
# Set this to your Reloaded-II Mods folder once.
$env:RELOADEDIIMODS = "C:\path\to\Reloaded-II - P5S\Mods"

# Builds straight into the Mods folder:
dotnet build P5S.ReShade.csproj -c Release
```

CI builds (GitHub Actions) publish a ready-to-use `publish/` folder and create a new GitHub Release for every build (versioned `1.0.<run number>`), attaching a `P5S.ReShade.7z` that can be drag 'n dropped straight into the Reloaded-II Launcher.
