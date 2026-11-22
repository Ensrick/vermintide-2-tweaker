// rig/GameProcess.cs
//
// VT2 test-rig process starter. Adapted from CrusaderDEHandicap/scripts/HiddenDesktopProcess.cs (same author).
// Starts a process suspended inside a kill-on-close job, at below-normal priority, with an optional
// child-only environment block, either on a private desktop (never switched to) or on the user desktop.
//
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;

public sealed class Vt2GameProcess : IDisposable
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct Startup
    {
        public int cb;
        public string reserved, desktop, title;
        public uint x, y, width, height, xchars, ychars, fill, flags;
        public short show, reservedSize;
        public IntPtr reservedPointer, input, output, error;
    }
    [StructLayout(LayoutKind.Sequential)] struct ProcessInfo { public IntPtr process, thread; public uint pid, tid; }
    [StructLayout(LayoutKind.Sequential)]
    struct BasicLimits
    {
        public long processTime, jobTime;
        public uint flags;
        public UIntPtr minWorkingSet, maxWorkingSet;
        public uint activeProcesses;
        public UIntPtr affinity;
        public uint priority, scheduling;
    }
    [StructLayout(LayoutKind.Sequential)] struct IoCounters { public ulong readOps, writeOps, otherOps, readBytes, writeBytes, otherBytes; }
    [StructLayout(LayoutKind.Sequential)]
    struct ExtendedLimits
    {
        public BasicLimits basic;
        public IoCounters io;
        public UIntPtr processMemory, jobMemory, peakProcessMemory, peakJobMemory;
    }
    delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateDesktop(string name, IntPtr device, IntPtr mode, uint flags, uint access, IntPtr security);
    [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("user32.dll")] static extern bool EnumDesktopWindows(IntPtr desktop, EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int max);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder text, int max);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern IntPtr CreateJobObject(IntPtr security, string name);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref ExtendedLimits limits, uint size);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool QueryInformationJobObject(IntPtr job, int infoClass, IntPtr info, uint size, out uint returned);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CreateProcess(string app, StringBuilder command, IntPtr processSecurity, IntPtr threadSecurity,
        bool inheritHandles, uint flags, IntPtr environment, string directory, ref Startup startup, out ProcessInfo process);
    [DllImport("kernel32.dll", SetLastError = true)] static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll", SetLastError = true)] static extern uint WaitForSingleObject(IntPtr handle, uint timeout);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetExitCodeProcess(IntPtr process, out uint code);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool TerminateProcess(IntPtr process, uint code);
    [DllImport("kernel32.dll", SetLastError = true)] static extern bool TerminateJobObject(IntPtr job, uint code);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);

    const uint CreateSuspended = 0x4, BelowNormalPriority = 0x4000, CreateUnicodeEnvironment = 0x400;

    IntPtr _desktop, _job;
    ProcessInfo _process;
    public string DesktopName { get; private set; }
    public int Pid { get { return (int)_process.pid; } }

    public static Vt2GameProcess Start(string app, string arguments, string directory, System.Collections.IDictionary environment, bool privateDesktop)
    {
        var p = new Vt2GameProcess();
        try { p.Launch(app, arguments, directory, environment, privateDesktop); }
        catch { p.Dispose(); throw; }
        return p;
    }

    // Child-only environment: the parent's variables with the given overrides applied (null value removes one).
    static IntPtr BuildEnvironment(System.Collections.IDictionary overrides)
    {
        var map = new SortedDictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (System.Collections.DictionaryEntry e in Environment.GetEnvironmentVariables()) map[(string)e.Key] = (string)e.Value;
        if (overrides != null)
            foreach (System.Collections.DictionaryEntry e in overrides)
            {
                if (e.Value == null) map.Remove((string)e.Key); else map[(string)e.Key] = e.Value.ToString();
            }
        var sb = new StringBuilder();
        foreach (var kv in map) { sb.Append(kv.Key).Append('=').Append(kv.Value).Append((char)0); }
        sb.Append((char)0);
        return Marshal.StringToHGlobalUni(sb.ToString());
    }

    void Launch(string app, string arguments, string directory, System.Collections.IDictionary environment, bool privateDesktop)
    {
        if (privateDesktop)
        {
            DesktopName = "Vt2Rig-" + Guid.NewGuid().ToString("N");
            _desktop = CreateDesktop(DesktopName, IntPtr.Zero, IntPtr.Zero, 0, 0xF01FF, IntPtr.Zero);
            if (_desktop == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateDesktop");
        }
        _job = CreateJobObject(IntPtr.Zero, null);
        if (_job == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateJobObject");
        var limits = new ExtendedLimits();
        // KILL_ON_JOB_CLOSE (0x2000) | DIE_ON_UNHANDLED_EXCEPTION (0x400: SEM_NOGPFAULTERRORBOX for every process in
        // the job, so a crash ends the process instead of opening the Windows Error Reporting dialog, which the
        // WER service would show on the user's desktop, outside the private one).
        limits.basic.flags = 0x2000 | 0x400;
        if (!SetInformationJobObject(_job, 9, ref limits, (uint)Marshal.SizeOf(typeof(ExtendedLimits))))
            throw new Win32Exception(Marshal.GetLastWin32Error(), "SetInformationJobObject");
        var startup = new Startup { cb = Marshal.SizeOf(typeof(Startup)) };
        if (privateDesktop) { startup.desktop = "WinSta0\\" + DesktopName; startup.flags = 1; startup.show = 0; }
        else { startup.flags = 1; startup.show = 7; /* SW_SHOWMINNOACTIVE: do not take focus */ }
        IntPtr env = BuildEnvironment(environment);
        try
        {
            if (!CreateProcess(app, new StringBuilder("\"" + app + "\" " + arguments), IntPtr.Zero, IntPtr.Zero, false,
                    CreateSuspended | BelowNormalPriority | CreateUnicodeEnvironment, env, directory, ref startup, out _process))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "CreateProcess");
        }
        finally { Marshal.FreeHGlobal(env); }
        if (!AssignProcessToJobObject(_job, _process.process))
        {
            TerminateProcess(_process.process, 125);
            throw new Win32Exception(Marshal.GetLastWin32Error(), "AssignProcessToJobObject");
        }
        if (ResumeThread(_process.thread) == uint.MaxValue)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "ResumeThread");
    }

    /// <summary>True when the game process has exited (waits up to <paramref name="milliseconds"/>).</summary>
    public bool WaitForExit(uint milliseconds) { return WaitForSingleObject(_process.process, milliseconds) == 0; }

    public uint ExitCode
    {
        get { uint code; return GetExitCodeProcess(_process.process, out code) ? code : uint.MaxValue; }
    }

    /// <summary>Process ids currently in the job (the game and any child it started).</summary>
    public int[] JobPids()
    {
        const int max = 256;
        int size = 8 + IntPtr.Size * max;
        IntPtr buffer = Marshal.AllocHGlobal(size);
        try
        {
            uint returned;
            if (!QueryInformationJobObject(_job, 3, buffer, (uint)size, out returned)) return new int[0]; // JobObjectBasicProcessIdList
            int count = Marshal.ReadInt32(buffer, 4);
            var pids = new int[Math.Min(count, max)];
            for (int i = 0; i < pids.Length; i++) pids[i] = (int)Marshal.ReadIntPtr(buffer, 8 + i * IntPtr.Size).ToInt64();
            return pids;
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }

    /// <summary>Visible top-level windows of the job's processes on the desktop this thread uses (the user's).</summary>
    public string[] WindowsOnUserDesktop()
    {
        var pids = new HashSet<uint>();
        foreach (int pid in JobPids()) pids.Add((uint)pid);
        var found = new List<string>();
        EnumWindows((hwnd, l) =>
        {
            uint pid;
            GetWindowThreadProcessId(hwnd, out pid);
            if (pids.Contains(pid) && IsWindowVisible(hwnd)) found.Add(Describe(hwnd, pid));
            return true;
        }, IntPtr.Zero);
        return found.ToArray();
    }

    /// <summary>Top-level windows on the private desktop (visible flag included): what the game created there.</summary>
    public string[] WindowsOnPrivateDesktop()
    {
        var found = new List<string>();
        if (_desktop == IntPtr.Zero) return found.ToArray();
        EnumDesktopWindows(_desktop, (hwnd, l) =>
        {
            uint pid;
            GetWindowThreadProcessId(hwnd, out pid);
            found.Add(Describe(hwnd, pid) + (IsWindowVisible(hwnd) ? " visible" : " hidden"));
            return true;
        }, IntPtr.Zero);
        return found.ToArray();
    }

    static string Describe(IntPtr hwnd, uint pid)
    {
        var title = new StringBuilder(256);
        var cls = new StringBuilder(256);
        GetWindowText(hwnd, title, 256);
        GetClassName(hwnd, cls, 256);
        return "pid " + pid + " class '" + cls + "' title '" + title + "'";
    }

    /// <summary>WP-H-10: one still of the game's largest visible window into a PNG (Vt2StillCapture).</summary>
    public Vt2Still CaptureStill(string path) { return Vt2StillCapture.Capture(_desktop, JobPids(), path); }

    /// <summary>Ends the game and every child (the job), for a timeout or a window on the user's desktop.</summary>
    public void Kill()
    {
        if (_job != IntPtr.Zero) TerminateJobObject(_job, 124);
        WaitForSingleObject(_process.process, 10000);
    }

    public void Dispose()
    {
        // Closing the job ends anything still running in it (KILL_ON_JOB_CLOSE).
        if (_job != IntPtr.Zero) { CloseHandle(_job); _job = IntPtr.Zero; }
        if (_process.thread != IntPtr.Zero) { CloseHandle(_process.thread); _process.thread = IntPtr.Zero; }
        if (_process.process != IntPtr.Zero) { CloseHandle(_process.process); _process.process = IntPtr.Zero; }
        if (_desktop != IntPtr.Zero) { CloseDesktop(_desktop); _desktop = IntPtr.Zero; }
    }
}

