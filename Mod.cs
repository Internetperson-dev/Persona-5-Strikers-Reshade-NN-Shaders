using System.Diagnostics;
using System.Text;
using Reloaded.Mod.Interfaces;

namespace P5S.ReShade;

/// <summary>
/// Copies the ReShade files bundled in the mod's <c>Files</c> folder into the game
/// directory when the mod is enabled, and removes them again once the game exits
/// (or the mod is disabled), so nothing is left behind in the game folder.
///
/// The two DLLs stay mapped into the running process, so Windows refuses to delete
/// them while the game is alive (including during <see cref="AppDomain.ProcessExit"/>).
/// A detached helper process is therefore spawned on load; it watches the game's PID
/// and deletes all deployed files as soon as the game has fully exited.
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
    private readonly List<string> _deployedFiles = new();
    private readonly List<string> _deployedDirectories = new();
    private bool _cleanupRequested;
    private bool _helperSpawned;

    public Mod(ModContext context)
    {
        _logger = context.Logger;
        _modDirectory = context.ModLoader.GetDirectoryForModId(context.ModConfig.ModId).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        _gameDirectory = GetGameDirectory(context.ModLoader);
        DeployFiles();
        SpawnCleanupHelper();

        // Fast path: remove what can be removed immediately on normal shutdown.
        // (Anything still locked - i.e. the DLLs - is handled by the helper process.)
        AppDomain.CurrentDomain.ProcessExit += (_, _) => CleanupFiles();
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
    /// folder structure and overwriting any existing files. Records everything it
    /// deploys so it can be removed again later.
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
            _deployedFiles.Add(destination);
            _logger.WriteLine($"[P5S.ReShade] Deployed '{relativePath}' to game directory.");
            deployed++;
        }

        // Track created sub-directories so they can be cleaned up too.
        foreach (var dir in Directory.EnumerateDirectories(sourceDir, "*", SearchOption.AllDirectories))
            _deployedDirectories.Add(Path.Combine(_gameDirectory, Path.GetRelativePath(sourceDir, dir)));

        // Sort deepest first so parent directories are emptied before removal.
        _deployedDirectories.Sort((a, b) => b.Length.CompareTo(a.Length));

        // ReShade-generated artifacts that should not outlive a session either.
        _deployedFiles.Add(Path.Combine(_gameDirectory, "ReShade.log"));
        _deployedDirectories.Add(Path.Combine(_gameDirectory, "ReShade_cache"));

        _logger.WriteLine($"[P5S.ReShade] Successfully deployed {deployed} ReShade file(s) to '{_gameDirectory}'.");
    }

    /// <summary>
    /// Spawns a hidden, detached helper process that waits for this game process to
    /// fully exit and then deletes every deployed file. This is what makes cleanup
    /// work for the DLLs, which remain locked until the process has terminated.
    /// </summary>
    private void SpawnCleanupHelper()
    {
        if (_deployedFiles.Count == 0)
            return;

        try
        {
            var gamePid = Environment.ProcessId;
            var scriptPath = Path.Combine(Path.GetTempPath(), $"P5S.ReShade.cleanup.{gamePid}.cmd");

            var script = new StringBuilder();
            script.AppendLine("@echo off");
            script.AppendLine("setlocal");
            script.AppendLine($"set \"target_pid={gamePid}\"");
            script.AppendLine(":wait");
            script.AppendLine("tasklist /FI \"PID eq %target_pid%\" | find /I \"%target_pid%\" >nul");
            script.AppendLine("if not errorlevel 1 ( ping -n 2 127.0.0.1 >nul & goto :wait )");
            script.AppendLine("set /a tries=0");
            script.AppendLine(":retry");
            foreach (var file in _deployedFiles)
                script.AppendLine($"if exist \"{file}\" ( del /f /q \"{file}\" >nul 2>&1 )");
            foreach (var dir in _deployedDirectories)
                script.AppendLine($"if exist \"{dir}\" ( rmdir /s /q \"{dir}\" >nul 2>&1 )");
            script.AppendLine("set /a tries+=1");
            script.AppendLine("if %tries% lss 10 ( ping -n 2 127.0.0.1 >nul & goto :retry )");
            script.AppendLine("del /f /q \"%~f0\" >nul 2>&1");
            script.AppendLine("endlocal");
            script.AppendLine("exit /b");

            File.WriteAllText(scriptPath, script.ToString());

            var startInfo = new ProcessStartInfo
            {
                FileName = "cmd.exe",
                Arguments = $"/c \"{scriptPath}\"",
                UseShellExecute = true,
                WindowStyle = ProcessWindowStyle.Hidden,
                CreateNoWindow = true
            };

            Process.Start(startInfo);
            _helperSpawned = true;
            _logger.WriteLine($"[P5S.ReShade] Spawned cleanup helper (PID {gamePid}); deployed files will be removed after the game exits.");
        }
        catch (Exception e)
        {
            _logger.WriteLine($"[P5S.ReShade] Failed to spawn cleanup helper: {e.Message}");
        }
    }

    /// <summary>
    /// Best-effort removal of the deployed files. Runs on process exit and on mod
    /// unload. Files still locked by the running game are skipped; the detached
    /// helper process removes them once the game has fully exited.
    /// </summary>
    private void CleanupFiles()
    {
        if (_cleanupRequested)
            return;
        _cleanupRequested = true;

        foreach (var file in _deployedFiles)
        {
            try { if (File.Exists(file)) File.Delete(file); }
            catch (Exception) { /* Locked, helper will handle. */ }
        }

        foreach (var dir in _deployedDirectories)
        {
            try { if (Directory.Exists(dir)) Directory.Delete(dir, recursive: true); }
            catch (Exception) { /* Locked, helper will handle. */ }
        }

        _logger.WriteLine($"[P5S.ReShade] Removed ReShade files from '{_gameDirectory}'.");
    }

    public void Dispose() => CleanupFiles();
}
