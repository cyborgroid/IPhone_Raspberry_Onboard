using System.Diagnostics;

namespace CyborgroidDashboard.Services;

/// <summary>Starts apps; under the mobile sway session they go on the apps workspace.</summary>
public static class AppLauncher
{
    private const string AppsWorkspace = "2";

    public static bool IsInstalled(string command)
    {
        var executable = command.Split(' ', 2)[0];
        var path = Environment.GetEnvironmentVariable("PATH") ?? "";
        return path.Split(':').Any(dir => File.Exists(Path.Combine(dir, executable)));
    }

    /// <summary>Commands are the fixed strings from the catalog, never user input.</summary>
    public static void Launch(string command)
    {
        if (Environment.GetEnvironmentVariable("SWAYSOCK") is not null)
        {
            Run("swaymsg", ["workspace", "number", AppsWorkspace]);
            Run("swaymsg", ["exec", "--", command]);
        }
        else
        {
            Run("/bin/sh", ["-c", command]);
        }
    }

    private static void Run(string file, IEnumerable<string> args)
    {
        var info = new ProcessStartInfo(file) { UseShellExecute = false };
        foreach (var arg in args)
        {
            info.ArgumentList.Add(arg);
        }
        Process.Start(info)?.Dispose();
    }
}