// WP-H-10: one still of the game window, taken by the host (the game is never asked to do anything).
public sealed class Vt2Still
{
    public bool Ok;
    public string Route = "PrintWindow";
    public string Path, Window, Error;
    public int Width, Height;
    public double MeanBrightness;
}

public static class Vt2StillCapture
{
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int left, top, right, bottom; }
    [StructLayout(LayoutKind.Sequential)]
    struct BitmapInfoHeader
    {
        public uint size;
        public int width, height;
        public ushort planes, bitCount;
        public uint compression, sizeImage;
        public int xPelsPerMeter, yPelsPerMeter;
        public uint clrUsed, clrImportant;
    }
    delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lParam);
    [DllImport("user32.dll", SetLastError = true)] static extern bool SetThreadDesktop(IntPtr desktop);
    [DllImport("user32.dll")] static extern bool EnumDesktopWindows(IntPtr desktop, EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc callback, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr hwnd, out Rect rect);
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr hwnd);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr hwnd, IntPtr dc);
    [DllImport("user32.dll", SetLastError = true)] static extern bool PrintWindow(IntPtr hwnd, IntPtr dc, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder text, int max);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleBitmap(IntPtr dc, int width, int height);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc, IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr obj);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern int GetDIBits(IntPtr dc, IntPtr bitmap, uint start, uint lines, byte[] bits, ref BitmapInfoHeader info, uint usage);

    const uint PW_CLIENTONLY = 0x1, PW_RENDERFULLCONTENT = 0x2;

    /// <summary>
    /// Captures the largest visible window of the given processes with PrintWindow(PW_CLIENTONLY | PW_RENDERFULLCONTENT)
    /// and writes it as a PNG. With a desktop handle the work runs on a new thread attached to that desktop
    /// (SetThreadDesktop needs a thread that owns no window); IntPtr.Zero means the caller's own desktop.
    /// </summary>
    public static Vt2Still Capture(IntPtr desktop, int[] pids, string path)
    {
        Vt2Still result = null;
        var thread = new System.Threading.Thread(() =>
        {
            try { result = CaptureHere(desktop, pids, path); }
            catch (Exception e) { result = new Vt2Still { Path = path, Error = e.GetType().Name + ": " + e.Message }; }
        });
        thread.IsBackground = true;
        thread.Start();
        if (!thread.Join(15000)) return new Vt2Still { Path = path, Error = "capture thread did not finish in 15 s" };
        return result;
    }

    static Vt2Still CaptureHere(IntPtr desktop, int[] pids, string path)
    {
        var still = new Vt2Still { Path = path };
        if (desktop != IntPtr.Zero && !SetThreadDesktop(desktop)) { still.Error = "SetThreadDesktop failed: " + Marshal.GetLastWin32Error(); return still; }
        var wanted = new HashSet<uint>();
        foreach (int pid in pids) wanted.Add((uint)pid);
        IntPtr best = IntPtr.Zero;
        long bestArea = 0;
        EnumWindowsProc pick = (hwnd, l) =>
        {
            uint pid;
            GetWindowThreadProcessId(hwnd, out pid);
            Rect r;
            if (wanted.Contains(pid) && IsWindowVisible(hwnd) && GetClientRect(hwnd, out r))
            {
                long area = (long)(r.right - r.left) * (r.bottom - r.top);
                if (area > bestArea) { bestArea = area; best = hwnd; }
            }
            return true;
        };
        if (desktop != IntPtr.Zero) EnumDesktopWindows(desktop, pick, IntPtr.Zero); else EnumWindows(pick, IntPtr.Zero);
        if (best == IntPtr.Zero) { still.Error = "no visible window of the game's processes"; return still; }
        var cls = new StringBuilder(256);
        GetClassName(best, cls, 256);
        still.Window = cls.ToString();
        Rect client;
        GetClientRect(best, out client);
        int w = client.right - client.left, h = client.bottom - client.top;
        if (w <= 0 || h <= 0) { still.Error = "window client area is empty"; return still; }
        IntPtr windowDc = GetDC(best);
        IntPtr memDc = CreateCompatibleDC(windowDc);
        IntPtr bitmap = CreateCompatibleBitmap(windowDc, w, h);
        IntPtr old = SelectObject(memDc, bitmap);
        try
        {
            if (!PrintWindow(best, memDc, PW_CLIENTONLY | PW_RENDERFULLCONTENT)) { still.Error = "PrintWindow failed: " + Marshal.GetLastWin32Error(); return still; }
            var info = new BitmapInfoHeader { size = (uint)Marshal.SizeOf(typeof(BitmapInfoHeader)), width = w, height = -h, planes = 1, bitCount = 32 };
            var bgra = new byte[w * h * 4];
            SelectObject(memDc, old);
            if (GetDIBits(memDc, bitmap, 0, (uint)h, bgra, ref info, 0) != h) { still.Error = "GetDIBits failed"; return still; }
            Vt2Png.Write(path, bgra, w, h, still);
            return still;
        }
        finally
        {
            SelectObject(memDc, old);
            DeleteObject(bitmap);
            DeleteDC(memDc);
            ReleaseDC(best, windowDc);
        }
    }
}

