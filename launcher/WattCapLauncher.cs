// WattCap Launcher v2 - animates the desktop icon's fans, then hands off to gpu-power-limit.cmd.
// Build: build.cmd (csc /target:winexe ... WattCapLauncher.cs Widget.cs)
using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

[assembly: AssemblyTitle("WattCap Launcher v2")]
[assembly: AssemblyProduct("WattCap Launcher")]
[assembly: AssemblyVersion("2.0.0.0")]
[assembly: AssemblyFileVersion("2.0.0.0")]

static class WattCapLauncher
{
    // ---------------- configuration ----------------
    const string CMD = @"C:\ProgramData\GPUPowerLimit\gpu-power-limit.cmd";
    const string WORKDIR = @"C:\ProgramData\GPUPowerLimit";
    const bool RUN_AS_ADMIN = true;           // original .lnk had the RunAsAdministrator flag
    const string ITEM_TEXT = "WattCap RTX Power Limit";
    internal const int FRAMES = 80;                    // frames per 40 deg blade period (9 blades), 0.5 deg steps
    internal const double PERIOD_DEG = 40.0;
    const double FADE = 0.15;  // overlay fade after the settle (last frame == static icon, so invisible)
    internal const double MAX_DEG_PER_S = 1080.0;      // 18 deg/frame @60fps (< half period: no backwards aliasing)

    internal static string Dir = AppDomain.CurrentDomain.BaseDirectory;
    static StringBuilder Log = new StringBuilder();
    static Stopwatch Clock = Stopwatch.StartNew();
    internal static void L(string s) { lock (Log) Log.AppendFormat("[{0,7:0.0} ms] {1}\r\n", Clock.Elapsed.TotalMilliseconds, s); }

    [STAThread]
    static int Main(string[] args)
    {
        bool launch = Array.IndexOf(args, "--launch") >= 0;       // desktop shortcut: icon fx + launch
        bool noLaunch = Array.IndexOf(args, "--nolaunch") >= 0;   // debugging: fx only
        bool noFx = Array.IndexOf(args, "--nofx") >= 0;
        foreach (var a in args) if (a.StartsWith("--uacms=")) int.TryParse(a.Substring(8), out SimUacMs);
        try { L("WattCap Launcher v2 start (" + string.Join(" ", args) + "), process uptime " + (DateTime.Now - Process.GetCurrentProcess().StartTime).TotalMilliseconds.ToString("0") + " ms"); } catch { }
        if (!launch)
        {
            Simulate = noLaunch || Array.IndexOf(args, "--selftest") >= 0;   // widget --nolaunch: UAC simulated (--uacms=N), never runs the cmd
            try { Widget.Run(Array.IndexOf(args, "--selftest") >= 0); }
            catch (Exception e) { L("widget failed: " + e); FlushLog("widget.log"); }
            return 0;
        }
        Simulate = noLaunch;
        if (!noFx) { try { Animate(); } catch (Exception e) { L("animation failed: " + e); } }
        if (!LaunchStarted) { L("animation did not start the launch; launching now"); StartLaunchThread(); }
        try { if (LaunchThread != null) LaunchThread.Join(120000); } catch { }
        L("done"); FlushLog("launcher.log");
        return 0;
    }

