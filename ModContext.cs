using Reloaded.Mod.Interfaces;
using Reloaded.Mod.Interfaces.Internal;

namespace P5S.ReShade;

public class ModContext
{
    /// <summary>
    /// Used for writing text to the Reloaded log.
    /// </summary>
    public ILogger Logger { get; init; } = null!;

    /// <summary>
    /// Provides access to the mod loader API.
    /// </summary>
    public IModLoader ModLoader { get; init; } = null!;

    /// <summary>
    /// Configuration of the current mod.
    /// </summary>
    public IModConfig ModConfig { get; init; } = null!;
}
