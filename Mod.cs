using System;
using System.IO;
using System.Runtime.InteropServices;
using Reloaded.Mod.Interfaces;

namespace P5S.ReShade;

/// <summary>
/// Loads ReShade directly out of the mod's <c>Files</c> folder when the mod is enabled.
///
/// The bundled ReShade module is deployed under the non-proxy name <c>ReShade64.dll</c>.
/// Because that name does not collide with <c>d3d11.dll</c>, ReShade's
/// <c>hooks::register_module</c> treats the game's already-loaded <c>d3d11.dll</c> as a
/// regular target and installs its function hooks immediately (instead of expecting to be
/// loaded as a proxy). This works on Windows (real system d3d11) and under Wine
/// (wined3d or DXVK d3d11, however the user's WINEDLLOVERRIDES resolves it), because
/// ReShade hooks whichever d3d11 module the game actually loaded.
///
/// The <c>RESHADE_BASE_PATH_OVERRIDE</c> environment variable points ReShade at the mod's
/// <c>Files</c> folder, so its configuration, shaders and preset all resolve relative to
/// the mod folder. Nothing is ever copied into the game directory, which means no "file is
/// in use" errors and nothing to clean up afterwards.
/// </summary>
public class Mod : IDisposable
{
    /// <summary>Sub-directory of the mod folder holding the bundled ReShade files.</summary>
    private const string FilesSubDirectory = "Files";

    /// <summary>File name the bundled ReShade module is deployed under.</summary>
    private const string ReShadeDllName = "ReShade64.dll";

    /// <summary>Environment variable ReShade reads to override its base path.</summary>
    private const string BasePathOverrideVariable = "RESHADE_BASE_PATH_OVERRIDE";

    /// <summary>Display name of the key bound to <c>[INPUT] KeyOverlay</c> in the bundled ReShade.ini.</summary>
    private const string OverlayKeyName = "Home";

    private readonly ILogger _logger;
    private readonly IntPtr _reshadeModule;

    public Mod(ModContext context)
    {
        _logger = context.Logger;

        var modDirectory = context.ModLoader.GetDirectoryForModId(context.ModConfig.ModId)
            .TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var filesDirectory = Path.Combine(modDirectory, FilesSubDirectory);
        var reshadePath = Path.Combine(filesDirectory, ReShadeDllName);

        if (!File.Exists(reshadePath))
        {
            _logger.WriteLine($"[P5S.ReShade] ReShade module not found at '{reshadePath}'. ReShade will not be loaded.");
            _reshadeModule = IntPtr.Zero;
            return;
        }

        // Point ReShade at the mod folder so its config, shaders and preset resolve relative
        // to it instead of the game directory. Only set it if the user has not already forced
        // a location themselves.
        if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable(BasePathOverrideVariable)))
            Environment.SetEnvironmentVariable(BasePathOverrideVariable, filesDirectory);

        _reshadeModule = LoadLibrary(reshadePath);
        _logger.WriteLine(_reshadeModule == IntPtr.Zero
            ? $"[P5S.ReShade] Failed to load ReShade from '{reshadePath}' (error 0x{Marshal.GetLastWin32Error():X8})."
            : $"[P5S.ReShade] ReShade loaded from '{reshadePath}'. Press {OverlayKeyName} in game to open the overlay.");
    }

    public void Dispose()
    {
        // The module must stay mapped for the lifetime of the game process: ReShade holds
        // hooks into the game and tears itself down when the process exits on its own.
        // Deliberately no FreeLibrary here.
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr LoadLibrary(string lpFileName);
}
