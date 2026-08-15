# P5S ReShade NN Shaders

A [Reloaded-II](https://reloaded-project.github.io/Reloaded-II/) mod for **Persona 5 Strikers** (`game.exe`) that installs [ReShade](https://reshade.me/) with the NN shaders for post processing anti-aliasing.

## What it does

When the mod is enabled and the game is launched through Reloaded-II, it loads ReShade directly from the mod's `Files/` folder (`ReShade64.dll`) and hooks the game's `d3d11.dll`:

- `ReShade64.dll` (ReShade 6.7.3.2150, 64-bit)
- `ReShade.ini` (uses relative paths, works at any install location)
- `ReShadePreset.ini` (enables `Sarenya_NNAA@nnaa.fx`)
- `ReShade_shaders/` (NN is the default method.)

ReShade is never copied into the game directory: it is loaded from the mod folder and configured there via `RESHADE_BASE_PATH_OVERRIDE`. This means nothing is left behind, there are no "file is in use" errors, and no cleanup is needed after the game exits.

Works on native Windows (hooks the system `d3d11.dll`) and under Wine (hooks the `d3d11.dll` that Wine resolves, whether wined3d or DXVK). ReShade loads its shader compiler (`D3DCompiler_47.dll`) from the system on Windows and from Wine's built-in copy otherwise, so no extra DLL needs to be bundled. Wine users who hit shader compile issues can override it via `WINEDLLOVERRIDES="d3dcompiler_47=native"` (with a copy of the DLL in the game or prefix directory).

## Install

1. Use `P5S.ReShade.7z` from the latest [GitHub Release](https://github.com/Internetperson-dev/Persona-5-Strikers-Reshade-NN-Shaders/releases) in Reloaded-II as an enabled modification. Press Home when the game boots and ensure the NN shader is enabled.

> To remove the mod entirely: disable it in the Launcher and delete the `P5S.ReShade` folder from `Mods/`. No files are ever written to the game directory, so there is nothing left to clean up.

## Building locally

Requires the .NET 7 SDK.

```powershell
# Set this to your Reloaded-II Mods folder once.
$env:RELOADEDIIMODS = "C:\path\to\Reloaded-II - P5S\Mods"

# Builds straight into the Mods folder:
dotnet build P5S.ReShade.csproj -c Release
```
