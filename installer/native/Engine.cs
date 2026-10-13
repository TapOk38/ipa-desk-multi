using System;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Collections.Generic;
using System.Text.RegularExpressions;
using System.Threading;
using System.Diagnostics;
using System.Xml;

namespace TapOk.Installer {
    public sealed class Device { public string Id,Name,ProductType,Version,Display; }
    public sealed class Ipa { public string Name,BundleId,Minimum,CredentialKey; }
    public sealed class Engine {
        readonly ITools tools; readonly Texts text; readonly string workRoot; readonly CancellationToken cancel;
        public Action<string> Status=delegate{};
        public Action<Device> DeviceUpdated=delegate{};
        public bool InstallStarted {get;private set;}
        public int PairingSeconds=120, NativeSeconds=1800;
        public Engine(ITools native,Texts language,string work,CancellationToken token) { tools=native;text=language;workRoot=Path.GetFullPath(work);cancel=token; }
        Exception Error(string key,params object[] args) {return new InvalidOperationException(text.Get(key,args));}
        ToolResult Run(string tool,string[] args,int seconds=30,string cwd="") {
            try { return tools.Run(tool,args,Math.Min(seconds,NativeSeconds),cwd,cancel); }
            catch(TimeoutException) {throw Error(InstallStarted?"Время ожидания истекло. Проверьте установку на iPhone.":"iPhone не отвечает. Разблокируйте его и проверьте USB-подключение.");}
        }
        static bool HasError(ToolResult r) {return Regex.IsMatch(r.Text,@"(?im)^\s*ERROR\b");}
        public static bool ValidId(string id) {return id!=null && Regex.IsMatch(id,@"\A(?:[a-fA-F0-9]{40}|[a-fA-F0-9]{8}-[a-fA-F0-9]{16})\z");}
        public static int[] VersionParts(string value) {
            if(value==null||!Regex.IsMatch(value,@"\A[0-9]+(?:\.[0-9]+){0,3}\z"))return null;
            var result=new int[4];var parts=value.Split('.');
            for(int i=0;i<parts.Length;i++)if(!Int32.TryParse(parts[i],out result[i]))return null;
            return result;
        }
        public static int? CompareVersions(string current,string minimum) {
            var a=VersionParts(current);var b=VersionParts(minimum);if(a==null||b==null)return null;
            for(int i=0;i<4;i++)if(a[i]!=b[i])return a[i].CompareTo(b[i]);return 0;
        }
        static string Clean(string value) {value=Regex.Replace(value??"",@"[\x00-\x1f\x7f]","");return value.Length>100?value.Substring(0,100):value;}
        public string[] Ids() {
            var r=Run("idevice_id",new[]{"-l"},20);
            if(r.Code!=0||HasError(r))throw Error("Не удалось обнаружить iPhone. Проверьте USB-кабель и наличие Apple Devices на компьютере.");
            var ids=Regex.Split(r.Out,@"[\r\n]+").Select(s=>s.Trim()).Where(s=>s.Length>0).ToArray();
            if(ids.Any(id=>!ValidId(id)))throw Error("Не удалось прочитать список iPhone. Проверьте USB-подключение.");
            return ids.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        }
        string DeviceValue(string id,string key) {
            var r=Run("ideviceinfo",new[]{"-s","-u",id,"-k",key},20);
            return r.Code==0&&!HasError(r)?Clean(Regex.Split(r.Out.Trim(),@"[\r\n]")[0]):"";
        }
        public Device Info(string id,bool disambiguate=false) {
            if(!ValidId(id))throw Error("Не удалось прочитать список iPhone. Проверьте USB-подключение.");
            string name=DeviceValue(id,"DeviceName"),product=DeviceValue(id,"ProductType"),version=DeviceValue(id,"ProductVersion"),model;
            if(!Regex.IsMatch(product,@"\A[A-Za-z]+\d+,\d+\z"))product="";
            if(VersionParts(version)==null)version="";
            if(!Models.Names.TryGetValue(product,out model))model=product.Length>0?product:"iPhone";
            return new Device {Id=id,Name=name.Length>0?name:"iPhone",ProductType=product,Version=version,Display=model+" • "+(version.Length>0?"iOS "+version:text.Get("iOS неизвестна"))+(disambiguate?" ("+id.Substring(id.Length-6)+")":"")};
        }
        public Device[] Devices() {var ids=Ids();return ids.Select(id=>Info(id,ids.Length>1)).ToArray();}
        public static string PairState(ToolResult r,string deviceId) {
            string id=Regex.Escape(deviceId);
            if(r.Code==0)return Regex.IsMatch(r.Text,@"(?im)^SUCCESS:\s*(?:Validated pairing with|Paired with) device "+id+@"\s*$")&&!HasError(r)?"ready":"failed";
            if(Regex.IsMatch(r.Text,@"(?im)^ERROR: Device "+id+@" said that the user denied the trust dialog\.\s*$"))return "denied";
            if(Regex.IsMatch(r.Text,@"(?im)^ERROR: Could not validate with device "+id+@" because a passcode is set\. Please enter the passcode on the device and retry\.\s*$"))return "locked";
            if(Regex.IsMatch(r.Text,@"(?im)^ERROR: Please accept the trust dialog on the screen of device "+id+@", then attempt to pair again\.\s*$"))return "pending";
            if(Regex.IsMatch(r.Text,@"(?im)^ERROR: Device "+id+@" is not paired with this host\s*$"))return "missing";
            if(Regex.IsMatch(r.Text,@"(?i)No device found|Could not connect to lockdownd"))return "disconnected";
            return "failed";
        }
        void PairError(string state) {
            if(state=="denied")throw Error("На iPhone отклонено доверие компьютеру. Подключите его заново и нажмите «Доверять».");
            if(state=="locked")throw Error("Разблокируйте iPhone и повторите установку.");
            if(state=="disconnected")throw Error("Не удалось подключиться к iPhone. Проверьте USB-кабель и повторите установку.");
            throw Error("Не удалось подтвердить доверие iPhone. Разблокируйте его и повторите установку.");
        }
        public void Pair(string id) {
            string state=PairState(Run("idevicepair",new[]{"-u",id,"validate"}),id);
            if(state=="ready")return;
            if(state!="missing"&&state!="pending")PairError(state);
            Status(text.Get("Разблокируйте iPhone и нажмите «Доверять»."));var watch=Stopwatch.StartNew();
            while(watch.Elapsed.TotalSeconds<PairingSeconds) {
                cancel.ThrowIfCancellationRequested();
                int remaining=Math.Max(1,(int)Math.Ceiling(PairingSeconds-watch.Elapsed.TotalSeconds));
                state=PairState(Run("idevicepair",new[]{"-u",id,"pair"},Math.Min(30,remaining)),id);
                if(state=="ready")return;if(state!="pending")PairError(state);
                if(cancel.WaitHandle.WaitOne(Math.Min(1000,remaining*1000)))cancel.ThrowIfCancellationRequested();
            }
            throw Error("Доверие не подтверждено. Нажмите «Доверять» на iPhone и повторите установку.");
        }
        public Ipa Inspect(string path) {
            if(String.IsNullOrWhiteSpace(path)||!File.Exists(path))throw Error("Выберите существующий файл IPA.");
            if(!String.Equals(Path.GetExtension(path),".ipa",StringComparison.OrdinalIgnoreCase))throw Error("Выберите файл с расширением .ipa.");
            try {
                using(var file=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read)) {
                    Dictionary<string,string> values;
                    using(var zip=new ZipArchive(file,ZipArchiveMode.Read,true)) {
                        var entries=zip.Entries.Where(e=>Regex.IsMatch(e.FullName,@"\APayload/[^/\\]+\.app/Info\.plist\z")).ToArray();
                        if(entries.Length!=1||entries[0].Length<=0||entries[0].Length>10485760)throw new InvalidDataException();
                        using(var entry=entries[0].Open())using(var bytes=new MemoryStream()) {
                            var buffer=new byte[65536];int count;
                            while((count=entry.Read(buffer,0,buffer.Length))>0){cancel.ThrowIfCancellationRequested();if(bytes.Length+count>10485760)throw new InvalidDataException();bytes.Write(buffer,0,count);}
                            values=IpaDeskMetadata.Read(bytes.ToArray());
                        }
                    }
                    string bundle,name,minimum;
                    if(!values.TryGetValue("CFBundleIdentifier",out bundle)||bundle.Length>255||!Regex.IsMatch(bundle,@"\A[A-Za-z0-9][A-Za-z0-9.\-]*\z"))throw new InvalidDataException();
                    if(!values.TryGetValue("CFBundleDisplayName",out name)||String.IsNullOrWhiteSpace(name))values.TryGetValue("CFBundleName",out name);
                    if(String.IsNullOrWhiteSpace(name))name=Path.GetFileNameWithoutExtension(path);
                    values.TryGetValue("MinimumOSVersion",out minimum);if(VersionParts(minimum)==null)minimum="";
                    file.Position=0;string hash;
                    using(var sha=System.Security.Cryptography.SHA256.Create()) {
                        var buffer=new byte[1048576];int count;
                        while((count=file.Read(buffer,0,buffer.Length))>0){cancel.ThrowIfCancellationRequested();sha.TransformBlock(buffer,0,count,buffer,0);}
                        sha.TransformFinalBlock(new byte[0],0,0);hash=BitConverter.ToString(sha.Hash).Replace("-","").ToLowerInvariant();
                    }
                    return new Ipa {BundleId=bundle,Name=Clean(name),Minimum=minimum,CredentialKey="sha256:"+hash};
                }
            } catch(OperationCanceledException){throw;} catch {throw Error("В файле IPA не найдено корректное приложение.");}
        }
        public string Failure(string message) {
            if(Regex.IsMatch(message,@"(?i)ApplicationVerificationFailed|BundleVerificationFailed|provisioning profile|0xe800801[568c]|0xe8008029|0xe8008001"))return text.Get("iPhone отклонил подпись или разрешение на установку этого IPA.");
            if(Regex.IsMatch(message,@"(?i)MinimumOSVersion|OSVersionTooLow|UnsupportedOSVersion|not supported.*version|requires.*iOS"))return text.Get("Для этого IPA требуется другая версия iOS.");
            if(Regex.IsMatch(message,@"(?i)DeviceFamilyNotSupported|Architecture|Incompatible"))return text.Get("Это приложение несовместимо с выбранным iPhone.");
            if(Regex.IsMatch(message,@"(?i)NoSpace|not enough.*space|disk.*full|InsufficientStorage"))return text.Get("На iPhone недостаточно свободного места.");
            if(Regex.IsMatch(message,@"(?i)DeviceLocked|PasswordProtected|passcode|lockdownd|pairing|trust"))return text.Get("Разблокируйте iPhone, нажмите «Доверять» и повторите установку.");
            if(Regex.IsMatch(message,@"(?i)Device removed|No device found|connection|AFC.*error|could not connect"))return text.Get("Соединение с iPhone прервано. Проверьте USB-кабель и результат установки на телефоне.");
            var match=Regex.Match(message,"Got error\\s+\"([A-Za-z0-9_\\-]{1,80})\"");
            return match.Success?text.Get("iPhone отклонил установку: ")+match.Groups[1].Value+".":text.Get("Установка не подтверждена. Проверьте сообщение на iPhone и совместимость IPA.");
        }
        bool Installed(string id,string bundle) {
            var r=Run("ideviceinstaller",new[]{"-u",id,"-l","-o","xml"},120);if(r.Code!=0||HasError(r))return false;
            try {
                var settings=new XmlReaderSettings {DtdProcessing=DtdProcessing.Ignore,XmlResolver=null,MaxCharactersInDocument=16777216,MaxCharactersFromEntities=1024};
                var doc=new XmlDocument {XmlResolver=null};
                using(var input=new StringReader(r.Out))using(var reader=XmlReader.Create(input,settings))doc.Load(reader);
                foreach(XmlNode dict in doc.SelectNodes("/plist/array/dict"))foreach(XmlNode key in dict.ChildNodes) {
                    if(key.Name!="key"||key.InnerText!="CFBundleIdentifier")continue;
                    var value=key.NextSibling;while(value!=null&&value.NodeType!=XmlNodeType.Element)value=value.NextSibling;
                    if(value!=null&&value.Name=="string"&&value.InnerText==bundle)return true;
                }
            } catch {return false;}return false;
        }
        public Ipa Install(string source,string id) {
            InstallStarted=false;string stage=null;
            try {
                cancel.ThrowIfCancellationRequested();if(!ValidId(id))throw Error("Подключите iPhone по USB и нажмите «Обновить».");
                if(!File.Exists(source))throw Error("Выберите существующий файл IPA.");
                if(!String.Equals(Path.GetExtension(source),".ipa",StringComparison.OrdinalIgnoreCase))throw Error("Выберите файл с расширением .ipa.");
                Status(text.Get("Проверка IPA…"));Directory.CreateDirectory(workRoot);
                if(Files.IsReparse(workRoot))throw new IOException(text.Choose("Invalid temporary folder.","Недопустимая временная папка."));
                stage=Path.Combine(workRoot,".work-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(stage);string payload=Path.Combine(stage,"payload.ipa");
                using(var input=new FileStream(source,FileMode.Open,FileAccess.Read,FileShare.Read))using(var output=new FileStream(payload,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {
                    var buffer=new byte[1048576];int count;while((count=input.Read(buffer,0,buffer.Length))>0){cancel.ThrowIfCancellationRequested();output.Write(buffer,0,count);}
                }
                // Keep the staged IPA read-locked until the native installer and confirmation finish.
                using(var hold=new FileStream(payload,FileMode.Open,FileAccess.Read,FileShare.Read)) {
                    var app=Inspect(payload);var ids=Ids();
                    if(!ids.Contains(id,StringComparer.OrdinalIgnoreCase))throw Error("iPhone отключён. Проверьте USB-кабель и нажмите «Обновить».");
                    Pair(id);var device=Info(id,ids.Length>1);DeviceUpdated(device);
                    if(CompareVersions(device.Version,app.Minimum)<0)throw Error("Для приложения нужна iOS {0} или новее. На iPhone установлена iOS {1}.",app.Minimum,device.Version);
                    cancel.ThrowIfCancellationRequested();Status(text.Get("Установка…"));InstallStarted=true;
                    var r=Run("ideviceinstaller",new[]{"-u",id,"-i","payload.ipa"},1800,stage);
                    if(r.Code!=0||HasError(r)||!Regex.IsMatch(r.Out,@"(?m)(?:^|[\r\n])Install:\s*Complete(?:\s*\(100%\))?\s*(?:[\r\n]|$)"))throw new InvalidOperationException(Failure(r.Text));
                    if(!Installed(id,app.BundleId))throw Error("iPhone сообщил об установке, но приложение не найдено в списке. Проверьте результат на телефоне.");
                    return app;
                }
            } finally {
                if(stage!=null&&Directory.Exists(stage)&&Path.GetDirectoryName(stage)==workRoot&&Regex.IsMatch(Path.GetFileName(stage),@"\A\.work-[a-f0-9]{32}\z")) {
                    try {if(Files.IsReparse(stage))throw new IOException();File.Delete(Path.Combine(stage,"payload.ipa"));Directory.Delete(stage,false);}
                    catch {Status(text.Get("Не удалось удалить временную копию IPA: ")+stage);}
                }
            }
        }
    }
}
