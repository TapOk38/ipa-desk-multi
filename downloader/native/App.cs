using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

[assembly:AssemblyTitle("TapOk IPA Downloader")]
[assembly:AssemblyProduct("TapOk IPA Downloader")]
[assembly:AssemblyDescription("Download App Store applications as IPA files")]
[assembly:AssemblyVersion("0.6.0.0")]
[assembly:AssemblyFileVersion("0.6.0.1")]
[assembly:AssemblyInformationalVersion("0.6.0-test.1")]

namespace TapOk.Downloader {
    static class Program {
        [DllImport("shell32.dll")]static extern int SHGetKnownFolderPath(ref Guid folder,uint flags,IntPtr token,out IntPtr path);
        static string Downloads(){var id=new Guid("374DE290-123F-4565-9164-39C4925E467B");IntPtr path;int code=SHGetKnownFolderPath(ref id,0,IntPtr.Zero,out path);if(code!=0)Marshal.ThrowExceptionForHR(code);try{return Marshal.PtrToStringUni(path);}finally{Marshal.FreeCoTaskMem(path);}}
        [STAThread]static int Main(string[] args){
            string fixture=null;try{
                if(args.Length>0){if(args.Length!=2||args[0]!="--smoke-test")throw new ArgumentException("Unknown arguments.");fixture=Path.GetFullPath(args[1]);}
                string root=fixture==null?Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"IPA-Desk-Multi"):Path.Combine(fixture,"accounts");
                string output=Path.Combine(fixture==null?Downloads():Path.Combine(fixture,"Downloads"),"TapOk IPA Downloader");Directory.CreateDirectory(root);
                string lang=Path.Combine(root,"language.txt");Texts.Russian=File.Exists(lang)&&File.ReadAllText(lang).Trim()=="ru";
                Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
                using(var gate=new FileStream(Path.Combine(root,"accounts.lock"),FileMode.OpenOrCreate,FileAccess.ReadWrite,FileShare.None))using(var form=new MainForm(root,output)){
                    if(fixture!=null){form.ShowInTaskbar=false;form.Opacity=0;form.Show();form.PerformLayout();Application.DoEvents();form.Smoke(fixture);}
                    else Application.Run(form);
                }return 0;
            }catch(Exception e){if(fixture!=null){Directory.CreateDirectory(fixture);File.WriteAllText(Path.Combine(fixture,"error.txt"),e.ToString());}else MessageBox.Show(e.Message,"TapOk IPA Downloader",MessageBoxButtons.OK,MessageBoxIcon.Error);return 1;}
        }
    }
    public sealed class MainForm : Form {
        readonly string root,output;List<Account> accounts;List<AppEntry> apps;
        readonly ListView accountView=new ListView(),appView=new ListView();readonly ComboBox language=new ComboBox();
        readonly TextBox log=new TextBox();readonly Label status=new Label();readonly List<Control> managed=new List<Control>();
        readonly Dictionary<Control,string[]> translations=new Dictionary<Control,string[]>();
        Button history,start,stop;bool refreshing,busy,closing;CancellationTokenSource cancel;
        static string T(string ru,string en){return Texts.T(ru,en);}
        public MainForm(string root,string output){
            this.root=root;this.output=output;accounts=Data.ReadAccounts(Path.Combine(root,"accounts.json"));apps=Data.ReadApps(Path.Combine(root,"download-list.json"));
            Text="TapOk IPA Downloader";ClientSize=new Size(1000,820);MinimumSize=new Size(860,720);StartPosition=FormStartPosition.CenterScreen;AutoScaleMode=AutoScaleMode.Dpi;Font=new Font("Segoe UI",10);BackColor=Color.FromArgb(245,247,251);
            var layout=new TableLayoutPanel{Dock=DockStyle.Fill,Padding=new Padding(22),ColumnCount=1,RowCount=9};foreach(int size in new[]{62,40,154,40,172,48,30})layout.RowStyles.Add(new RowStyle(SizeType.Absolute,size));layout.RowStyles.Add(new RowStyle(SizeType.Percent,100));layout.RowStyles.Add(new RowStyle(SizeType.Absolute,0));Controls.Add(layout);
            var header=new TableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=2};header.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));header.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,135));
            header.Controls.Add(new Label{Text=Text,Dock=DockStyle.Fill,Font=new Font("Segoe UI",23,FontStyle.Bold),ForeColor=Color.FromArgb(24,38,68)},0,0);
            language.DropDownStyle=ComboBoxStyle.DropDownList;language.Items.AddRange(new object[]{"English","Русский"});language.SelectedIndex=Texts.Russian?1:0;language.Dock=DockStyle.Top;header.Controls.Add(language,1,0);managed.Add(language);layout.Controls.Add(header,0,0);
            var appBar=Bar();ButtonOf(appBar,"Добавить приложение","Add app",()=>EditApp(false));ButtonOf(appBar,"Изменить","Edit",()=>EditApp(true));ButtonOf(appBar,"Удалить","Remove",RemoveApp);ButtonOf(appBar,"Выбрать все","Select all",()=>SetApps(true));ButtonOf(appBar,"Снять выбор","Clear selection",()=>SetApps(false));layout.Controls.Add(appBar,0,1);
            Configure(appView);appView.Columns.Add("",470);appView.Columns.Add("App Store ID",240);appView.ItemChecked+=(s,e)=>{if(refreshing||busy)return;Try(()=>{var entry=(AppEntry)e.Item.Tag;var next=apps.Select(a=>new AppEntry{Id=a.Id,Name=a.Name,Selected=a.Id==entry.Id?e.Item.Checked:a.Selected}).ToList();Data.SaveApps(Path.Combine(root,"download-list.json"),next);apps=next;});};managed.Add(appView);layout.Controls.Add(appView,0,2);
            var accountBar=Bar();ButtonOf(accountBar,"Добавить учётку","Add account",()=>EditAccount(false));ButtonOf(accountBar,"Изменить","Edit",()=>EditAccount(true));ButtonOf(accountBar,"Удалить","Remove",RemoveAccount);ButtonOf(accountBar,"Выбрать все","Select all",()=>SetAccounts(true));ButtonOf(accountBar,"Снять выбор","Clear selection",()=>SetAccounts(false));history=ButtonOf(accountBar,"История покупок","Purchase history",()=>BeginWork(true));layout.Controls.Add(accountBar,0,3);
            Configure(accountView);accountView.Columns.Add("Apple ID",300);accountView.Columns.Add("",230);accountView.Columns.Add("",360);managed.Add(accountView);layout.Controls.Add(accountView,0,4);
            var actions=Bar();start=ButtonOf(actions,"Скачать IPA","Download IPA",()=>BeginWork(false));start.BackColor=Color.FromArgb(41,94,220);start.ForeColor=Color.White;
            stop=ButtonOf(actions,"Отмена","Cancel",()=>{if(cancel!=null){cancel.Cancel();stop.Enabled=false;status.Text=T("Отмена…","Cancelling…");}});managed.Remove(stop);stop.Enabled=false;ButtonOf(actions,"Открыть папку","Open folder",()=>{Directory.CreateDirectory(output);Process.Start(new ProcessStartInfo(output){UseShellExecute=true});});layout.Controls.Add(actions,0,5);
            status.Dock=DockStyle.Fill;status.Text=T("Выберите приложения и учётки.","Select apps and accounts.");layout.Controls.Add(status,0,6);
            log.Multiline=true;log.ReadOnly=true;log.ScrollBars=ScrollBars.Vertical;log.Dock=DockStyle.Fill;log.BackColor=Color.FromArgb(22,31,50);log.ForeColor=Color.White;log.Font=new Font("Consolas",9);layout.Controls.Add(log,0,7);
            language.SelectedIndexChanged+=(s,e)=>Try(()=>{Texts.Russian=language.SelectedIndex==1;Data.Atomic(Path.Combine(root,"language.txt"),Texts.Russian?"ru":"en");Translate();});
            FormClosing+=(s,e)=>{if(busy){e.Cancel=true;closing=true;if(cancel!=null)cancel.Cancel();stop.Enabled=false;}};
            RefreshApps();RefreshAccounts();Translate();
        }
        static FlowLayoutPanel Bar(){return new FlowLayoutPanel{Dock=DockStyle.Fill,WrapContents=false,AutoScroll=true};}
        static void Configure(ListView list){list.Dock=DockStyle.Fill;list.View=View.Details;list.CheckBoxes=true;list.FullRowSelect=true;list.HideSelection=false;list.MultiSelect=false;}
        Button ButtonOf(FlowLayoutPanel bar,string ru,string en,Action action){var b=new Button{AutoSize=true,Height=33,MinimumSize=new Size(94,33),FlatStyle=FlatStyle.Flat,Margin=new Padding(0,1,6,1)};b.FlatAppearance.BorderColor=Color.FromArgb(207,215,227);translations[b]=new[]{ru,en};b.Text=T(ru,en);b.Click+=(s,e)=>Try(action);bar.Controls.Add(b);managed.Add(b);return b;}
        void Try(Action action){try{action();}catch(Exception e){MessageBox.Show(this,e.Message,Text,MessageBoxButtons.OK,MessageBoxIcon.Error);RefreshApps();}}
        void Translate(){foreach(var item in translations)item.Key.Text=T(item.Value[0],item.Value[1]);appView.Columns[0].Text=T("Приложение","App");accountView.Columns[1].Text=T("Описание","Description");accountView.Columns[2].Text=T("Результат","Result");if(!busy)status.Text=T("Выберите приложения и учётки.","Select apps and accounts.");}
        void RefreshApps(){refreshing=true;try{appView.Items.Clear();foreach(var a in apps){var row=new ListViewItem(String.IsNullOrEmpty(a.Name)?a.Id:a.Name){Tag=a,Checked=a.Selected};row.SubItems.Add(a.Id);appView.Items.Add(row);}}finally{refreshing=false;}}
        void RefreshAccounts(){var selected=new HashSet<string>(accountView.CheckedItems.Cast<ListViewItem>().Select(i=>((Account)i.Tag).Id));accountView.Items.Clear();foreach(var a in accounts){var row=new ListViewItem(a.Email){Tag=a,Checked=selected.Contains(a.Id)};row.SubItems.Add(a.Description??"");row.SubItems.Add("");accountView.Items.Add(row);}}
        void SetApps(bool value){var next=apps.Select(a=>new AppEntry{Id=a.Id,Name=a.Name,Selected=value}).ToList();Data.SaveApps(Path.Combine(root,"download-list.json"),next);apps=next;RefreshApps();}
        void SetAccounts(bool value){foreach(ListViewItem item in accountView.Items)item.Checked=value;}
        void EditApp(bool edit){AppEntry old=edit&&appView.SelectedItems.Count>0?(AppEntry)appView.SelectedItems[0].Tag:null;if(edit&&old==null)return;
            var values=InputDialog.Ask(this,T("Приложение","App"),new[]{T("Ссылка App Store или ID","App Store link or ID"),T("Название (необязательно)","Name (optional)")},new[]{old==null?"":old.Id,old==null?"":old.Name},-1);if(values==null)return;
            var next=apps.Where(a=>old==null||a.Id!=old.Id).ToList();var entry=new AppEntry{Id=Data.Id(values[0]),Name=values[1].Trim(),Selected=old==null||old.Selected};if(old==null)next.Add(entry);else next.Insert(apps.FindIndex(a=>a.Id==old.Id),entry);Data.SaveApps(Path.Combine(root,"download-list.json"),next);apps=next;RefreshApps();}
        void RemoveApp(){if(appView.SelectedItems.Count==0)return;var old=(AppEntry)appView.SelectedItems[0].Tag;var next=apps.Where(a=>a.Id!=old.Id).ToList();Data.SaveApps(Path.Combine(root,"download-list.json"),next);apps=next;RefreshApps();}
        void EditAccount(bool edit){Account old=edit&&accountView.SelectedItems.Count>0?(Account)accountView.SelectedItems[0].Tag:null;if(edit&&old==null)return;
            var values=InputDialog.Ask(this,T("Учётная запись","Account"),new[]{"Apple ID",old==null?T("Пароль","Password"):T("Новый пароль (пусто — сохранить прежний)","New password (blank to keep current)"),T("Описание","Description")},new[]{old==null?"":old.Email,"",old==null?"":old.Description},1);if(values==null)return;
            if(old==null && values[1].Length==0)throw new ArgumentException(T("Введите пароль.","Enter a password."));
            var entry=new Account{Id=old==null?Guid.NewGuid().ToString("N"):old.Id,Email=values[0].Trim(),Description=values[2].Trim(),Password=values[1].Length==0?old.Password:Data.Protect(values[1])};
            var next=accounts.Where(a=>a!=old).ToList();if(old==null)next.Add(entry);else next.Insert(accounts.IndexOf(old),entry);Data.SaveAccounts(Path.Combine(root,"accounts.json"),next);accounts=next;RefreshAccounts();}
        void RemoveAccount(){if(accountView.SelectedItems.Count==0)return;var old=(Account)accountView.SelectedItems[0].Tag;if(MessageBox.Show(this,T("Удалить учётку ","Remove account ")+old.Email+"?",Text,MessageBoxButtons.YesNo,MessageBoxIcon.Question)!=DialogResult.Yes)return;var next=accounts.Where(a=>a!=old).ToList();Data.SaveAccounts(Path.Combine(root,"accounts.json"),next);accounts=next;RefreshAccounts();}
        void SetBusy(bool value){busy=value;foreach(var c in managed)c.Enabled=!value;stop.Enabled=value;}
        void Ui(Action a){if(!IsDisposed && IsHandleCreated)BeginInvoke(a);}
        void Log(string text){Ui(()=>{status.Text=text;log.AppendText("["+DateTime.Now.ToString("HH:mm:ss")+"] "+text+Environment.NewLine);});}
        string Code(string email){try{return (string)Invoke(new Func<string>(()=>{if(cancel.IsCancellationRequested)throw new OperationCanceledException();return InputDialog.Code(this,email,cancel.Token);}));}catch(TargetInvocationException e){if(e.InnerException is OperationCanceledException)throw new OperationCanceledException();throw;}}
        async void BeginWork(bool purchases){
            if(busy)return;var selected=purchases?(accountView.SelectedItems.Count>0?new List<Account>{(Account)accountView.SelectedItems[0].Tag}:new List<Account>()):accountView.CheckedItems.Cast<ListViewItem>().Select(i=>(Account)i.Tag).ToList();var targets=apps.Where(a=>a.Selected).ToList();
            if(selected.Count==0 || (!purchases&&targets.Count==0)){MessageBox.Show(this,T("Выберите учётку и приложения. Для истории покупок выделите строку учётки.","Select accounts and apps. For purchase history, highlight an account row."),Text);return;}
            SetBusy(true);cancel=new CancellationTokenSource();List<AppEntry> found=null;int ok=0,failed=0;
            try{await Task.Run(()=>{
                string tool=Component.Prepare(root,cancel.Token,Log);
                foreach(var a in selected){cancel.Token.ThrowIfCancellationRequested();Engine engine=null;Session session=null;
                    Action<string> result=text=>Ui(()=>{foreach(ListViewItem row in accountView.Items)if(((Account)row.Tag).Id==a.Id)row.SubItems[2].Text=text;});
                    try{
                        string accountFolder=Regex.Replace(a.Email,@"[^a-zA-Z0-9@._-]","_");if(accountFolder.Length>70)accountFolder=accountFolder.Substring(0,70);accountFolder+="-"+a.Id.Substring(0,8);
                        var destinations=new Dictionary<string,string>();foreach(var app in targets){string folder=Path.Combine(output,Data.Id(app.Id),accountFolder);if(purchases)break;Directory.CreateDirectory(folder);string probe=Path.Combine(folder,Guid.NewGuid().ToString("N")+".write-test");File.WriteAllText(probe,"");File.Delete(probe);destinations[app.Id]=folder;}
                        session=new Session(root,a.Email);var work=purchases?session.Root:destinations[targets[0].Id];engine=new Engine(new NativeTool(tool,session.Environment),session.Passphrase,s=>{Log(s);result(s);},Code,cancel.Token);engine.Login(a,work);
                        if(purchases){found=engine.Purchases(work,DateTime.Now.Year);result(T("Список получен","List received"));}
                        else{int accountOk=0,accountErrors=0;foreach(var app in targets){cancel.Token.ThrowIfCancellationRequested();try{var path=engine.Download(app,a,destinations[app.Id]);ok++;accountOk++;Log(T("Сохранён: ","Saved: ")+path);}catch(OperationCanceledException){throw;}catch(Exception e){failed++;accountErrors++;Log(app.Id+": "+engine.Redact(e.Message));}}result(T("Скачано: ","Downloaded: ")+accountOk+T("; ошибок: ","; errors: ")+accountErrors);}
                    }catch(OperationCanceledException){throw;}catch(Exception e){failed++;string error=engine==null?e.Message:engine.Redact(e.Message);Log(error);result(T("Ошибка — см. журнал","Error — see log"));if(purchases)throw new InvalidOperationException(error);}
                    finally{if(session!=null)try{session.Dispose();}catch{Log(T("Не удалось удалить временные данные входа.","Could not remove temporary sign-in data."));}}
                }
            });if(purchases&&found!=null&&!closing){var selectedApps=PurchaseDialog.Select(this,found);if(selectedApps!=null){var next=Data.Merge(apps,selectedApps);Data.SaveApps(Path.Combine(root,"download-list.json"),next);apps=next;RefreshApps();}}status.Text=purchases?T("Список получен.","List received."):T("Скачано: ","Downloaded: ")+ok+T("; ошибок: ","; errors: ")+failed;
            }catch(OperationCanceledException){status.Text=T("Отменено.","Cancelled.");}catch(Exception e){log.AppendText(e.Message+Environment.NewLine);status.Text=T("Ошибка — см. журнал.","Error — see log.");}
            finally{SetBusy(false);cancel.Dispose();cancel=null;if(closing)Close();}
        }
        public void Smoke(string fixture){bool original=Texts.Russian;language.SelectedIndex=original?0:1;Application.DoEvents();if(start.Text!=(original?"Download IPA":"Скачать IPA"))throw new Exception("Language switch failed.");language.SelectedIndex=original?1:0;SetBusy(true);if(history.Enabled||language.Enabled||appView.Enabled||accountView.Enabled)throw new Exception("Busy controls unlocked.");SetBusy(false);
            using(var bitmap=new Bitmap(Width,Height)){DrawToBitmap(bitmap,new Rectangle(0,0,Width,Height));bitmap.Save(Path.Combine(fixture,"interface.png"));}
            Data.Atomic(Path.Combine(fixture,"interface.json"),Data.Json().Serialize(new {Language=Texts.Russian?"ru":"en",Title=Text,Download=start.Text,AccountCount=accounts.Count,AppCount=apps.Count,Output=output,SwitchVerified=true}));
        }
    }
    static class InputDialog {
        public static string[] Ask(IWin32Window owner,string title,string[] labels,string[] values,int password){
            using(var form=new Form{Text=title,ClientSize=new Size(490,65+labels.Length*62),StartPosition=FormStartPosition.CenterParent,FormBorderStyle=FormBorderStyle.FixedDialog,MaximizeBox=false,MinimizeBox=false,Font=new Font("Segoe UI",10)}){
                var boxes=new List<TextBox>();for(int i=0;i<labels.Length;i++){form.Controls.Add(new Label{Text=labels[i],Left=18,Top=10+i*62,Width=450});var box=new TextBox{Text=values[i]??"",Left=18,Top=34+i*62,Width=450,UseSystemPasswordChar=i==password};boxes.Add(box);form.Controls.Add(box);}
                var save=new Button{Text=Texts.T("Сохранить","Save"),Left=270,Top=form.ClientSize.Height-40,Width=95,DialogResult=DialogResult.OK};var cancel=new Button{Text=Texts.T("Отмена","Cancel"),Left=375,Top=save.Top,Width=95,DialogResult=DialogResult.Cancel};form.Controls.Add(save);form.Controls.Add(cancel);form.AcceptButton=save;form.CancelButton=cancel;return form.ShowDialog(owner)==DialogResult.OK?boxes.Select(b=>b.Text).ToArray():null;
            }
        }
        public static string Code(Form owner,string email,CancellationToken token){
            using(var form=new Form{Text=Texts.T("Код подтверждения","Verification code"),ClientSize=new Size(460,145),StartPosition=FormStartPosition.CenterParent,FormBorderStyle=FormBorderStyle.FixedDialog,MaximizeBox=false,MinimizeBox=false,Font=new Font("Segoe UI",10)}){
                form.Controls.Add(new Label{Text=email,Left=18,Top=15,Width=420});var input=new TextBox{Left=18,Top=48,Width=420,MaxLength=6};form.Controls.Add(input);var ok=new Button{Text="OK",Left=240,Top=92,Width=95,DialogResult=DialogResult.OK};var no=new Button{Text=Texts.T("Отмена","Cancel"),Left=343,Top=92,Width=95,DialogResult=DialogResult.Cancel};form.Controls.Add(ok);form.Controls.Add(no);form.AcceptButton=ok;form.CancelButton=no;
                using(token.Register(()=>{if(form.IsHandleCreated&&!form.IsDisposed)try{form.BeginInvoke(new Action(()=>form.Close()));}catch(InvalidOperationException){}})){if(token.IsCancellationRequested)throw new OperationCanceledException();if(form.ShowDialog(owner)!=DialogResult.OK)throw new OperationCanceledException();return input.Text.Trim();}
            }
        }
    }
    public sealed class PurchaseDialog : Form {
        readonly List<AppEntry> apps;readonly HashSet<string> checkedIds=new HashSet<string>();readonly ListView list=new ListView();readonly TextBox search=new TextBox();bool filling;
        public PurchaseDialog(List<AppEntry> apps){this.apps=apps;Text=Texts.T("История покупок","Purchase history");ClientSize=new Size(710,500);MinimumSize=new Size(570,400);StartPosition=FormStartPosition.CenterParent;Font=new Font("Segoe UI",10);
            var root=new TableLayoutPanel{Dock=DockStyle.Fill,Padding=new Padding(14),ColumnCount=1,RowCount=3};root.RowStyles.Add(new RowStyle(SizeType.Absolute,34));root.RowStyles.Add(new RowStyle(SizeType.Percent,100));root.RowStyles.Add(new RowStyle(SizeType.Absolute,42));Controls.Add(root);search.Dock=DockStyle.Fill;root.Controls.Add(search,0,0);search.TextChanged+=(s,e)=>Fill();list.Dock=DockStyle.Fill;list.View=View.Details;list.FullRowSelect=true;list.CheckBoxes=true;list.Columns.Add(Texts.T("Приложение","App"),435);list.Columns.Add("App Store ID",200);root.Controls.Add(list,0,1);list.ItemChecked+=(s,e)=>{if(filling)return;string id=((AppEntry)e.Item.Tag).Id;if(e.Item.Checked)checkedIds.Add(id);else checkedIds.Remove(id);};
            var bar=new FlowLayoutPanel{Dock=DockStyle.Fill};var all=new Button{Text=Texts.T("Выбрать все","Select all"),AutoSize=true};all.Click+=(s,e)=>{foreach(ListViewItem row in list.Items)row.Checked=true;};var clear=new Button{Text=Texts.T("Снять выбор","Clear selection"),AutoSize=true};clear.Click+=(s,e)=>{checkedIds.Clear();Fill();};var add=new Button{Text=Texts.T("Добавить выбранные","Add selected"),AutoSize=true,DialogResult=DialogResult.OK};var cancel=new Button{Text=Texts.T("Отмена","Cancel"),AutoSize=true,DialogResult=DialogResult.Cancel};bar.Controls.AddRange(new Control[]{all,clear,add,cancel});root.Controls.Add(bar,0,2);AcceptButton=add;CancelButton=cancel;Fill();}
        void Fill(){filling=true;list.BeginUpdate();try{list.Items.Clear();foreach(var a in apps.Where(a=>(a.Name??"").IndexOf(search.Text,StringComparison.OrdinalIgnoreCase)>=0||a.Id.Contains(search.Text))){var row=new ListViewItem(String.IsNullOrEmpty(a.Name)?a.Id:a.Name){Tag=a,Checked=checkedIds.Contains(a.Id)};row.SubItems.Add(a.Id);list.Items.Add(row);}}finally{list.EndUpdate();filling=false;}}
        public static List<AppEntry> Select(Form owner,List<AppEntry> apps){using(var form=new PurchaseDialog(apps)){if(form.ShowDialog(owner)!=DialogResult.OK)return null;return apps.Where(a=>form.checkedIds.Contains(a.Id)).ToList();}}
        public void SmokeFilter(){if(apps.Count<2)throw new ArgumentException();list.Items[0].Checked=true;search.Text=apps[1].Id;list.Items[0].Checked=true;search.Text="";if(checkedIds.Count!=2||list.CheckedItems.Count!=2)throw new Exception("Filter lost selections.");}
    }
}
