using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace TapOk.Downloader {
    public sealed class ToolResult {public int ExitCode; public string Text;}
    public interface ITool {ToolResult Run(string[] args,int seconds,CancellationToken token,string work);}
    public sealed class NativeTool : ITool {
        readonly string path; readonly Dictionary<string,string> environment;
        public NativeTool(string path,Dictionary<string,string> environment){this.path=path;this.environment=environment;}
        public static string Quote(string value){var b=new StringBuilder("\"");int slashes=0;foreach(char c in value){if(c=='\\'){slashes++;continue;}b.Append('\\',c=='"'?slashes*2+1:slashes);b.Append(c);slashes=0;}return b.Append('\\',slashes*2).Append('"').ToString();}
        public ToolResult Run(string[] args,int seconds,CancellationToken token,string work){
            token.ThrowIfCancellationRequested();
            var si=new ProcessStartInfo(path){Arguments=String.Join(" ",args.Select(Quote)),WorkingDirectory=work,UseShellExecute=false,CreateNoWindow=true,RedirectStandardOutput=true,RedirectStandardError=true,RedirectStandardInput=true,StandardOutputEncoding=Encoding.UTF8,StandardErrorEncoding=Encoding.UTF8};
            foreach(var p in environment)si.EnvironmentVariables[p.Key]=p.Value;
            using(var p=new Process{StartInfo=si}){
                bool started=false;try{
                    started=p.Start();if(!started)throw new IOException("Cannot start IPATool.");p.StandardInput.Close();
                    var output=p.StandardOutput.ReadToEndAsync();var error=p.StandardError.ReadToEndAsync();var clock=Stopwatch.StartNew();
                    while(!p.WaitForExit(100)){token.ThrowIfCancellationRequested();if(clock.Elapsed.TotalSeconds>seconds)throw new TimeoutException(Texts.T("Превышено время ожидания ответа. Проверьте интернет.","Response timed out. Check your internet connection."));}
                    token.ThrowIfCancellationRequested();return new ToolResult{ExitCode=p.ExitCode,Text=output.GetAwaiter().GetResult()+"\n"+error.GetAwaiter().GetResult()};
                }finally{if(started && !p.HasExited){p.Kill();p.WaitForExit();}}
            }
        }
    }
    public sealed class Session : IDisposable {
        public readonly string Root,Parent,Passphrase;public readonly Dictionary<string,string> Environment;
        public Session(string dataRoot,string email){
            var accountRoot=Path.Combine(dataRoot,"sessions","accounts",Data.HashText(email.Trim().ToLowerInvariant()));Directory.CreateDirectory(accountRoot);
            var keyPath=Path.Combine(accountRoot,"session-key.dpapi");byte[] entropy=Encoding.UTF8.GetBytes("IPA-Desk/session-key/v1");byte[] key=null;
            try{
                if(!File.Exists(keyPath)){key=new byte[32];using(var rng=RandomNumberGenerator.Create())rng.GetBytes(key);var encrypted=ProtectedData.Protect(key,entropy,DataProtectionScope.CurrentUser);try{using(var output=new FileStream(keyPath,FileMode.CreateNew))output.Write(encrypted,0,encrypted.Length);}catch(IOException){if(!File.Exists(keyPath))throw;}Array.Clear(key,0,key.Length);}
                key=ProtectedData.Unprotect(File.ReadAllBytes(keyPath),entropy,DataProtectionScope.CurrentUser);if(key.Length!=32)throw new InvalidDataException("Invalid session key.");Passphrase=Convert.ToBase64String(key);
            }finally{if(key!=null)Array.Clear(key,0,key.Length);}
            Parent=Path.Combine(accountRoot,"runs");Root=Path.Combine(Parent,Guid.NewGuid().ToString("N"));var profile=Path.Combine(Root,"profile");Directory.CreateDirectory(profile);var drive=Path.GetPathRoot(profile);
            Environment=new Dictionary<string,string>{{"USERPROFILE",profile},{"HOMEDRIVE",drive.TrimEnd('\\')},{"HOMEPATH",profile.Substring(drive.Length-1)},{"XDG_STATE_HOME",Path.Combine(Root,"state")},{"XDG_DATA_HOME",Path.Combine(Root,"state")},{"LOCALAPPDATA",Path.Combine(dataRoot,"sessions","runtime")},{"HTTP_PROXY",""},{"HTTPS_PROXY",""},{"ALL_PROXY",""},{"NO_PROXY","*"},{"GODEBUG","http2client=0"},{"IPATOOL_AUTH_MODE","cpp"},{"IPATOOL_NATIVE_AUTH_DIAGNOSTIC",""}};
        }
        public static void DeleteTree(string root,string parent){
            if(!Directory.Exists(root))return;
            if(!String.Equals(Path.GetDirectoryName(Path.GetFullPath(root)),Path.GetFullPath(parent),StringComparison.OrdinalIgnoreCase)||!Regex.IsMatch(Path.GetFileName(root),"^[a-f0-9]{32}$"))throw new IOException("Invalid temporary directory.");
            for(var d=new DirectoryInfo(root);d!=null;d=d.Parent)if((d.Attributes&FileAttributes.ReparsePoint)!=0)throw new IOException("Linked temporary directory.");
            var queue=new Stack<string>();queue.Push(root);while(queue.Count>0)foreach(var path in Directory.EnumerateFileSystemEntries(queue.Pop())){var attr=File.GetAttributes(path);if((attr&FileAttributes.ReparsePoint)!=0)throw new IOException("Linked temporary file.");if((attr&FileAttributes.Directory)!=0)queue.Push(path);}
            Directory.Delete(root,true);
        }
        public void Dispose(){DeleteTree(Root,Parent);}
    }
    public sealed class Engine {
        readonly ITool tool;readonly string key;readonly Action<string> log;readonly Func<string,string> code;readonly CancellationToken token;readonly List<string> secrets=new List<string>();
        public Engine(ITool tool,string key,Action<string> log,Func<string,string> code,CancellationToken token){this.tool=tool;this.key=key;this.log=log;this.code=code;this.token=token;secrets.Add(key);}
        public string Redact(string text){text=text??"";foreach(string s in secrets)if(!String.IsNullOrEmpty(s)){text=text.Replace(s,"[redacted]");string quoted=Data.Json().Serialize(s);text=text.Replace(quoted.Substring(1,quoted.Length-2),"[redacted]");}return Regex.Replace(text,@"(?i)(https?|socks5h?)://[^\s/]*@","$1://[redacted]@");}
        ToolResult Run(string[] args,int timeout,string work){token.ThrowIfCancellationRequested();return tool.Run(new[]{"--format","json","--keychain-passphrase",key}.Concat(args).ToArray(),timeout,token,work);}
        public static List<Dictionary<string,object>> Records(string text){var result=new List<Dictionary<string,object>>();foreach(var line in text.Split('\n')){if(!line.TrimStart().StartsWith("{"))continue;try{var d=Data.Json().Deserialize<Dictionary<string,object>>(line);if(d!=null)result.Add(d);}catch(ArgumentException){}}return result;}
        static Dictionary<string,object> Success(ToolResult result){return result.ExitCode==0?Records(result.Text).LastOrDefault(r=>Object.Equals(Data.Get(r,"success"),true)):null;}
        public static bool NeedsCode(ToolResult r){
            if(Regex.IsMatch(r.Text,@"(?im)^\s*(?:Error: )?two-factor auth code required\."))return true;
            return Records(r.Text).Any(d=>new[]{"message","error"}.Any(f=>Regex.IsMatch(Data.Str(Data.Get(d,f)),@"(?i)\b(?:2fa|auth(?:entication)?|verification|security)[ -]+code\s+(?:is\s+)?required\b|\b(?:invalid|incorrect|expired)\s+(?:2fa|auth(?:entication)?|verification|security)\s+code\b|\b(?:2fa|auth(?:entication)?|verification|security)\s+code\s+(?:is\s+)?(?:invalid|incorrect|expired)\b")));
        }
        string Error(ToolResult r){var error=Records(r.Text).Select(d=>Data.Str(Data.Get(d,"error"))).LastOrDefault(x=>x.Length>0)??r.Text;error=Redact(error).Trim();if(error.Length==0)error="IPATool did not confirm success.";return error.Substring(0,Math.Min(1600,error.Length));}
        public void Login(Account a,string work){
            string password=Data.Unprotect(a.Password);secrets.Add(password);if(password.StartsWith("-"))throw new InvalidOperationException(Texts.T("IPATool не поддерживает пароль, начинающийся с дефиса.","IPATool does not support passwords beginning with a hyphen."));string authCode="";
            for(int attempt=0;attempt<4;attempt++){
                log(Texts.T("Вход: ","Signing in: ")+a.Email);var args=new List<string>{"auth","login","--email",a.Email,"--password",password};if(authCode.Length>0){args.Add("--auth-code");args.Add(authCode);}
                var r=Run(args.ToArray(),900,work);var success=Success(r);
                if(success!=null){if(!String.Equals(Data.Str(Data.Get(success,"email")),a.Email,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException(Texts.T("Apple подтвердил другую учётную запись. Операция остановлена.","Apple confirmed a different account. Operation stopped."));log(Texts.T("Вход выполнен.","Signed in."));return;}
                if(!NeedsCode(r))throw new InvalidOperationException(Error(r));if(attempt==3)break;
                authCode=code(a.Email);token.ThrowIfCancellationRequested();if(!Regex.IsMatch(authCode??"",@"^[0-9]{6}$"))throw new InvalidOperationException(Texts.T("Нужен шестизначный код Apple.","Enter the six-digit Apple verification code."));secrets.Add(authCode);
            }
            throw new InvalidOperationException(Texts.T("Не удалось подтвердить код 2FA.","Could not verify the 2FA code."));
        }
        public List<AppEntry> Purchases(string work,int currentYear){
            var apps=new List<AppEntry>();var ids=new HashSet<string>();
            for(int year=currentYear;year>=2008;year--){token.ThrowIfCancellationRequested();log(Texts.T("История покупок за ","Purchase history for ")+year+"…");var r=Run(new[]{"list-purchases","--range",year+"-all"},90,work);
                if(r.ExitCode!=0)throw new IOException(Texts.T("Не удалось получить покупки за ","Could not retrieve purchases for ")+year+".");
                var record=Records(r.Text).LastOrDefault(d=>d.ContainsKey("apps"));var items=Data.Items(Data.Get(record,"apps"));int count;
                if(items==null||!Int32.TryParse(Data.Str(Data.Get(record,"count")),out count)||count!=items.Length)throw new InvalidDataException(Texts.T("Некорректный список покупок.","Invalid purchase history response."));
                foreach(var item in items){token.ThrowIfCancellationRequested();var d=item as Dictionary<string,object>;if(Data.Str(Data.Get(d,"kind"))!="iOS App")continue;string id=Data.Id(Data.Str(Data.Get(d,"id")));if(ids.Add(id))apps.Add(new AppEntry{Id=id,Name=Data.Str(Data.Get(d,"name"))});}
            }return apps;
        }
        public string Download(AppEntry app,Account account,string folder){
            Data.Id(app.Id);Directory.CreateDirectory(folder);string partial=Path.Combine(folder,".ipa-desk-"+Guid.NewGuid().ToString("N")+".partial.ipa");
            try{
                log(Texts.T("Загрузка IPA: ","Downloading IPA: ")+app.Id);var r=Run(new[]{"download","--output",Path.GetFileName(partial),"--app-id",app.Id,"--purchase"},7200,folder);if(Success(r)==null)throw new IOException(Error(r));token.ThrowIfCancellationRequested();
                string stem=FileStem(partial,app.Id,account.Email,account.Description,folder);string final=Path.Combine(folder,stem+".ipa");int n=1;while(File.Exists(final))final=Path.Combine(folder,stem+" ("+(n++)+").ipa");token.ThrowIfCancellationRequested();File.Move(partial,final);return final;
            }finally{foreach(string path in new[]{partial,partial+".tmp"})if(File.Exists(path))try{File.Delete(path);}catch{log(Texts.T("Не удалось удалить незавершённую загрузку.","Could not remove an incomplete download."));}}
        }
        public static string Part(string v){return Regex.Replace((v??"").Trim(),@"[\x00-\x1f\s<>:""/\\|?*]+","_").Trim('.','_',' ');}
        public static string FileStem(string path,string id,string email,string description,string folder){
            var meta=new Dictionary<string,string>();using(var zip=ZipFile.OpenRead(path)){
                var entries=zip.Entries.Where(e=>Regex.IsMatch(e.FullName,@"^Payload/[^/]+\.app/Info\.plist$")).ToList();if(entries.Count!=1)throw new InvalidDataException("IPA must contain one Payload/*.app/Info.plist.");var entry=entries[0];
                if(entry.Length<=16*1024*1024)using(var s=entry.Open())using(var m=new MemoryStream()){byte[] buffer=new byte[8192];int n;while((n=s.Read(buffer,0,buffer.Length))>0){if(m.Length+n>16*1024*1024)throw new InvalidDataException("Info.plist too large.");m.Write(buffer,0,n);}try{meta=IpaDeskMetadata.Read(m.ToArray());}catch(InvalidDataException){}catch(System.Xml.XmlException){}}
            }
            Func<string,string> get=k=>meta.ContainsKey(k)?meta[k]:"";string name=Part(get("CFBundleName"));if(name.Length==0)name=Part(get("CFBundleDisplayName"));if(name.Length==0)name="app-"+id;
            string version=Part(get("CFBundleShortVersionString")),ios=Part(get("MinimumOSVersion")),desc=Part(description);string middle=(version.Length>0?"_"+version:"")+(ios.Length>0?"_iOS_"+ios+"+":"")+"_"+Part(email);int budget=Math.Min(220,245-folder.Length);
            while(name.Length+middle.Length+(desc.Length>0?1+desc.Length:0)>budget){if(desc.Length>12 && desc.Length>=name.Length)desc=desc.Substring(0,desc.Length-1);else if(name.Length>12)name=name.Substring(0,name.Length-1);else if(desc.Length>12)desc=desc.Substring(0,desc.Length-1);else throw new PathTooLongException(Texts.T("Слишком длинный путь загрузки.","Download path is too long."));}
            string stem=name+middle+(desc.Length>0?"_"+desc:"");if(Regex.IsMatch(stem,@"^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)"))stem="_"+stem;return stem;
        }
    }
}
