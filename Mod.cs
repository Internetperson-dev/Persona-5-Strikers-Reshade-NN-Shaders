using Reloaded.Mod.Interfaces;

namespace P5S.ReShade;

/// <summary>
/// Copies the ReShade files bundled in the mod's <c>Files</c> folder
/// into the game directory. Runs once when the mod is loaded by Reloaded-II.
/// </summary>
public class Mod : IDisposable
{
    /// <summary>
    /// Sub-directory of the mod folder containing the files to deploy.
    /// </summary>
    private const string FilesSubDirectory = "Files";

    private readonly ILogger _logger;
    private readonly string _modDirectory;
    private readonly string _gameDirectory;

    public Mod(ModContext context)
    {
        _logger = context.Logger;
        _modDirectory = context.ModLoader.GetDirectoryForModId(context.ModConfig.ModId).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        _gameDirectory = GetGameDirectory(context.ModLoader);
        DeployFiles();
    }

    /// <summary>
    /// Determines the directory of the running game executable.
    /// Uses the application location from the Reloaded-II app config when available,
    /// otherwise falls back to the directory of the current process.
    /// </summary>
    private string GetGameDirectory(IModLoader modLoader)
    {
        var appLocation = modLoader.GetAppConfig().AppLocation;
        if (!string.IsNullOrEmpty(appLocation) && Path.IsPathRooted(appLocation))
            return Path.GetDirectoryName(appLocation) ?? string.Empty;

        var processPath = Environment.ProcessPath;
        if (!string.IsNullOrEmpty(processPath))
            return Path.GetDirectoryName(processPath) ?? string.Empty;

        throw new InvalidOperationException("Could not determine the game directory. AppLocation is empty and the process path is unavailable.");
    }

    /// <summary>
    /// Copies every file under <c>Files</c> into the game directory, preserving the
    /// folder structure and overwriting any existing files.
    /// </summary>
    private void DeployFiles()
    {
        var sourceDir = Path.Combine(_modDirectory, FilesSubDirectory);
        if (!Directory.Exists(sourceDir))
        {
            _logger.WriteLine($"[P5S.ReShade] No '{FilesSubDirectory}' folder found in mod directory '{_modDirectory}'. Nothing to deploy.");
            return;
        }

        Directory.CreateDirectory(_gameDirectory);

        var deployed = 0;
        foreach (var file in Directory.EnumerateFiles(sourceDir, "*", SearchOption.AllDirectories))
        {
            var relativePath = Path.GetRelativePath(sourceDir, file);
            var destination = Path.Combine(_gameDirectory, relativePath);
            Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
            File.Copy(file, destination, overwrite: true);
            _logger.WriteLine($"[P5S.ReShade] Deployed '{relativePath}' to game directory.");
            deployed++;
        }

        _logger.WriteLine($"[P5S.ReShade] Successfully deployed {deployed} ReShade file(s) to '{_gameDirectory}'.");
    }

    public void Dispose() { }
}
