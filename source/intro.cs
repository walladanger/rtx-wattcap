// WattCap intro renderer. C# 5 / .NET Framework 4.x compatible (Windows PowerShell 5.1 Add-Type).
// Scenes draw into a fixed 80x45 virtual canvas; every frame that canvas is scaled to the live
// console size (half-block pixels, 2 per cell) and letterboxed, so resizing rescales everything.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace WattCap
{
    public static class Intro
    {
        // ---- config, set from PowerShell ----
        public static string Style = "invaders";
        public static int Watts = 310;
        public static double Stock = 350;
        public static int NGpu = 0;
        public static string Match = "3090";
        public static int Seed = 1;
        public static string Ticker = "";
        public static bool Abort = false;   // set when Esc is pressed (stops a multi-scene playlist)

        public static readonly string[] Openings = { "peaks", "aurora", "vortex", "storm" };
        public static readonly string[] Closings = { "iris", "sunset", "shutter", "cooldown" };

        const string CSI = "\u001b[";
        internal const int VW = 80, VH = 45;          // design units (scene coordinates)
        internal const int K = 2, HW = VW * K, HH = VH * K;   // canvas is 2x finer than design units
        internal static readonly byte[] vb = new byte[HW * HH];
        internal static int px_, py_;                 // screen pixel being painted (for dithering)
        internal static Random rng = new Random(1);
        internal static int accent = 45;

        // ---- screen state ----
        internal static int cols, rows, SW, SH;
        internal static double sc, offX, offY;
        internal static byte[] spix = new byte[0];
        static int[] mapX = new int[0], mapY = new int[0], prevKey = new int[0];
        static bool fullRedraw = true;
        static string tickSrc = "";

        [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(int h);
        [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr h, out int m);
        [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr h, int m);

        public static void EnableVT()
        {
            try
            {
                IntPtr h = GetStdHandle(-11);
                int m;
                if (GetConsoleMode(h, out m)) SetConsoleMode(h, m | 0x0004 | 0x0001);
            }
            catch { }
        }

        internal abstract class Scene
        {
            public abstract void Step(double t, double dt);
            public abstract void DrawVirtual(double t);
            public abstract void DrawBackground(double t);
            public abstract double End { get; }
            public virtual void MaskVirtual(double t) { }
        }

        internal delegate int PixFn(double u, double v);

        static Scene MakeScene()
        {
            rng = new Random(Seed);
            switch (Style)
            {
                case "aurora": return new Aurora();
                case "vortex": return new Vortex();
                case "storm": return new Storm();
                case "iris": return new Iris();
                case "sunset": return new Sunset();
                case "shutter": return new Shutter();
                case "cooldown": return new Cooldown();
                default: return new Peaks();
            }
        }

        // ---- scaling --------------------------------------------------------
        internal static bool Resize(int c, int r)
        {
            if (c == cols && r == rows) return false;
            cols = c; rows = r;
            SW = c; SH = (r - 1) * 2;
            sc = Math.Min((double)SW / VW, (double)SH / VH);
            offX = (SW - VW * sc) / 2.0; offY = (SH - VH * sc) / 2.0;
            spix = new byte[SW * SH];
            mapX = new int[SW]; mapY = new int[SH];
            for (int x = 0; x < SW; x++) { int m = (int)Math.Floor((x + 0.5 - offX) / sc * K); mapX[x] = (m >= 0 && m < HW) ? m : -1; }
            for (int y = 0; y < SH; y++) { int m = (int)Math.Floor((y + 0.5 - offY) / sc * K); mapY[y] = (m >= 0 && m < HH) ? m : -1; }
            prevKey = new int[c * (r - 1)];
            fullRedraw = true;
            return true;
        }

        internal static uint Hash(int x, int y)
        {
            uint h = (uint)(x * 374761393 + y * 668265263);
            h = (h ^ (h >> 13)) * 1274126177u;
            return h ^ (h >> 16);
        }

        static string Frame(Scene s, double t)
        {
            Array.Clear(vb, 0, vb.Length);
            s.DrawVirtual(t);
            s.MaskVirtual(t);
            s.DrawBackground(t);
            for (int y = 0; y < SH; y++)
            {
                int my = mapY[y]; if (my < 0) continue;
                int row = my * HW, o = y * SW;
                for (int x = 0; x < SW; x++)
                {
                    int mx = mapX[x]; if (mx < 0) continue;
                    byte c = vb[row + mx]; if (c != 0) spix[o + x] = c;
                }
            }
            // dissolve out over the last 0.5 s
            double d = (t - (s.End - 0.5)) / 0.5;
            if (d > 0)
            {
                uint lim = (uint)(Math.Min(1.0, d) * uint.MaxValue);
                for (int y = 0; y < SH; y++) for (int x = 0; x < SW; x++)
                    if (Hash(x, y >> 1) < lim) spix[y * SW + x] = 16;
            }
            return Emit(t);
        }

        static string Emit(double t)
        {
            StringBuilder sb = new StringBuilder(cols * rows * 12);
            if (fullRedraw)
            {
                sb.Append(CSI).Append("0m").Append(CSI).Append("2J");
                for (int i = 0; i < prevKey.Length; i++) prevKey[i] = -1;
                fullRedraw = false;
            }
            int curFg = -1, curBg = -1, curR = -1, curC = -1;
            int prows = rows - 1;
            for (int r = 0; r < prows; r++)
            {
                int o0 = (r * 2) * SW, o1 = o0 + SW;
                for (int c = 0; c < cols; c++)
                {
                    int top = spix[o0 + c], bot = spix[o1 + c];
                    int key = (top << 8) | bot;
                    int ci = r * cols + c;
                    if (prevKey[ci] == key) continue;
                    prevKey[ci] = key;
                    if (curR != r || curC != c) sb.Append(CSI).Append(r + 1).Append(';').Append(c + 1).Append('H');
                    if (top == bot)
                    {
                        if (curBg != top) { sb.Append(CSI).Append("48;5;").Append(top).Append('m'); curBg = top; }
                        sb.Append(' ');
                    }
                    else
                    {
                        if (curFg != top) { sb.Append(CSI).Append("38;5;").Append(top).Append('m'); curFg = top; }
                        if (curBg != bot) { sb.Append(CSI).Append("48;5;").Append(bot).Append('m'); curBg = bot; }
                        sb.Append('\u2580');
                    }
                    curR = r; curC = c + 1;
                }
            }
            // ticker (text row, full width minus last cell)
            int tw = Math.Max(1, cols - 1);
            while (tickSrc.Length < Ticker.Length + tw) tickSrc += Ticker;
            int off = Ticker.Length > 0 ? (int)(t * 20) % Ticker.Length : 0;
            sb.Append(CSI).Append(rows).Append(";1H").Append(CSI).Append("48;5;234m").Append(CSI).Append("38;5;").Append(accent).Append('m');
            sb.Append(tickSrc.Substring(off, tw)).Append(CSI).Append("0m");
            return sb.ToString();
        }

        // ---- entry points -------------------------------------------------------
        public static void Run()
        {
            EnableVT();
            Abort = false;
            Encoding oldEnc = null; bool oldCC = false;
            try { oldEnc = Console.OutputEncoding; } catch { }
            try { oldCC = Console.TreatControlCAsInput; } catch { }
            TextWriter o = Console.Out;
            try
            {
                try { Console.OutputEncoding = new UTF8Encoding(false); } catch { }
                try { Console.TreatControlCAsInput = true; } catch { }
                o = Console.Out;
                o.Write(CSI + "?1049h" + CSI + "?25l" + CSI + "2J");
                Scene s = MakeScene();
                cols = 0; rows = 0;
                Stopwatch sw = Stopwatch.StartNew();
                double last = 0;
                while (true)
                {
                    double t = sw.Elapsed.TotalSeconds;
                    double dt = Math.Min(0.05, t - last); last = t;
                    if (t >= s.End) break;
                    s.Step(t, dt);
                    int w = 0, h = 0;
                    try { w = Console.WindowWidth; h = Console.WindowHeight; } catch { }
                    if (w >= 20 && h >= 8)
                    {
                        Resize(w, h);
                        o.Write(Frame(s, t)); o.Flush();
                    }
                    bool skip = false;
                    try { while (Console.KeyAvailable) { if (Console.ReadKey(true).Key == ConsoleKey.Escape) Abort = true; skip = true; } } catch { }
                    if (skip) break;
                    int ms = 33 - (int)((sw.Elapsed.TotalSeconds - t) * 1000);
                    if (ms > 0) Thread.Sleep(ms);
                }
            }
            finally
            {
                o.Write(CSI + "0m" + CSI + "2J" + CSI + "?25h" + CSI + "?1049l"); o.Flush();
                try { Console.TreatControlCAsInput = oldCC; } catch { }
                try { if (oldEnc != null) Console.OutputEncoding = oldEnc; } catch { }
            }
        }

        // Test hook: simulate at 30 fps and write full ANSI frames at given times/sizes.
        public static void Dump(string dir, double[] times, int[] ws, int[] hs)
        {
            Scene s = MakeScene();
            double t = 0, dt = 1.0 / 30; int k = 0;
            while (k < times.Length && t < 60)
            {
                s.Step(t, dt);
                while (k < times.Length && t >= times[k] - 1e-9)
                {
                    cols = 0; Resize(ws[k], hs[k]);
                    File.WriteAllText(Path.Combine(dir, string.Format("f{0:000}.ans", k)), Frame(s, t));
                    k++;
                }
                t += dt;
            }
        }

        public static double SceneEnd()
        {
            Scene s = MakeScene(); double t = 0;
            while (t < 60 && t < s.End) { s.Step(t, 1.0 / 30); t += 1.0 / 30; }
            return s.End;
        }

        // ---- drawing helpers -----------------------------------------------------
        internal static void Px(int x, int y, int c)
        {
            if (x < 0 || y < 0 || x >= VW || y >= VH) return;
            for (int dy = 0; dy < K; dy++) for (int dx = 0; dx < K; dx++) vb[(y * K + dy) * HW + x * K + dx] = (byte)c;
        }

        internal static void PxH(int x, int y, int c)
        {
            if (x >= 0 && y >= 0 && x < HW && y < HH) vb[y * HW + x] = (byte)c;
        }

        static readonly int[] Bay = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };
        internal static double Bayer(int x, int y) { return (Bay[((y & 3) << 2) | (x & 3)] + 0.5) / 16.0; }

        // palette index with ordered dithering between neighbouring entries (v in 0..8)
        internal static int Dith(double v)
        {
            if (v <= 0) return 0;
            if (v >= 8) return 8;
            int k = (int)Math.Floor(v);
            return (v - k) > Bayer(px_, py_) ? k + 1 : k;
        }

        internal static byte Ink(char ch, int body, int acc)
        {
            switch (ch)
            {
                case '#': return (byte)body;
                case '+': return (byte)acc;
                case 'o': return 231;
                case 'x': return 16;
                case 'g': return 178;
                default: return 0;
            }
        }

        internal static void Blit(string[] spr, int x, int y, int body, int acc)
        {
            for (int r = 0; r < spr.Length; r++)
                for (int c = 0; c < spr[r].Length; c++)
                {
                    byte k = Ink(spr[r][c], body, acc);
                    if (k != 0) Px(x + c, y + r, k);
                }
        }

        internal static void BlitSolid(string[] spr, int x, int y, int col)
        {
            for (int r = 0; r < spr.Length; r++)
                for (int c = 0; c < spr[r].Length; c++)
                    if (spr[r][c] != '.') Px(x + c, y + r, col);
        }

        // 3x5 font
        static readonly Dictionary<char, string[]> F3 = new Dictionary<char, string[]>();
        // 5x7 font for the logo
        static readonly Dictionary<char, string[]> F5 = new Dictionary<char, string[]>();

        static void G3(char c, string a, string b, string d, string e, string f) { F3[c] = new string[] { a, b, d, e, f }; }
        static void G5(char c, params string[] r) { F5[c] = r; }

        static Intro()
        {
            G3('A', ".#.", "#.#", "###", "#.#", "#.#"); G3('B', "##.", "#.#", "##.", "#.#", "##.");
            G3('C', ".##", "#..", "#..", "#..", ".##"); G3('D', "##.", "#.#", "#.#", "#.#", "##.");
            G3('E', "###", "#..", "##.", "#..", "###"); G3('F', "###", "#..", "##.", "#..", "#..");
            G3('G', ".##", "#..", "#.#", "#.#", ".##"); G3('H', "#.#", "#.#", "###", "#.#", "#.#");
            G3('I', "###", ".#.", ".#.", ".#.", "###"); G3('J', "..#", "..#", "..#", "#.#", ".#.");
            G3('K', "#.#", "#.#", "##.", "#.#", "#.#"); G3('L', "#..", "#..", "#..", "#..", "###");
            G3('M', "#.#", "###", "###", "#.#", "#.#"); G3('N', "##.", "#.#", "#.#", "#.#", "#.#");
            G3('O', ".#.", "#.#", "#.#", "#.#", ".#."); G3('P', "##.", "#.#", "##.", "#..", "#..");
            G3('Q', ".#.", "#.#", "#.#", "##.", ".##"); G3('R', "##.", "#.#", "##.", "#.#", "#.#");
            G3('S', ".##", "#..", ".#.", "..#", "##."); G3('T', "###", ".#.", ".#.", ".#.", ".#.");
            G3('U', "#.#", "#.#", "#.#", "#.#", "###"); G3('V', "#.#", "#.#", "#.#", "#.#", ".#.");
            G3('W', "#.#", "#.#", "###", "###", "#.#"); G3('X', "#.#", "#.#", ".#.", "#.#", "#.#");
            G3('Y', "#.#", "#.#", ".#.", ".#.", ".#."); G3('Z', "###", "..#", ".#.", "#..", "###");
            G3('0', "###", "#.#", "#.#", "#.#", "###"); G3('1', ".#.", "##.", ".#.", ".#.", "###");
            G3('2', "##.", "..#", ".#.", "#..", "###"); G3('3', "##.", "..#", ".#.", "..#", "##.");
            G3('4', "#.#", "#.#", "###", "..#", "..#"); G3('5', "###", "#..", "##.", "..#", "##.");
            G3('6', ".##", "#..", "###", "#.#", "###"); G3('7', "###", "..#", ".#.", ".#.", ".#.");
            G3('8', "###", "#.#", "###", "#.#", "###"); G3('9', "###", "#.#", "###", "..#", "##.");
            G3(' ', "...", "...", "...", "...", "..."); G3('/', "..#", "..#", ".#.", "#..", "#..");
            G3('-', "...", "...", "###", "...", "..."); G3(':', "...", ".#.", "...", ".#.", "...");
            G3('.', "...", "...", "...", "...", ".#.");

            G5('R', "####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#");
            G5('T', "#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#..");
            G5('X', "#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#");
            G5('0', ".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###.");
            G5('1', "..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###.");
            G5('2', ".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####");
            G5('3', "####.", "....#", "....#", ".###.", "....#", "....#", "####.");
            G5('4', "...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#.");
            G5('5', "#####", "#....", "####.", "....#", "....#", "#...#", ".###.");
            G5('6', ".###.", "#....", "#....", "####.", "#...#", "#...#", ".###.");
            G5('7', "#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#...");
            G5('8', ".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###.");
            G5('9', ".###.", "#...#", "#...#", ".####", "....#", "....#", ".###.");
            G5('W', "#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#");
            G5('A', ".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#");
            G5('C', ".###.", "#...#", "#....", "#....", "#....", "#...#", ".###.");
            G5('P', "####.", "#...#", "#...#", "####.", "#....", "#....", "#....");
            G5(' ', "...", "...", "...", "...", "...", "...", "...");
        }

        internal static int Text3W(string s) { return Math.Max(0, s.Length * 4 - 1); }

        internal static void Text3(string s, int x, int y, int col)
        {
            s = s.ToUpperInvariant();
            for (int i = 0; i < s.Length; i++)
            {
                string[] g;
                if (!F3.TryGetValue(s[i], out g)) g = F3[' '];
                for (int r = 0; r < 5; r++) for (int c = 0; c < 3; c++)
                    if (g[r][c] == '#') Px(x + i * 4 + c, y + r, col);
            }
        }

        // ---- the logo ("RTX " + match) -------------------------------------------
        internal static bool[,] logoMask;
        internal static int logoW;

        internal static void BuildLogo()
        {
            BuildLogo("WATTCAP");
        }

        internal static void BuildLogo(string word)
        {
            List<string[]> gl = new List<string[]>();
            foreach (char ch in word) if (F5.ContainsKey(ch)) gl.Add(F5[ch]);
            int w = 0;
            for (int i = 0; i < gl.Count; i++) w += gl[i][0].Length + (i < gl.Count - 1 ? 1 : 0);
            logoW = w; logoMask = new bool[7, w];
            int x0 = 0;
            for (int i = 0; i < gl.Count; i++)
            {
                for (int r = 0; r < 7; r++) for (int c = 0; c < gl[i][r].Length; c++)
                    logoMask[r, x0 + c] = gl[i][r][c] == '#';
                x0 += gl[i][0].Length + 1;
            }
            // Scale2x/EPX: doubles the resolution and rounds the diagonals, still crisp pixel art
            logoHi = new bool[14, w * 2];
            for (int r = 0; r < 7; r++) for (int c = 0; c < w; c++)
            {
                bool P = logoMask[r, c], A = r > 0 && logoMask[r - 1, c], B = c < w - 1 && logoMask[r, c + 1];
                bool C = c > 0 && logoMask[r, c - 1], D = r < 6 && logoMask[r + 1, c];
                bool p1 = P, p2 = P, p3 = P, p4 = P;
                if (C == A && C != D && A != B) p1 = A;
                if (A == B && A != C && B != D) p2 = B;
                if (D == C && D != B && C != A) p3 = C;
                if (B == D && B != A && D != C) p4 = D;
                logoHi[2 * r, 2 * c] = p1; logoHi[2 * r, 2 * c + 1] = p2; logoHi[2 * r + 1, 2 * c] = p3; logoHi[2 * r + 1, 2 * c + 1] = p4;
            }
        }

        internal static bool[,] logoHi;

        static bool LH(int r, int c) { return r >= 0 && c >= 0 && r < 14 && c < logoW * 2 && logoHi[r, c]; }

        // colOff: per-design-column vertical offset (may be null). Drawn at 2x resolution with outline, shadow and bevel.
        internal static void DrawLogo(int x0, int y0, int[] colOff, int baseCol, int shineCol, double shinePos, int shadowCol, int visCols = int.MaxValue, int minCol = 0)
        {
            int hw = logoW * 2;
            bool grey = baseCol >= 232;
            int top = grey ? 255 : baseCol, bot = grey ? Math.Max(236, baseCol - 6) : baseCol;
            for (int pass = 0; pass < 3; pass++)
                for (int hc = 0; hc < hw; hc++)
                {
                    int c = hc / 2;
                    if (c >= visCols || c < minCol) continue;
                    int oy = colOff == null ? 0 : colOff[c] * K;
                    for (int hr = 0; hr < 14; hr++)
                    {
                        if (!logoHi[hr, hc]) continue;
                        int X = x0 * K + hc, Y = y0 * K + hr + oy;
                        if (pass == 0) { PxH(X + 2, Y + 2, shadowCol); continue; }
                        if (pass == 1)
                        {
                            for (int dy = -1; dy <= 1; dy++) for (int dx = -1; dx <= 1; dx++) PxH(X + dx, Y + dy, 16);
                            continue;
                        }
                        double sh = c - hr / 2.0 - shinePos;
                        int col = (sh >= 0 && sh < 4) ? shineCol : (!LH(hr - 1, hc) ? top : (!LH(hr + 1, hc) ? bot : baseCol));
                        PxH(X, Y, col);
                    }
                }
        }

        internal static void Subtitle(double t0, double t, int y, int col1, int col2)
        {
            Subtitle(t0, t, y, col1, col2, "POWER LIMIT", null);
        }

        internal static void Subtitle(double t0, double t, int y, int col1, int col2, string l1, string l2)
        {
            if (l2 == null) l2 = Watts + " W" + (NGpu > 0 ? " X" + NGpu : "");
            int n = (int)Math.Floor((t - t0) / 0.045);
            if (n <= 0) return;
            string a = l1.Substring(0, Math.Min(n, l1.Length));
            Text3(a, (VW - Text3W(l1)) / 2, y, col1);
            int n2 = n - l1.Length - 3;
            if (n2 > 0) Text3(l2.Substring(0, Math.Min(n2, l2.Length)), (VW - Text3W(l2)) / 2, y + 7, col2);
        }

        internal static double Clamp01(double v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }

        internal static double Bounce(double p)
        {
            p = Clamp01(p);
            if (p < 1 / 2.75) return 7.5625 * p * p;
            if (p < 2 / 2.75) { p -= 1.5 / 2.75; return 7.5625 * p * p + 0.75; }
            if (p < 2.5 / 2.75) { p -= 2.25 / 2.75; return 7.5625 * p * p + 0.9375; }
            p -= 2.625 / 2.75; return 7.5625 * p * p + 0.984375;
        }

        internal static double Rr(double a, double b) { return a + (b - a) * rng.NextDouble(); }

        internal static int Lvl(double n) { return Dith(n * 9 - 0.5); }

        // Paint the whole screen background: f gets canvas coordinates (may fall outside 0..VW/0..VH in the letterbox).
        internal static void Paint(PixFn f)
        {
            for (int y = 0; y < SH; y++)
            {
                double v = (y + 0.5 - offY) / sc; int o = y * SW;
                for (int x = 0; x < SW; x++) { px_ = x; py_ = y; spix[o + x] = (byte)f((x + 0.5 - offX) / sc, v); }
            }
        }

        internal delegate bool HideFn(double x, double y);

        // Erase canvas pixels for which hide(x,y) is true (used by closing masks)
        internal static void MaskVB(HideFn hide)
        {
            for (int y = 0; y < HH; y++) for (int x = 0; x < HW; x++)
                if (vb[y * HW + x] != 0 && hide((x + 0.5) / K, (y + 0.5) / K)) vb[y * HW + x] = 0;
        }

        // Dim factor for a soft panel behind the logo (same look as the original plasma intro)
        internal static double Panel(double u, double v, double x0, double x1, double y0, double y1, double a)
        {
            if (u < x0 || u > x1 || v < y0 || v > y1) return 1;
            double fe = Math.Min(Math.Min(u - x0, x1 - u) / 5.0, Math.Min(v - y0, y1 - v) / 3.0);
            if (fe > 1) fe = 1;
            return 1 - a * (fe + 0.25) / 1.25;
        }

        // ---- particles --------------------------------------------------------------
        internal class Part { public double x, y, vx, vy, life, max; public int col; }
        internal static readonly List<Part> parts = new List<Part>();

        internal static void Burst(double x, double y, int n, double spd, int[] cols, double life)
        {
            for (int i = 0; i < n; i++)
            {
                double a = rng.NextDouble() * Math.PI * 2, v = spd * (0.3 + 0.7 * rng.NextDouble());
                Part p = new Part();
                p.x = x; p.y = y; p.vx = Math.Cos(a) * v; p.vy = Math.Sin(a) * v - spd * 0.25;
                p.max = p.life = life * (0.5 + 0.5 * rng.NextDouble());
                p.col = cols[rng.Next(cols.Length)];
                parts.Add(p);
            }
        }

        internal static void StepParts(double dt)
        {
            for (int i = parts.Count - 1; i >= 0; i--)
            {
                Part p = parts[i];
                p.vy += 26 * dt; p.x += p.vx * dt; p.y += p.vy * dt; p.life -= dt;
                if (p.life <= 0) parts.RemoveAt(i);
            }
        }

        internal static void DrawParts()
        {
            foreach (Part p in parts)
                Px((int)Math.Round(p.x), (int)Math.Round(p.y), p.life / p.max < 0.35 ? 240 : p.col);
        }
    }

    // =================================================================================
    //  Scene toolkit shared by all plasma scenes
    // =================================================================================
    internal abstract class PlasmaScene : Intro.Scene
    {
        protected const int VW = Intro.VW, VH = Intro.VH;
        protected const double TAU = Math.PI * 2;
        protected int[] off;
        protected double Dur = 7.0;

        public override double End { get { return Dur; } }
        public override void Step(double t, double dt) { }

        // global fade in / fade out of the field
        protected double G(double t) { return Intro.Clamp01(t / 0.8) * Intro.Clamp01((End - 0.3 - t) / 0.6); }

        protected int LogoX() { return (VW - Intro.logoW) / 2; }

        protected static int Pick(int n) { return Intro.rng.Next(n); }
    }

    // =================================================================================
    //  OPENING 1  Peaks: seeded field whose peaks are clipped at Watts/Stock (throttle plateau)
    // =================================================================================
    internal class Peaks : PlasmaScene
    {
        double k1, a1, k2, a2, k3, k4, a3, k5, a5, cx0, cy0, h1, h2, p1, p2, cap;
        int[] pal; int thr;

        static readonly int[][] Pals = {
            new int[] { 16, 22, 22, 28, 34, 35, 41, 77, 120 },
            new int[] { 16, 17, 17, 18, 24, 25, 31, 38, 87 },
            new int[] { 16, 53, 53, 54, 55, 91, 128, 170, 213 } };
        static readonly int[] Thr = { 214, 209, 222 };
        static readonly int[] Hi = { 120, 87, 213 };

        double R(double a, double b) { return Intro.Rr(a, b); }

        public Peaks()
        {
            Random g = Intro.rng;
            int pi = g.Next(3); pal = Pals[pi]; thr = Thr[pi]; Intro.accent = Hi[pi];
            k1 = R(1.2, 2.6); a1 = R(0.9, 1.6); k2 = R(1.0, 2.0); a2 = -R(0.7, 1.4);
            k3 = R(1.0, 3.0) * (g.NextDouble() < 0.5 ? -1 : 1); k4 = R(1.0, 2.4); a3 = R(0.9, 1.6);
            k5 = R(2.5, 5.0); a5 = R(1.4, 2.4); cx0 = R(0.2, 0.8); cy0 = R(0.2, 0.8);
            h1 = R(0.35, 0.65); h2 = R(0.55, 1.05); p1 = R(0, 6.28); p2 = R(0, 6.28);
            cap = Math.Max(0.5, Math.Min(0.97, Intro.Watts / Intro.Stock));
            Intro.BuildLogo();
            off = new int[Intro.logoW];
            Dur = 7.5;
        }

        int LogoXs(double t)
        {
            double p = Intro.Clamp01((t - 0.5) / 1.5), e = 1 - Math.Pow(1 - p, 3);
            int lt = LogoX();
            return (int)Math.Round(lt + (VW - lt + 2) * (1 - e));
        }

        public override void DrawVirtual(double t)
        {
            if (t < 0.5 || G(t) < 0.3) return;
            double amp = 2.0 * Intro.Clamp01((2.9 - t) / 0.9);
            double wp = (t - 4.0) / 1.3 * (Intro.logoW + 16) - 8;
            for (int c = 0; c < off.Length; c++)
            {
                double o = amp * Math.Sin(c * 0.45 - t * 7);
                if (t > 4.0 && t < 5.3) { double d = (c - wp) / 3.0; o -= 1.4 * Math.Exp(-d * d); }
                off[c] = (int)Math.Round(o);
            }
            double g = G(t);
            int b = g > 0.7 ? 252 : (g > 0.45 ? 245 : 240), s = g > 0.7 ? 231 : 250;
            Intro.DrawLogo(LogoXs(t), 19, off, b, s, ((t - 2.3) * 40) % (Intro.logoW + 50) - 20, 235);
        }

        public override void DrawBackground(double t)
        {
            byte[] sp = Intro.spix; int SW = Intro.SW, SH = Intro.SH;
            double sc = Intro.sc, ox = Intro.offX, oy = Intro.offY, g = G(t);
            double hx = 0.5 + 0.36 * Math.Sin(t * h1 + p1), hy = 0.5 + 0.34 * Math.Sin(t * h2 + p2);
            double dimA = 0.8 * Intro.Clamp01((t - 0.6) / 1.2);
            double bx0 = LogoXs(t) - 6, bx1 = LogoXs(t) + Intro.logoW + 6, by0 = 15, by1 = 31;
            for (int y = 0; y < SH; y++)
            {
                double v = (y + 0.5 - oy) / sc, Y = v / VH;
                double sy = Math.Sin(Y * TAU * k2 + t * a2);
                double qy = (Y - hy) / 0.30, gy = Math.Exp(-qy * qy) * 0.55;
                double uy = Y * 2 - 1;
                for (int x = 0; x < SW; x++)
                {
                    double u = (x + 0.5 - ox) / sc, X = u / VW;
                    double dx = X - cx0, dy = (Y - cy0) * VH / VW;
                    double s = Math.Sin(X * TAU * k1 + t * a1) + sy
                             + Math.Sin((X * k3 + Y * k4) * TAU + t * a3)
                             + Math.Sin(Math.Sqrt(dx * dx + dy * dy) * TAU * k5 - t * a5);
                    double qx = (X - hx) / 0.17;
                    double ux = X * 2 - 1;
                    double n = (0.36 + 0.24 * s + Math.Exp(-qx * qx) * gy) * (1 - 0.38 * (ux * ux * 0.8 + uy * uy)) * g;
                    n *= Intro.Panel(u, v, bx0, bx1, by0, by1, dimA);
                    Intro.px_ = x; Intro.py_ = y;
                    int k = n >= cap ? -1 : Intro.Dith(n / cap * 9 - 0.5);
                    sp[y * SW + x] = (byte)(k < 0 ? thr : pal[k]);
                }
            }
        }
    }

    // =================================================================================
    //  OPENING 2  Aurora: rippling vertical light curtains, logo scans in left to right
    // =================================================================================
    internal class Aurora : PlasmaScene
    {
        static readonly int[][] Pals = {
            new int[] { 16, 17, 23, 29, 35, 41, 84, 183, 219 },     // green into pink
            new int[] { 16, 17, 18, 19, 25, 61, 99, 141, 183 },     // blue into violet
            new int[] { 16, 23, 29, 30, 36, 72, 114, 186, 229 } };  // teal into gold
        static readonly int[] Acc = { 84, 141, 186 };
        int[] pal; double k, sp, wr;

        public Aurora()
        {
            int v = Pick(3); pal = Pals[v]; Intro.accent = Acc[v];
            k = Intro.Rr(1.6, 3.2); sp = Intro.Rr(0.5, 0.95); wr = Intro.Rr(0.7, 1.3);
            Intro.BuildLogo(); off = new int[Intro.logoW];
            Dur = 7.0;
        }

        public override void DrawVirtual(double t)
        {
            if (t < 0.6 || G(t) < 0.3) return;
            for (int c = 0; c < off.Length; c++) off[c] = (int)Math.Round(1.1 * Math.Sin(c * 0.3 - t * 3.2));
            int vis = (int)((t - 0.7) * 22);
            Intro.DrawLogo(LogoX(), 19, off, 252, 231, ((t - 2.4) * 40) % (Intro.logoW + 50) - 20, 235, vis);
        }

        public override void DrawBackground(double t)
        {
            double g = G(t), dimA = 0.75 * Intro.Clamp01((t - 0.6) / 1.0);
            double bx0 = LogoX() - 6, bx1 = LogoX() + Intro.logoW + 6;
            Intro.Paint(delegate(double u, double v)
            {
                double X = u / VW, Y = v / VH;
                double w = Math.Sin(Y * TAU * 0.9 + t * 0.7) * wr + Math.Sin(X * TAU * 0.6 - t * 0.4) * 0.6;
                double c1 = Math.Sin(X * TAU * k + w + t * sp);
                double c2 = Math.Sin(X * TAU * k * 1.7 - w * 1.3 - t * sp * 1.3 + 1.7);
                double vert = Intro.Clamp01(1.2 - Y * 1.1);
                double n = (0.5 + 0.28 * c1 + 0.18 * c2) * (0.25 + 0.85 * vert) * g;
                n *= Intro.Panel(u, v, bx0, bx1, 15, 31, dimA);
                int lv = Intro.Lvl(n);
                if (lv <= 1 && (Intro.Hash((int)Math.Floor(u * 2.5), (int)Math.Floor(v * 2.5)) % 173) == 0) return 245;
                return pal[lv];
            });
        }
    }

    // =================================================================================
    //  OPENING 3  Vortex: a spiral galaxy of plasma, logo rises from the bottom
    // =================================================================================
    internal class Vortex : PlasmaScene
    {
        static readonly int[][] Pals = {
            new int[] { 16, 52, 88, 124, 160, 166, 208, 214, 229 },   // ember
            new int[] { 16, 53, 89, 125, 161, 168, 213, 159, 231 },   // magenta into cyan
            new int[] { 16, 22, 28, 64, 70, 106, 148, 190, 231 } };   // toxic
        static readonly int[] Acc = { 214, 213, 190 };
        int[] pal; int arms; double sw, w;

        public Vortex()
        {
            int v = Pick(3); pal = Pals[v]; Intro.accent = Acc[v];
            arms = 2 + Pick(3); sw = Intro.Rr(2.0, 4.0) * (Pick(2) == 0 ? 1 : -1); w = Intro.Rr(1.6, 2.6);
            Intro.BuildLogo(); off = new int[Intro.logoW];
            Dur = 7.0;
        }

        int LogoY(double t)
        {
            double p = Intro.Clamp01((t - 0.5) / 1.6), e = 1 - Math.Pow(1 - p, 3);
            return 19 + (int)Math.Round((1 - e) * 36);
        }

        public override void DrawVirtual(double t)
        {
            if (t < 0.5 || G(t) < 0.3) return;
            double amp = 1.6 * Intro.Clamp01((3.4 - t) / 1.4);
            for (int c = 0; c < off.Length; c++) off[c] = (int)Math.Round(amp * Math.Sin(c * 0.5 - t * 6));
            Intro.DrawLogo(LogoX(), LogoY(t), off, 252, 231, ((t - 2.6) * 40) % (Intro.logoW + 50) - 20, 235);
        }

        public override void DrawBackground(double t)
        {
            double g = G(t), dimA = 0.8 * Intro.Clamp01((t - 1.2) / 1.0);
            double bx0 = LogoX() - 6, bx1 = LogoX() + Intro.logoW + 6;
            double cx = 0.5 + 0.10 * Math.Sin(t * 0.5), cy = 0.5 + 0.08 * Math.Cos(t * 0.4);
            Intro.Paint(delegate(double u, double v)
            {
                double X = u / VW, Y = v / VH;
                double dx = X - cx, dy = (Y - cy) * VH / VW;
                double r = Math.Sqrt(dx * dx + dy * dy), a = Math.Atan2(dy, dx);
                double n = 0.40 + 0.26 * Math.Sin(a * arms + r * TAU * sw - t * w)
                         + 0.14 * Math.Sin(r * TAU * 2.6 - t * 1.8)
                         + 0.55 * Math.Exp(-(r / 0.10) * (r / 0.10));
                n *= (1.05 - 0.9 * r * r) * g;
                n *= Intro.Panel(u, v, bx0, bx1, 15, 31, dimA);
                return pal[Intro.Lvl(n)];
            });
        }
    }

    // =================================================================================
    //  OPENING 4  Storm: interference of three drifting sources, lightning flashes, logo drops in
    // =================================================================================
    internal class Storm : PlasmaScene
    {
        static readonly int[][] Pals = {
            new int[] { 16, 17, 18, 24, 27, 33, 39, 81, 231 },        // electric blue
            new int[] { 16, 53, 54, 55, 92, 99, 135, 177, 231 },      // violet
            new int[] { 16, 52, 88, 124, 160, 196, 203, 217, 231 } }; // red
        static readonly int[] Acc = { 81, 177, 203 };
        int[] pal; double kk; double[] px = new double[3], py = new double[3], fa = new double[3], fb = new double[3], ph = new double[3];
        double[] ft = new double[3];

        public Storm()
        {
            int v = Pick(3); pal = Pals[v]; Intro.accent = Acc[v];
            kk = Intro.Rr(3.0, 5.0);
            for (int i = 0; i < 3; i++)
            {
                fa[i] = Intro.Rr(0.3, 0.8); fb[i] = Intro.Rr(0.3, 0.8); ph[i] = Intro.Rr(0, 6.28);
                px[i] = Intro.Rr(0.15, 0.4); py[i] = Intro.Rr(0.15, 0.35);
            }
            ft[0] = Intro.Rr(1.4, 2.0); ft[1] = Intro.Rr(2.9, 3.8); ft[2] = Intro.Rr(4.5, 5.5);
            Intro.BuildLogo(); off = new int[Intro.logoW];
            Dur = 7.0;
        }

        double Flash(double t)
        {
            double f = 0;
            for (int i = 0; i < 3; i++)
                if (t >= ft[i]) f += Math.Exp(-(t - ft[i]) * 6) * (0.65 + 0.35 * Math.Sin((t - ft[i]) * 60));
            return Intro.Clamp01(f);
        }

        public override void DrawVirtual(double t)
        {
            if (t < 0.5 || G(t) < 0.3) return;
            int ly = (int)Math.Round(-9 + 28 * Intro.Bounce((t - 0.5) / 1.0));
            if (Flash(t) > 0.4) ly += ((int)(t * 30) % 2 == 0) ? 1 : -1;
            for (int c = 0; c < off.Length; c++) off[c] = 0;
            Intro.DrawLogo(LogoX(), ly, off, 252, 231, ((t - 2.0) * 40) % (Intro.logoW + 50) - 20, 235);
        }

        public override void DrawBackground(double t)
        {
            double g = G(t), dimA = 0.7 * Intro.Clamp01((t - 0.6) / 1.0), fl = Flash(t);
            double bx0 = LogoX() - 6, bx1 = LogoX() + Intro.logoW + 6;
            double[] sx = new double[3], sy = new double[3];
            for (int i = 0; i < 3; i++)
            {
                sx[i] = 0.5 + px[i] * Math.Sin(t * fa[i] + ph[i]) * 2;
                sy[i] = 0.5 + py[i] * Math.Sin(t * fb[i] + ph[i] * 1.7) * 2;
            }
            Intro.Paint(delegate(double u, double v)
            {
                double X = u / VW, Y = v / VH, s = 0;
                for (int i = 0; i < 3; i++)
                {
                    double dx = X - sx[i], dy = (Y - sy[i]) * VH / VW;
                    double d = Math.Sqrt(dx * dx + dy * dy);
                    s += Math.Sin(d * TAU * kk * (0.85 + 0.15 * i) - t * (1.6 + 0.5 * i));
                }
                double ux = X * 2 - 1, uy = Y * 2 - 1;
                double n = (0.32 + 0.16 * s + 0.42 * fl) * (1 - 0.3 * (ux * ux * 0.8 + uy * uy)) * g;
                n *= Intro.Panel(u, v, bx0, bx1, 15, 31, dimA);
                return pal[Intro.Lvl(n)];
            });
        }
    }

    // =================================================================================
    //  CLOSING 1  Iris: gold ripple field, WATTCAP locks in, a circular iris snaps shut
    // =================================================================================
    internal class Iris : PlasmaScene
    {
        static readonly int[][] Pals = {
            new int[] { 16, 58, 94, 136, 172, 214, 220, 226, 230 },   // gold
            new int[] { 16, 53, 89, 125, 161, 204, 211, 218, 225 },   // rose
            new int[] { 16, 23, 30, 37, 44, 51, 87, 123, 159 } };     // cyan
        static readonly int[] Acc = { 220, 211, 87 };
        int[] pal; double k, a;
        const double T0 = 3.9, T1 = 5.7;

        public Iris()
        {
            int v = Pick(3); pal = Pals[v]; Intro.accent = Acc[v];
            k = Intro.Rr(1.8, 2.8); a = Intro.Rr(2.4, 3.4);
            Intro.BuildLogo("WATTCAP"); off = new int[Intro.logoW];
            Dur = 6.2;
        }

        double Radius(double t)
        {
            double p = Intro.Clamp01((t - T0) / (T1 - T0));
            return p <= 0 ? -1 : 120 * Math.Pow(1 - p, 2.2);
        }

        public override void DrawVirtual(double t)
        {
            if (t < 0.5) return;
            double cx = Intro.logoW / 2.0, half = (t - 0.5) * 10;
            for (int c = 0; c < off.Length; c++) off[c] = 0;
            Intro.DrawLogo(LogoX(), 19, off, 252, 231, ((t - 1.6) * 40) % (Intro.logoW + 50) - 20, 235,
                (int)Math.Ceiling(cx + half), (int)Math.Floor(cx - half));
            double R = Radius(t);
            if (R >= 0) Intro.MaskVB(delegate(double x, double y) { double dx = x - 40, dy = y - 22.5; return Math.Sqrt(dx * dx + dy * dy) > R; });
        }

        public override void DrawBackground(double t)
        {
            double g = Intro.Clamp01(t / 0.6), R = Radius(t), dimA = 0.75 * Intro.Clamp01((t - 0.5) / 1.0);
            double bx0 = LogoX() - 6, bx1 = LogoX() + Intro.logoW + 6;
            Intro.Paint(delegate(double u, double v)
            {
                double dx = u - 40, dy = v - 22.5, d = Math.Sqrt(dx * dx + dy * dy);
                if (R >= 0)
                {
                    if (d > R) return 16;
                    if (d > R - 1.5) return 231;
                }
                double X = u / VW, Y = v / VH;
                double n = 0.42 + 0.20 * Math.Sin(d / 45.0 * TAU * k - t * a)
                         + 0.14 * Math.Sin((X * 1.5 + Y * 2.0) * TAU + t * 1.3)
                         + 0.10 * Math.Sin(X * TAU * 3 - t);
                n *= (1 - 0.35 * (d / 45.0) * (d / 45.0)) * g;
                n *= Intro.Panel(u, v, bx0, bx1, 15, 31, dimA);
                return pal[Intro.Lvl(n)];
            });
        }
    }

    // =================================================================================
    //  CLOSING 2  Sunset: retro striped sun sinks behind the horizon over a wave grid
    // =================================================================================
    internal class Sunset : PlasmaScene
    {
        static readonly int[][] Pals = {
            new int[] { 16, 53, 89, 125, 161, 197, 203, 209, 222 },   // sunset
            new int[] { 16, 17, 54, 91, 127, 163, 207, 123, 159 },    // synthwave
            new int[] { 16, 23, 29, 35, 41, 78, 120, 157, 194 } };    // mint
        static readonly int[] Acc = { 209, 207, 120 };
        int[] pal;
        const double HZ = 29, SR = 13;

        public Sunset()
        {
            int v = Pick(3); pal = Pals[v]; Intro.accent = Acc[v];
            Intro.BuildLogo("WATTCAP"); off = new int[Intro.logoW];
            Dur = 6.6;
        }

        double SunY(double t) { return 17 + 5.0 * t; }

        public override void DrawVirtual(double t)
        {
            if (t < 0.5 || G(t) < 0.3) return;
            for (int c = 0; c < off.Length; c++) off[c] = (int)Math.Round(0.9 * Math.Sin(c * 0.4 - t * 2.5));
            Intro.DrawLogo(LogoX(), 6, off, 252, 231, ((t - 1.4) * 40) % (Intro.logoW + 50) - 20, 235, (int)((t - 0.5) * 24));
        }

        public override void DrawBackground(double t)
        {
            double g = G(t), cy = SunY(t);
            double bx0 = LogoX() - 6, bx1 = LogoX() + Intro.logoW + 6, dimA = 0.7 * Intro.Clamp01((t - 0.5) / 1.0);
            Intro.Paint(delegate(double u, double v)
            {
                double X = u / VW, lv;
                if (v >= HZ)
                {
                    if (v < HZ + 0.8) return pal[Intro.Dith(7 * g)];
                    double q = v - HZ;
                    double band = Math.Sin(Math.Sqrt(q) * 7.0 - t * 3.0);
                    lv = 1.0 + (band > 0.55 ? 2.0 : 0.0) + 0.6 * Math.Sin(X * TAU * 6 + t * 2);
                    // sun reflection column
                    if (cy - SR < HZ && Math.Abs(u - 40) < 9 - q * 0.2 && band > -0.2) lv += 3.0;
                    return pal[Intro.Dith(lv * g)];
                }
                double dx = u - 40, dy = v - cy, dd = Math.Sqrt(dx * dx + dy * dy);
                lv = 1.2 + 1.6 * (1 - v / HZ) + 0.6 * Math.Sin(X * TAU * 3 + t * 0.8) + 3.0 * Math.Exp(-(dd / 22.0) * (dd / 22.0));
                if (dd <= SR)
                {
                    double fr = (v - (cy - SR)) / (2 * SR);
                    bool gap = fr > 0.5 && ((int)Math.Floor(v)) % 4 < (int)((fr - 0.5) * 9);
                    if (!gap) lv = 8 - fr * 5;
                }
                lv *= Intro.Panel(u, v, bx0, bx1, 4, 16, dimA);
                return pal[Intro.Dith(lv * g)];
            });
        }
    }

    // =================================================================================
    //  CLOSING 3  Shutter: cool plasma behind venetian-blind slats that snap shut top to bottom
    // =================================================================================
    internal class Shutter : PlasmaScene
    {
        static readonly int[][] Pals = {
            new int[] { 16, 17, 24, 31, 38, 44, 80, 123, 231 },       // ice
            new int[] { 16, 22, 28, 34, 70, 112, 154, 192, 231 },     // lime
            new int[] { 16, 52, 88, 124, 160, 196, 203, 210, 224 } }; // crimson
        static readonly int[] Acc = { 123, 154, 210 };
        int[] pal; double k1, k2, k3, a1, a2, a3;
        const double S0 = 3.2;

        public Shutter()
        {
            int v = Pick(3); pal = Pals[v]; Intro.accent = Acc[v];
            k1 = Intro.Rr(1.5, 3.0); k2 = Intro.Rr(1.5, 3.0); k3 = Intro.Rr(1.0, 2.5);
            a1 = Intro.Rr(1.0, 1.8); a2 = Intro.Rr(0.8, 1.6); a3 = Intro.Rr(1.2, 2.0);
            Intro.BuildLogo("WATTCAP"); off = new int[Intro.logoW];
            Dur = 5.9;
        }

        // 0 open, 1 slat, 2 slat edge
        int Slat(double t, double v)
        {
            double j = Math.Floor(v / 3.0), jc = Math.Max(0, Math.Min(14, j)), f = v / 3.0 - j;
            double p = Intro.Clamp01((t - S0) / 1.1 - jc / 14.0 * 0.6);
            if (p <= 0) return 0;
            double ap = 1 - p, d = Math.Abs(f - 0.5) * 2;
            if (d < ap) return 0;
            return d < ap + 0.18 ? 2 : 1;
        }

        public override void DrawVirtual(double t)
        {
            if (t < 0.5) return;
            for (int c = 0; c < off.Length; c++) off[c] = 0;
            Intro.DrawLogo(LogoX(), 19, off, 252, 231, ((t - 1.5) * 40) % (Intro.logoW + 50) - 20, 235, (int)((t - 0.5) * 24));
        }

        public override void MaskVirtual(double t)
        {
            if (t < S0) return;
            Intro.MaskVB(delegate(double x, double y) { return Slat(t, y) != 0; });
        }

        public override void DrawBackground(double t)
        {
            double g = Intro.Clamp01(t / 0.6), dimA = 0.75 * Intro.Clamp01((t - 0.5) / 1.0);
            double bx0 = LogoX() - 6, bx1 = LogoX() + Intro.logoW + 6;
            Intro.Paint(delegate(double u, double v)
            {
                if (t >= S0)
                {
                    int st = Slat(t, v);
                    if (st == 1) return ((int)Math.Floor(v)) % 2 == 0 ? 238 : 236;
                    if (st == 2) return 250;
                }
                double X = u / VW, Y = v / VH;
                double n = 0.42 + 0.20 * Math.Sin(X * TAU * k1 + t * a1) + 0.18 * Math.Sin(Y * TAU * k2 - t * a2)
                         + 0.16 * Math.Sin((X + Y) * TAU * k3 + t * a3);
                double ux = X * 2 - 1, uy = Y * 2 - 1;
                n *= (1 - 0.3 * (ux * ux * 0.8 + uy * uy)) * g;
                n *= Intro.Panel(u, v, bx0, bx1, 15, 31, dimA);
                return pal[Intro.Lvl(n)];
            });
        }
    }

    // =================================================================================
    //  CLOSING 4  Cooldown: hot plasma cools front by front while the wattage counts down to the cap
    // =================================================================================
    internal class Cooldown : PlasmaScene
    {
        static readonly int[][] Hot = {
            new int[] { 16, 52, 88, 124, 160, 166, 208, 214, 229 },
            new int[] { 16, 53, 89, 125, 161, 204, 209, 215, 229 },
            new int[] { 16, 58, 94, 136, 172, 178, 214, 220, 230 } };
        static readonly int[][] Cold = {
            new int[] { 16, 17, 18, 24, 25, 31, 38, 45, 123 },
            new int[] { 16, 17, 54, 55, 61, 98, 105, 141, 189 },
            new int[] { 16, 22, 23, 29, 30, 36, 42, 49, 121 } };
        static readonly int[] Acc = { 45, 141, 49 };
        int[] hot, cold; double k1, k2, k3, k4, a1, a2, a3, a4;
        const double C0 = 1.0, C1 = 3.8;

        public Cooldown()
        {
            int v = Pick(3); hot = Hot[v]; cold = Cold[v]; Intro.accent = Acc[v];
            k1 = Intro.Rr(1.4, 2.6); k2 = Intro.Rr(1.4, 2.6); k3 = Intro.Rr(1.0, 2.2); k4 = Intro.Rr(2.0, 4.0);
            a1 = Intro.Rr(1.0, 1.8); a2 = Intro.Rr(0.8, 1.6); a3 = Intro.Rr(1.2, 2.0); a4 = Intro.Rr(1.4, 2.4);
            Intro.BuildLogo(); off = new int[Intro.logoW];
            Dur = 6.6;
        }

        double P(double t) { double p = Intro.Clamp01((t - C0) / (C1 - C0)); return 1 - Math.Pow(1 - p, 2.2); }

        public override void DrawVirtual(double t)
        {
            if (G(t) < 0.3) return;
            int col = t < C0 ? 214 : (t < C1 ? 231 : Intro.accent);
            Intro.DrawLogo((VW - Intro.logoW) / 2, 19, null, col, 231, ((t - 1.2) * 40) % (Intro.logoW + 50) - 20, 235);
        }

        public override void DrawBackground(double t)
        {
            double g = G(t), p = P(t), yf = -0.15 + 1.35 * p;
            double bx0 = 40 - 24, bx1 = 40 + 24, dimA = 0.7 * Intro.Clamp01(t / 0.8);
            Intro.Paint(delegate(double u, double v)
            {
                double X = u / VW, Y = v / VH;
                double dx = X - 0.5, dy = (Y - 0.5) * VH / VW, d = Math.Sqrt(dx * dx + dy * dy);
                double n = 0.40 + 0.18 * Math.Sin(X * TAU * k1 + t * a1) + 0.16 * Math.Sin(Y * TAU * k2 - t * a2)
                         + 0.14 * Math.Sin((X + Y) * TAU * k3 + t * a3) + 0.12 * Math.Sin(d * TAU * k4 - t * a4);
                n *= (1 - 0.6 * d * d) * g;
                n *= Intro.Panel(u, v, bx0, bx1, 15, 31, dimA);
                double front = yf + 0.035 * Math.Sin(X * TAU * 3 + t * 2);
                if (p > 0 && p < 0.995 && Math.Abs(Y - front) < 0.022) return 231;
                return (Y < front ? cold : hot)[Intro.Lvl(n)];
            });
        }
    }
}