    internal static void FlushLog(string name)
    {
        try { lock (Log) { File.AppendAllText(Path.Combine(Dir, name), Log.ToString()); Log.Length = 0; } } catch { }
    }
    internal static void SetDpiAware()
    {
        try { if (SetProcessDpiAwarenessContext((IntPtr)(-4)) == false) SetProcessDPIAware(); }
        catch { try { SetProcessDPIAware(); } catch { } }
    }
    // ---- launch state shared with the animation (set from the launch thread) ----
    internal static volatile bool LaunchStarted, LaunchDone, Simulate;
    internal static int SimUacMs = 800;
    static Thread LaunchThread;
    internal static void StartLaunchThread()
    {
        if (LaunchStarted) return;
        LaunchStarted = true; LaunchDone = false;
        LaunchThread = new Thread(LaunchCmd); LaunchThread.IsBackground = false; LaunchThread.Start();
    }
    internal static void ResetLaunch() { LaunchStarted = false; LaunchDone = false; }
    internal static IntPtr DesktopOwner() { return FindWindow("Progman", null); }
    internal static int LogicalIconSize()
    {
        int logical = 48;
        try
        {
            using (var k = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\Shell\Bags\1\Desktop"))
                if (k != null && k.GetValue("IconSize") != null) logical = Convert.ToInt32(k.GetValue("IconSize"));
        }
        catch { }
        return logical;
    }

    static void LaunchCmd()
    {
        try
        {
            if (Simulate) { L("SIMULATED launch (no cmd), UAC " + SimUacMs + " ms"); Thread.Sleep(SimUacMs); return; }
            var sei = new SHELLEXECUTEINFO();
            sei.cbSize = Marshal.SizeOf(typeof(SHELLEXECUTEINFO));
            sei.fMask = 0x00000400; // SEE_MASK_FLAG_NO_UI
            sei.lpVerb = RUN_AS_ADMIN ? "runas" : "open";
            sei.lpFile = CMD;
            sei.lpDirectory = WORKDIR;
            sei.nShow = 1;
            bool ok = ShellExecuteEx(ref sei);
            L("ShellExecuteEx(" + sei.lpVerb + ") -> " + ok + (ok ? "" : " err " + Marshal.GetLastWin32Error()));
            if (!ok && RUN_AS_ADMIN && Marshal.GetLastWin32Error() != 1223) // 1223 = user cancelled UAC
            {
                sei.lpVerb = "open"; ok = ShellExecuteEx(ref sei);  // cmd self-elevates anyway
                L("fallback open -> " + ok);
            }
        }
        catch (Exception e) { L("launch failed: " + e.Message); }
        finally { LaunchDone = true; L("launch returned"); }
    }

    // ---------------- icon location ----------------
    static bool FindIcon(out RECT rc, out int imgSize, out IntPtr lv)
    {
        rc = new RECT(); imgSize = 0;
        lv = FindDesktopListView();
        if (lv == IntPtr.Zero) { L("desktop SysListView32 not found"); return false; }
        uint pid; GetWindowThreadProcessId(lv, out pid);
        IntPtr hp = OpenProcess(0x0008 | 0x0010 | 0x0020 | 0x0400, false, pid);
        if (hp == IntPtr.Zero) { L("OpenProcess failed"); return false; }
        IntPtr mem = VirtualAllocEx(hp, IntPtr.Zero, (UIntPtr)4096, 0x3000, 0x04);
        try
        {
            if (mem == IntPtr.Zero) { L("VirtualAllocEx failed"); return false; }
            int count = (int)SendMessage(lv, 0x1004 /*LVM_GETITEMCOUNT*/, IntPtr.Zero, IntPtr.Zero);
            L("desktop items: " + count);
            IntPtr textRemote = (IntPtr)(mem.ToInt64() + 1024);
            for (int i = 0; i < count; i++)
            {
                // LVITEMW (x64): mask@0 iItem@4 iSubItem@8 state@12 stateMask@16 pszText@24 cchTextMax@32
                byte[] item = new byte[88];
                BitConverter.GetBytes(0x0001u).CopyTo(item, 0);
                BitConverter.GetBytes(i).CopyTo(item, 4);
                BitConverter.GetBytes(textRemote.ToInt64()).CopyTo(item, 24);
                BitConverter.GetBytes(260).CopyTo(item, 32);
                IntPtr n; WriteProcessMemory(hp, mem, item, item.Length, out n);
                int len = (int)SendMessage(lv, 0x1073 /*LVM_GETITEMTEXTW*/, (IntPtr)i, mem);
                if (len <= 0) continue;
                byte[] tb = new byte[len * 2];
                ReadProcessMemory(hp, textRemote, tb, tb.Length, out n);
                string t = Encoding.Unicode.GetString(tb);
                if (!string.Equals(t, ITEM_TEXT, StringComparison.OrdinalIgnoreCase) &&
                    !string.Equals(t, ITEM_TEXT + ".lnk", StringComparison.OrdinalIgnoreCase)) continue;
                byte[] r = new byte[16]; BitConverter.GetBytes(1 /*LVIR_ICON*/).CopyTo(r, 0);
                WriteProcessMemory(hp, mem, r, 16, out n);
                if (SendMessage(lv, 0x100E /*LVM_GETITEMRECT*/, (IntPtr)i, mem) == IntPtr.Zero) { L("LVM_GETITEMRECT failed"); return false; }
                ReadProcessMemory(hp, mem, r, 16, out n);
                rc.left = BitConverter.ToInt32(r, 0); rc.top = BitConverter.ToInt32(r, 4);
                rc.right = BitConverter.ToInt32(r, 8); rc.bottom = BitConverter.ToInt32(r, 12);
                byte[] p = new byte[8];
                WriteProcessMemory(hp, mem, p, 8, out n);
                SendMessage(lv, 0x1010 /*LVM_GETITEMPOSITION*/, (IntPtr)i, mem);
                ReadProcessMemory(hp, mem, p, 8, out n);
                L(string.Format("item {0} '{1}' client iconRect=({2},{3},{4},{5}) pos=({6},{7})", i, t, rc.left, rc.top, rc.right, rc.bottom, BitConverter.ToInt32(p, 0), BitConverter.ToInt32(p, 4)));
                POINT tl = new POINT { x = rc.left, y = rc.top }; ClientToScreen(lv, ref tl);
                int w = rc.right - rc.left, h = rc.bottom - rc.top;
                rc.left = tl.x; rc.top = tl.y; rc.right = tl.x + w; rc.bottom = tl.y + h;
                imgSize = DesktopIconPixels(lv);
                return true;
            }
            L("item '" + ITEM_TEXT + "' not found");
            return false;
        }
        finally { if (mem != IntPtr.Zero) VirtualFreeEx(hp, mem, UIntPtr.Zero, 0x8000); CloseHandle(hp); }
    }

    static int DesktopIconPixels(IntPtr lv)
    {
        int logical = 48;
        try
        {
            using (var k = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\Shell\Bags\1\Desktop"))
                if (k != null && k.GetValue("IconSize") != null) logical = Convert.ToInt32(k.GetValue("IconSize"));
        }
        catch { }
        int dpi = 96;
        try { dpi = (int)GetDpiForWindow(lv); } catch { }
        if (dpi <= 0) dpi = 96;
        int px = (int)Math.Round(logical * dpi / 96.0);
        L("IconSize=" + logical + " dpi=" + dpi + " -> " + px + " px");
        return px;
    }

    static IntPtr FindDesktopListView()
    {
        IntPtr progman = FindWindow("Progman", null);
        IntPtr dv = FindWindowEx(progman, IntPtr.Zero, "SHELLDLL_DefView", null);
        IntPtr w = IntPtr.Zero;
        while (dv == IntPtr.Zero && (w = FindWindowEx(IntPtr.Zero, w, "WorkerW", null)) != IntPtr.Zero)
            dv = FindWindowEx(w, IntPtr.Zero, "SHELLDLL_DefView", null);
        return dv == IntPtr.Zero ? IntPtr.Zero : FindWindowEx(dv, IntPtr.Zero, "SysListView32", null);
    }

    // ---------------- animation ----------------
    static void Animate()
    {
        SetDpiAware();
        RECT rc; int size; IntPtr lv;
        if (!FindIcon(out rc, out size, out lv)) return;
        int iw = rc.right - rc.left, ih = rc.bottom - rc.top;
        if (iw <= 0 || ih <= 0 || iw > 1024 || size <= 0 || size > 512) { L("rect not sane, skipping"); return; }
        if (size > iw) size = iw;
        // Shell centers the image horizontally in LVIR_ICON and bottom-aligns it (2px gap) for large icons.
        int x = rc.left + (iw - size) / 2;
        int y = rc.bottom - size - Math.Max(0, Math.Min(2, ih - size));
        if (ih - size > 6) y = rc.top + (ih - size) / 2;
        L(string.Format("screen iconRect=({0},{1},{2},{3}) overlay=({4},{5}) {6}x{6}", rc.left, rc.top, rc.right, rc.bottom, x, y, size));
        // Only animate if the icon is actually visible (not covered by a window).
        IntPtr hit = WindowFromPoint(new POINT { x = x + size / 2, y = y + size / 2 });
        if (hit != lv && GetAncestor(hit, 2) != GetAncestor(lv, 2)) { L("icon covered by window " + hit + ", skipping"); return; }

        byte[][] frames = LoadFrames(size);
        if (frames == null) return;
        L("frames loaded");

        IntPtr hwnd = CreateWindowEx(0x00080000 | 0x00000020 | 0x00000008 | 0x00000080 | 0x08000000,
            "Static", "WattCapFx", unchecked((int)0x80000000), x, y, size, size, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero);
        if (hwnd == IntPtr.Zero) { L("CreateWindowEx failed"); return; }
        IntPtr screenDC = GetDC(IntPtr.Zero), memDC = CreateCompatibleDC(screenDC);
        var bmi = new BITMAPINFOHEADER { biSize = 40, biWidth = size, biHeight = -size, biPlanes = 1, biBitCount = 32 };
        IntPtr bits; IntPtr dib = CreateDIBSection(screenDC, ref bmi, 0, out bits, IntPtr.Zero, 0);
        IntPtr old = SelectObject(memDC, dib);
        timeBeginPeriod(1);
        try
        {
            var ptDst = new POINT { x = x, y = y }; var sz = new SIZE { cx = size, cy = size }; var ptSrc = new POINT();
            var spin = new Spin(); var t0 = Stopwatch.StartNew(); bool shown = false; int drawn = 0; double fadeAt = -1;
            while (true)
            {
                double t = t0.Elapsed.TotalSeconds;
                double ang = spin.Update(t, LaunchDone);
                if (spin.WantLaunch) { spin.WantLaunch = false; L("full speed -> launch"); StartLaunchThread(); }
                if (spin.Finished && fadeAt < 0) fadeAt = t;
                double fa = fadeAt < 0 ? 1.0 : 1.0 - (t - fadeAt) / FADE;
                if (fa <= 0) break;
                if (t > 120) { L("timeout"); break; }
                int f = Spin.Frame(ang);
                Marshal.Copy(frames[f], 0, bits, frames[f].Length);
                var bf = new BLENDFUNCTION { BlendOp = 0, SourceConstantAlpha = (byte)Math.Max(0, Math.Min(255, fa * 255)), AlphaFormat = 1 };
                UpdateLayeredWindow(hwnd, screenDC, ref ptDst, ref sz, memDC, ref ptSrc, 0, ref bf, 2);
                if (!shown) { ShowWindow(hwnd, 4 /*SW_SHOWNOACTIVATE*/); shown = true; L("overlay shown"); }
                drawn++;
                MSG m; while (PeekMessage(out m, IntPtr.Zero, 0, 0, 1)) { TranslateMessage(ref m); DispatchMessage(ref m); }
                double next = (drawn) / 60.0 - t0.Elapsed.TotalSeconds;
                if (next > 0.001) Thread.Sleep((int)(next * 1000));
                else DwmFlushSafe();
            }
            L(spin.Summary());
            L(string.Format("animation done: {0} frames in {1:0} ms", drawn, t0.Elapsed.TotalMilliseconds));
        }
        finally
        {
            timeEndPeriod(1);
            DestroyWindow(hwnd); SelectObject(memDC, old); DeleteObject(dib); DeleteDC(memDC); ReleaseDC(IntPtr.Zero, screenDC);
        }
    }
    static void DwmFlushSafe() { try { DwmFlush(); } catch { } }

    internal static string SheetFor(int size)
    {
        int[] sizes = { 24, 32, 36, 40, 48, 56, 60, 64, 72, 80, 96, 112, 120, 128, 144, 160, 168, 192, 240, 256 };
        foreach (int s in sizes) { string f = Path.Combine(Dir, "assets\\fans_" + s + ".png"); if (s >= size && File.Exists(f)) return f; }
        return Path.Combine(Dir, "assets\\fans_256.png");
    }

    static byte[][] LoadFrames(int size)
    {
        string exact = Path.Combine(Dir, "assets\\fans_" + size + ".png");
        string file = File.Exists(exact) ? exact : null;
        if (file == null)
        {   // nearest larger sheet, scaled down
            file = SheetFor(size);
        }
        if (!File.Exists(file)) { L("missing " + file); return null; }
        L("sheet " + Path.GetFileName(file) + (file == exact ? " (exact)" : " (scaled)"));
        var res = new byte[FRAMES][];
        using (var sheet = new Bitmap(file))
        {
            int fs = sheet.Height;
            using (var bmp = new Bitmap(size, size, PixelFormat.Format32bppPArgb))
            using (var g = Graphics.FromImage(bmp))
            {
                g.InterpolationMode = System.Drawing.Drawing2D.InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
                g.CompositingMode = System.Drawing.Drawing2D.CompositingMode.SourceCopy;
                for (int i = 0; i < FRAMES; i++)
                {
                    g.DrawImage(sheet, new Rectangle(0, 0, size, size), new Rectangle(i * fs, 0, fs, fs), GraphicsUnit.Pixel);
                    var bd = bmp.LockBits(new Rectangle(0, 0, size, size), ImageLockMode.ReadOnly, PixelFormat.Format32bppPArgb);
                    res[i] = new byte[size * size * 4];
                    for (int row = 0; row < size; row++)
                        Marshal.Copy((IntPtr)(bd.Scan0.ToInt64() + (long)row * bd.Stride), res[i], row * size * 4, size * 4);
                    bmp.UnlockBits(bd);
                }
            }
        }
        return res;
    }

    // ---------------- interop ----------------
    [StructLayout(LayoutKind.Sequential)] internal struct RECT { public int left, top, right, bottom; }
    [StructLayout(LayoutKind.Sequential)] internal struct POINT { public int x, y; }
    [StructLayout(LayoutKind.Sequential)] internal struct SIZE { public int cx, cy; }
    [StructLayout(LayoutKind.Sequential, Pack = 1)] internal struct BLENDFUNCTION { public byte BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat; }
    [StructLayout(LayoutKind.Sequential)] internal struct BITMAPINFOHEADER { public int biSize, biWidth, biHeight; public short biPlanes, biBitCount; public int biCompression, biSizeImage, biXPelsPerMeter, biYPelsPerMeter, biClrUsed, biClrImportant; }
    [StructLayout(LayoutKind.Sequential)] internal struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam, lParam; public uint time; public POINT pt; }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    internal struct SHELLEXECUTEINFO
    {
        public int cbSize; public uint fMask; public IntPtr hwnd; public string lpVerb, lpFile, lpParameters, lpDirectory;
        public int nShow; public IntPtr hInstApp, lpIDList; public string lpClass; public IntPtr hkeyClass; public uint dwHotKey; public IntPtr hIcon, hProcess;
    }
    [DllImport("shell32.dll", CharSet = CharSet.Unicode, SetLastError = true)] internal static extern bool ShellExecuteEx(ref SHELLEXECUTEINFO i);
    [DllImport("user32.dll")] internal static extern bool SetProcessDpiAwarenessContext(IntPtr v);
    [DllImport("user32.dll")] internal static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] internal static extern uint GetDpiForWindow(IntPtr h);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern IntPtr FindWindow(string c, string n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string n);
    [DllImport("user32.dll")] internal static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("user32.dll")] internal static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] internal static extern bool ClientToScreen(IntPtr h, ref POINT p);
    [DllImport("user32.dll")] internal static extern IntPtr WindowFromPoint(POINT p);
    [DllImport("user32.dll")] internal static extern IntPtr GetAncestor(IntPtr h, uint f);
    [DllImport("kernel32.dll")] internal static extern IntPtr OpenProcess(uint a, bool i, uint pid);
    [DllImport("kernel32.dll")] internal static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll")] internal static extern IntPtr VirtualAllocEx(IntPtr p, IntPtr a, UIntPtr s, uint t, uint pr);
    [DllImport("kernel32.dll")] internal static extern bool VirtualFreeEx(IntPtr p, IntPtr a, UIntPtr s, uint t);
    [DllImport("kernel32.dll")] internal static extern bool WriteProcessMemory(IntPtr p, IntPtr a, byte[] b, int s, out IntPtr n);
    [DllImport("kernel32.dll")] internal static extern bool ReadProcessMemory(IntPtr p, IntPtr a, byte[] b, int s, out IntPtr n);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] internal static extern IntPtr CreateWindowEx(int ex, string cls, string name, int style, int x, int y, int w, int h, IntPtr p, IntPtr m, IntPtr i, IntPtr l);
    [DllImport("user32.dll")] internal static extern bool DestroyWindow(IntPtr h);
    [DllImport("user32.dll")] internal static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] internal static extern bool UpdateLayeredWindow(IntPtr h, IntPtr dst, ref POINT pd, ref SIZE s, IntPtr src, ref POINT ps, int key, ref BLENDFUNCTION b, int f);
    [DllImport("user32.dll")] internal static extern bool PeekMessage(out MSG m, IntPtr h, uint a, uint b, uint r);
    [DllImport("user32.dll")] internal static extern bool TranslateMessage(ref MSG m);
    [DllImport("user32.dll")] internal static extern IntPtr DispatchMessage(ref MSG m);
    [DllImport("user32.dll")] internal static extern IntPtr GetDC(IntPtr h);
    [DllImport("user32.dll")] internal static extern int ReleaseDC(IntPtr h, IntPtr dc);
    [DllImport("gdi32.dll")] internal static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] internal static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] internal static extern IntPtr SelectObject(IntPtr dc, IntPtr o);
    [DllImport("gdi32.dll")] internal static extern bool DeleteObject(IntPtr o);
    [DllImport("gdi32.dll")] internal static extern IntPtr CreateDIBSection(IntPtr dc, ref BITMAPINFOHEADER b, uint u, out IntPtr bits, IntPtr s, uint o);
    [DllImport("winmm.dll")] internal static extern uint timeBeginPeriod(uint p);
    [DllImport("winmm.dll")] internal static extern uint timeEndPeriod(uint p);
    [DllImport("dwmapi.dll")] internal static extern int DwmFlush();
}

