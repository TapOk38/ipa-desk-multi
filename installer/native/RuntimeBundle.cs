using System;
using System.IO;
using System.IO.Compression;
using System.Collections.Generic;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;

namespace TapOk.Installer {
    // Every process owns a fresh directory in TEMP. No downloads, elevation,
    // registry changes, PowerShell, or executable extraction beside the app.
    public sealed class RuntimeBundle : IDisposable {
        public string Root {get;private set;}
        public string Tools {get{return Path.Combine(Root,"tools");}}
        public string Work {get{return Path.Combine(Root,"work");}}
        readonly string temp;
        readonly List<string> files=new List<string>();
        readonly HashSet<string> directories=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        RuntimeBundle() {
            temp=Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar);
            Root=Path.Combine(temp,"TapOk-IPA-Installer-"+Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(Root);
            if(Files.IsReparse(Root))throw new IOException("Invalid temporary folder.");
        }
        public static RuntimeBundle Open() {
            var bundle=new RuntimeBundle();
            try {
                using(var input=Assembly.GetExecutingAssembly().GetManifestResourceStream("TapOk.USB.Components.zip")) {
                    if(input==null||input.Length>134217728)throw new InvalidDataException("Missing installation components.");
                    using(var sha=SHA256.Create())if(!String.Equals(BitConverter.ToString(sha.ComputeHash(input)).Replace("-",""),PinnedTools.PayloadSha256,StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("Installation components are damaged.");
                    input.Position=0;
                    using(var zip=new ZipArchive(input,ZipArchiveMode.Read)) {
                        long total=0;var names=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                        foreach(var entry in zip.Entries) {
                            if(entry.FullName.Contains("\\")||entry.FullName.Contains(":")||entry.FullName.Split('/').Any(p=>p==".."||p=="."||p.Length==0)||!names.Add(entry.FullName))throw new InvalidDataException("Invalid component path.");
                            string path=Path.GetFullPath(Path.Combine(bundle.Root,entry.FullName.Replace('/',Path.DirectorySeparatorChar)));
                            if(!path.StartsWith(bundle.Root+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase)||entry.Length<0||entry.Length>67108864||(total+=entry.Length)>134217728)throw new InvalidDataException("Invalid component archive.");
                            bundle.CreateDirectory(Path.GetDirectoryName(path));
                            using(var source=entry.Open())using(var target=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.None)) {
                                bundle.files.Add(path);var buffer=new byte[65536];long written=0;int count;
                                while((count=source.Read(buffer,0,buffer.Length))>0){written+=count;if(written>entry.Length)throw new InvalidDataException("Invalid component size.");target.Write(buffer,0,count);}
                                if(written!=entry.Length)throw new InvalidDataException("Incomplete component.");
                            }
                        }
                    }
                }
                bundle.CreateDirectory(bundle.Tools);bundle.CreateDirectory(bundle.Work);
                new ProcessTools(bundle.Tools,PinnedTools.Hashes).Verify();
                return bundle;
            } catch {bundle.Dispose();throw;}
        }
        void CreateDirectory(string path) {
            if(path==Root)return;
            if(!path.StartsWith(Root+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))throw new IOException("Invalid temporary path.");
            CreateDirectory(Path.GetDirectoryName(path));Directory.CreateDirectory(path);
            if(Files.IsReparse(path))throw new IOException("Invalid temporary folder.");directories.Add(path);
        }
        bool Safe(string path) {
            if(Path.GetDirectoryName(Root)!=temp||!path.StartsWith(Root+Path.DirectorySeparatorChar,StringComparison.OrdinalIgnoreCase))return false;
            for(string parent=Path.GetDirectoryName(path);parent!=null;parent=Path.GetDirectoryName(parent)) {
                if(!Directory.Exists(parent)||Files.IsReparse(parent))return false;if(parent==Root)return true;
            }
            return false;
        }
        public void Dispose() {
            // Delete only files extracted by this instance, never recurse through TEMP.
            foreach(var file in files)try{if(Safe(file)&&File.Exists(file)&&!Files.IsReparse(file))File.Delete(file);}catch{}
            foreach(var directory in directories.OrderByDescending(p=>p.Length))try{if(Safe(directory)&&Directory.Exists(directory)&&!Files.IsReparse(directory))Directory.Delete(directory,false);}catch{}
            try{if(Path.GetDirectoryName(Root)==temp&&Directory.Exists(Root)&&!Files.IsReparse(Root))Directory.Delete(Root,false);}catch{}
        }
    }
}
