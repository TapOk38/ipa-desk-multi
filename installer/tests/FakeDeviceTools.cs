using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

// Test fixture: performs no USB, network, installation or account operations.
class FakeDeviceTools
{
    const string First = "1111111111111111111111111111111111111111";
    const string Second = "00008110-001A2B3C4D5E001E";
    static string Value(string[] args, string key)
    {
        int position = Array.IndexOf(args, key);
        return position >= 0 && position + 1 < args.Length ? args[position + 1] : "";
    }
    static bool Has(string[] args, string key) { return Array.IndexOf(args, key) >= 0; }
    static void Log(string tool, string[] args)
    {
        string path = Environment.GetEnvironmentVariable("IPA_INSTALL_TEST_LOG");
        if (!String.IsNullOrEmpty(path))
            File.AppendAllText(path, new JavaScriptSerializer().Serialize(new { tool = tool, arguments = args, cwd = Environment.CurrentDirectory }) + "\n", new UTF8Encoding(false));
    }
    static string InstalledApplications(bool empty)
    {
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><array>" +
            (empty ? "" : "<dict><key>CFBundleIdentifier</key><string>com.example.fixture</string><key>CFBundleDisplayName</key><string>Test App</string><key>CFBundleVersion</key><string>1</string></dict>") + "</array></plist>";
    }
    static int Main(string[] args)
    {
        Console.OutputEncoding = new UTF8Encoding(false);
        string tool = Path.GetFileNameWithoutExtension(Environment.GetCommandLineArgs()[0]).ToLowerInvariant();
        string scenario = Environment.GetEnvironmentVariable("IPA_INSTALL_TEST_SCENARIO") ?? "happy";
        Log(tool, args);
        if (Has(args, "--version") || Has(args, "-v")) { Console.WriteLine(tool + " TEST ONLY"); return 0; }
        if (tool == "idevice_id")
        {
            if (scenario == "enumeration-fail") { Console.Error.WriteLine("ERROR: usbmuxd is not running"); return 1; }
            if (scenario == "none" || scenario == "removed") return 0;
            Console.WriteLine(First);
            if (scenario == "multi" || scenario == "selected-second") Console.WriteLine(Second);
            return 0;
        }
        if (tool == "idevicepair")
        {
            if (scenario.StartsWith("pair-"))
            {
                string stateFile = Environment.GetEnvironmentVariable("IPA_INSTALL_TEST_LOG") + ".pair-state";
                if (Has(args, "validate"))
                {
                    if (File.Exists(stateFile) && File.ReadAllText(stateFile) == "paired")
                    { Console.WriteLine("SUCCESS: Validated pairing with device " + Value(args, "-u")); return 0; }
                    if (scenario == "pair-validate-denied")
                    { Console.Error.WriteLine("ERROR: Device " + Value(args, "-u") + " said that the user denied the trust dialog."); return 1; }
                    if (scenario == "pair-direct-pending")
                    { Console.Error.WriteLine("ERROR: Please accept the trust dialog on the screen of device " + Value(args, "-u") + ", then attempt to pair again."); return 1; }
                    Console.Error.WriteLine("ERROR: Device " + Value(args, "-u") + " is not paired with this host");
                    return 1;
                }
                if (Has(args, "pair"))
                {
                    if (scenario == "pair-denied")
                    { Console.Error.WriteLine("ERROR: Device " + Value(args, "-u") + " said that the user denied the trust dialog."); return 1; }
                    if (scenario == "pair-no-success")
                    { Console.WriteLine("Pairing command finished without confirmation"); return 0; }
                    if (scenario == "pair-forever" || scenario == "pair-cancel" || (scenario == "pair-pending" && !File.Exists(stateFile)))
                    {
                        File.WriteAllText(stateFile, "pending");
                        Console.Error.WriteLine("ERROR: Please accept the trust dialog on the screen of device " + Value(args, "-u") + ", then attempt to pair again.");
                        return 1;
                    }
                    File.WriteAllText(stateFile, "paired");
                    Console.WriteLine("SUCCESS: Paired with device " + Value(args, "-u"));
                    return 0;
                }
            }
            if (scenario == "untrusted" || scenario == "locked")
            {
                Console.Error.WriteLine(scenario == "locked" ? "ERROR: Could not validate with device " + Value(args, "-u") + " because a passcode is set. Please enter the passcode on the device and retry." : "ERROR: Could not validate pairing with device (SSL error).");
                return 1;
            }
            Console.WriteLine("SUCCESS: Validated pairing with device " + Value(args, "-u"));
            return 0;
        }
        if (tool == "ideviceinfo")
        {
            if (scenario == "untrusted" || scenario == "locked")
            {
                Console.Error.WriteLine("ERROR: Could not connect to lockdownd, error code -21");
                return 1;
            }
            string key = Value(args, "-k");
            if (key == "DeviceName") Console.WriteLine(Value(args, "-u") == Second ? "Second iPhone" : "Test iPhone");
            else if (key == "ProductVersion")
            {
                if (scenario == "ios-unknown") return 0;
                if (scenario == "ios-invalid") Console.WriteLine("unknown 18 beta");
                else if (scenario == "ios-low") Console.WriteLine("16.9");
                else if (scenario == "ios-ten") Console.WriteLine("16.10");
                else if (scenario == "ios-micro-low") Console.WriteLine("16.10.1");
                else Console.WriteLine("18.5");
            }
            else if (key == "ProductType") Console.WriteLine(scenario == "model-unknown" ? "iPhone99,9" : (Value(args, "-u") == Second ? "iPhone14,5" : "iPhone16,2"));
            else Console.WriteLine("DeviceName: Test iPhone\nProductVersion: 18.5\nProductType: iPhone16,2");
            return 0;
        }
        if (tool == "ideviceinstaller")
        {
            if (Has(args, "-l")) { Console.WriteLine(InstalledApplications(scenario == "missing-installed")); return 0; }
            if (Has(args, "-i"))
            {
                string input = Value(args, "-i");
                if (!File.Exists(input)) { Console.Error.WriteLine("ERROR: Input file argument did not survive quoting"); return 1; }
                string expected = Environment.GetEnvironmentVariable("IPA_INSTALL_TEST_EXPECTED_SHA256");
                using (var file = File.OpenRead(input))
                using (var hash = System.Security.Cryptography.SHA256.Create())
                {
                    string actual = BitConverter.ToString(hash.ComputeHash(file)).Replace("-", "");
                    if (!String.IsNullOrEmpty(expected) && !String.Equals(actual, expected, StringComparison.OrdinalIgnoreCase))
                    { Console.Error.WriteLine("ERROR: Installation input content changed"); return 1; }
                }
                if (scenario == "slow") { Console.WriteLine("Install: Installing (5%)"); Console.Out.Flush(); Thread.Sleep(30000); }
                if (scenario == "exit0-error") { Console.Error.WriteLine("ERROR: Install failed. Got error \"ApplicationVerificationFailed\" with code 0xe8008015"); return 0; }
                if (scenario == "no-complete") { Console.WriteLine("Install: Installing (90%)"); return 0; }
                Console.WriteLine("Copying 'fixture.ipa' to device... DONE.");
                Console.WriteLine("Install: CreatingStagingDirectory (5%)");
                Console.WriteLine("Install: Installing (90%)");
                Console.WriteLine("Install: Complete");
                return scenario == "nonzero-complete" ? 1 : 0;
            }
        }
        if (tool == "plistutil")
        {
            string input = Value(args, "-i"), output = Value(args, "-o");
            if (!String.IsNullOrEmpty(input) && !String.IsNullOrEmpty(output)) { File.Copy(input, output, true); return 0; }
        }
        Console.Error.WriteLine("ERROR: Unexpected fake tool invocation");
        return 9;
    }
}
