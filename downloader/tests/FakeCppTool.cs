using System;
using System.IO;
using System.Linq;
using System.Threading;
using System.Web.Script.Serialization;
using System.IO.Compression;
public class FakeCppTool {
    static string V(string[] args,string key) { int i=Array.IndexOf(args,key); return i>=0 && i+1<args.Length ? args[i+1] : ""; }
    static void J(object value) { Console.WriteLine(new JavaScriptSerializer().Serialize(value)); }
    static int Main(string[] args) {
        Console.OutputEncoding = System.Text.Encoding.UTF8;
        if (args.Length==1 && args[0]=="--version") { Console.WriteLine("ipatool test"); return 0; }
        bool go = args.Contains("--non-interactive");
        string scenario=Environment.GetEnvironmentVariable("IPA_DESK_TEST_SCENARIO") ?? "happy";
        string state=Environment.GetEnvironmentVariable("XDG_STATE_HOME");
        string profile=Environment.GetEnvironmentVariable("USERPROFILE");
        if (Environment.GetEnvironmentVariable("IPATOOL_AUTH_MODE")!="cpp" || Environment.GetEnvironmentVariable("NO_PROXY")!="*" || V(args,"--keychain-passphrase").Length!=44) throw new Exception("child configuration incorrect");
        string cpp=Path.Combine(profile,".ipatool"), account=Path.Combine(cpp,"account"), imported=Path.Combine(state,"imported");
        if (args.Contains("login")) {
            if(go) throw new Exception("Go login called");
            Directory.CreateDirectory(cpp);
            if (scenario=="slow") { Thread.Sleep(30000); return 1; }
            if (V(args,"--password")!="pw test&\"\\") { J(new{success=false,error="wrong test password"}); return 1; }
            string email=V(args,"--email");
            if (File.Exists(account)) throw new Exception("reused a saved account");
            if (scenario=="login-fail") { Console.Error.WriteLine("Login error: rejected pw test&\"\\"); return 1; }
            if (scenario=="twofa-network") { Console.Error.WriteLine("Login error: verification request failed: timeout"); return 1; }
            if (scenario!="no-twofa" && V(args,"--auth-code")=="") { Console.Error.WriteLine("Error: two-factor auth code required. Retry with --auth-code CODE"); return 1; }
            if (scenario=="wrong-account") email="other@example.invalid";
            if (scenario!="save-fail") File.WriteAllText(account,email);
            string audit=Environment.GetEnvironmentVariable("IPA_DESK_TEST_AUDIT");
            if (!String.IsNullOrEmpty(audit)) File.AppendAllText(audit,new JavaScriptSerializer().Serialize(new{profile=profile,state=state})+Environment.NewLine);
            J(new{success=true,email=email}); return 0;
        }
        if(args.Contains("import-cpp")) {
            if(!go || !File.Exists(account) || File.ReadAllText(account)!=V(args,"--email")) { J(new{success=false,error="invalid fresh session"}); return 1; }
            Directory.CreateDirectory(state); File.WriteAllText(imported,"imported");
            J(new{success=true,email=V(args,"--email")}); return 0;
        }
        if(args.Contains("list-purchases")) {
            if(!go || !File.Exists(imported)) throw new Exception("purchase list routing incorrect");
            if(scenario=="owned-offline") { J(new{success=false,error="list unavailable"}); return 1; }
            if(scenario=="owned-empty") { J(new{count=0,totalCount=0,apps=new object[0]}); return 0; }
            if(scenario=="owned-pages" && V(args,"--page")=="1") { J(new{totalCount=101,apps=Enumerable.Range(1,100).Select(i=>new{name="App "+i,bundleID="com.test.app"+i,id=i}).ToArray()}); return 0; }
            J(new{count=1,totalCount=scenario=="owned-pages"?101:1,apps=new[]{new{name="Test App",bundleID="com.test.app",id=101}}}); return 0;
        }
        if(args.Contains("download")) {
            if(go || !File.Exists(account) || !args.Contains("--purchase") || V(args,"--app-id")!="101" || V(args,"--bundle-identifier")!="") throw new Exception("download routing incorrect");
            if(scenario=="license") { Console.Error.WriteLine("Error: you must purchase this app first."); return 1; }
            if(scenario=="expired") { Console.Error.WriteLine("Error: session expired. Please log in again."); return 1; }
            string path=V(args,"--output");
            // Reproduce the reported native narrow-path failure, without Apple requests.
            if (path.Any(c => c > 127)) {
                Console.Error.WriteLine("Download error: filesystem error: Cannot convert character sequence: Illegal byte sequence"); return 1;
            }
            string audit = Environment.GetEnvironmentVariable("IPA_DESK_TEST_DOWNLOAD_AUDIT");
            if (!String.IsNullOrEmpty(audit)) File.AppendAllText(audit,new JavaScriptSerializer().Serialize(new{cwd=Environment.CurrentDirectory,output=path})+Environment.NewLine);
            if (scenario!="missing-file") File.WriteAllText(path+".tmp", "test raw download");
            if (scenario=="download-slow") { Thread.Sleep(30000); return 1; }
            if(scenario!="missing-file") { using(var zip=ZipFile.Open(path,ZipArchiveMode.Create)) { var e=zip.CreateEntry(scenario=="bad-zip"?"wrong.txt":"Payload/Test.app/Info.plist"); using(var w=new StreamWriter(e.Open())) w.Write("test.correct"); } }
            if(scenario=="download-fail") { Console.Error.WriteLine("PROGRESS:33\nDownload error: network interrupted"); return 1; }
            J(new{success=true,output=path}); return 0;
        }
        throw new Exception("unexpected command");
    }
}
