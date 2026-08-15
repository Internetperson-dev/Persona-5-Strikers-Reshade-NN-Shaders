# P5S ReShade NN Shaders

A [Reloaded-II](https://reloaded-project.github.io/Reloaded-II/) mod for **Persona 5 Strikers** (`game.exe`) that installs [ReShade](https://reshade.me/) with the NN shaders for post processing anti-aliasing .

## What it does

When the mod is enabled and the game is launched through Reloaded-II, it copies the bundled ReShade files from the mod's `Files/` folder into the game directory:

- `d3d11.dll` (ReShade 6.7.3.2150, 64-bit)
- `d3dcompiler_47.dll`
- `ReShade.ini` (uses relative paths, works at any install location)
- `ReShadePreset.ini`
- `ReShade_shaders/` (NN is the default method. )

## Install

1. Use `P5S.ReShade.7z` from the latest [GitHub Release](https://github.com/Internetperson-dev/Persona-5-Strikers-Reshade-NN-Shaders/releases)  in Reloaded-II as an enabled modification. Press home when the game boots and ensure the NN shader is enabled.

> To remove the mod, disable it in the Launcher and delete the files it deployed (`d3d11.dll`, `d3dcompiler_47.dll`, `ReShade.ini`, `ReShadePreset.ini`, `ReShade_shaders/`, `ReShade_cache/`) from your game folder. Disabling the mod alone does not delete them.

## Building locally

Requires the .NET 7 SDK.

```powershell
# Set this to your Reloaded-II Mods folder once.
$env:RELOADEDIIMODS = "C:\path\to\Reloaded-II - P5S\Mods"

# Builds straight into the Mods folder:
dotnet build P5S.ReShade.csproj -c Release
```
