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