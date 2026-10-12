using System;
using System.Collections;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("IPA Desk Multi")]
[assembly: AssemblyDescription("Download App Store applications as IPA files")]
[assembly: AssemblyProduct("IPA Desk Multi")]
[assembly: AssemblyVersion("0.4.0.0")]
[assembly: AssemblyFileVersion("0.4.0.0")]
[assembly: AssemblyInformationalVersion("0.4.0-beta.1")]

internal static class Launcher
{
    private static bool russian = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "ru";
    private static string T(string ru, string en) { return russian ? ru : en; }
    private static void LoadLanguage(string root)
    {
        try
        {
            string saved = File.ReadAllText(Path.Combine(root, "language.txt")).Trim();
            if (saved == "ru" || saved == "en") russian = saved == "ru";
        }
        catch { }
    }
    [DllImport("shell32.dll")]
    private static extern int SHGetKnownFolderPath(ref Guid folder, uint flags, IntPtr token, out IntPtr path);

    [STAThread]
    private static int Main(string[] args)
    {
        string testRoot = null;
        string dataRoot = null;
        try
        {
            if (args.Length != 0)
            {
                if (args.Length != 2 || args[0] != "--smoke-test")
                    throw new ArgumentException(T("Неизвестные параметры запуска.", "Unknown startup arguments."));
                testRoot = Path.GetFullPath(args[1]);
            }
            dataRoot = testRoot ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "IPA-Desk-Multi");
            LoadLanguage(testRoot == null ? dataRoot : Path.Combine(testRoot, "accounts"));
            Directory.CreateDirectory(dataRoot);
            string runtimeRoot = Path.Combine(dataRoot, "app", PayloadInfo.Sha256.Substring(0, 32));
            ExtractPayload(runtimeRoot);
            string outputRoot = testRoot == null ? Path.Combine(GetDownloads(), "IPA Desk Multi") : Path.Combine(testRoot, "Downloads");
            string powershell = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), @"System32\WindowsPowerShell\v1.0\powershell.exe");
            if (!File.Exists(powershell)) throw new FileNotFoundException(T("В Windows не найден Windows PowerShell.", "Windows PowerShell was not found."));
            NormalizePathEnvironment();
            var start = new ProcessStartInfo(powershell);
            start.Arguments = "-NoLogo -NoProfile -NonInteractive -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File " + Quote(Path.Combine(runtimeRoot, "IPA-Desk.ps1")) + " -OutputRoot " + Quote(outputRoot);
            string screenshot = null;
            if (testRoot != null)
            {
                screenshot = Path.Combine(testRoot, "interface.png");
                if (File.Exists(screenshot)) File.Delete(screenshot);
                start.Arguments += " -SmokeTestPath " + Quote(screenshot) + " -TestDataRoot " + Quote(Path.Combine(testRoot, "accounts"));
            }
            start.WorkingDirectory = runtimeRoot;
            start.UseShellExecute = false;
            start.CreateNoWindow = true;
            start.WindowStyle = ProcessWindowStyle.Hidden;
            start.RedirectStandardError = true;
            start.RedirectStandardOutput = true;
            start.EnvironmentVariables["GODEBUG"] = "http2client=0";
            foreach (string key in new[] { "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY" }) start.EnvironmentVariables.Remove(key);
            start.EnvironmentVariables["NO_PROXY"] = "*";
            using (var process = Process.Start(start))
            {
                // Drain both streams concurrently so a child cannot block on a full pipe.
                var errors = process.StandardError.ReadToEndAsync();
                var output = process.StandardOutput.ReadToEndAsync();
                if (testRoot != null && !process.WaitForExit(60000))
                {
                    process.Kill();
                    process.WaitForExit();
                    throw new TimeoutException(T("Проверка запуска превысила 60 секунд.", "Startup verification exceeded 60 seconds."));
                }
                process.WaitForExit();
                string error = errors.GetAwaiter().GetResult();
                output.GetAwaiter().GetResult();
                if (process.ExitCode != 0) throw new InvalidOperationException(T("Ошибка запуска программы.\r\n", "Application startup failed.\r\n") + error);
            }
            if (testRoot != null)
            {
                if (!File.Exists(screenshot)) throw new InvalidOperationException(T("Окно приложения не прошло проверку запуска.", "The application window failed startup verification."));
                File.WriteAllText(Path.Combine(testRoot, "smoke-result.txt"), "OK\r\nRuntime: " + runtimeRoot + "\r\nOutput: " + outputRoot, Encoding.UTF8);
            }
            return 0;
        }
        catch (Exception error)
        {
            string log = null;
            try
            {
                if (dataRoot != null)
                {
                    Directory.CreateDirectory(dataRoot);
                    log = Path.Combine(dataRoot, "Launcher-error.log");
                    File.WriteAllText(log, error.ToString(), Encoding.UTF8);
                }
            }
            catch { log = null; }
            if (testRoot == null)
                MessageBox.Show(T("Не удалось запустить IPA Desk Multi.\r\n", "Could not start IPA Desk Multi.\r\n") + error.Message + (log == null ? "" : T("\r\n\r\nЖурнал: ", "\r\n\r\nLog: ") + log), "IPA Desk Multi", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    private static string GetDownloads()
    {
        Guid downloads = new Guid("374DE290-123F-4565-9164-39C4925E467B");
        IntPtr path;
        int result = SHGetKnownFolderPath(ref downloads, 0, IntPtr.Zero, out path);
        if (result != 0) Marshal.ThrowExceptionForHR(result);
        try { return Marshal.PtrToStringUni(path); }
        finally { Marshal.FreeCoTaskMem(path); }
    }

    private static void NormalizePathEnvironment()
    {
        var values = Environment.GetEnvironmentVariables();
        string value = null;
        foreach (DictionaryEntry entry in values)
            if (string.Equals((string)entry.Key, "PATH", StringComparison.OrdinalIgnoreCase))
            {
                if (value == null) value = (string)entry.Value;
                Environment.SetEnvironmentVariable((string)entry.Key, null);
            }
        if (value != null) Environment.SetEnvironmentVariable("Path", value);
    }

    private static string Quote(string value)
    {
        // Windows argv quoting, including quotes and trailing backslashes.
        var result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in value)
        {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') result.Append('\\', slashes * 2 + 1);
            else result.Append('\\', slashes);
            result.Append(c);
            slashes = 0;
        }
        result.Append('\\', slashes * 2).Append('"');
        return result.ToString();
    }

    private static string Hash(Stream stream)
    {
        using (var sha = SHA256.Create())
            return BitConverter.ToString(sha.ComputeHash(stream)).Replace("-", "").ToLowerInvariant();
    }

    private static void ExtractPayload(string root)
    {
        Directory.CreateDirectory(root);
        string prefix = Path.GetFullPath(root) + Path.DirectorySeparatorChar;
        FileStream gate = null;
        for (int attempt = 0; gate == null; attempt++)
        {
            try { gate = new FileStream(Path.Combine(root, ".extract.lock"), FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
            catch (IOException) { if (attempt >= 100) throw; Thread.Sleep(100); }
        }
        using (gate)
        using (var payload = Assembly.GetExecutingAssembly().GetManifestResourceStream("IPA.Payload.zip"))
        {
            if (payload == null || Hash(payload) != PayloadInfo.Sha256) throw new InvalidDataException(T("Повреждён файл программы. Скачайте EXE повторно.", "The application file is damaged. Download the EXE again."));
            payload.Position = 0;
            using (var zip = new ZipArchive(payload, ZipArchiveMode.Read))
            {
                foreach (var entry in zip.Entries)
                {
                    string destination = Path.GetFullPath(Path.Combine(root, entry.FullName));
                    if (!destination.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) || entry.FullName.EndsWith("/"))
                        throw new InvalidDataException(T("Недопустимый путь внутри пакета.", "Invalid path inside the application package."));
                    string expected;
                    using (var source = entry.Open()) expected = Hash(source);
                    if (File.Exists(destination))
                        using (var existing = File.OpenRead(destination))
                            if (Hash(existing) == expected) continue;
                    Directory.CreateDirectory(Path.GetDirectoryName(destination));
                    string temporary = Path.Combine(Path.GetDirectoryName(destination), ".tmp-" + Guid.NewGuid().ToString("N").Substring(0, 12));
                    try
                    {
                        using (var source = entry.Open())
                        using (var target = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None)) source.CopyTo(target);
                        if (File.Exists(destination)) File.Replace(temporary, destination, null);
                        else File.Move(temporary, destination);
                    }
                    finally { if (File.Exists(temporary)) File.Delete(temporary); }
                }
            }
        }
    }
}
