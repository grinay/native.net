**How to use and what is important to deliver native libraries with .NET**

In this article I will focus only on **Linux** and **OSX**, as for **Windows** I almost never face the problem of
finding a library which is not available in the form of **.dll**.

All the examples and code snippets also available in the repository https://github.com/grinay/native.net

In my work I’m often facing the cases when I have to integrate third party native libraries written in other languages
with
dotnet.

This might be challenging for a few reasons.

1. You need to figure out how to call lib API interface from C# with correct marshalling. (Type mapping)

2. Build libraries for target runtimes. (Target OS, Target CPU)

3. Deploy into target runtime - correctly link all dependencies, set correct paths to them, make sure they are available
   on
   the target system.

4. Make it cross platform. Often it requires the development team members inside the company to run the app on the
   different operating systems.

In my career, I have spent a considerable amount of time understanding the aspects I mentioned earlier.

Additionally, I frequently observe developers attempting to operate various libraries in a serverless environment, such
as AWS Lambda, only to discover they don’t function as expected. This issue often remains unclear to many developers on
how to effectively tackle it.

In this article, I will address these challenges, providing practical examples to illustrate my solutions.

As an example we will take the **Qpdf** tool, which helps to perform different operations on pdf files.
Our target will be Lambda function with ARM architecture and OSX apple silicon (arm64) for local development.

Let's start with the first problem.

**There are few possible solutions:**
Deliver all libraries along with our app.
Create a lambda layer with dependencies.
Create a custom runtime docker image for lambda.

We will concentrate solely on the first approach, as it will enable us not only to meet our own needs but also to
develop fully functional nuget packages for online publication. This approach will allow other users to benefit from our
work, and ensure that all necessary libraries are included with our app.

## Let’s outline the steps:

We need to find out which OS we are targeting.

- Build **.so** and **.dylib** libraries.
- Build C# wrapper for our library.
- Put it all together into our project.

# Build libraries
## Linux build

As per discussion earlier, we are going to target aws lambda with ARM architecture.

Briefly checking the targeting OS on

[https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html](https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html)

I see that my target OS for dotnet 6 runtime will be Amazon Linux 2.

We are going to build our binaries right inside Amazon linux 2 running in docker.

