using System;
using System.IO;
using System.Linq;
using System.Drawing;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Reflection;
[assembly:AssemblyTitle("TapOk IPA Installer — Windows")]
[assembly:AssemblyProduct("TapOk IPA Installer")]
[assembly:AssemblyVersion("1.2.0.0")]
[assembly:AssemblyFileVersion("1.2.0.0")]
[assembly:AssemblyInformationalVersion("1.2.0-test.2")]
namespace TapOk.Installer {
    public sealed class MainWindow : Form {
        readonly string dataRoot,workRoot;readonly bool smoke;readonly Texts text;readonly ITools tools;
        readonly TextBox path=new TextBox {ReadOnly=true,Dock=DockStyle.Fill},phone=new TextBox {ReadOnly=true,Dock=DockStyle.Fill};
        readonly TextBox log=new TextBox {Multiline=true,ReadOnly=true,ScrollBars=ScrollBars.Vertical,Dock=DockStyle.Fill,BackColor=Color.FromArgb(20,29,47),ForeColor=Color.White,Font=new Font("Consolas",10)};
        readonly ComboBox language=new ComboBox {DropDownStyle=ComboBoxStyle.DropDownList,Width=128,Anchor=AnchorStyles.Right};
        readonly Button browse=new Button(),refresh=new Button(),install=new Button(),stop=new Button(),account=new Button();
        readonly Label fileLabel=new Label(),status=new Label {AutoSize=false,Dock=DockStyle.Fill};
        public const string AppleDevicesUrl="https://apps.microsoft.com/detail/9np83lwlpz9k";
        readonly LinkLabel appleDevices=new LinkLabel {Dock=DockStyle.Fill,TextAlign=ContentAlignment.BottomLeft};
        readonly ProgressBar progress=new ProgressBar {Dock=DockStyle.Fill,Height=6,MarqueeAnimationSpeed=0};
        CancellationTokenSource cancel;Engine active;Device selected;bool closing;
        public MainWindow(string root,ITools native,bool test,string work) {
            dataRoot=root;workRoot=work;tools=native;smoke=test;text=new Texts(Files.ReadLanguage(root));
            Text="TapOk IPA Installer — Windows";ClientSize=new Size(840,620);MinimumSize=new Size(740,520);StartPosition=FormStartPosition.CenterScreen;
            Font=new Font("Segoe UI",10);BackColor=Color.FromArgb(246,247,252);AutoScaleMode=AutoScaleMode.Dpi;
            var grid=new TableLayoutPanel {Dock=DockStyle.Fill,Padding=new Padding(24),ColumnCount=3,RowCount=8};
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,92));grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute,140));
            foreach(int height in new[]{76,46,46,58,32,10})grid.RowStyles.Add(new RowStyle(SizeType.Absolute,height));grid.RowStyles.Add(new RowStyle(SizeType.Percent,100));grid.RowStyles.Add(new RowStyle(SizeType.Absolute,24));
            var header=new Label {Text="TapOk IPA Installer",Font=new Font("Segoe UI",23,FontStyle.Bold),ForeColor=Color.FromArgb(30,52,78),Dock=DockStyle.Fill,AutoSize=false};
            grid.Controls.Add(header,0,0);grid.SetColumnSpan(header,2);grid.Controls.Add(language,2,0);
            language.Items.AddRange(new object[]{"English","Русский"});language.SelectedIndex=text.Language=="ru"?1:0;
            fileLabel.Dock=DockStyle.Fill;fileLabel.TextAlign=ContentAlignment.MiddleLeft;grid.Controls.Add(fileLabel,0,1);grid.Controls.Add(path,1,1);grid.Controls.Add(browse,2,1);
            grid.Controls.Add(new Label {Text="iPhone",Dock=DockStyle.Fill,TextAlign=ContentAlignment.MiddleLeft},0,2);grid.Controls.Add(phone,1,2);grid.Controls.Add(refresh,2,2);
            var actions=new FlowLayoutPanel {Dock=DockStyle.Fill,WrapContents=false};actions.Controls.AddRange(new Control[]{install,stop,account});grid.Controls.Add(actions,0,3);grid.SetColumnSpan(actions,3);
            foreach(var button in new[]{browse,refresh,install,stop,account}) {button.Height=36;button.Width=120;button.FlatStyle=FlatStyle.Flat;button.Margin=new Padding(3,3,8,3);}
            browse.Dock=DockStyle.Fill;refresh.Dock=DockStyle.Fill;install.BackColor=Color.FromArgb(43,90,224);install.ForeColor=Color.White;account.Width=235;
            grid.Controls.Add(status,0,4);grid.SetColumnSpan(status,3);grid.Controls.Add(progress,0,5);grid.SetColumnSpan(progress,3);grid.Controls.Add(log,0,6);grid.SetColumnSpan(log,3);
            grid.Controls.Add(appleDevices,0,7);grid.SetColumnSpan(appleDevices,2);
            grid.Controls.Add(new Label {Text="1.2.0-test.2",ForeColor=Color.DimGray,Dock=DockStyle.Fill,TextAlign=ContentAlignment.BottomRight},2,7);
            appleDevices.LinkClicked+=delegate {try{System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(AppleDevicesUrl){UseShellExecute=true});}catch{MessageBox.Show(this,text.Choose("Open this address in your browser: ","Откройте адрес в браузере: ")+AppleDevicesUrl,"Apple Devices");}};
            Controls.Add(grid);ApplyLanguage();
            browse.Click+=delegate {using(var dialog=new OpenFileDialog {Filter="IPA (*.ipa)|*.ipa",CheckFileExists=true})if(dialog.ShowDialog(this)==DialogResult.OK)ChooseFile(dialog.FileName);};
            refresh.Click+=async delegate {await Scan();};install.Click+=async delegate {await StartInstall();};stop.Click+=delegate {Cancel();};account.Click+=delegate {Credentials(false);};
            language.SelectedIndexChanged+=delegate {text.Language=language.SelectedIndex==1?"ru":"en";ApplyLanguage();try{Files.AtomicWrite(Path.Combine(dataRoot,"language.txt"),System.Text.Encoding.UTF8.GetBytes(text.Language));}catch{Write(text.Get("Не удалось сохранить язык. При следующем запуске выбор может сброситься."));}};
            AllowDrop=true;DragEnter+=delegate(object s,DragEventArgs e){if(cancel==null&&e.Data.GetDataPresent(DataFormats.FileDrop))e.Effect=DragDropEffects.Copy;};
            DragDrop+=delegate(object s,DragEventArgs e){var files=e.Data.GetData(DataFormats.FileDrop) as string[];if(cancel==null&&files!=null&&files.Length==1)ChooseFile(files[0]);};
            FormClosing+=delegate(object s,FormClosingEventArgs e){if(cancel!=null){e.Cancel=true;closing=true;Cancel();}};
            Shown+=async delegate {if(!smoke)await Scan();};
        }
        void ApplyLanguage() {
            fileLabel.Text=text.Get("IPA-файл");browse.Text=text.Get("Выбрать…");refresh.Text=text.Get("Обновить");install.Text=text.Get("Установить");stop.Text=text.Get("Отмена");account.Text=text.Get("Учётные данные iCloud");
            appleDevices.Text=text.Choose("Install Apple Devices","Установить Apple Devices");
            if(selected==null)phone.Text=text.Get("Подключите iPhone по USB");status.Text=text.Get("Подключите iPhone по USB и нажмите «Обновить»");EnableControls();
        }
        void EnableControls() {bool idle=cancel==null;browse.Enabled=refresh.Enabled=account.Enabled=language.Enabled=idle;install.Enabled=idle&&selected!=null&&File.Exists(path.Text);stop.Enabled=!idle;progress.Style=idle?ProgressBarStyle.Blocks:ProgressBarStyle.Marquee;progress.MarqueeAnimationSpeed=idle?0:30;}
        void ChooseFile(string file) {if(!String.Equals(Path.GetExtension(file),".ipa",StringComparison.OrdinalIgnoreCase)){Write(text.Get("Выберите файл с расширением .ipa."));return;}path.Text=file;Write(text.Get("Файл: ")+Path.GetFileName(file));EnableControls();}
        void Write(string message) {status.Text=message;log.AppendText("["+DateTime.Now.ToString("HH:mm:ss")+"] "+message+Environment.NewLine);}
        void Ui(Action action) {if(!IsDisposed&&!Disposing)BeginInvoke(action);}
        void Cancel() {if(cancel!=null){cancel.Cancel();stop.Enabled=false;status.Text=text.Get("Остановка…");}}
        async Task Job(Func<Engine,object> operation,Action<object> completed) {
            if(cancel!=null)return;cancel=new CancellationTokenSource();EnableControls();
            active=new Engine(tools,new Texts(text.Language),workRoot,cancel.Token);
            active.Status=s=>Ui(()=>Write(s));active.DeviceUpdated=d=>Ui(()=>{selected=d;phone.Text=d.Display;});
            try {var result=await Task.Run(()=>operation(active));if(!closing)completed(result);}
            catch(OperationCanceledException){Write(text.Get(active.InstallStarted?"Ожидание остановлено. Проверьте установку на iPhone.":"Операция отменена."));}
            catch(Exception ex){Write(text.Get("Ошибка")+": "+ex.Message);}
            finally {cancel.Dispose();cancel=null;if(selected==null)phone.Text=text.Get("Подключите iPhone по USB");EnableControls();if(closing)Close();}
        }
        async Task Scan() {
            selected=null;phone.Text=text.Get("Поиск iPhone…");Write(phone.Text);
            await Job(e=>e.Devices(),result=>{var devices=(Device[])result;selected=devices.Length==1?devices[0]:null;phone.Text=selected!=null?selected.Display:text.Get("Подключите iPhone по USB");Write(text.Get(devices.Length==1?"iPhone подключён":devices.Length==0?"Подключите iPhone по USB и нажмите «Обновить»":"Оставьте подключённым один iPhone и нажмите «Обновить»"));});
        }
        async Task StartInstall() {
            if(selected==null)return;string file=path.Text,id=selected.Id;bool success=false;
            await Job(e=>e.Install(file,id),result=>{Write(text.Get("Установлено: ")+((Ipa)result).Name);success=true;});
            if(success&&!closing)Credentials(true);
        }
        void Credentials(bool afterInstall) {
            try {
                var store=new CredentialStore(Path.Combine(dataRoot,"accounts.dat"));var saved=store.Get(CredentialStore.SharedKey);if(afterInstall&&saved==null)return;
                using(var dialog=new Form {Text=text.Get(afterInstall?"Введите на iPhone":"Учётные данные iCloud"),ClientSize=new Size(510,275),Font=Font,StartPosition=FormStartPosition.CenterParent,FormBorderStyle=FormBorderStyle.FixedDialog,MaximizeBox=false,MinimizeBox=false}) {
                    var mail=new TextBox {Left=24,Top=49,Width=460,Text=saved==null?"":saved.AppleId,ReadOnly=afterInstall};
                    var password=new TextBox {Left=24,Top=115,Width=460,Text=saved==null?"":saved.Password,UseSystemPasswordChar=true,ReadOnly=afterInstall};
                    var show=new CheckBox {Left=24,Top=151,Width=460,Text=text.Get("Показать пароль")};show.CheckedChanged+=delegate{password.UseSystemPasswordChar=!show.Checked;};
                    var save=new Button {Left=24,Top=209,Width=160,Height=36,Text=text.Get(afterInstall?"Изменить":"Сохранить")};
                    var close=new Button {Left=324,Top=209,Width=160,Height=36,Text=text.Get("Закрыть"),DialogResult=DialogResult.Cancel};
                    dialog.Controls.AddRange(new Control[]{new Label {Left=24,Top=24,Text="Apple ID",Width=450},mail,new Label {Left=24,Top=90,Text=text.Get("Пароль"),Width=450},password,show,save,close});dialog.CancelButton=close;
                    bool editing=!afterInstall;
                    save.Click+=delegate {if(!editing){editing=true;mail.ReadOnly=password.ReadOnly=false;save.Text=text.Get("Сохранить");return;}
                        if(String.IsNullOrWhiteSpace(mail.Text)||password.Text.Length==0){MessageBox.Show(dialog,text.Get("Введите Apple ID и пароль."));return;}
                        try{store.Set(CredentialStore.SharedKey,mail.Text,password.Text);dialog.DialogResult=DialogResult.OK;}catch{MessageBox.Show(dialog,text.Get("Не удалось сохранить учётные данные."));}};
                    try{dialog.ShowDialog(this);}finally{mail.Clear();password.Clear();}
                }
            } catch {MessageBox.Show(this,text.Get("Не удалось прочитать сохранённые учётные данные."),text.Get("Ошибка"));}
        }
        public void Smoke(string directory) {
            // Explicit diagnostics mode: isolated profile and no USB process invocation.
            Shown+=delegate {var timer=new System.Windows.Forms.Timer {Interval=500};timer.Tick+=delegate {timer.Stop();try {
                using(var bitmap=new Bitmap(Width,Height)){DrawToBitmap(bitmap,new Rectangle(0,0,Width,Height));bitmap.Save(Path.Combine(directory,"window-"+text.Language+".png"));}
                File.WriteAllText(Path.Combine(directory,"smoke-"+text.Language+".txt"),"OK\n"+Text+"\n"+install.Text+"\n"+account.Text+"\n"+appleDevices.Text+"\n"+AppleDevicesUrl+"\nUSB calls: 0");
            }finally{timer.Dispose();Close();}};timer.Start();};
        }
    }
    public static class Program {
        [STAThread] public static int Main(string[] args) {
            Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);
            try {
                bool smoke=args.Length==2&&args[0]=="--smoke-test";
                string root=smoke?Path.GetFullPath(args[1]):Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"IPA-Install");
                if(smoke)Directory.CreateDirectory(root);
                using(var bundle=RuntimeBundle.Open()) {
                    var tools=new ProcessTools(bundle.Tools,PinnedTools.Hashes);
                    if(smoke)File.WriteAllText(Path.Combine(root,"runtime-path.txt"),bundle.Root);
                    using(var window=new MainWindow(root,tools,smoke,bundle.Work)){if(smoke)window.Smoke(root);Application.Run(window);}
                }
                return 0;
            } catch(Exception ex){MessageBox.Show(ex.Message,"TapOk IPA Installer",MessageBoxButtons.OK,MessageBoxIcon.Error);return 1;}
        }
    }
}
