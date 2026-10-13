using System;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Security.Cryptography;
using System.Threading;

namespace TapOk.Downloader {
    // This bundle is prepared at build time. Runtime component preparation is offline.
    public sealed class Component : IDisposable {
        public const string ExeHash="F053593059A5ADA859F2D28F8707BEB8D53F02B7830A9895C5913653A23A0CE2";
        public const string Resource="TapOk.IPATool.zip";
        public string Root {get;private set;}
        public string Exe {get{return Path.Combine(Root,"ipatool-cpp.exe");}}
        readonly string temp;
        FileStream lease;
        static readonly string[] Names={"ipatool-cpp.exe","LICENSE.txt","THIRD_PARTY.md","ipatool-MIT.txt","ipatool-cpp-MIT.txt"};
        Component(){temp=Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar);Root=Path.Combine(temp,"TapOk-IPA-Downloader-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(Root);if(Linked(Root))throw new IOException("Invalid temporary folder.");}
        static bool Linked(string path){return (File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0;}
        public static Component Open(CancellationToken token,Action<string> log){
            token.ThrowIfCancellationRequested();var component=new Component();
            try {
                log(Texts.T("Подготовка компонента IPATool…","Preparing IPATool component…"));
                using(var resource=Assembly.GetExecutingAssembly().GetManifestResourceStream(Resource)){
                    if(resource==null||resource.Length>83886080)throw new InvalidDataException("Missing IPATool component.");
                    using(var sha=SHA256.Create())if(BitConverter.ToString(sha.ComputeHash(resource)).Replace("-","")!=ComponentInfo.ZipHash)throw new InvalidDataException("Component archive SHA-256 mismatch.");
                    resource.Position=0;token.ThrowIfCancellationRequested();
                    using(var zip=new ZipArchive(resource,ZipArchiveMode.Read)){
                        if(zip.Entries.Count!=Names.Length)throw new InvalidDataException("Invalid component archive.");
                        foreach(string name in Names){
                            var entry=zip.GetEntry(name);long limit=name=="ipatool-cpp.exe"?83886080:1048576;
                            if(entry==null||entry.Length<1||entry.Length>limit)throw new InvalidDataException("Invalid component entry.");
                            using(var input=entry.Open())using(var output=new FileStream(Path.Combine(component.Root,name),FileMode.CreateNew,FileAccess.Write,FileShare.None)){
                                var buffer=new byte[65536];int count;long total=0;
                                while((count=input.Read(buffer,0,buffer.Length))>0){token.ThrowIfCancellationRequested();total+=count;if(total>entry.Length)throw new InvalidDataException("Invalid component length.");output.Write(buffer,0,count);}
                                if(total!=entry.Length)throw new InvalidDataException("Incomplete component.");
                            }
                        }
                    }
                }
                token.ThrowIfCancellationRequested();
                // Verify and hold the exact file open read-only until the UI closes.
                component.lease=new FileStream(component.Exe,FileMode.Open,FileAccess.Read,FileShare.Read);
                using(var sha=SHA256.Create())if(BitConverter.ToString(sha.ComputeHash(component.lease)).Replace("-","")!=ExeHash)throw new InvalidDataException("IPATool SHA-256 mismatch.");
                return component;
            }catch{component.Dispose();throw;}
        }
        public void Dispose(){
            if(lease!=null){lease.Dispose();lease=null;}
            if(!Directory.Exists(Root)||Path.GetDirectoryName(Root)!=temp||Linked(Root))return;
            // Only known files owned by this instance are eligible for cleanup.
            foreach(string name in Names)try{string path=Path.Combine(Root,name);if(File.Exists(path)&&!Linked(path))File.Delete(path);}catch{}
            try{Directory.Delete(Root,false);}catch{}
        }
    }
}