The arm image for docker is here [https://hub.docker.com/_/amazonlinux](https://hub.docker.com/_/amazonlinux), let's pull it upfront.

```
docker pull arm64v8/amazonlinux:2
```

Let’s check the documentation of the tool we are going to use [https://qpdf.readthedocs.io/en/stable/qpdf-job.html](https://qpdf.readthedocs.io/en/stable/qpdf-job.html)
we are interested in json job interface.

There is a **C api** available for us in file **qpdfjob-c.h** , let’s go into the repo and see what we have there.

[qpdfjob-c.h](https://github.com/qpdf/qpdf/blob/e9166457fad8d446572b8434d1895aa586baf6b7/include/qpdf/qpdfjob-c.h#L73)



Now let's do the build of the library. In this case for my luck there is a good documentation which is clearly saying
the
steps to take to build a library.

https://qpdf.readthedocs.io/en/stable/installation.html

Based on documentation I created a docker file which is doing the build.
For simplicity I took the basic dependencies list and ask ChatGPT to help me write the basic Dockerfile. Also for some
reasons QPDF didn't go well to build with openssl package installed, so I've added openssl sources to build along with
Qpdf. Also ChatGPT was handy here to add it to the Dockerfile.

[Dockerfile](Linux/Dockerfile)

Let's build it up

```
docker build -f Linux/Dockerfile -t qpdfarm  .
```

Then we need to copy native library along with all its dependencies as artefacts.
To do that we need to run container with some help script *(I'll explain it later in the article)* and mount a folder for artifacts.
In github repo there is linux folder which contains the script and the Dockerfile.
We need to mount folder with the script into the container.
```
docker run -it -v ./linux:/root/scripts -v ./artefacts:/root/artefacts  qpdfarm
```

Go into our build folder:

```
cd /tmp/qpdfsource/build/libqpdf
```

let's check the dependencies:

```
bash-4.2# ldd libqpdf.so.29.9.0 
linux-vdso.so.1 (0x0000ffffa8596000)
libz.so.1 => /lib64/libz.so.1 (0x0000ffffa7f34000)
libjpeg.so.62 => /lib64/libjpeg.so.62 (0x0000ffffa7ed3000)
libcrypto.so.1.1 => /usr/local/lib/libcrypto.so.1.1 (0x0000ffffa7bfc000)
libgnutls.so.28 => /lib64/libgnutls.so.28 (0x0000ffffa7aa9000)
libstdc++.so.6 => /lib64/libstdc++.so.6 (0x0000ffffa78f4000)
libm.so.6 => /lib64/libm.so.6 (0x0000ffffa7833000)
libgcc_s.so.1 => /lib64/libgcc_s.so.1 (0x0000ffffa7802000)
libc.so.6 => /lib64/libc.so.6 (0x0000ffffa767c000)
/lib/ld-linux-aarch64.so.1 (0x0000ffffa8558000)
libdl.so.2 => /lib64/libdl.so.2 (0x0000ffffa765b000)
libpthread.so.0 => /lib64/libpthread.so.0 (0x0000ffffa7626000)
libp11-kit.so.0 => /lib64/libp11-kit.so.0 (0x0000ffffa74db000)
libtasn1.so.6 => /lib64/libtasn1.so.6 (0x0000ffffa74aa000)
libnettle.so.4 => /lib64/libnettle.so.4 (0x0000ffffa7469000)
libhogweed.so.2 => /lib64/libhogweed.so.2 (0x0000ffffa7428000)
libgmp.so.10 => /lib64/libgmp.so.10 (0x0000ffffa73a7000)
libffi.so.6 => /lib64/libffi.so.6 (0x0000ffffa7386000)
```

Ok we're not necessarily need all of these libs, as some of them are system related and available by default on target
system.

Let's check the other way with patchelf, it has the options to filter out only those which really needed.

```
bash-4.2# patchelf --print-needed libqpdf.so.29.9.0
libz.so.1
libjpeg.so.62
libcrypto.so.1.1
libgnutls.so.28
libstdc++.so.6
libm.so.6
libgcc_s.so.1
libc.so.6
```

**So what is next?**
We need to copy all those dependencies and as well their subdependencies.
To simplify that process I wrote a script:

[deps-collector.sh](Linux/deps-collector.sh)

The script will take as an argument the library path in our case **libqpdf.so.29.9.0**
and then recursively go over all dependencies and copy them into **./lib** folder along with qpdf library.
One of the most important step here is to change dependencies path with patchelf so our library may find all its dependencies in the same folder.
Here is the example of how **patchelf** is doing that, for better understanding.  (Script actually has this step and you don't need to do it explicitly)
```
patchelf --set-rpath "\$ORIGIN" file.so  
```

**RPATH** - is runtime searchable path and **$ORIGIN** is special value for ELF which means "exact path" and we are
setting it to a current folder, so when library is loaded it also search for its dependencies in the same folder.


It's time to run the script to collect all dependencies and set the correct path.
```
chmod +x /root/scripts/deps-collector.sh
/root/scripts/deps-collector.sh /tmp/qpdfsource/build/libqpdf/libqpdf.so.29.9.0
```

In a lib folder we now see all dependencies:
```
bash-4.2# ls -la lib
total 24080
drwxr-xr-x 2 root root     4096 Apr 21 07:05 .
drwxr-xr-x 1 root root     4096 Apr 21 07:05 ..
-rwxr-xr-x 1 root root  1939633 Apr 21 07:05 libc.so.6
-rwxr-xr-x 1 root root  3469513 Apr 21 07:05 libcrypto.so.1.1
-rwxr-xr-x 1 root root   132425 Apr 21 07:05 libdl.so.2
-rwxr-xr-x 1 root root   133137 Apr 21 07:05 libffi.so.6
-rwxr-xr-x 1 root root   200465 Apr 21 07:05 libgcc_s.so.1
-rwxr-xr-x 1 root root   540593 Apr 21 07:05 libgmp.so.10
-rwxr-xr-x 1 root root  1419281 Apr 21 07:05 libgnutls.so.28
-rwxr-xr-x 1 root root   271369 Apr 21 07:05 libhogweed.so.2
-rwxr-xr-x 1 root root   397849 Apr 21 07:05 libjpeg.so.62
-rwxr-xr-x 1 root root   862089 Apr 21 07:05 libm.so.6
-rwxr-xr-x 1 root root   270889 Apr 21 07:05 libnettle.so.4
-rwxr-xr-x 1 root root  1381657 Apr 21 07:05 libp11-kit.so.0
-rwxr-xr-x 1 root root   205257 Apr 21 07:05 libpthread.so.0
-rwxr-xr-x 1 root root 10919744 Apr 21 07:05 libqpdf.so.29.9.0
-rwxr-xr-x 1 root root  2071249 Apr 21 07:05 libstdc++.so.6
-rwxr-xr-x 1 root root   198785 Apr 21 07:05 libtasn1.so.6
-rwxr-xr-x 1 root root   199201 Apr 21 07:05 libz.so.1
```
Let's make sure the dependencies path are fixed as well
```
bash-4.2# ldd lib/libqpdf.so.29.9.0 
        linux-vdso.so.1 (0x0000ffff9d7a9000)
        libz.so.1 => /tmp/qpdfsource/build/libqpdf/lib/libz.so.1 (0x0000ffff9d137000)
        libjpeg.so.62 => /tmp/qpdfsource/build/libqpdf/lib/libjpeg.so.62 (0x0000ffff9d0c5000)
        libcrypto.so.1.1 => /usr/local/lib/libcrypto.so.1.1 (0x0000ffff9cdee000)
        libgnutls.so.28 => /tmp/qpdfsource/build/libqpdf/lib/libgnutls.so.28 (0x0000ffff9cc83000)
        libstdc++.so.6 => /tmp/qpdfsource/build/libqpdf/lib/libstdc++.so.6 (0x0000ffff9ca79000)
        libm.so.6 => /tmp/qpdfsource/build/libqpdf/lib/libm.so.6 (0x0000ffff9c9a6000)
        libgcc_s.so.1 => /tmp/qpdfsource/build/libqpdf/lib/libgcc_s.so.1 (0x0000ffff9c965000)
        libc.so.6 => /tmp/qpdfsource/build/libqpdf/lib/libc.so.6 (0x0000ffff9c78b000)
        /lib/ld-linux-aarch64.so.1 (0x0000ffff9d76b000)
        libdl.so.2 => /lib64/libdl.so.2 (0x0000ffff9c76a000)
        libpthread.so.0 => /lib64/libpthread.so.0 (0x0000ffff9c735000)
        libp11-kit.so.0 => /tmp/qpdfsource/build/libqpdf/lib/libp11-kit.so.0 (0x0000ffff9c5e3000)
        libtasn1.so.6 => /tmp/qpdfsource/build/libqpdf/lib/libtasn1.so.6 (0x0000ffff9c5a2000)
        libnettle.so.4 => /tmp/qpdfsource/build/libqpdf/lib/libnettle.so.4 (0x0000ffff9c54f000)
        libhogweed.so.2 => /tmp/qpdfsource/build/libqpdf/lib/libhogweed.so.2 (0x0000ffff9c4fc000)
        libgmp.so.10 => /tmp/qpdfsource/build/libqpdf/lib/libgmp.so.10 (0x0000ffff9c468000)
        libffi.so.6 => /tmp/qpdfsource/build/libqpdf/lib/libffi.so.6 (0x0000ffff9c437000)
```

All this files we need to copy into our project or nuget package, for now we just copy them into artefacts folder.
```
cp -R lib /root/artefacts/linux-arm64
exit
```
Now we have all native libs built for amazon linux 2 arm64.

Now let's do the same but for OSX on apple silicon.

## OSX build.

We would need the following tools and deps (you can install them with brew)
```
brew install gcc cmake zlib jpeg gnutls openssl
```
go to OSX folder and look into build.sh script. 
Let build the qpdf library for OSX.
```
cd OSX
chmod +x build.sh
./build.sh
cd ../
```
let's check deps:
```
otool -L OSX/qpdfsource/build/libqpdf/libqpdf.29.9.0.dylib
libqpdf.29.9.0.dylib:
        @rpath/libqpdf.29.dylib (compatibility version 29.0.0, current version 29.9.0)
        /usr/lib/libz.1.dylib (compatibility version 1.0.0, current version 1.2.12)
        /opt/homebrew/opt/jpeg-turbo/lib/libjpeg.8.dylib (compatibility version 8.0.0, current version 8.3.2)
        /opt/homebrew/opt/openssl@3/lib/libssl.3.dylib (compatibility version 3.0.0, current version 3.0.0)
        /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib (compatibility version 3.0.0, current version 3.0.0)
        /opt/homebrew/opt/gnutls/lib/libgnutls.30.dylib (compatibility version 68.0.0, current version 68.1.0)
        /usr/lib/libc++.1.dylib (compatibility version 1.0.0, current version 1700.255.0)
        /usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1345.100.2)
```

Now we need to collect all dependencies and set the correct path for them.
There is also script [deps-collector-osx.sh](OSX/deps-collector-osx.sh) to do that in the OSX folder. 
It works similar to the linux one but uses different tools. 
It might require sudo to run(At least for this case)

```
sudo ./OSX/deps-collector-osx.sh ./OSX/qpdfsource/build/libqpdf/libqpdf.29.9.0.dylib artefacts/osx-arm64
```
Let's check the lib folder  and also dependencies paths.
```
ls -la artefacts/osx-arm64 
total 64320
drwxr-xr-x  15 grinay  staff       480 Apr 21 18:01 .
drwxr-xr-x   6 grinay  staff       192 Apr 21 18:01 ..
-rw-r--r--   1 root    staff   4199888 Apr 21 18:01 libcrypto.3.dylib
-r--r--r--   1 root    staff    452800 Apr 21 18:01 libgmp.10.dylib
-rw-r--r--   1 root    staff   1852576 Apr 21 18:01 libgnutls.30.dylib
-r--r--r--   1 root    staff    316224 Apr 21 18:01 libhogweed.6.dylib
-rw-r--r--   1 root    staff    259312 Apr 21 18:01 libidn2.0.dylib
-r--r--r--   1 root    staff    162656 Apr 21 18:01 libintl.8.dylib
-rw-r--r--   1 root    staff    472752 Apr 21 18:01 libjpeg.8.dylib
-r--r--r--   1 root    staff    333104 Apr 21 18:01 libnettle.8.dylib
-rw-r--r--   1 root    staff   1472752 Apr 21 18:01 libp11-kit.0.dylib
-rwxr-xr-x   1 root    staff  20640752 Apr 21 18:01 libqpdf.29.9.0.dylib
-r--r--r--   1 root    staff    793168 Apr 21 18:01 libssl.3.dylib
-rw-r--r--   1 root    staff    108208 Apr 21 18:01 libtasn1.6.dylib
-r--r--r--   1 root    staff   1836128 Apr 21 18:01 libunistring.5.dylib

otool -L artefacts/osx-arm64/libqpdf.29.9.0.dylib 
lib/libqpdf.29.9.0.dylib:
        @rpath/libqpdf.29.9.0.dylib (compatibility version 29.0.0, current version 29.9.0)
        /usr/lib/libz.1.dylib (compatibility version 1.0.0, current version 1.2.12)
        @loader_path/libjpeg.8.dylib (compatibility version 8.0.0, current version 8.3.2)
        @loader_path/libssl.3.dylib (compatibility version 3.0.0, current version 3.0.0)
        @loader_path/libcrypto.3.dylib (compatibility version 3.0.0, current version 3.0.0)
        @loader_path/libgnutls.30.dylib (compatibility version 68.0.0, current version 68.1.0)
        /usr/lib/libc++.1.dylib (compatibility version 1.0.0, current version 1700.255.0)
        /usr/lib/libSystem.B.dylib (compatibility version 1.0.0, current version 1345.100.2)
```

Alright, everything looks good, now we have all the native libraries with their dependencies for both target OS.


# Create wrapper for C#

There are many articles on internet how to use C/C++ libs with C#.
I will not dive into that process too much and will  leave some useful links at the end of the article
Fow now I provide just the bare minimum to order we  able to use dynamically
linked lib. 

let's rename the libqpdf.29.9.0.dylib to libqpdf.29.dylib for OSX and libqpdf.so.29.9.0 to libqpdf.29.so for linux to make it easier to use in the code.
```
sudo chown -R $USER artefacts
mv artefacts/osx-arm64/libqpdf.29.9.0.dylib artefacts/osx-arm64/libqpdf.29.dylib
mv artefacts/linux-arm64/libqpdf.so.29.9.0 artefacts/linux-arm64/libqpdf.29.so

```

```csharp
using System.Runtime.InteropServices;

namespace QPdf.net;

public class QpdfWrapper
{
    private const string BinaryPath = "libqpdf.29";
    [DllImport(BinaryPath, CallingConvention = CallingConvention.Cdecl,
        EntryPoint = "qpdfjob_run_from_json")]
    public static extern int RunFromJSON(
        [MarshalAs(UnmanagedType.LPStr)] string json);
}

```

Before continue want to give a bit of theory about how the native libraries are loaded in .NET.
(https://learn.microsoft.com/en-us/dotnet/standard/native-interop/native-library-loading)

There are few ways to deliver native libs:
1. Put them right into the root folder of the app on publish command, means all .so or .dylib files copied right into app folder. (Like flattening)
2. Put native libs into the runtimes folder under specific runtime identifier. (https://learn.microsoft.com/en-us/nuget/create-packages/native-files-in-net-packages#native-assets)
For our case we will put osx libs into runtimes/osx-arm64/native and linux libs into runtimes/linux-arm64/native.

There is "NativeQpdf" folder which has the sample code for testing integration it takes the input pdf and extract the first page into the new pdf file.
Let's copy our native libs into the runtimes folder.
```
mkdir -p NativeQpdf/runtimes/linux-arm64/native
mkdir -p NativeQpdf/runtimes/osx-arm64/native
cp artefacts/linux-arm64/* NativeQpdf/runtimes/linux-arm64/native
cp artefacts/osx-arm64/* NativeQpdf/runtimes/osx-arm64/native
```

In the .csproj file I added a task to copy my runtimes folder into the output folder.
```
    <ItemGroup>
        <Content Include="runtimes\**">
            <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
        </Content>
    </ItemGroup>
```

Let's test in OSX.
```
cd NativeQpdf
dotnet run test.pdf test_page1.pdf && ls -la test_page1.pdf
-rw-r--r--  1 grinay  staff  59816 Apr 23 18:38 test_page1.pdf
```
It's working with no issue. 
However if you would run it in amazon linux 2
```
dotnet publish -r linux-arm64 -c Release --sc -o ./linuxbuild && cp test.pdf ./linuxbuild
docker run -it -v ./linuxbuild:/app arm64v8/amazonlinux:2 /app/NativeQpdf /app/test.pdf /app/test_page1.pdf
```
You will get an error
```
➜  NativeQpdf git:(main) ✗ docker run -it -v ./linuxbuild:/app arm64v8/amazonlinux:2 /app/NativeQpdf /app/test.pdf /app/test_page1.pdf
Unhandled exception. System.DllNotFoundException: Unable to load shared library 'libqpdf.29' or one of its dependencies. In order to help diagnose loading problems, consider setting the LD_DEBUG environment variable: liblibqpdf.29: cannot open shared object file: No such file or directory
   at NativeQpdf.QpdfWrapper.RunFromJSON(String json)
   at Program.Main(String[] args) in [...]/NativeQpdf/Program.cs:line 34

```
And if you would like to debug it you may try to run as
```
docker run -it -e LD_DEBUG='libs' -v ./linuxbuild:/app arm64v8/amazonlinux:2 /app/NativeQpdf /app/test.pdf /app/test_page1.pdf
```
In the long output you will see that it's not even trying to search lib inside the runtimes folder. Frankly I don't know the reasons for it.
But I have a solution for it.

1. As mentioned early is flattening, just copy all .so files into the root folder of the app.
2. Is to set DllImportResolver in our code, and take full control over where to load libraries for qpdf.
I prefer the second way.

Here is the code for it. [QpdfWrapper.cs](NativeQpdf/QpdfWrapper.cs)
```csharp
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

namespace NativeQpdf;

public class QpdfWrapper
{
    private const string BinaryPath = "libqpdf.29";

    [DllImport(BinaryPath, CallingConvention = CallingConvention.Cdecl,
        EntryPoint = "qpdfjob_run_from_json")]
    public static extern int RunFromJSON(
        [MarshalAs(UnmanagedType.LPStr)] string json);

    [ModuleInitializer]
    internal static void Initialize()
    {
        NativeLibrary.SetDllImportResolver(Assembly.GetExecutingAssembly(), (libraryName, assembly, searchPath) =>
        {
            if (libraryName == BinaryPath)
            {
                var isArm = RuntimeInformation.OSArchitecture == Architecture.Arm64;
                var isOsx = RuntimeInformation.IsOSPlatform(OSPlatform.OSX);
                var isLinux = RuntimeInformation.IsOSPlatform(OSPlatform.Linux);
    
                if (isLinux && isArm)
                {
                    return NativeLibrary.Load("runtimes/linux-arm64/native/" + BinaryPath + ".so", assembly, default);
                }
                else if (isOsx && isArm)
                {
                    return NativeLibrary.Load("runtimes/osx-arm64/native/" + BinaryPath + ".dylib", assembly, default);
                }
    
                return NativeLibrary.Load(BinaryPath, assembly, default);
            }
    
            return default;
        });
    }
}
```

Let's test again and adding ls -la for output file to make sure program works:
```
dotnet publish -r linux-arm64 -c Release --sc -o ./linuxbuild && cp test.pdf ./linuxbuild
docker run -it -v ./linuxbuild:/app arm64v8/amazonlinux:2 /bin/sh -c "/app/NativeQpdf /app/test.pdf /app/test_page1.pdf && ls -la /app/test_page1.pdf"
```

And indeed it works:
```
➜  NativeQpdf git:(main) ✗ dotnet publish -r linux-arm64 -c Release --sc -o ./linuxbuild && cp test.pdf ./linuxbuild
MSBuild version 17.7.4+3ebbd7c49 for .NET
  Determining projects to restore...
  All projects are up-to-date for restore.
  NativeQpdf -> /Users/grinay/RiderProjects/native.net/NativeQpdf/bin/Release/net6.0/linux-arm64/NativeQpdf.dll
  NativeQpdf -> /Users/grinay/RiderProjects/native.net/NativeQpdf/linuxbuild/
➜  NativeQpdf git:(main) ✗ docker run -it -v ./linuxbuild:/app arm64v8/amazonlinux:2 /bin/sh -c "/app/NativeQpdf /app/test.pdf /app/test_page1.pdf && ls -la /app/test_page1.pdf"
-rw-r--r-- 1 root root 59816 Apr 23 10:47 /app/test_page1.pdf
```

So now we now how to build and deliver our libs. 
If you're going to deliver it as nuget packages, you're doing absolutely the same way, copy native libs into the runtimes folder and set DllImportResolver in your code for the cases when runtimes folder didn't work as expected.

# Some additional notes.
Some useful links and tools which may help you to work with native libraries.

Book which gives a good understanding of marshaling in C#.
https://app.box.com/s/oqihv7z1od


**Here is the list of helpful tools:**
SWIG - The tool to automatically generate C# wrappers for C/C++ libraries
Dylibbundler - OSX app to collect dependencies on lib and fix paths
PatchELF - Linux tool to change paths in ELF
Otool (OSX) -OSX tool to check dependencies
Ldd - Linux tool to check dependencies

And some tips which I'm often using, for example when I need to build some libraries for OSX , 
but I'm not sure how, or don't know the exact flags to use, I often using drew repositories to find the clues.

For example I built opencv runtimes for OSX arm, and I went to https://formulae.brew.sh/formula/opencv opencv page.
There is usually a link to formula in this case here https://github.com/Homebrew/homebrew-core/blob/651ab1c2c5e65bdcf080d994d143451135f5f920/Formula/o/opencv.rb

And I can see the flags which were used to build the library and the steps, so I can easily replicate them in my builds. 

I hope this article was helpful for you, and you will be able to deliver your native libraries with no issues.