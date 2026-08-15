using Reloaded.Mod.Interfaces;
using Reloaded.Mod.Interfaces.Internal;

namespace P5S.ReShade;

public class Startup : IMod
{
    private ILogger _logger = null!;
    private IModLoader _modLoader = null!;
    private IModConfig _modConfig = null!;
    private Mod _mod = null!;

    /// <summary>
    /// Entry point for the mod.
    /// </summary>
    public void StartEx(IModLoaderV1 loaderApi, IModConfigV1 modConfig)
    {
        _modLoader = (IModLoader)loaderApi;
        _modConfig = (IModConfig)modConfig;
        _logger = (ILogger)_modLoader.GetLogger();

        _mod = new Mod(new ModContext
        {
            Logger = _logger,
            ModLoader = _modLoader,
            ModConfig = _modConfig
        });
    }

    public void Suspend() { }

    public void Resume() { }

    public void Unload() => _mod.Dispose();

    public bool CanUnload() => true;

    public bool CanSuspend() => false;

    public Action Disposing => () => _mod.Dispose();
}
