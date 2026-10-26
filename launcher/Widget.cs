// WattCap Launcher v2 - desktop widget: double-size WattCap button pinned to the desktop layer.
// Double-click: fan spin-up + launch. Hover: highlight. Right-drag or Ctrl+left-drag: move (saved).
// Right-click (no drag): menu (Launch / Reset position / Exit).
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using W = WattCapLauncher;

static class Widget
{
    delegate IntPtr WndProcD(IntPtr h, uint m, IntPtr w, IntPtr l);
    static WndProcD proc = WndProc;
    static IntPtr hwnd, owner;
    static int dpi = 96, img, pad, width, height, posX, posY;
    static Bitmap[] frames;
    static int frame;
    static bool hover, animating, dragging, rightDown, quitting;
    static W.POINT dragStartCursor; static int dragStartX, dragStartY;
    static System.Diagnostics.Stopwatch anim = new System.Diagnostics.Stopwatch();
    static string Settings { get { return Path.Combine(W.Dir, "settings.ini"); } }
    static Spin spin; static bool selfTest;
    static Mutex mutex;

    public static void Run(bool selftest)
    {
        selfTest = selftest;
        bool created;
        mutex = new Mutex(true, @"Local\WattCapWidget_v2", out created);
        if (!created) { W.L("widget already running"); W.FlushLog("widget.log"); return; }
        W.SetDpiAware();
        var wc = new WNDCLASSEX { cbSize = Marshal.SizeOf(typeof(WNDCLASSEX)), style = 0x0008 /*CS_DBLCLKS*/,
            lpfnWndProc = Marshal.GetFunctionPointerForDelegate(proc), hInstance = GetModuleHandle(null),
            hCursor = LoadCursor(IntPtr.Zero, (IntPtr)32649 /*IDC_HAND*/), lpszClassName = "WattCapWidget" };
        RegisterClassEx(ref wc);
        LoadPos();
        while (!quitting)
        {
            owner = W.DesktopOwner();
            // WS_EX_LAYERED | TOOLWINDOW (no taskbar) | NOACTIVATE; WS_POPUP; owned by Progman = lives on the desktop layer
            hwnd = CreateWindowEx(0x00080000 | 0x00000080 | 0x08000000, "WattCapWidget", "WattCap", unchecked((int)0x80000000),
                posX, posY, 10, 10, owner, IntPtr.Zero, wc.hInstance, IntPtr.Zero);
            if (hwnd == IntPtr.Zero) { W.L("CreateWindowEx failed"); break; }
            Layout();
            Render();
            ShowWindow(hwnd, 4);
            SetWindowPos(hwnd, (IntPtr)1 /*HWND_BOTTOM*/, 0, 0, 0, 0, 0x0013);
            SetTimer(hwnd, (IntPtr)2, 2000, IntPtr.Zero);
            if (selfTest) SetTimer(hwnd, (IntPtr)3, 500, IntPtr.Zero);
            W.L(string.Format("widget up at ({0},{1}) {2}x{3} img={4} dpi={5} owner=0x{6:X}", posX, posY, width, height, img, dpi, owner.ToInt64()));
            W.FlushLog("widget.log");
            MSG m;
            while (GetMessage(out m, IntPtr.Zero, 0, 0) > 0) { TranslateMessage(ref m); DispatchMessage(ref m); }
            if (!quitting) { W.L("widget window lost (explorer restart?), recreating"); Thread.Sleep(3000); }
        }
        W.L("widget exit"); W.FlushLog("widget.log");
    }

    static void Layout()
    {
        int d = 96; try { d = (int)GetDpiForWindow(hwnd); } catch { }
        if (d <= 0) d = 96;
        dpi = d;
        int iconPx = (int)Math.Round(W.LogicalIconSize() * dpi / 96.0);
        img = iconPx * 2;                       // double the desktop icon size
        pad = Math.Max(4, img / 10);
        width = img + pad * 2;
        height = img + pad + (int)Math.Ceiling(img * 0.30);
        if (frames != null) foreach (var f in frames) f.Dispose();
        frames = new Bitmap[W.FRAMES];
        using (var sheet = new Bitmap(W.SheetFor(img)))
        {
            int fs = sheet.Height;
            for (int i = 0; i < W.FRAMES; i++)
            {
                frames[i] = new Bitmap(img, img, PixelFormat.Format32bppPArgb);
                using (var g = Graphics.FromImage(frames[i]))
                {
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic; g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.CompositingMode = CompositingMode.SourceCopy;
                    g.DrawImage(sheet, new Rectangle(0, 0, img, img), new Rectangle(i * fs, 0, fs, fs), GraphicsUnit.Pixel);
                }
            }
        }
        ClampToScreen();
    }