// Shared fan motion: smooth ease-in spin-up -> full speed (launch) -> hold until the launch returns
// (>= MIN_HOLD) -> quadratic coast-down landing exactly on a blade-period multiple -> damped settle jolt.
class Spin
{
    public const double SPINUP = 1.35, MIN_HOLD = 0.4, SETTLE = 0.55, WMAX = WattCapLauncher.MAX_DEG_PER_S;
    const double JOLT_DEG = 3.0, JOLT_HZ = 5.0, JOLT_DECAY = 7.0, DOWN_TARGET = 2.75, DOWN_MIN = 2.4, DOWN_MAX = 3.1;
    public bool WantLaunch, Finished;
    bool launched; double downAt = -1, downTheta, downD, vEnd, target, settleAt = -1, wD;
    double fullAt = -1, doneSeenAt = -1;
    static double Up(double s) { return WMAX * SPINUP * (s * s * s - 0.5 * s * s * s * s); } // integral of smoothstep
    public double Update(double t, bool launchDone)
    {
        if (t < SPINUP) { double s = t / SPINUP; return Up(s); }
        if (!launched) { launched = true; WantLaunch = true; fullAt = t; }
        if (downAt < 0)
        {
            double th = Up(1) + WMAX * (t - SPINUP);
            if (launchDone && doneSeenAt < 0) doneSeenAt = t;
            if (!(launchDone && t - SPINUP >= MIN_HOLD)) return th;
            // plan the coast: w(tau) = vEnd + (WMAX - vEnd)(1 - tau/D)^2  => distance = vEnd*D + (WMAX - vEnd)*D/3
            wD = 2 * Math.PI * JOLT_HZ; vEnd = JOLT_DEG * wD;   // residual speed that feeds the jolt (deg/s)
            downAt = t; downTheta = th;
            double per = WattCapLauncher.PERIOD_DEG, k = Math.Ceiling((th + dist(DOWN_MIN)) / per), best = -1, bestErr = 1e9;
            for (double kk = k; ; kk++)
            {
                double D = (kk * per - th) / (vEnd + (WMAX - vEnd) / 3.0);
                if (D > DOWN_MAX) break;
                if (D >= DOWN_MIN && Math.Abs(D - DOWN_TARGET) < bestErr) { bestErr = Math.Abs(D - DOWN_TARGET); best = kk; }
            }
            if (best < 0) best = k;
            target = best * per; downD = (target - th) / (vEnd + (WMAX - vEnd) / 3.0);
        }
        double tau = t - downAt;
        if (tau < downD)
        {
            double u = 1 - tau / downD;
            return downTheta + vEnd * tau + (WMAX - vEnd) * downD / 3.0 * (1 - u * u * u);
        }
        // damped oscillation around the target, continuous velocity (starts with vEnd), ends exactly on target
        double ts = tau - downD;
        if (ts >= SETTLE) { Finished = true; return target; }
        if (settleAt < 0) settleAt = t;
        return target + vEnd / wD * Math.Exp(-JOLT_DECAY * ts) * Math.Sin(wD * ts);
    }
    double dist(double D) { double w = 2 * Math.PI * JOLT_HZ, v = JOLT_DEG * w; return v * D + (WMAX - v) * D / 3.0; }
    public static int Frame(double ang)
    {
        double p = WattCapLauncher.PERIOD_DEG, a = ang % p; if (a < 0) a += p;
        return (int)Math.Round(a / p * WattCapLauncher.FRAMES) % WattCapLauncher.FRAMES;
    }
    public string Summary()
    {
        return string.Format("motion: full speed/launch at {0:0.000}s, launch returned at {1:0.000}s, coast {2:0.000}-{3:0.000}s ({4:0.00}s, {5:0} deg -> {6:0} deg), settle {7:0.000}-{8:0.000}s, final frame {9}",
            fullAt, doneSeenAt, downAt, downAt + downD, downD, downTheta, target, settleAt, settleAt + SETTLE, Frame(target));
    }
}
