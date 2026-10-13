using System;
using System.Threading;
using System.Web.Script.Serialization;
static class ToolFixture {
    static int Main(string[] args){
        Console.OutputEncoding=new System.Text.UTF8Encoding(false);
        if(args.Length>0 && args[0]=="sleep"){Thread.Sleep(20000);return 0;}
        if(args.Length>0 && args[0]=="pipes"){for(int i=0;i<10000;i++){Console.Out.WriteLine(new string('o',80));Console.Error.WriteLine(new string('e',80));}return 0;}
        Console.Out.WriteLine(new JavaScriptSerializer().Serialize(args));return 0;
    }
}