    static void ClampToScreen()
    {
        var pt = new W.POINT { x = posX + width / 2, y = posY + height / 2 };
        if (MonitorFromPoint(pt, 0 /*NULL*/) == IntPtr.Zero) { posX = int.MinValue; }
        if (posX == int.MinValue)
        {
            var mi = new MONITORINFO { cbSize = 40 };
            GetMonitorInfo(MonitorFromPoint(new W.POINT(), 1 /*PRIMARY*/), ref mi);
            posX = mi.rcWork.right - width - 40; posY = mi.rcWork.top + 40;
        }
    }

    static void Render()
    {
        IntPtr screenDC = GetDC(IntPtr.Zero), memDC = CreateCompatibleDC(screenDC);
        var bmi = new W.BITMAPINFOHEADER { biSize = 40, biWidth = width, biHeight = -height, biPlanes = 1, biBitCount = 32 };
        IntPtr bits; IntPtr dib = W.CreateDIBSection(screenDC, ref bmi, 0, out bits, IntPtr.Zero, 0);
        IntPtr old = SelectObject(memDC, dib);
        try
        {
            using (var bmp = new Bitmap(width, height, width * 4, PixelFormat.Format32bppPArgb, bits))
            using (var g = Graphics.FromImage(bmp))
            {
                g.Clear(Color.FromArgb(1, 0, 0, 0));   // alpha 1 everywhere: whole tile is clickable/hoverable
                g.SmoothingMode = SmoothingMode.AntiAlias;
                if (hover || dragging)
                {
                    using (var path = Rounded(new RectangleF(0.5f, 0.5f, width - 1, height - 1), Math.Max(3, dpi / 24f)))
                    using (var br = new SolidBrush(Color.FromArgb(dragging ? 70 : 48, 160, 205, 255)))
                    using (var pen = new Pen(Color.FromArgb(110, 190, 225, 255), 1f))
                    { g.FillPath(br, path); g.DrawPath(pen, path); }
                }
                g.DrawImageUnscaled(frames[frame], pad, pad);
                float fontPx = Math.Max(11f, img * 0.16f);
                using (var font = new Font("Segoe UI Semibold", fontPx, FontStyle.Regular, GraphicsUnit.Pixel))
                using (var sf = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Near })
                using (var path = new GraphicsPath())
                {
                    var r = new RectangleF(0, pad + img + pad * 0.3f, width, height - img - pad);
                    path.AddString("WattCap", font.FontFamily, (int)font.Style, fontPx, r, sf);
                    using (var m = new Matrix()) { m.Translate(1f, 1.2f);
                        using (var sh = (GraphicsPath)path.Clone()) { sh.Transform(m);
                            using (var pen = new Pen(Color.FromArgb(120, 0, 0, 0), Math.Max(2f, fontPx / 6f)) { LineJoin = LineJoin.Round }) g.DrawPath(pen, sh);
                            using (var b = new SolidBrush(Color.FromArgb(200, 0, 0, 0))) g.FillPath(b, sh); } }
                    using (var b = new SolidBrush(Color.White)) g.FillPath(b, path);
                }
            }
            var pd = new W.POINT { x = posX, y = posY }; var sz = new W.SIZE { cx = width, cy = height }; var ps = new W.POINT();
            var bf = new W.BLENDFUNCTION { SourceConstantAlpha = 255, AlphaFormat = 1 };
            W.UpdateLayeredWindow(hwnd, screenDC, ref pd, ref sz, memDC, ref ps, 0, ref bf, 2);
        }
        finally { SelectObject(memDC, old); DeleteObject(dib); DeleteDC(memDC); ReleaseDC(IntPtr.Zero, screenDC); }
    }

    static GraphicsPath Rounded(RectangleF r, float rad)
    {
        var p = new GraphicsPath(); float d = rad * 2;
        p.AddArc(r.X, r.Y, d, d, 180, 90); p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90); p.AddArc(r.X, r.Bottom - d, d, d, 90, 90); p.CloseFigure();
        return p;
    }

    static void StartLaunch()
    {
        if (animating) return; // launch happens at full speed, once per animation
        W.L("double-click: spin-up, launch at full speed");
        W.ResetLaunch(); spin = new Spin(); renders = 0;
        animating = true; anim.Restart(); W.timeBeginPeriod(1);
        SetTimer(hwnd, (IntPtr)1, 15, IntPtr.Zero); // ~60 fps with 1 ms timer resolution
    }

    static int renders;
    static void SavePos()
    {
        try { File.WriteAllText(Settings, "; WattCap Launcher v2 widget position (physical px)\r\nx=" + posX + "\r\ny=" + posY + "\r\n"); } catch { }
    }
    static void LoadPos()
    {
        posX = int.MinValue; posY = 0;
        try
        {
            foreach (var line in File.ReadAllLines(Settings))
            {
                if (line.StartsWith("x=")) posX = int.Parse(line.Substring(2));
                if (line.StartsWith("y=")) posY = int.Parse(line.Substring(2));
            }
        }
        catch { posX = int.MinValue; }
    }

    static void Menu()
    {
        IntPtr m = CreatePopupMenu();
        AppendMenu(m, 0, (IntPtr)1, "Launch WattCap");
        AppendMenu(m, 0x800, IntPtr.Zero, null);
        AppendMenu(m, 0, (IntPtr)2, "Reset position");
        AppendMenu(m, 0, (IntPtr)3, "Exit widget");
        W.POINT p; GetCursorPos(out p);
        SetForegroundWindow(hwnd);
        int cmd = TrackPopupMenu(m, 0x0100 /*RETURNCMD*/ | 0x0002, p.x, p.y, 0, hwnd, IntPtr.Zero);
        DestroyMenu(m);
        if (cmd == 1) StartLaunch();
        else if (cmd == 2) { posX = int.MinValue; ClampToScreen(); SavePos(); Render(); }
        else if (cmd == 3) { quitting = true; DestroyWindow(hwnd); }
    }

    static void BeginDrag() { GetCursorPos(out dragStartCursor); dragStartX = posX; dragStartY = posY; SetCapture(hwnd); }
    static void DragMove()
    {
        W.POINT p; GetCursorPos(out p);
        if (!dragging && Math.Abs(p.x - dragStartCursor.x) + Math.Abs(p.y - dragStartCursor.y) < 5) return;
        dragging = true;
        posX = dragStartX + p.x - dragStartCursor.x; posY = dragStartY + p.y - dragStartCursor.y;
        Render();
    }

    static IntPtr WndProc(IntPtr h, uint msg, IntPtr wp, IntPtr lp)
    {
        try
        {
            switch (msg)
            {
                case 0x0046: // WM_WINDOWPOSCHANGING: always stay at the bottom of the z-order (desktop layer)
                    {
                        var pos = (WINDOWPOS)Marshal.PtrToStructure(lp, typeof(WINDOWPOS));
                        pos.hwndInsertAfter = (IntPtr)1; pos.flags &= ~0x0004u; // HWND_BOTTOM, clear SWP_NOZORDER
                        Marshal.StructureToPtr(pos, lp, false);
                        break;
                    }
                case 0x0021: return (IntPtr)3; // WM_MOUSEACTIVATE -> MA_NOACTIVATE
                case 0x0200: // WM_MOUSEMOVE
                    if (!hover) { hover = true; var t = new TRACKMOUSEEVENT { cbSize = 16 + IntPtr.Size, dwFlags = 2, hwndTrack = h }; TrackMouseEvent(ref t); Render(); }
                    if (GetCapture() == h) DragMove();
                    return IntPtr.Zero;
                case 0x02A3: hover = false; if (!dragging) Render(); return IntPtr.Zero; // WM_MOUSELEAVE
                case 0x0201: BeginDrag(); return IntPtr.Zero;      // LBUTTONDOWN: left-drag moves
                case 0x0204: rightDown = true; BeginDrag(); return IntPtr.Zero;                    // RBUTTONDOWN
                case 0x0202: case 0x0205: // LBUTTONUP / RBUTTONUP
                    {
                        bool wasDrag = dragging, wasRight = rightDown && msg == 0x0205;
                        if (GetCapture() == h) ReleaseCapture();
                        dragging = false; rightDown = false;
                        if (wasDrag) { SavePos(); W.L("moved to " + posX + "," + posY); W.FlushLog("widget.log"); Render(); }
                        else if (wasRight) Menu();
                        return IntPtr.Zero;
                    }
                case 0x0203: StartLaunch(); return IntPtr.Zero;   // LBUTTONDBLCLK
                case 0x0113: // WM_TIMER
                    if (wp == (IntPtr)1)
                    {
                        double t = anim.Elapsed.TotalSeconds;
                        double ang = spin.Update(t, W.LaunchDone);
                        if (spin.WantLaunch) { spin.WantLaunch = false; W.L("full speed -> launch"); W.StartLaunchThread(); }
                        int f = Spin.Frame(ang);
                        if (f != frame) { frame = f; Render(); renders++; }
                        if (spin.Finished || t > 120)
                        {
                            frame = 0; Render();   // resting frame == static icon
                            KillTimer(h, (IntPtr)1); W.timeEndPeriod(1); animating = false;
                            W.L(string.Format("animation done in {0:0.000}s, {1} renders", t, renders)); W.L(spin.Summary()); W.FlushLog("widget.log");
                            if (selfTest) { quitting = true; DestroyWindow(h); }
                        }
                    }
                    else if (wp == (IntPtr)3) { KillTimer(h, (IntPtr)3); StartLaunch(); }
                    else if (wp == (IntPtr)2)
                    {   // watchdog: explorer restarted -> re-own to the new Progman; keep at bottom
                        IntPtr o = W.DesktopOwner();
                        if (o != owner && o != IntPtr.Zero) { owner = o; SetWindowLongPtr(h, -8, o); W.L("re-owned to new Progman"); }
                        SetWindowPos(h, (IntPtr)1, 0, 0, 0, 0, 0x0013);
                    }
                    return IntPtr.Zero;
                case 0x02E0: Layout(); Render(); return IntPtr.Zero; // WM_DPICHANGED
                case 0x007E: Layout(); Render(); return IntPtr.Zero; // WM_DISPLAYCHANGE
                case 0x0002: PostQuitMessage(0); return IntPtr.Zero; // WM_DESTROY
            }
        }
        catch (Exception e) { W.L("wndproc: " + e.Message); }
        return DefWindowProc(h, msg, wp, lp);
    }

    // ---------------- interop ----------------
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct WNDCLASSEX { public int cbSize; public uint style; public IntPtr lpfnWndProc; public int cbClsExtra, cbWndExtra; public IntPtr hInstance, hIcon, hCursor, hbrBackground; public string lpszMenuName, lpszClassName; public IntPtr hIconSm; }
    [StructLayout(LayoutKind.Sequential)] struct MSG { public IntPtr hwnd; public uint message; public IntPtr wParam, lParam; public uint time; public W.POINT pt; }
    [StructLayout(LayoutKind.Sequential)] struct WINDOWPOS { public IntPtr hwnd, hwndInsertAfter; public int x, y, cx, cy; public uint flags; }
    [StructLayout(LayoutKind.Sequential)] struct TRACKMOUSEEVENT { public int cbSize; public uint dwFlags; public IntPtr hwndTrack; public uint dwHoverTime; }
    [StructLayout(LayoutKind.Sequential)] struct MONITORINFO { public int cbSize; public W.RECT rcMonitor, rcWork; public uint dwFlags; }
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern ushort RegisterClassEx(ref WNDCLASSEX w);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr CreateWindowEx(int ex, string cls, string name, int style, int x, int y, int w, int h, IntPtr p, IntPtr m, IntPtr i, IntPtr l);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern IntPtr DefWindowProc(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandle(string n);
    [DllImport("user32.dll")] static extern IntPtr LoadCursor(IntPtr i, IntPtr n);
    [DllImport("user32.dll")] static extern int GetMessage(out MSG m, IntPtr h, uint a, uint b);
    [DllImport("user32.dll")] static extern bool TranslateMessage(ref MSG m);
    [DllImport("user32.dll")] static extern IntPtr DispatchMessage(ref MSG m);
    [DllImport("user32.dll")] static extern void PostQuitMessage(int c);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] static extern bool DestroyWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
    [DllImport("user32.dll")] static extern IntPtr SetWindowLongPtr(IntPtr h, int i, IntPtr v);
    [DllImport("user32.dll")] static extern IntPtr SetTimer(IntPtr h, IntPtr id, uint ms, IntPtr f);
    [DllImport("user32.dll")] static extern bool KillTimer(IntPtr h, IntPtr id);
    [DllImport("user32.dll")] static extern uint GetDpiForWindow(IntPtr h);
    [DllImport("user32.dll")] static extern bool TrackMouseEvent(ref TRACKMOUSEEVENT t);
    [DllImport("user32.dll")] static extern IntPtr SetCapture(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr GetCapture();
    [DllImport("user32.dll")] static extern bool ReleaseCapture();
    [DllImport("user32.dll")] static extern bool GetCursorPos(out W.POINT p);
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] static extern IntPtr CreatePopupMenu();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool AppendMenu(IntPtr m, uint f, IntPtr id, string s);
    [DllImport("user32.dll")] static extern int TrackPopupMenu(IntPtr m, uint f, int x, int y, int r, IntPtr h, IntPtr rc);
    [DllImport("user32.dll")] static extern bool DestroyMenu(IntPtr m);
    [DllImport("user32.dll")] static extern IntPtr MonitorFromPoint(W.POINT p, uint f);
    [DllImport("user32.dll")] static extern bool GetMonitorInfo(IntPtr m, ref MONITORINFO mi);
    [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
    [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h, IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr CreateCompatibleDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern bool DeleteDC(IntPtr dc);
    [DllImport("gdi32.dll")] static extern IntPtr SelectObject(IntPtr dc, IntPtr o);
    [DllImport("gdi32.dll")] static extern bool DeleteObject(IntPtr o);
}
