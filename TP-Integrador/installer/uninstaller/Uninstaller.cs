using System;
using System.Diagnostics;
using System.IO;
using Microsoft.Win32;
using System.Windows.Forms;

internal static class Uninstaller
{
    private static readonly string[] AppKeys = new string[]
    {
        @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{A4F5D4B5-9D8F-4F38-8D4B-0F5B7A43F0D8}_is1",
        @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{9D7C3C18-36F3-4C89-8E99-5AAB2A1BD8B1}_is1"
    };

    private static bool Ask(string text)
    {
        return MessageBox.Show(
            text,
            "Desinstalar Tower Defense Cooperative",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Question) == DialogResult.Yes;
    }

    private static bool Run(string file, string arguments, bool waitForExit = true)
    {
        try
        {
            using (var process = Process.Start(new ProcessStartInfo
            {
                FileName = file,
                Arguments = arguments,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            }))
            {
                if (process != null && waitForExit)
                    process.WaitForExit();
            }
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static string FindUninstaller(string name, out bool isQuiet)
    {
        isQuiet = false;
        RegistryHive[] hives = { RegistryHive.LocalMachine, RegistryHive.CurrentUser };
        RegistryView[] views = { RegistryView.Registry64, RegistryView.Registry32 };
        foreach (RegistryHive hive in hives)
        {
            foreach (RegistryView view in views)
            {
                try
                {
                    using (RegistryKey root = RegistryKey.OpenBaseKey(hive, view))
                    using (RegistryKey uninstall = root.OpenSubKey(
                        @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"))
                    {
                        if (uninstall == null)
                            continue;
                        foreach (string subkeyName in uninstall.GetSubKeyNames())
                        {
                            using (RegistryKey item = uninstall.OpenSubKey(subkeyName))
                            {
                                string displayName = item == null ? null :
                                    item.GetValue("DisplayName") as string;
                                if (displayName != null &&
                                    displayName.IndexOf(name, StringComparison.OrdinalIgnoreCase) >= 0)
                                {
                                    string quiet = item.GetValue("QuietUninstallString") as string;
                                    if (!String.IsNullOrWhiteSpace(quiet))
                                    {
                                        isQuiet = true;
                                        return quiet;
                                    }
                                    string normal = item.GetValue("UninstallString") as string;
                                    if (!String.IsNullOrWhiteSpace(normal))
                                    {
                                        return normal;
                                    }
                                }
                            }
                        }
                    }
                }
                catch
                {
                }
            }
        }
        return null;
    }

    private static void RemoveDependency(string displayName, string packageId, string extraSilentArgs)
    {
        bool isQuiet;
        string uninstaller = FindUninstaller(displayName, out isQuiet);
        if (!String.IsNullOrWhiteSpace(uninstaller))
        {
            string cmd = uninstaller;
            if (!isQuiet && !String.IsNullOrWhiteSpace(extraSilentArgs) &&
                cmd.IndexOf(extraSilentArgs, StringComparison.OrdinalIgnoreCase) < 0)
            {
                cmd = cmd + " " + extraSilentArgs;
            }
            Run("cmd.exe", "/C " + cmd);
            return;
        }

        string winget = Environment.ExpandEnvironmentVariables(
            "%LOCALAPPDATA%\\Microsoft\\WindowsApps\\winget.exe");
        if (!File.Exists(winget))
            winget = "winget.exe";

        Run(winget, "uninstall --id " + packageId +
            " --exact --silent --accept-source-agreements");
    }

    private static void DeleteDirectorySafe(string path)
    {
        if (String.IsNullOrWhiteSpace(path) || !Directory.Exists(path))
            return;
        try
        {
            Directory.Delete(path, true);
        }
        catch
        {
        }
    }

    private static void DeleteFileSafe(string path)
    {
        if (String.IsNullOrWhiteSpace(path) || !File.Exists(path))
            return;
        try
        {
            File.Delete(path);
        }
        catch
        {
        }
    }

    public static void Main()
    {
        if (!Ask("¿Estás seguro de que querés desinstalar Tower Defense Cooperative y eliminar todos sus datos?"))
            return;

        bool removeDocker = Ask("¿También querés desinstalar Docker Desktop?");
        bool removeRadmin = Ask("¿También querés desinstalar Radmin VPN?");

        // 1. Stop game processes
        string[] gameProcs = { "CoTowerDefense", "TowerDefense", "Godot_v4.3-stable_win64", "Godot_v4.3-stable_win64_console" };
        foreach (string procName in gameProcs)
        {
            try
            {
                foreach (Process p in Process.GetProcessesByName(procName))
                {
                    try { p.Kill(); } catch { }
                }
            }
            catch { }
        }

        // 2. Remove firewall rules
        Run("netsh.exe", "advfirewall firewall delete rule name=\"Tower Defense Local\"");
        Run("netsh.exe", "advfirewall firewall delete rule name=\"Tower Defense Tailscale\"");

        // 3. Remove all game user data
        string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
        string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string commonAppData = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
        string tempPath = Path.GetTempPath();

        string[] dataDirs = new string[]
        {
            Path.Combine(appData, @"Godot\app_userdata\Tower Defense Cooperative"),
            Path.Combine(appData, @"Godot\app_userdata\Co-Tower Defense"),
            Path.Combine(appData, @"Godot\app_userdata\CoTowerDefense"),
            Path.Combine(localAppData, @"Godot\app_userdata\Tower Defense Cooperative"),
            Path.Combine(localAppData, @"Godot\app_userdata\Co-Tower Defense"),
            Path.Combine(commonAppData, "TowerDefense"),
            Path.Combine(tempPath, "tower-defense-installer")
        };
        foreach (string dir in dataDirs)
            DeleteDirectorySafe(dir);

        // 4. Remove shortcuts
        string[] desktops = new string[]
        {
            Environment.GetFolderPath(Environment.SpecialFolder.CommonDesktopDirectory),
            Environment.GetFolderPath(Environment.SpecialFolder.DesktopDirectory)
        };
        foreach (string desk in desktops)
        {
            if (!String.IsNullOrWhiteSpace(desk))
            {
                DeleteFileSafe(Path.Combine(desk, "Co-Tower Defense.lnk"));
                DeleteFileSafe(Path.Combine(desk, "Tower Defense Cooperative.lnk"));
            }
        }

        // 5. Uninstall optional dependencies if the user chose to
        if (removeDocker)
        {
            RemoveDependency("Docker Desktop", "Docker.DockerDesktop", "uninstall --quiet");
        }

        if (removeRadmin)
        {
            RemoveDependency("Radmin VPN", "Famatech.RadminVPN", "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART");
            string commonDesk = Environment.GetFolderPath(Environment.SpecialFolder.CommonDesktopDirectory);
            if (!String.IsNullOrWhiteSpace(commonDesk))
                DeleteFileSafe(Path.Combine(commonDesk, "Radmin VPN.lnk"));
        }

        // 6. Find the registered installation in the Windows Registry
        string uninstallString = null;
        string installLocation = null;
        RegistryView[] views = { RegistryView.Registry64, RegistryView.Registry32 };
        foreach (string appKey in AppKeys)
        {
            foreach (RegistryView view in views)
            {
                try
                {
                    using (RegistryKey root = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view))
                    using (RegistryKey key = root.OpenSubKey(appKey))
                    {
                        if (key != null)
                        {
                            if (String.IsNullOrWhiteSpace(uninstallString))
                                uninstallString = key.GetValue("UninstallString") as string;
                            if (String.IsNullOrWhiteSpace(installLocation))
                                installLocation = key.GetValue("InstallLocation") as string;
                        }
                    }
                }
                catch { }
            }
        }

        if (!String.IsNullOrWhiteSpace(uninstallString))
        {
            Run("cmd.exe", "/C " + uninstallString + " /VERYSILENT /SUPPRESSMSGBOXES /NORESTART");
        }

        // 7. Remove the game folders entirely (in background after this process exits)
        string programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        string dir1 = Path.Combine(programFiles, "CoTowerDefense");
        string dir2 = Path.Combine(programFiles, "TowerDefenseCooperative");

        DeleteDirectorySafe(installLocation);
        DeleteDirectorySafe(dir1);
        DeleteDirectorySafe(dir2);

        string cleanupCmd = "/C timeout /t 2 /nobreak >nul";
        if (!String.IsNullOrWhiteSpace(installLocation))
            cleanupCmd += " & rmdir /s /q \"" + installLocation.TrimEnd('\\') + "\" 2>nul";
        cleanupCmd += " & rmdir /s /q \"" + dir1 + "\" 2>nul & rmdir /s /q \"" + dir2 + "\" 2>nul";
        Run("cmd.exe", cleanupCmd, false);

        MessageBox.Show(
            "Tower Defense Cooperative y todos sus datos fueron eliminados correctamente.",
            "Desinstalar Tower Defense Cooperative",
            MessageBoxButtons.OK,
            MessageBoxIcon.Information);
    }
}
