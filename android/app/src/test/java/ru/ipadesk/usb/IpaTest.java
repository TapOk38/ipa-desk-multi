package ru.ipadesk.usb;

import com.dd.plist.*;
import org.junit.*;
import org.junit.rules.TemporaryFolder;
import static org.junit.Assert.*;
import java.io.*;
import java.util.zip.*;

public class IpaTest {
    @Rule public TemporaryFolder temp=new TemporaryFolder();
    private void entry(ZipOutputStream z,String name,byte[] data)throws Exception {
        z.putNextEntry(new ZipEntry(name));z.write(data);z.closeEntry();
    }
    private File ipa(boolean executable)throws Exception {
        File f=temp.newFile();
        try(ZipOutputStream z=new ZipOutputStream(new FileOutputStream(f))) {
            NSDictionary info=Plists.dict("CFBundleIdentifier","test.app","CFBundleExecutable","AppBinary",
                "CFBundleDisplayName","Проверка","CFBundleShortVersionString","2.16.9","MinimumOSVersion","16.6");
            entry(z,"__MACOSX/._file",new byte[0]);
            entry(z,"Payload/DifferentName.app/Info.plist",BinaryPropertyListWriter.writeToArray(info));
            if(executable)entry(z,"Payload/DifferentName.app/AppBinary",new byte[]{1,2});
            entry(z,"Payload/DifferentName.app/SC_Info/AppBinary.sinf",new byte[]{3,4,5});
            entry(z,"iTunesMetadata.plist",Plists.dict("itemId",123).toXMLPropertyList().getBytes("UTF-8"));
        }return f;
    }
    @Test public void findsBinaryPlistAndPreservesAppStoreOptions()throws Exception {
        Ipa ipa=Ipa.open(ipa(true));assertEquals("Проверка",ipa.title);assertEquals("16.6",ipa.minimum);
        assertArrayEquals(new byte[]{3,4,5},ipa.sinf);
        assertFalse(ipa.options().containsKey("PackageType"));
        assertTrue(ipa.options().containsKey("ApplicationSINF"));assertTrue(ipa.options().containsKey("iTunesMetadata"));
    }
    @Test public void rejectsMissingExecutable()throws Exception {File f=ipa(false);assertThrows(IOException.class,()->Ipa.open(f));}
    @Test public void comparesNumericVersions()throws Exception {
        assertTrue(Ipa.compareVersions("16.10","16.6")>0);assertTrue(Ipa.compareVersions("16.5.9","16.6")<0);
        assertEquals(0,Ipa.compareVersions("26.0","26"));
        assertThrows(IOException.class,()->Ipa.compareVersions("broken","16.6"));
    }
    @Test public void rejectsMalformedArchive()throws Exception {File f=temp.newFile();assertThrows(IOException.class,()->Ipa.open(f));}
    @Test public void completeIsNotSuccessWhenErrorPresent() {
        assertThrows(IOException.class,()->Installer.installStatus(Plists.dict("Status","Complete","Error","ApplicationVerificationFailed")));
    }
    @Test public void completionMustBeExplicit()throws Exception {
        assertEquals("Complete",Installer.installStatus(Plists.dict("Status","Complete")));
        assertThrows(IOException.class,()->Installer.installStatus(Plists.dict("PercentComplete",100)));
    }
    @Test public void rejectsHugePlistPrefix()throws Exception {
        byte[] prefix={0x7f,(byte)0xff,(byte)0xff,(byte)0xff};
        assertThrows(IOException.class,()->new Plists.Channel(new ByteArrayInputStream(prefix),new ByteArrayOutputStream()).receive());
    }
}
