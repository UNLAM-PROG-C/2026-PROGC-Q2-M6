using System;
using System.Diagnostics;
using Microsoft.Win32;
using System.Windows.Forms;

internal static class Uninstaller
{
    private const string AppKey =
        @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{9D7C3C18-36F3-4C89-8E99-5AAB2A1BD8B1}_is1";

    private static bool Ask(string text)
    {
        return MessageBox.Show(
            text,
            "Tower Defense Cooperative",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Question) == DialogResult.Yes;
    }

    private static bool Run(string file, string arguments)
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
                if (process != null)
                    process.WaitForExit();
            }
            return true;
        }
        catch (System.ComponentModel.Win32Exception)
        {
            MessageBox.Show(
                "No se pudo ejecutar " + file + ". La desinstalación del juego continuará.",
                "Tower Defense Cooperative",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
            return false;
        }
        catch (InvalidOperationException)
        {
            MessageBox.Show(
                "No se pudo iniciar la desinstalación opcional. La desinstalación del juego continuará.",
                "Tower Defense Cooperative",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
            return false;
        }
    }

    private static string FindUninstaller(string name)
    {
        RegistryView[] views = { RegistryView.Registry64, RegistryView.Registry32 };
        foreach (RegistryView view in views)
        {
            using (RegistryKey root = RegistryKey.OpenBaseKey(
                RegistryHive.LocalMachine, view))
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
                            return item.GetValue("QuietUninstallString") as string ??
                                item.GetValue("UninstallString") as string;
                        }
                    }
                }
            }
        }
        return null;
    }

    private static void RemoveDependency(string displayName, string packageId)
    {
        string uninstaller = FindUninstaller(displayName);
        if (!String.IsNullOrWhiteSpace(uninstaller))
        {
            Run("cmd.exe", "/C " + uninstaller);
            return;
        }

        string winget = Environment.ExpandEnvironmentVariables(
            "%WINDIR%\\System32\\winget.exe");
        Run(winget, "uninstall --id " + packageId +
            " --silent --accept-source-agreements --accept-package-agreements");
    }

    public static void Main()
    {
        bool removeDocker = Ask("¿También querés desinstalar Docker Desktop?");
        bool removeRadmin = Ask("¿También querés desinstalar Radmin VPN?");

        Run("powershell.exe",
            "-NoProfile -ExecutionPolicy Bypass -Command " +
            "\"Remove-NetFirewallRule -DisplayName 'Tower Defense Local' -ErrorAction SilentlyContinue; " +
            "Remove-NetFirewallRule -DisplayName 'Tower Defense Tailscale' -ErrorAction SilentlyContinue\"");

        if (removeDocker)
            RemoveDependency("Docker Desktop", "Docker.DockerDesktop");

        if (removeRadmin)
            RemoveDependency("Radmin VPN", "Famatech.RadminVPN");

        string uninstallString = null;
        RegistryView[] views = { RegistryView.Registry64, RegistryView.Registry32 };
        foreach (RegistryView view in views)
        {
            using (RegistryKey root = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, view))
            using (RegistryKey key = root.OpenSubKey(AppKey))
            {
                if (key != null)
                {
                    uninstallString = key.GetValue("UninstallString") as string;
                    if (!String.IsNullOrWhiteSpace(uninstallString))
                        break;
                }
            }
        }

        if (!String.IsNullOrWhiteSpace(uninstallString))
        {
            Run("cmd.exe", "/C " + uninstallString +
                " /VERYSILENT /SUPPRESSMSGBOXES /NORESTART");
            return;
        }

        MessageBox.Show(
            "No se encontró la instalación registrada del juego.",
            "Tower Defense Cooperative",
            MessageBoxButtons.OK,
            MessageBoxIcon.Information);
    }
}
