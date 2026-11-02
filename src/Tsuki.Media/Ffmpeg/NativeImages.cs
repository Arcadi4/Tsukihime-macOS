// The native images the process has loaded, per platform. `FfmpegLibrary.LoadedModulePaths` proves that the FFmpeg libraries the process runs come from the folder the
// game chose (ARCHITECTURE 1.11); the runtime's Process.Modules is Windows-only, so macOS reads dyld's image list and Linux reads /proc/self/maps.
using System.Diagnostics;
using System.Runtime.InteropServices;

namespace Tsuki.Media.Ffmpeg;

/// <summary>The full paths of the native images (libraries and the executable) mapped into this process.</summary>
internal static partial class NativeImages
{
    /// <summary>The images, one entry per file, in load order (the executable first). Empty on an unknown platform.</summary>
    public static IReadOnlyList<string> Enumerate()
    {
        IEnumerable<string> images = OperatingSystem.IsMacOS() ? Dyld()
            : OperatingSystem.IsLinux() ? Maps()
            : OperatingSystem.IsWindows() ? Modules()
            : [];
        return [.. images.Distinct(StringComparer.Ordinal)];
    }

    /// <summary>macOS: the dyld image list (<c>_dyld_image_count</c> / <c>_dyld_get_image_name</c> in libSystem).</summary>
    private static IEnumerable<string> Dyld()
    {
        uint count = _dyld_image_count();
        for (uint i = 0; i < count; i++)
        {
            if (Marshal.PtrToStringUTF8(_dyld_get_image_name(i)) is { Length: > 0 } path)
            {
                yield return path;
            }
        }
    }

    /// <summary>Linux: the mapped files of <c>/proc/self/maps</c> (the path is everything after the inode field).</summary>
    private static IEnumerable<string> Maps()
    {
        string[] lines;
        try
        {
            lines = File.ReadAllLines("/proc/self/maps");
        }
        catch (IOException)
        {
            yield break;
        }
        catch (UnauthorizedAccessException)
        {
            yield break;
        }

        foreach (string line in lines)
        {
            int slash = line.IndexOf(" /", StringComparison.Ordinal);
            if (slash >= 0)
            {
                yield return line[(slash + 1)..];
            }
        }
    }

    /// <summary>Windows: <see cref="Process.Modules"/>.</summary>
    private static IEnumerable<string> Modules()
    {
        List<string> paths = [];
        try
        {
            using Process process = Process.GetCurrentProcess();
            foreach (ProcessModule module in process.Modules)
            {
                paths.Add(module.FileName);
            }
        }
        catch (InvalidOperationException)
        {
            // a process that exited while it was read: the caller gets what was collected
        }
        catch (System.ComponentModel.Win32Exception)
        {
        }

        return paths;
    }

    [LibraryImport("libSystem.B.dylib")]
    private static partial uint _dyld_image_count();

    [LibraryImport("libSystem.B.dylib")]
    private static partial nint _dyld_get_image_name(uint index);
}
