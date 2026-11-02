// Working-set trimming of memory-mapped file pages (package K11). The archives are mapped whole (24 GB for allpac1); every page a decode touches stays in the
// process's working set until the operating system needs the memory, so the "working set" of a long play grows by the size of everything the game ever read, with
// nothing leaking. Dropping the pages from the working set moves them to the system cache (standby list): a later read of the same page is a soft fault, no disk read.
using System.Runtime.InteropServices;

namespace Tsuki.Platform;

/// <summary>Native page-table helpers for mapped files.</summary>
public static partial class MemoryPages
{
    /// <summary>
    /// Removes the pages of <c>[address, address + length)</c> from the process's working set (Windows: <c>VirtualUnlock</c> on pages that are not locked, which is its
    /// documented way to do that; the "not locked" error it reports is the normal result. macOS: <c>madvise</c> with <c>MADV_DONTNEED</c>, which drops the pages and
    /// repopulates them from the file on the next read). Does nothing on other systems. Safe while other threads read the range.
    /// </summary>
    /// <param name="address">Start of the range (inside a mapped view, page aligned).</param>
    /// <param name="length">Bytes.</param>
    public static void TrimResident(nint address, nuint length)
    {
        if (length == 0)
        {
            return;
        }

        if (OperatingSystem.IsWindows())
        {
            _ = VirtualUnlock(address, length);
        }
        else if (OperatingSystem.IsMacOS())
        {
            _ = Madvise(address, length, MadvDontNeed);
        }
    }

    /// <summary>macOS <c>MADV_DONTNEED</c> (sys/mman.h): pages may be reclaimed; a later access repopulates them.</summary>
    private const int MadvDontNeed = 4;

    [LibraryImport("libc", EntryPoint = "madvise", SetLastError = true)]
    private static partial int Madvise(nint address, nuint length, int advice);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool VirtualUnlock(nint address, nuint size);
}
