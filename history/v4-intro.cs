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

        const string CSI = "\u001b[";
        internal const int VW = 80, VH = 45;
        internal static readonly byte[] vb = new byte[VW * VH];
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

        static void EnableVT()
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
        }

        static Scene MakeScene()
        {
            rng = new Random(Seed);
            if (Style == "plasma") return new Plasma();
            return new Invaders();
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
            for (int x = 0; x < SW; x++) { int m = (int)Math.Floor((x + 0.5 - offX) / sc); mapX[x] = (m >= 0 && m < VW) ? m : -1; }
            for (int y = 0; y < SH; y++) { int m = (int)Math.Floor((y + 0.5 - offY) / sc); mapY[y] = (m >= 0 && m < VH) ? m : -1; }
            prevKey = new int[c * (r - 1)];
            fullRedraw = true;
            return true;
        }

        static uint Hash(int x, int y)
        {
            uint h = (uint)(x * 374761393 + y * 668265263);
            h = (h ^ (h >> 13)) * 1274126177u;
            return h ^ (h >> 16);
        }

        static string Frame(Scene s, double t)
        {
            Array.Clear(vb, 0, vb.Length);
            s.DrawVirtual(t);
            s.DrawBackground(t);
            for (int y = 0; y < SH; y++)
            {
                int my = mapY[y]; if (my < 0) continue;
                int row = my * VW, o = y * SW;
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
                    try { while (Console.KeyAvailable) { Console.ReadKey(true); skip = true; } } catch { }
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
            if (x >= 0 && y >= 0 && x < VW && y < VH) vb[y * VW + x] = (byte)c;
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
            string word = "RTX ";
            foreach (char ch in Match.ToUpperInvariant()) if (F5.ContainsKey(ch) && ch != ' ') word += ch;
            List<string[]> gl = new List<string[]>();
            foreach (char ch in word) gl.Add(F5[ch]);
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
        }

        // colOff: per-column vertical offset (may be null)
        internal static void DrawLogo(int x0, int y0, int[] colOff, int baseCol, int shineCol, double shinePos, int shadowCol)
        {
            for (int pass = 0; pass < 2; pass++)
                for (int c = 0; c < logoW; c++)
                {
                    int oy = colOff == null ? 0 : colOff[c];
                    for (int r = 0; r < 7; r++)
                    {
                        if (!logoMask[r, c]) continue;
                        if (pass == 0) { Px(x0 + c + 1, y0 + r + oy + 1, shadowCol); continue; }
                        double sh = c - r - shinePos;
                        Px(x0 + c, y0 + r + oy, (sh >= 0 && sh < 4) ? shineCol : baseCol);
                    }
                }
        }

        internal static void Subtitle(double t0, double t, int y, int col1, int col2)
        {
            string l1 = "POWER LIMIT";
            string l2 = Watts + " W" + (NGpu > 0 ? " X" + NGpu : "");
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
    //  Invaders: original robot squad, 5 designs x 3 colour schemes (15 unique bots)
    // =================================================================================
    internal class Invaders : Intro.Scene
    {
        const int VW = Intro.VW, VH = Intro.VH;
        const int NC = 5, NR = 3, CW = 12, RH = 8, BW = 9, BH = 6;

        static readonly string[][][] Bots = new string[][][] {
            new string[][] {   // antenna bot
                new string[] { "...+.+...", "..#####..", ".##o#o##.", ".#######.", "..#.#.#..", ".#.....#." },
                new string[] { "..+...+..", "..#####..", ".##o#o##.", ".#######.", "..#.#.#..", "..#...#.." } },
            new string[][] {   // visor bot, scanning eye
                new string[] { "..#####..", ".#######.", "#+o+++++#", ".#######.", "..#...#..", ".##...##." },
                new string[] { "..#####..", ".#######.", "#+++++o+#", ".#######.", "..#...#..", "..##.##.." } },
            new string[][] {   // cyclops
                new string[] { "...###...", "..#ooo#..", "#.#oxo#.#", "#########", "..#...#..", ".#.....#." },
                new string[] { "...###...", "..#ooo#..", "..#xoo#..", "#########", "#.#...#.#", "..#...#.." } },
            new string[][] {   // box bot with grille
                new string[] { "+.......+", ".#######.", ".#o###o#.", ".#+.+.+#.", ".#######.", "#.#...#.#" },
                new string[] { ".+.....+.", ".#######.", ".#o###o#.", ".#.+.+.#.", ".#######.", ".#.#.#.#." } },
            new string[][] {   // spider bot
                new string[] { "...###...", ".#######.", "##o###o##", ".#######.", "#.#.#.#.#", "#.......#" },
                new string[] { "...###...", ".#######.", "##x###x##", ".#######.", ".#.#.#.#.", "#.#...#.#" } },
        };
        static readonly int[] Body = { 171, 45, 118 };
        static readonly int[] Acc = { 219, 159, 229 };

        static readonly string[][] Boss = new string[][] {
            new string[] { ".....#####.....", "...#########...", "..##o##o##o##..", ".#############.", "..+.+.+.+.+.+.." },
            new string[] { ".....#####.....", "...#########...", "..##o##o##o##..", ".#############.", "...+.+.+.+.+..." } };

        static readonly string[][] Ship = new string[][] {
            new string[] { "......#......", ".....###.....", "#############", "#+o+#+o+#+o+#", ".g.g.g.g.g.g." },
            new string[] { "......#......", ".....###.....", "#############", "#o+o#o+o#o+o#", ".g.g.g.g.g.g." } };

        class Shot { public double x, y, vy; public bool mine; }

        bool[] alive = new bool[NC * NR];
        double[] flash = new double[NC * NR];
        double fx = 11, fy = 14, stepT = 0, bombT = 1.6, fireCd = 0, chainT = 0;
        int dir = 1, frame = 0, kills = 0;
        double px = 40, target = 40;
        int shipFrame = 0; double shipAnim = 0;
        List<Shot> shots = new List<Shot>();
        double bossX = -20, bossV = 22; bool bossLive = false, bossStarted = false; double bossY = 7;
        double tClear = -1, nextFw = 0;
        double[,] stars;

        public Invaders()
        {
            for (int i = 0; i < alive.Length; i++) alive[i] = true;
            Intro.BuildLogo();
            Intro.accent = 45;
            Intro.parts.Clear();
            stars = new double[140, 3];
            for (int i = 0; i < 140; i++)
            {
                stars[i, 0] = Intro.rng.NextDouble(); stars[i, 1] = Intro.rng.NextDouble();
                stars[i, 2] = Intro.rng.Next(3);
            }
            if (Intro.rng.NextDouble() < 0.5) { bossX = VW + 5; bossV = -22; }
        }

        public override double End { get { return tClear < 0 ? 1e9 : tClear + 4.4; } }

        int Alive() { int n = 0; foreach (bool a in alive) if (a) n++; return n; }
        double BotX(int c) { return fx + c * CW; }
        double BotY(int r) { return fy + r * RH; }

        void Kill(int i)
        {
            alive[i] = false; flash[i] = 0.08; kills++;
            int r = i / NC, c = i % NC;
            Intro.Burst(BotX(c) + 4, BotY(r) + 3, 16, 26, new int[] { Body[r], Acc[r], 231 }, 0.8);
        }

        public override void Step(double t, double dt)
        {
            for (int i = 0; i < stars.GetLength(0); i++)
            {
                stars[i, 1] += (0.008 + 0.018 * stars[i, 2]) * dt;
                if (stars[i, 1] >= 1) { stars[i, 1] -= 1; stars[i, 0] = Intro.rng.NextDouble(); }
            }
            for (int i = 0; i < flash.Length; i++) if (flash[i] > 0) flash[i] -= dt;
            Intro.StepParts(dt);
            shipAnim += dt; if (shipAnim > 0.08) { shipAnim = 0; shipFrame ^= 1; }

            // formation drops in
            fy = 14 - 34 * (1 - Intro.Clamp01(t / 0.9)) * (1 - Intro.Clamp01(t / 0.9));
            int n = Alive();

            if (t > 0.9 && n > 0)
            {
                stepT -= dt;
                if (stepT <= 0)
                {
                    stepT = 0.05 + 0.30 * n / (double)alive.Length;
                    frame ^= 1;
                    int minC = NC, maxC = -1;
                    for (int i = 0; i < alive.Length; i++) if (alive[i]) { minC = Math.Min(minC, i % NC); maxC = Math.Max(maxC, i % NC); }
                    double nx = fx + dir * 2;
                    if (nx + minC * CW < 2 || nx + maxC * CW + BW > VW - 2) dir = -dir; else fx = nx;
                }
                // bombs from the lowest bot in a random live column
                bombT -= dt;
                if (bombT <= 0)
                {
                    bombT = 0.55 + Intro.rng.NextDouble() * 0.7;
                    int c = Intro.rng.Next(NC);
                    for (int k = 0; k < NC; k++, c = (c + 1) % NC)
                    {
                        int low = -1;
                        for (int r = NR - 1; r >= 0; r--) if (alive[r * NC + c]) { low = r; break; }
                        if (low >= 0)
                        {
                            Shot b = new Shot(); b.x = BotX(c) + 4; b.y = BotY(low) + BH; b.vy = 34; b.mine = false;
                            shots.Add(b); break;
                        }
                    }
                }
            }

            // boss run
            if (!bossStarted && t > 3.0) { bossStarted = true; bossLive = true; }
            if (bossLive)
            {
                bossX += bossV * dt;
                if (bossX > VW + 16 || bossX < -18) bossLive = false;
            }

            // chain-detonate stragglers so the intro always ends
            if (t > 9.5 && n > 0)
            {
                chainT -= dt;
                if (chainT <= 0) { chainT = 0.09; for (int i = 0; i < alive.Length; i++) if (alive[i]) { Kill(i); break; } }
            }

            // player AI
            if (t > 1.0 && tClear < 0)
            {
                double best = 1e9; double tx = px;
                for (int c = 0; c < NC; c++)
                {
                    int low = -1;
                    for (int r = NR - 1; r >= 0; r--) if (alive[r * NC + c]) { low = r; break; }
                    if (low < 0) continue;
                    double cx = BotX(c) + 4 + dir * 1.5;
                    double score = Math.Abs(cx - px) - low * 3;
                    if (score < best) { best = score; tx = cx; }
                }
                if (bossLive && bossX > 0 && bossX < VW - 15)
                {
                    double lead = bossV * (39 - bossY - 2) / 95.0;
                    double bx = bossX + 7 + lead;
                    if (Math.Abs(bx - px) < 18) tx = bx;
                }
                foreach (Shot b in shots)
                    if (!b.mine && b.y > 24 && Math.Abs(b.x - px) < 7) { tx = px + (px < b.x ? -14 : 14); break; }
                target = Math.Max(7, Math.Min(VW - 7, tx));
                double mv = 55 * dt;
                if (Math.Abs(target - px) <= mv) px = target; else px += Math.Sign(target - px) * mv;

                fireCd -= dt;
                int mine = 0; foreach (Shot b in shots) if (b.mine) mine++;
                if (fireCd <= 0 && mine < 2 && Math.Abs(target - px) < 1.6)
                {
                    Shot s = new Shot(); s.x = Math.Round(px); s.y = 37; s.vy = -95; s.mine = true;
                    shots.Add(s); fireCd = 0.2;
                }
            }
            else if (tClear >= 0)
            {
                double mv = 30 * dt, tx = VW / 2.0 + Math.Sin(t * 1.3) * 6;
                if (Math.Abs(tx - px) <= mv) px = tx; else px += Math.Sign(tx - px) * mv;
            }

            // shots
            for (int i = shots.Count - 1; i >= 0; i--)
            {
                Shot s = shots[i];
                s.y += s.vy * dt;
                bool gone = s.y < -3 || s.y > VH;
                if (s.mine && !gone)
                {
                    for (int k = 0; k < alive.Length && !gone; k++)
                    {
                        if (!alive[k]) continue;
                        double bx = BotX(k % NC), by = BotY(k / NC);
                        if (s.x >= bx && s.x < bx + BW && s.y >= by && s.y < by + BH) { Kill(k); gone = true; }
                    }
                    if (!gone && bossLive && s.x >= bossX && s.x < bossX + 15 && s.y >= bossY && s.y < bossY + 5)
                    {
                        bossLive = false; gone = true;
                        Intro.Burst(bossX + 7, bossY + 2, 40, 34, new int[] { 203, 226, 231, 209 }, 1.1);
                    }
                }
                else if (!s.mine && !gone && s.y >= 39)
                {
                    if (Math.Abs(s.x - px) < 6.5) { Intro.Burst(s.x, 39, 6, 14, new int[] { 226, 231 }, 0.35); gone = true; }
                    else if (s.y >= 43) { Intro.Burst(s.x, 43, 3, 8, new int[] { 240 }, 0.3); gone = true; }
                }
                if (gone) shots.RemoveAt(i);
            }

            if (Alive() == 0 && tClear < 0) { tClear = t; nextFw = t + 1.1; }
            if (tClear >= 0 && t > nextFw && t < tClear + 3.6)
            {
                nextFw = t + 0.32;
                int[][] pals = new int[][] { new int[] { 45, 159, 231 }, new int[] { 171, 219, 231 }, new int[] { 118, 229, 231 }, new int[] { 214, 226, 231 } };
                Intro.Burst(8 + Intro.rng.NextDouble() * (VW - 16), 6 + Intro.rng.NextDouble() * 6, 22, 22, pals[Intro.rng.Next(4)], 0.9);
            }
        }

        public override void DrawVirtual(double t)
        {
            // HUD: power meter counts from stock down to the cap as bots fall
            double pw = Intro.Stock - (Intro.Stock - Intro.Watts) * kills / (double)alive.Length;
            bool done = kills >= alive.Length;
            Intro.Text3("PWR", 1, 1, 244);
            Intro.Text3(((int)Math.Round(pw)) + "W", 17, 1, done ? ((int)(t * 6) % 2 == 0 ? 214 : 226) : 231);
            string cap = "CAP " + Intro.Watts + "W" + (Intro.NGpu > 0 ? " X" + Intro.NGpu : "");
            Intro.Text3(cap, VW - 1 - Intro.Text3W(cap), 1, 244);

            // ground
            for (int x = 0; x < VW; x++) Intro.Px(x, 44, (x % 2 == 0) ? 22 : 28);

            // bots
            for (int i = 0; i < alive.Length; i++)
            {
                int r = i / NC, c = i % NC;
                int bx = (int)Math.Round(BotX(c)), by = (int)Math.Round(BotY(r));
                if (alive[i]) Intro.Blit(Bots[c][frame], bx, by, Body[r], Acc[r]);
                else if (flash[i] > 0) Intro.BlitSolid(Bots[c][frame], bx, by, 231);
            }
            if (bossLive) Intro.Blit(Boss[((int)(t * 8)) % 2], (int)Math.Round(bossX), (int)bossY, 203, 226);

            foreach (Shot s in shots)
            {
                int x = (int)Math.Round(s.x), y = (int)Math.Round(s.y);
                if (s.mine) { Intro.Px(x, y, 231); Intro.Px(x, y + 1, 159); }
                else { int z = ((int)(s.y) / 2) % 2; Intro.Px(x + z, y, 209); Intro.Px(x + 1 - z, y + 1, 203); Intro.Px(x + z, y + 2, 209); }
            }

            Intro.Blit(Ship[shipFrame], (int)Math.Round(px) - 6, 39, 250, 240);
            Intro.DrawParts();

            if (tClear >= 0)
            {
                double tl = t - tClear - 0.3;
                if (tl > 0)
                {
                    int lx = (VW - Intro.logoW) / 2;
                    int ly = (int)Math.Round(-9 + (14 + 9) * Intro.Bounce(tl / 0.9));
                    Intro.DrawLogo(lx, ly, null, 252, 231, (tl - 0.9) * 40 - 8, 236);
                    Intro.Subtitle(tClear + 1.1, t, 24, 250, 214);
                }
            }
        }

        public override void DrawBackground(double t)
        {
            byte[] sp = Intro.spix; int SW = Intro.SW, SH = Intro.SH;
            for (int i = 0; i < sp.Length; i++) sp[i] = 16;
            for (int i = 0; i < stars.GetLength(0); i++)
            {
                int x = (int)(stars[i, 0] * SW), y = (int)(stars[i, 1] * SH);
                if (x < 0 || y < 0 || x >= SW || y >= SH) continue;
                int layer = (int)stars[i, 2];
                double tw = Math.Sin(t * (2 + layer) + i);
                int col = layer == 0 ? 236 : (layer == 1 ? 240 : (tw > 0.3 ? 252 : 245));
                sp[y * SW + x] = (byte)col;
            }
        }
    }

    // =================================================================================
    //  Plasma: seeded field whose peaks are clipped at Watts/Stock (the throttle plateau)
    // =================================================================================
    internal class Plasma : Intro.Scene
    {
        const int VW = Intro.VW, VH = Intro.VH;
        double k1, a1, k2, a2, k3, k4, a3, k5, a5, cx0, cy0, h1, h2, p1, p2, cap;
        int[] pal; int thr;
        int[] off;

        static readonly int[][] Pals = {
            new int[] { 16, 22, 22, 28, 34, 35, 41, 77, 120 },
            new int[] { 16, 17, 17, 18, 24, 25, 31, 38, 87 },
            new int[] { 16, 53, 53, 54, 55, 91, 128, 170, 213 } };
        static readonly int[] Thr = { 214, 209, 222 };
        static readonly int[] Hi = { 120, 87, 213 };

        double R(double a, double b) { return a + (b - a) * Intro.rng.NextDouble(); }

        public Plasma()
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
        }

        public override double End { get { return 7.5; } }
        public override void Step(double t, double dt) { }

        double G(double t) { return Intro.Clamp01(t / 0.8) * Intro.Clamp01((End - 0.3 - t) / 0.6); }

        int LogoX(double t)
        {
            double p = Intro.Clamp01((t - 0.5) / 1.5), e = 1 - Math.Pow(1 - p, 3);
            int lt = (VW - Intro.logoW) / 2;
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
            Intro.DrawLogo(LogoX(t), 13, off, b, s, ((t - 2.3) * 40) % (Intro.logoW + 50) - 20, 235);
            if (g > 0.5) Intro.Subtitle(2.2, t, 24, 250, thr);
        }

        public override void DrawBackground(double t)
        {
            byte[] sp = Intro.spix; int SW = Intro.SW, SH = Intro.SH;
            double sc = Intro.sc, ox = Intro.offX, oy = Intro.offY, g = G(t);
            double hx = 0.5 + 0.36 * Math.Sin(t * h1 + p1), hy = 0.5 + 0.34 * Math.Sin(t * h2 + p2);
            double dimA = 0.8 * Intro.Clamp01((t - 0.6) / 1.2);
            double bx0 = LogoX(t) - 6, bx1 = LogoX(t) + Intro.logoW + 6, by0 = 9, by1 = 38;
            double TAU = Math.PI * 2;
            for (int y = 0; y < SH; y++)
            {
                double v = (y + 0.5 - oy) / sc, Y = v / VH;
                double sy = Math.Sin(Y * TAU * k2 + t * a2);
                double qy = (Y - hy) / 0.30, gy = Math.Exp(-qy * qy) * 0.55;
                double uy = Y * 2 - 1;
                bool inY = v >= by0 && v <= by1;
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
                    if (inY && u >= bx0 && u <= bx1)
                    {
                        double fe = Math.Min(Math.Min(u - bx0, bx1 - u) / 5.0, Math.Min(v - by0, by1 - v) / 3.0);
                        if (fe > 1) fe = 1;
                        n *= 1 - dimA * (fe + 0.25) / 1.25;
                    }
                    int k = n >= cap ? -1 : (n <= 0 ? 0 : (int)Math.Floor(n / cap * 9));
                    if (k > 8) k = 8;
                    sp[y * SW + x] = (byte)(k < 0 ? thr : pal[k]);
                }
            }
        }
    }
}
