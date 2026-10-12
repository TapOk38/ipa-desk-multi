using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Xml;

// Read only top-level string fields used in an IPA filename. No object execution,
// external XML resources, recursive binary objects, or extraction to disk.
public static class IpaDeskMetadata {
    public static Dictionary<string,string> Read(byte[] bytes) {
        if (bytes.Length > 16*1024*1024) throw new InvalidDataException("Large plist");
        if (bytes.Length >= 8 && Encoding.ASCII.GetString(bytes,0,8)=="bplist00")
            return new Binary(bytes).Read();
        var settings = new XmlReaderSettings { DtdProcessing=DtdProcessing.Ignore, XmlResolver=null, MaxCharactersInDocument=16*1024*1024 };
        var doc = new XmlDocument { XmlResolver=null };
        using(var stream=new MemoryStream(bytes)) using(var reader=XmlReader.Create(stream,settings)) doc.Load(reader);
        var dict=doc.SelectSingleNode("/plist/dict");
        if(dict==null) throw new InvalidDataException("Missing plist dictionary");
        var result=new Dictionary<string,string>();
        foreach(XmlNode key in dict.ChildNodes) {
            if(key.Name!="key") continue;
            var value=key.NextSibling;
            while(value!=null && value.NodeType!=XmlNodeType.Element) value=value.NextSibling;
            if(value!=null && value.Name=="string") result[key.InnerText]=value.InnerText;
        }
        return result;
    }
    private sealed class Binary {
        readonly byte[] data;
        readonly int offsetSize, refSize, count, top, table;
        public Binary(byte[] bytes) {
            data=bytes;
            if(data.Length<40) throw new InvalidDataException("Short plist");
            int t=data.Length-32;
            offsetSize=data[t+6]; refSize=data[t+7];
            if(offsetSize<1 || offsetSize>8 || refSize<1 || refSize>8) throw new InvalidDataException("Invalid widths");
            count=Number(t+8,8,data.Length); top=Number(t+16,8,data.Length); table=Number(t+24,8,data.Length);
            if(count<1 || count>1000000 || top>=count || table<8 || (long)table+(long)count*offsetSize>t) throw new InvalidDataException("Invalid table");
        }
        int Number(int at,int size,int limit) {
            if(at<0 || size<1 || size>8 || (long)at+size>limit) throw new InvalidDataException("Invalid range");
            ulong value=0; for(int i=0;i<size;i++) value=(value<<8)|data[at+i];
            if(value>Int32.MaxValue) throw new InvalidDataException("Large number");
            return (int)value;
        }
        int Offset(int id) {
            if(id<0 || id>=count) throw new InvalidDataException("Invalid reference");
            int offset=Number(table+id*offsetSize,offsetSize,data.Length-32);
            if(offset<8 || offset>=table) throw new InvalidDataException("Invalid offset");
            return offset;
        }
        int Length(ref int at,int marker) {
            int length=marker&15;
            if(length!=15) return length;
            if(at>=table) throw new InvalidDataException("Missing length");
            int m=data[at++];
            if((m>>4)!=1 || (m&15)>3) throw new InvalidDataException("Invalid length");
            int width=1<<(m&15); length=Number(at,width,table); at+=width;
            return length;
        }
        string Text(int id) {
            int at=Offset(id); int marker=data[at++], type=marker>>4;
            if(type!=5 && type!=6 && type!=7) return null;
            int length=Length(ref at,marker); long size=(long)length*(type==6?2:1);
            if(size>1024*1024 || (long)at+size>table) throw new InvalidDataException("Invalid text");
            var encoding=type==6?Encoding.BigEndianUnicode:(type==7?Encoding.UTF8:Encoding.ASCII);
            return encoding.GetString(data,at,(int)size);
        }
        public Dictionary<string,string> Read() {
            int at=Offset(top); int marker=data[at++];
            if((marker>>4)!=13) throw new InvalidDataException("Not a dictionary");
            int length=Length(ref at,marker);
            if(length>100000 || (long)at+(long)length*refSize*2>table) throw new InvalidDataException("Invalid dictionary");
            var result=new Dictionary<string,string>();
            for(int i=0;i<length;i++) {
                string key=Text(Number(at+i*refSize,refSize,table));
                if(key!="CFBundleName" && key!="CFBundleDisplayName" && key!="CFBundleShortVersionString" && key!="MinimumOSVersion") continue;
                string value=Text(Number(at+(length+i)*refSize,refSize,table));
                if(value!=null) result[key]=value;
            }
            return result;
        }
    }
}
