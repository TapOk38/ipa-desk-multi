using System;
using System.IO;
using System.Text;
using System.Linq;
using System.Collections.Generic;
using System.Diagnostics;
using System.Security.Cryptography;
using System.Threading;
using System.Threading.Tasks;
using System.Web.Script.Serialization;

namespace TapOk.Installer {
    public static class Files {
        public static string Hash(byte[] bytes) { using(var sha=SHA256.Create()) return BitConverter.ToString(sha.ComputeHash(bytes)).Replace("-", ""); }
        public static string HashFile(string path) { using(var sha=SHA256.Create()) using(var file=File.OpenRead(path)) return BitConverter.ToString(sha.ComputeHash(file)).Replace("-", ""); }
        public static void AtomicWrite(string path, byte[] bytes) {
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            string temp=Path.Combine(Path.GetDirectoryName(path), ".accounts-"+Guid.NewGuid().ToString("N")+".tmp");
            try {
                using(var stream=new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None)) { stream.Write(bytes,0,bytes.Length); stream.Flush(true); }
                if(File.Exists(path)) File.Replace(temp,path,null); else File.Move(temp,path);
            } finally { if(File.Exists(temp)) File.Delete(temp); }
        }
        public static bool IsReparse(string path) { return (File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0; }
        public static string ReadLanguage(string root) { try { string p=Path.Combine(root,"language.txt"); if(new FileInfo(p).Length<=16 && File.ReadAllText(p).Trim()=="ru") return "ru"; } catch {} return "en"; }
    }
    public sealed class Credential { public string Key {get;set;} public string AppleId {get;set;} public string Password {get;set;} }
    public sealed class CredentialDatabase { public int Version {get;set;} public Credential[] Entries {get;set;} }
    public sealed class CredentialStore {
        public const string SharedKey="icloud:default";
        readonly string path;
        static readonly byte[] Entropy=Encoding.UTF8.GetBytes("IPA-Install account storage v1");
        public CredentialStore(string file) { path=Path.GetFullPath(file); }
        T Locked<T>(Func<T> action) {
            using(var mutex=new Mutex(false,"Local\\IPAInstall.Credentials."+Files.Hash(Encoding.UTF8.GetBytes(path.ToUpperInvariant())))) {
                bool held=false;
                try { try { held=mutex.WaitOne(5000); } catch(AbandonedMutexException) { held=true; }
                    if(!held) throw new IOException("Credential storage is busy."); return action();
                } finally { if(held) mutex.ReleaseMutex(); }
            }
        }
        static void ValidKey(string key) { if(String.IsNullOrWhiteSpace(key)||key.Length>4096) throw new InvalidDataException("Invalid credential key."); }
        static JavaScriptSerializer Serializer() { return new JavaScriptSerializer {MaxJsonLength=8388608,RecursionLimit=16}; }
        CredentialDatabase Read() {
            if(!File.Exists(path)) return new CredentialDatabase {Version=1,Entries=new Credential[0]};
            using(var f=File.OpenRead(path)) { if(f.Length<9||f.Length>16777216) throw new InvalidDataException("Invalid credential storage."); }
            byte[] stored=File.ReadAllBytes(path), plain=null;
            if(stored.Length<9 || stored.Length>16777216 || Encoding.ASCII.GetString(stored,0,8)!="IPAINS01") throw new InvalidDataException("Invalid credential storage.");
            CredentialDatabase db;
            try {
                plain=ProtectedData.Unprotect(stored.Skip(8).ToArray(),Entropy,DataProtectionScope.CurrentUser);
                if(plain.Length>8388608) throw new InvalidDataException("Large credential storage.");
                // Validate types before typed deserialization; never coerce corrupt fields.
                string json=new UTF8Encoding(false,true).GetString(plain);
                var raw=Serializer().DeserializeObject(json) as Dictionary<string,object>;
                object version, entries;
                if(raw==null||!raw.TryGetValue("Version",out version)||!(version is int)||(int)version!=1||!raw.TryGetValue("Entries",out entries)||!(entries is System.Collections.IList)) throw new InvalidDataException("Invalid credential storage.");
                var list=(System.Collections.IList)entries;
                if(list.Count>4096) throw new InvalidDataException("Large credential storage.");
                foreach(var item in list) {
                    var entry=item as Dictionary<string,object>;
                    if(entry==null || new[]{"Key","AppleId","Password"}.Any(k=>!entry.ContainsKey(k)||!(entry[k] is string))) throw new InvalidDataException("Invalid credential storage.");
                }
                db=Serializer().Deserialize<CredentialDatabase>(json);
            } finally { if(plain!=null) Array.Clear(plain,0,plain.Length); }
            var seen=new HashSet<string>(StringComparer.Ordinal);
            foreach(var e in db.Entries) { ValidKey(e.Key); if(String.IsNullOrWhiteSpace(e.AppleId)||String.IsNullOrEmpty(e.Password)||!seen.Add(e.Key)) throw new InvalidDataException("Invalid credential storage."); }
            return db;
        }
        void Write(CredentialDatabase db) {
            byte[] plain=Encoding.UTF8.GetBytes(Serializer().Serialize(db));
            try {
                if(plain.Length>8388608) throw new InvalidDataException("Large credential storage.");
                byte[] encrypted=ProtectedData.Protect(plain,Entropy,DataProtectionScope.CurrentUser);
                Files.AtomicWrite(path,Encoding.ASCII.GetBytes("IPAINS01").Concat(encrypted).ToArray());
            } finally { Array.Clear(plain,0,plain.Length); }
        }
        public Credential Get(string key) { ValidKey(key); return Locked(()=>Read().Entries.FirstOrDefault(e=>e.Key==key)); }
        public void Set(string key,string appleId,string password) {
            ValidKey(key); if(String.IsNullOrWhiteSpace(appleId)||String.IsNullOrEmpty(password)) throw new ArgumentException("Enter an Apple ID and password.");
            Locked(()=>{ var db=Read(); var items=db.Entries.Where(e=>e.Key!=key).ToList(); if(items.Count>=4096) throw new InvalidDataException("Credential storage is full."); items.Add(new Credential{Key=key,AppleId=appleId.Trim(),Password=password}); db.Entries=items.ToArray(); Write(db); return true; });
        }
        public void Remove(string key) { ValidKey(key); Locked(()=>{var db=Read(); var items=db.Entries.Where(e=>e.Key!=key).ToArray(); if(items.Length!=db.Entries.Length){db.Entries=items;Write(db);}return true;}); }
    }
    public sealed class ToolResult { public int Code; public string Out="",Err=""; public string Text {get{return Out+"\n"+Err;}} }
    public interface ITools { ToolResult Run(string tool,string[] args,int seconds,string cwd,CancellationToken cancel); }
    public sealed class ProcessTools : ITools {
        readonly string root; readonly Dictionary<string,string> hashes;
        public ProcessTools(string directory, Dictionary<string,string> expected) { root=Path.GetFullPath(directory); hashes=new Dictionary<string,string>(expected,StringComparer.OrdinalIgnoreCase); }
        public void Verify() {
            if(!Directory.Exists(root)||Files.IsReparse(root)) throw new IOException("The tools folder is missing or invalid.");
            foreach(var item in hashes) {
                if(Path.GetFileName(item.Key)!=item.Key) throw new InvalidDataException("Invalid component name.");
                string file=Path.Combine(root,item.Key);
                if(!File.Exists(file)||Files.IsReparse(file)||!String.Equals(Files.HashFile(file),item.Value,StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Missing or changed installation component: "+item.Key);
            }
        }
        public static string Quote(string text) {
            return "\""+System.Text.RegularExpressions.Regex.Replace(System.Text.RegularExpressions.Regex.Replace(text,@"(\\*)""","$1$1\\\""),@"(\\+)$","$1$1")+"\"";
        }
        public ToolResult Run(string tool,string[] args,int seconds,string cwd,CancellationToken cancel) {
            cancel.ThrowIfCancellationRequested();
            if(!hashes.ContainsKey(tool+".exe")) throw new InvalidOperationException("Unknown installation component.");
            Verify();
            var start=new ProcessStartInfo(Path.Combine(root,tool+".exe"),String.Join(" ",args.Select(Quote))) {
                WorkingDirectory=String.IsNullOrEmpty(cwd)?root:cwd,UseShellExecute=false,CreateNoWindow=true,
                RedirectStandardInput=true,RedirectStandardOutput=true,RedirectStandardError=true,
                StandardOutputEncoding=Encoding.UTF8,StandardErrorEncoding=Encoding.UTF8
            };
            // Remove search directories inherited from unrelated programs. Required DLLs sit beside each tool.
            start.EnvironmentVariables["PATH"]=root+";"+Environment.GetFolderPath(Environment.SpecialFolder.System);
            using(var p=new Process {StartInfo=start}) {
                bool started=false;
                try {
                    started=p.Start(); if(!started) throw new IOException("Could not start installation component."); p.StandardInput.Close();
                    var output=ReadBounded(p.StandardOutput); var error=ReadBounded(p.StandardError); var watch=Stopwatch.StartNew();
                    while(!p.WaitForExit(100)) { cancel.ThrowIfCancellationRequested(); if(output.IsFaulted||error.IsFaulted) throw new IOException("Installation component output exceeded its limit."); if(watch.Elapsed.TotalSeconds>=seconds) throw new TimeoutException(); }
                    cancel.ThrowIfCancellationRequested();
                    if(p.ExitCode==-1073741515||p.ExitCode==-1073741701) throw new IOException("Could not load installation components.");
                    return new ToolResult {Code=p.ExitCode,Out=output.GetAwaiter().GetResult(),Err=error.GetAwaiter().GetResult()};
                } finally { if(started) { try {if(!p.HasExited){p.Kill();p.WaitForExit(3000);}} catch {} } }
            }
        }
        static async Task<string> ReadBounded(StreamReader reader) {
            var text=new StringBuilder(); var buffer=new char[8192]; int count;
            while((count=await reader.ReadAsync(buffer,0,buffer.Length).ConfigureAwait(false))>0) { if(text.Length+count>16777216) throw new InvalidDataException("Large component output."); text.Append(buffer,0,count); }
            return text.ToString();
        }
    }
}
