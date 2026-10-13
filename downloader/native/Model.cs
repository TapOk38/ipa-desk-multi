using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Web.Script.Serialization;

namespace TapOk.Downloader {
    public sealed class Account { public string Id {get;set;} public string Email {get;set;} public string Password {get;set;} public string Description {get;set;} }
    public sealed class AppEntry { public string Id {get;set;} public string Name {get;set;} public bool Selected {get;set;} public AppEntry(){Selected=true;} }
    public static class Texts {
        public static bool Russian;
        public static string T(string ru,string en){return Russian?ru:en;}
    }
    public static class Data {
        public static JavaScriptSerializer Json(){return new JavaScriptSerializer {MaxJsonLength=32*1024*1024,RecursionLimit=64};}
        public static string Str(object v){return Convert.ToString(v,CultureInfo.InvariantCulture)??"";}
        public static object Get(Dictionary<string,object> d,string key){object v;return d!=null && d.TryGetValue(key,out v)?v:null;}
        public static object[] Items(object value){var list=value as System.Collections.IList;return list==null?null:list.Cast<object>().ToArray();}
        public static string Id(string value){
            value=(value??"").Trim();
            if(Regex.IsMatch(value,@"^[1-9][0-9]{0,17}$"))return value;
            Uri uri; if(Uri.TryCreate(value,UriKind.Absolute,out uri) && uri.Scheme=="https" && uri.Host=="apps.apple.com"){
                var m=Regex.Match(uri.AbsolutePath,@"/id([1-9][0-9]{0,17})/?$");if(m.Success)return m.Groups[1].Value;
            }
            throw new ArgumentException(Texts.T("Введите App Store ID или ссылку на приложение.","Enter an App Store ID or app link."));
        }
        public static string Protect(string value){var bytes=Encoding.UTF8.GetBytes(value);try{return Convert.ToBase64String(ProtectedData.Protect(bytes,Encoding.UTF8.GetBytes("IPA-Desk-Multi/accounts/v1"),DataProtectionScope.CurrentUser));}finally{Array.Clear(bytes,0,bytes.Length);}}
        public static string Unprotect(string value){byte[] bytes=null;try{bytes=ProtectedData.Unprotect(Convert.FromBase64String(value),Encoding.UTF8.GetBytes("IPA-Desk-Multi/accounts/v1"),DataProtectionScope.CurrentUser);return Encoding.UTF8.GetString(bytes);}catch{throw new InvalidOperationException(Texts.T("Не удалось открыть пароль. Измените учётку и сохраните пароль заново.","Cannot decrypt password. Edit the account and save the password again."));}finally{if(bytes!=null)Array.Clear(bytes,0,bytes.Length);}}
        public static void Atomic(string path,string content){Directory.CreateDirectory(Path.GetDirectoryName(path));string temp=path+"."+Guid.NewGuid().ToString("N")+".tmp";try{File.WriteAllText(temp,content,new UTF8Encoding(false));if(File.Exists(path))File.Replace(temp,path,null);else File.Move(temp,path);}finally{if(File.Exists(temp))File.Delete(temp);}}
        public static List<Account> ReadAccounts(string path){
            if(!File.Exists(path))return new List<Account>();
            try{
                var d=Json().Deserialize<Dictionary<string,object>>(File.ReadAllText(path));
                if(Str(Get(d,"Version"))!="1")throw new FormatException();
                var a=Json().ConvertToType<List<Account>>(Get(d,"Accounts"));ValidateAccounts(a);return a;
            }catch{throw new InvalidDataException(Texts.T("Не удалось прочитать accounts.json. Исходный файл не изменён.","Cannot read accounts.json. The original file has not been changed."));}
        }
        public static void ValidateAccounts(List<Account> accounts){
            if(accounts==null)throw new FormatException();
            var emails=new HashSet<string>(StringComparer.OrdinalIgnoreCase);var ids=new HashSet<string>();
            foreach(var a in accounts){if(a==null||!Regex.IsMatch(a.Id??"",@"^[a-f0-9]{32}$")||!Regex.IsMatch(a.Email??"",@"^\S+@\S+\.\S+$")||String.IsNullOrEmpty(a.Password)||!emails.Add(a.Email)||!ids.Add(a.Id))throw new ArgumentException(Texts.T("Некорректная или повторяющаяся учётная запись.","Invalid or duplicate account."));}
        }
        public static void SaveAccounts(string path,List<Account> a){ValidateAccounts(a);Atomic(path,Json().Serialize(new {Version=1,Accounts=a}));}
        public static List<AppEntry> ReadApps(string path){
            if(!File.Exists(path))return new List<AppEntry>();
            try{
                var d=Json().Deserialize<Dictionary<string,object>>(File.ReadAllText(path));var version=Str(Get(d,"Version"));var raw=Items(Get(d,"Apps"));if(raw==null)throw new FormatException();
                var a=new List<AppEntry>();
                foreach(var v in raw){
                    if(version=="1")a.Add(new AppEntry{Id=Id(Str(v)),Name=""});
                    else if(version=="2"){
                        var item=v as Dictionary<string,object>;if(item==null)throw new FormatException();
                        object selected=Get(item,"Selected");if(selected!=null && !(selected is bool))throw new FormatException();
                        a.Add(new AppEntry{Id=Id(Str(Get(item,"Id"))),Name=Str(Get(item,"Name")),Selected=selected==null || (bool)selected});
                    }else throw new FormatException();
                }
                ValidateApps(a);return a;
            }catch{throw new InvalidDataException(Texts.T("Не удалось прочитать список приложений. Исходный файл не изменён.","Cannot read the app list. The original file has not been changed."));}
        }
        public static void ValidateApps(List<AppEntry> apps){var seen=new HashSet<string>();foreach(var a in apps){if(Id(a.Id)!=a.Id||!seen.Add(a.Id)||(a.Name??"").Length>200)throw new ArgumentException(Texts.T("Некорректное или повторяющееся приложение.","Invalid or duplicate app."));}}
        public static void SaveApps(string path,List<AppEntry> a){ValidateApps(a);Atomic(path,Json().Serialize(new {Version=2,Apps=a}));}
        public static List<AppEntry> Merge(List<AppEntry> existing,IEnumerable<AppEntry> selected){var copy=existing.Select(a=>new AppEntry{Id=a.Id,Name=a.Name,Selected=a.Selected}).ToList();foreach(var a in selected){var found=copy.Find(x=>x.Id==a.Id);if(found==null)copy.Add(new AppEntry{Id=a.Id,Name=a.Name,Selected=true});else{found.Selected=true;if(String.IsNullOrEmpty(found.Name))found.Name=a.Name;}}ValidateApps(copy);return copy;}
        public static string Hash(string path){using(var s=File.OpenRead(path))using(var sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(s)).Replace("-","");}
        public static string HashText(string text){using(var sha=SHA256.Create())return BitConverter.ToString(sha.ComputeHash(Encoding.UTF8.GetBytes(text))).Replace("-","").ToLowerInvariant();}
    }
}
