using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Collections.Generic;
using System.Threading;
using System.Diagnostics;
using TapOk.Installer;

class NativeTests {
    const string Id="1111111111111111111111111111111111111111";
    static int checks;
    static string root,fixture,toolRoot,caseRoot;
    static Dictionary<string,string> hashes;
    static void Check(bool value,string name){if(!value)throw new Exception("FAIL: "+name);checks++;Console.WriteLine("PASS: "+name);}
    static void Fails(Action action,string name){bool failed=false;try{action();}catch{failed=true;}Check(failed,name);}
    static void WriteIpa(string path,string minimum="",string entry="Payload/Test.app/Info.plist",bool duplicate=false){
        using(var file=File.Create(path))using(var zip=new ZipArchive(file,ZipArchiveMode.Create)) {
            for(int i=0;i<(duplicate?2:1);i++)using(var writer=new StreamWriter(zip.CreateEntry(entry).Open(),new UTF8Encoding(false)))writer.Write("<?xml version=\"1.0\"?><!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\"><plist><dict><key>CFBundleIdentifier</key><string>com.example.fixture</string><key>CFBundleDisplayName</key><string>Тестовое приложение</string><key>MinimumOSVersion</key><string>"+minimum+"</string></dict></plist>");
        }
    }
    static byte[] BinaryPlist() {
        using(var stream=new MemoryStream()) {
            byte[] header=Encoding.ASCII.GetBytes("bplist00");stream.Write(header,0,header.Length);var offsets=new List<int>();offsets.Add((int)stream.Position);
            foreach(byte b in new byte[]{0xd2,1,2,3,4})stream.WriteByte(b);
            foreach(string s in new[]{"CFBundleIdentifier","CFBundleDisplayName","com.example.fixture","Тестовое приложение"}) {
                offsets.Add((int)stream.Position);stream.WriteByte(0x6f);stream.WriteByte(0x10);stream.WriteByte((byte)s.Length);byte[] data=Encoding.BigEndianUnicode.GetBytes(s);stream.Write(data,0,data.Length);
            }
            int table=(int)stream.Position;foreach(int at in offsets){stream.WriteByte((byte)(at>>8));stream.WriteByte((byte)at);}
            var trailer=new byte[32];trailer[6]=2;trailer[7]=1;trailer[15]=5;trailer[30]=(byte)(table>>8);trailer[31]=(byte)table;stream.Write(trailer,0,32);return stream.ToArray();
        }
    }
    static Engine Make(string scenario,CancellationToken token){
        caseRoot=Path.Combine(root,scenario+"-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(caseRoot);
        Environment.SetEnvironmentVariable("IPA_INSTALL_TEST_SCENARIO",scenario);Environment.SetEnvironmentVariable("IPA_INSTALL_TEST_LOG",Path.Combine(caseRoot,"calls.jsonl"));Environment.SetEnvironmentVariable("IPA_INSTALL_TEST_EXPECTED_SHA256",null);
        return new Engine(new ProcessTools(toolRoot,hashes),new Texts("en"),caseRoot,token){NativeSeconds=5,PairingSeconds=2};
    }
    static void Success(string scenario,string ipa=null,string id=Id){
        var e=Make(scenario,CancellationToken.None);ipa=ipa??fixture;string hash=Files.HashFile(ipa);Environment.SetEnvironmentVariable("IPA_INSTALL_TEST_EXPECTED_SHA256",hash);
        var app=e.Install(ipa,id);Check(app.BundleId=="com.example.fixture",scenario+" completes");Check(Directory.GetDirectories(caseRoot,".work-*").Length==0,scenario+" cleans staged copy");Check(Files.HashFile(ipa)==hash,scenario+" preserves source");
        string calls=File.ReadAllText(Path.Combine(caseRoot,"calls.jsonl"));Check(calls.Contains("payload.ipa")&&!calls.Contains(ipa.Replace("\\","\\\\")),scenario+" passes relative ASCII IPA path");
    }
    static void Failure(string scenario,bool beforeInstall=false,string ipa=null){
        var e=Make(scenario,CancellationToken.None);Fails(()=>e.Install(ipa??fixture,Id),scenario+" rejected");
        if(beforeInstall)Check(!e.InstallStarted,scenario+" stops before installation");Check(Directory.GetDirectories(caseRoot,".work-*").Length==0,scenario+" removes temporary IPA");
    }
    static int Main(string[] args){try{
        root=Path.GetFullPath(args[0]);toolRoot=Path.GetFullPath(args[1]);Directory.CreateDirectory(root);
        hashes=Directory.GetFiles(toolRoot,"*.exe").ToDictionary(Path.GetFileName,Files.HashFile);fixture=Path.Combine(root,"Тест [1] & приложение.ipa");WriteIpa(fixture);
        Check(Engine.CompareVersions("16.10","16.9")==1,"numeric iOS comparison");Check(Engine.CompareVersions("16.10.1","16.10.2")==-1,"iOS patch comparison");Check(Engine.CompareVersions("18 beta","16")==null,"invalid version is unknown");Check(Engine.CompareVersions("999999999999","16")==null,"overflow version rejected");
        Check(!Engine.ValidId("-u other")&&Engine.ValidId(Id)&&Engine.ValidId("00008110-001A2B3C4D5E001E"),"device identifier validation");
        Check(Engine.PairState(new ToolResult{Code=0,Out="SUCCESS: Paired with device "+new string('2',40)},Id)=="failed","unrelated device success rejected");
        Check(Engine.PairState(new ToolResult{Code=1,Out="SUCCESS: Paired with device "+Id},Id)=="failed","nonzero pairing success rejected");
        Check(Engine.PairState(new ToolResult{Code=0,Out="SUCCESS: Paired with device "+Id,Err="ERROR: failure"},Id)=="failed","contradictory pairing response rejected");
        var engine=Make("happy",CancellationToken.None);var app=engine.Inspect(fixture);Check(app.Name=="Тестовое приложение","Unicode IPA metadata");Check(app.CredentialKey=="sha256:"+Files.HashFile(fixture).ToLowerInvariant(),"IPA identity uses actual content");
        string bad=Path.Combine(root,"invalid.ipa");File.WriteAllText(bad,"bad");Fails(()=>engine.Inspect(bad),"non ZIP rejected");
        string duplicate=Path.Combine(root,"duplicate.ipa");WriteIpa(duplicate,"","Payload/Test.app/Info.plist",true);Fails(()=>engine.Inspect(duplicate),"multiple app metadata rejected");
        string traversal=Path.Combine(root,"nested.ipa");WriteIpa(traversal,"","Payload/Test.app/../Info.plist");Fails(()=>engine.Inspect(traversal),"non-root app metadata rejected");
        string binary=Path.Combine(root,"binary.ipa");using(var file=File.Create(binary))using(var zip=new ZipArchive(file,ZipArchiveMode.Create))using(var entry=zip.CreateEntry("Payload/Test.app/Info.plist").Open()){var bytes=BinaryPlist();entry.Write(bytes,0,bytes.Length);}
        Check(engine.Inspect(binary).Name=="Тестовое приложение","binary plist metadata read without an external converter");
        string minimum=Path.Combine(root,"minimum.ipa");WriteIpa(minimum,"16.10");string micro=Path.Combine(root,"micro.ipa");WriteIpa(micro,"16.10.2");
        Check(Make("none",CancellationToken.None).Devices().Length==0,"no device");Check(Make("multi",CancellationToken.None).Devices().Length==2,"multiple devices");
        Check(Make("model-unknown",CancellationToken.None).Devices()[0].Display.Contains("iPhone99,9"),"unknown model not guessed");
        Check(Make("happy",CancellationToken.None).Devices()[0].Display.Contains("iPhone 15 Pro Max"),"known model label");
        Check(Make("ios-invalid",CancellationToken.None).Devices()[0].Version=="","invalid device version cleared");
        Success("happy");Success("happy",binary);Success("pair-pending");Success("pair-direct-pending");Success("selected-second",null,"00008110-001A2B3C4D5E001E");Success("ios-ten",minimum);Success("ios-unknown",minimum);
        foreach(var scenario in new[]{"enumeration-fail","removed","untrusted","locked","pair-denied","pair-validate-denied","pair-no-success","pair-forever"})Failure(scenario,true);
        Failure("ios-low",true,minimum);Failure("ios-micro-low",true,micro);
        foreach(var scenario in new[]{"exit0-error","nonzero-complete","no-complete","missing-installed"})Failure(scenario);
        var timer=Stopwatch.StartNew();var timed=Make("slow",CancellationToken.None);timed.NativeSeconds=1;Fails(()=>timed.Install(fixture,Id),"native timeout");Check(timed.InstallStarted&&timer.Elapsed.TotalSeconds<10,"timeout bounded after install start");Check(Directory.GetDirectories(caseRoot,".work-*").Length==0,"timeout cleans staged file after child exits");
        using(var cts=new CancellationTokenSource()){cts.Cancel();var e=Make("happy",cts.Token);Fails(()=>e.Install(fixture,Id),"pre-cancelled operation");Check(!e.InstallStarted,"pre-cancel does not start installation");}
        using(var cts=new CancellationTokenSource()){var e=Make("slow",cts.Token);e.Status=s=>{if(s=="Installing…")cts.CancelAfter(350);};try{e.Install(fixture,Id);throw new Exception("Cancellation not raised");}catch(OperationCanceledException){}Check(e.InstallStarted,"cancel during install preserves uncertain-result state");Check(Directory.GetDirectories(caseRoot,".work-*").Length==0,"cancel terminates child before cleanup");}
        var native=new ProcessTools(toolRoot,hashes);native.Verify();Check(true,"pinned fixture components verified");string changed=Path.Combine(toolRoot,"plistutil.exe");byte[] original=File.ReadAllBytes(changed);try{File.AppendAllText(changed,"changed");Fails(()=>native.Run("idevice_id",new[]{"-l"},5,"",CancellationToken.None),"changed dependency blocked before execution");}finally{File.WriteAllBytes(changed,original);}
        string storage=Path.Combine(root,"credentials.dat");var store=new CredentialStore(storage);Check(store.Get(CredentialStore.SharedKey)==null,"empty credential storage");store.Set("legacy-key","fixture@example.invalid","fixture-only-legacy");store.Set(CredentialStore.SharedKey," second@example.invalid ","тест & пароль");Check(store.Get(CredentialStore.SharedKey).AppleId=="second@example.invalid","account trimming");Check(store.Get(CredentialStore.SharedKey).Password=="тест & пароль","Unicode protected credential round trip");Check(!Encoding.UTF8.GetString(File.ReadAllBytes(storage)).Contains("second@example.invalid"),"credential bytes encrypted");store.Set(CredentialStore.SharedKey,"updated@example.invalid","new-fixture");Check(store.Get("legacy-key").Password=="fixture-only-legacy","unrelated credential preserved");store.Remove(CredentialStore.SharedKey);Check(store.Get(CredentialStore.SharedKey)==null&&store.Get("legacy-key")!=null,"targeted credential removal");
        File.WriteAllText(storage,"corrupt");string before=Files.HashFile(storage);Fails(()=>store.Set(CredentialStore.SharedKey,"fixture@example.invalid","fixture"),"corrupt store not overwritten");Check(Files.HashFile(storage)==before,"corrupt store preserved");
        string compatibility=Path.Combine(root,"legacy.dat");if(File.Exists(compatibility)){var legacy=new CredentialStore(compatibility);Check(legacy.Get(CredentialStore.SharedKey).Password=="legacy fixture password","reads PowerShell DPAPI format");legacy.Set(CredentialStore.SharedKey,"native@example.invalid","native fixture password");Check(legacy.Get("legacy-key").AppleId=="old@example.invalid","migration preserves legacy entries");}
        Check(Files.ReadLanguage(root)=="en","default English");File.WriteAllText(Path.Combine(root,"language.txt"),"ru");Check(Files.ReadLanguage(root)=="ru","saved Russian preference");
        Console.WriteLine(checks+" native checks passed");File.WriteAllText(Path.Combine(root,"result.txt"),checks+" native checks passed; fake tools only; no USB or Apple requests.");return 0;
    }catch(Exception ex){Console.Error.WriteLine(ex);return 1;}finally{Environment.SetEnvironmentVariable("IPA_INSTALL_TEST_SCENARIO",null);Environment.SetEnvironmentVariable("IPA_INSTALL_TEST_LOG",null);Environment.SetEnvironmentVariable("IPA_INSTALL_TEST_EXPECTED_SHA256",null);}}
}
