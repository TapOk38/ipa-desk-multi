using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Text;
using System.Threading;
using TapOk.Downloader;

static class NativeTests {
    static int checks;static string root;
    static void Check(bool ok,string text){if(!ok)throw new Exception("FAIL: "+text);checks++;Console.WriteLine("PASS: "+text);}
    static void Throws(Action action,string text){bool failed=false;try{action();}catch{failed=true;}Check(failed,text);}
    sealed class FakeTool:ITool {
        public readonly List<string[]> Calls=new List<string[]>();public readonly Queue<ToolResult> Results=new Queue<ToolResult>();public Action<string[],string> Before;
        public ToolResult Run(string[] args,int seconds,CancellationToken token,string work){token.ThrowIfCancellationRequested();Calls.Add(args);if(Before!=null)Before(args,work);if(Results.Count==0)throw new Exception("No fixture response; network is forbidden in tests.");return Results.Dequeue();}
        public void Add(string text,int exit=0){Results.Enqueue(new ToolResult{ExitCode=exit,Text=text});}
    }
    static Account Account(){return new Account{Id=new string('a',32),Email="fixture@example.invalid",Password=Data.Protect("fixture-secret-1"),Description="Тест"};}
    static Engine MakeEngine(FakeTool tool,Func<string,string> code=null,CancellationToken token=default(CancellationToken)){return new Engine(tool,"fixture-session-key",s=>{},code??(s=>"123456"),token);}
    static void Ipa(string path){using(var zip=ZipFile.Open(path,ZipArchiveMode.Create))using(var s=new StreamWriter(zip.CreateEntry("Payload/Test.app/Info.plist").Open(),new UTF8Encoding(false)))s.Write("<?xml version=\"1.0\"?><plist><dict><key>CFBundleName</key><string>Home Keys</string><key>CFBundleShortVersionString</key><string>1.2.1</string><key>MinimumOSVersion</key><string>15.0</string></dict></plist>");}
    [STAThread]static int Main(string[] args){try{root=Path.GetFullPath(args[0]);Directory.CreateDirectory(root);Run();Console.WriteLine("Native checks passed: "+checks);return 0;}catch(Exception e){Console.Error.WriteLine(e);return 1;}}
    static void Run(){
        Check(Data.Id("https://apps.apple.com/ru/app/example/id123456789?x=1")=="123456789","Apple URL parsing");
        foreach(var value in new[]{"0","-1","1; calc","https://apps.apple.com.evil.test/id1","https://example.com/id1","http://apps.apple.com/id1"})Throws(()=>Data.Id(value),"Reject invalid ID or URL: "+value);
        var fixture=Data.ReadAccounts(Path.Combine(root,"legacy-accounts.json"));Check(fixture.Count==1&&Data.Unprotect(fixture[0].Password)=="fixture-only","Existing PowerShell DPAPI accounts are readable without migration");
        var a=Account();string accounts=Path.Combine(root,"native-accounts.json");Data.SaveAccounts(accounts,new List<Account>{a});Check(Data.Unprotect(Data.ReadAccounts(accounts)[0].Password)=="fixture-secret-1","Native account round trip");string saved=Data.Hash(accounts);
        Throws(()=>Data.SaveAccounts(accounts,new List<Account>{a,a}),"Reject duplicate accounts");Check(Data.Hash(accounts)==saved,"Invalid save preserves account store");
        Check(!File.ReadAllText(accounts).Contains("fixture-secret-1"),"Password is not stored as plaintext");
        string apps=Path.Combine(root,"apps.json");File.WriteAllText(apps,"{\"Version\":1,\"Apps\":[\"101\",\"202\"]}");var entries=Data.ReadApps(apps);Check(entries.Count==2&&entries.All(x=>x.Selected),"Legacy app list migration");entries[0].Selected=false;Data.SaveApps(apps,entries);Check(!Data.ReadApps(apps)[0].Selected,"Selection survives save");
        var merged=Data.Merge(entries,new[]{new AppEntry{Id="101",Name="Previously obtained"},new AppEntry{Id="303",Name="Removed app"}});Check(merged.Count==3&&merged[0].Selected&&merged[0].Name=="Previously obtained"&&!entries[0].Selected,"Purchase selection merges without mutating existing list");
        saved=Data.Hash(apps);Throws(()=>Data.SaveApps(apps,new List<AppEntry>{new AppEntry{Id="1"},new AppEntry{Id="1"}}),"Reject duplicate app IDs");Check(Data.Hash(apps)==saved,"Invalid app save preserves source");
        using(var picker=new PurchaseDialog(merged)){picker.Opacity=0;picker.ShowInTaskbar=false;picker.Show();System.Windows.Forms.Application.DoEvents();picker.SmokeFilter();Check(true,"Purchase picker retains selected apps across filters");}
        var f=new FakeTool();f.Add("{\"success\":true,\"email\":\"fixture@example.invalid\"}");var e=MakeEngine(f);e.Login(a,root);Check(f.Calls.Count==1 && f.Calls[0][0]=="--format" && f.Calls[0][2]=="--keychain-passphrase" && !f.Calls[0].Contains("--non-interactive"),"Native login uses existing CPP protocol");
        f=new FakeTool();f.Add("{\"success\":true,\"email\":\"other@example.invalid\"}");Throws(()=>MakeEngine(f).Login(a,root),"Wrong-account login is rejected before purchases");Check(f.Calls.Count==1,"Wrong-account flow stops immediately");
        f=new FakeTool();f.Add("Error: two-factor auth code required.");f.Add("{\"success\":true,\"email\":\"fixture@example.invalid\"}");int prompts=0;e=MakeEngine(f,s=>{prompts++;return "123456";});e.Login(a,root);Check(prompts==1&&f.Calls[1].Contains("--auth-code"),"2FA callback and retry");Check(!e.Redact("fixture-secret-1 fixture-session-key 123456").Contains("fixture")&&!e.Redact("123456").Contains("123456"),"Password, session key and code are redacted");
        Check(Engine.NeedsCode(new ToolResult{Text="{\"error\":\"invalid authentication code\"}"}),"Structured invalid-code detection");Check(!Engine.NeedsCode(new ToolResult{Text="{\"error\":\"incorrect password\"}"}),"Password errors do not request 2FA");
        f=new FakeTool();for(int i=0;i<4;i++)f.Add("two-factor auth code required.");Throws(()=>MakeEngine(f).Login(a,root),"2FA retry limit");Check(f.Calls.Count==4,"No fifth login attempt");
        f=new FakeTool();f.Add("two-factor auth code required.");Throws(()=>MakeEngine(f,s=>"bad").Login(a,root),"Invalid code rejected without another login");Check(f.Calls.Count==1,"Malformed 2FA not sent");
        f=new FakeTool();f.Add("two-factor auth code required.");Throws(()=>MakeEngine(f,s=>{throw new OperationCanceledException();}).Login(a,root),"Cancelled code entry aborts login");Check(f.Calls.Count==1,"No request after cancelled code entry");
        var badPassword=Account();badPassword.Password=Data.Protect("-unsupported");f=new FakeTool();Throws(()=>MakeEngine(f).Login(badPassword,root),"Unsupported CLI password rejected before sending");Check(f.Calls.Count==0,"No credential request for unsupported password");
        f=new FakeTool();f.Add("{\"count\":3,\"apps\":[{\"id\":\"101\",\"name\":\"Removed App\",\"kind\":\"iOS App\"},{\"id\":\"999\",\"name\":\"Book\",\"kind\":\"Book\"},{\"id\":\"202\",\"name\":\"Other\",\"kind\":\"iOS App\"}]}");f.Add("{\"count\":1,\"apps\":[{\"id\":\"101\",\"name\":\"Removed App\",\"kind\":\"iOS App\"}]}");var purchases=MakeEngine(f).Purchases(root,2009);Check(purchases.Count==2&&purchases[0].Name=="Removed App","History includes delisted apps, deduplicates and filters non-app purchases");Check(f.Calls[0].Last()=="2009-all"&&f.Calls[1].Last()=="2008-all","Every requested year is covered");
        f=new FakeTool();for(int y=DateTime.Now.Year;y>=2008;y--)f.Add("{\"count\":0,\"apps\":[]}");Check(MakeEngine(f).Purchases(root,DateTime.Now.Year).Count==0 && f.Calls.Count==DateTime.Now.Year-2007,"Empty years do not terminate full history");
        f=new FakeTool();f.Add("{\"count\":0,\"apps\":[]}");f.Add("private invoice data",1);Throws(()=>MakeEngine(f).Purchases(root,2009),"Partial history is not returned after an error");
        f=new FakeTool();f.Add("{\"count\":1,\"apps\":[]}");Throws(()=>MakeEngine(f).Purchases(root,2008),"Invalid purchase count rejected");
        f=new FakeTool();f.Add("{\"success\":true}");f.Before=(arg,work)=>Ipa(Path.Combine(work,arg[Array.IndexOf(arg,"--output")+1]));var target=new AppEntry{Id="101"};string download=MakeEngine(f).Download(target,a,root);Check(File.Exists(download)&&Path.GetFileName(download).StartsWith("Home_Keys_1.2.1_iOS_15.0+_fixture@example.invalid_"),"IPA metadata and account description used in filename");Check(f.Calls[0].Contains("--purchase")&&!Path.IsPathRooted(f.Calls[0][Array.IndexOf(f.Calls[0],"--output")+1]),"Download uses purchase option and ASCII relative output");
        f.Add("{\"success\":true}");string second=MakeEngine(f).Download(target,a,root);Check(second!=download&&File.Exists(download),"Duplicate download never overwrites existing IPA");
        f=new FakeTool();f.Add("{\"success\":true}");f.Before=(arg,work)=>File.WriteAllText(Path.Combine(work,arg[Array.IndexOf(arg,"--output")+1]),"invalid");Throws(()=>MakeEngine(f).Download(target,a,root),"Invalid IPA rejected");Check(Directory.GetFiles(root,"*.partial.ipa*").Length==0,"Failed partial file removed");
        using(var cts=new CancellationTokenSource()){f=new FakeTool();f.Add("{\"success\":true}");f.Before=(arg,work)=>{Ipa(Path.Combine(work,arg[Array.IndexOf(arg,"--output")+1]));cts.Cancel();};Throws(()=>MakeEngine(f,null,cts.Token).Download(target,a,root),"Cancellation after transfer prevents final file");Check(Directory.GetFiles(root,"*.partial.ipa*").Length==0,"Cancelled partial file removed");}
        string run;using(var session=new Session(root,a.Email)){run=session.Root;Check(Directory.Exists(run)&&session.Environment["IPATOOL_AUTH_MODE"]=="cpp","Session uses isolated profile and native mode");File.WriteAllText(Path.Combine(run,"sample"),"fixture");}Check(!Directory.Exists(run),"Temporary session removed");Throws(()=>Session.DeleteTree(root,root),"Session cleanup refuses unrelated directory");
        var refs=typeof(MainForm).Assembly.GetReferencedAssemblies();Check(!refs.Any(r=>r.Name.Contains("Automation")),"Product has no PowerShell runtime dependency");Check(typeof(MainForm).Assembly.GetManifestResourceNames().SequenceEqual(new[]{Component.Resource}),"Product embeds only the pinned component archive");
        string bundleRoot;
        using(var bundle=Component.Open(CancellationToken.None,s=>{})){
            bundleRoot=bundle.Root;
            Check(Path.GetDirectoryName(bundleRoot)==Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar),"Component is extracted directly into TEMP");
            Check(Data.Hash(bundle.Exe)==Component.ExeHash,"Embedded executable matches pinned upstream checksum");
            using(var isolated=new Session(root,"version@example.invalid")){
                var help=new NativeTool(bundle.Exe,isolated.Environment).Run(new string[0],15,CancellationToken.None,isolated.Root);
                Check(help.ExitCode==0&&help.Text.Contains("ipatool-cpp")&&help.Text.Contains("list-purchases"),"Embedded tool launches from TEMP and displays help without Apple requests");
            }
            Check(Directory.GetFiles(bundleRoot).Length==5&&File.Exists(Path.Combine(bundleRoot,"ipatool-cpp-MIT.txt")),"Bundle includes only executable and license notices");
            Throws(()=>{using(var stream=File.Open(bundle.Exe,FileMode.Open,FileAccess.Write)){}},"Verified executable cannot be modified while in use");
            using(var another=Component.Open(CancellationToken.None,s=>{}))Check(another.Root!=bundleRoot&&File.Exists(bundle.Exe),"Concurrent instances use separate component folders");
        }
        Check(!Directory.Exists(bundleRoot),"Component folder is removed on normal exit");
        using(var cts=new CancellationTokenSource()){
            cts.Cancel();Throws(()=>Component.Open(cts.Token,s=>{}),"Cancelled startup does not prepare component");
        }
        var beforeBundles=Directory.GetDirectories(Path.GetTempPath(),"TapOk-IPA-Downloader-*");
        using(var cts=new CancellationTokenSource())Throws(()=>Component.Open(cts.Token,s=>cts.Cancel()),"Cancellation during preparation is handled");
        Check(!Directory.GetDirectories(Path.GetTempPath(),"TapOk-IPA-Downloader-*").Except(beforeBundles).Any(),"Cancelled preparation leaves no component folder");
        var transport=new NativeTool(Path.Combine(AppDomain.CurrentDomain.BaseDirectory,"ToolFixture.exe"),new Dictionary<string,string>());
        var argv=new[]{"with space","quote\"inside",@"C:\path with space\","Русский","$() & ;", ""};var response=transport.Run(argv,10,CancellationToken.None,root);
        Check(Data.Json().Deserialize<string[]>(response.Text.Trim()).SequenceEqual(argv),"Native arguments preserve quotes, Unicode and trailing backslashes without shell interpolation");
        response=transport.Run(new[]{"pipes"},10,CancellationToken.None,root);Check(response.ExitCode==0&&response.Text.Length>1500000,"Native stdout and stderr drain concurrently");
        var clock=Stopwatch.StartNew();Throws(()=>transport.Run(new[]{"sleep"},1,CancellationToken.None,root),"Native process timeout terminates child");Check(clock.Elapsed.TotalSeconds<6,"Timeout is bounded");
        using(var cts=new CancellationTokenSource()){cts.CancelAfter(250);clock.Restart();Throws(()=>transport.Run(new[]{"sleep"},20,cts.Token,root),"Cancellation terminates native process");Check(clock.Elapsed.TotalSeconds<6,"Cancellation is bounded");}
    }
}