/// <summary>A minimal PNG writer (8-bit RGB, filter 0, zlib) plus the mean brightness of the image.</summary>
public static class Vt2Png
{
    static readonly uint[] Crc = BuildCrc();
    static uint[] BuildCrc()
    {
        var t = new uint[256];
        for (uint n = 0; n < 256; n++) { uint c = n; for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1; t[n] = c; }
        return t;
    }
    static uint Crc32(byte[] data, int offset, int count)
    {
        uint c = 0xFFFFFFFFu;
        for (int i = offset; i < offset + count; i++) c = Crc[(c ^ data[i]) & 0xFF] ^ (c >> 8);
        return c ^ 0xFFFFFFFFu;
    }
    static void BigEndian(System.IO.Stream s, uint v) { s.WriteByte((byte)(v >> 24)); s.WriteByte((byte)(v >> 16)); s.WriteByte((byte)(v >> 8)); s.WriteByte((byte)v); }
    static void Chunk(System.IO.Stream s, string type, byte[] data)
    {
        BigEndian(s, (uint)data.Length);
        var buf = new byte[4 + data.Length];
        Encoding.ASCII.GetBytes(type, 0, 4, buf, 0);
        Buffer.BlockCopy(data, 0, buf, 4, data.Length);
        s.Write(buf, 0, buf.Length);
        BigEndian(s, Crc32(buf, 0, buf.Length));
    }

    /// <summary>Writes top-down 32-bit BGRA pixels as an RGB PNG and fills Width, Height, MeanBrightness, Ok.</summary>
    public static void Write(string path, byte[] bgra, int width, int height, Vt2Still still)
    {
        var raw = new byte[height * (1 + width * 3)];
        double sum = 0;
        int o = 0;
        for (int y = 0; y < height; y++)
        {
            raw[o++] = 0;
            for (int x = 0; x < width; x++)
            {
                int i = (y * width + x) * 4;
                byte b = bgra[i], g = bgra[i + 1], r = bgra[i + 2];
                raw[o++] = r; raw[o++] = g; raw[o++] = b;
                sum += 0.299 * r + 0.587 * g + 0.114 * b;
            }
        }
        byte[] packed;
        using (var ms = new System.IO.MemoryStream())
        {
            using (var z = new System.IO.Compression.ZLibStream(ms, System.IO.Compression.CompressionLevel.Optimal, true)) z.Write(raw, 0, raw.Length);
            packed = ms.ToArray();
        }
        var ihdr = new byte[13];
        ihdr[0] = (byte)(width >> 24); ihdr[1] = (byte)(width >> 16); ihdr[2] = (byte)(width >> 8); ihdr[3] = (byte)width;
        ihdr[4] = (byte)(height >> 24); ihdr[5] = (byte)(height >> 16); ihdr[6] = (byte)(height >> 8); ihdr[7] = (byte)height;
        ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
        using (var f = System.IO.File.Create(path))
        {
            f.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }, 0, 8);
            Chunk(f, "IHDR", ihdr);
            Chunk(f, "IDAT", packed);
            Chunk(f, "IEND", new byte[0]);
        }
        still.Path = path;
        still.Width = width;
        still.Height = height;
        still.MeanBrightness = width * height > 0 ? sum / (width * height) : 0;
        still.Ok = true;
    }
}
