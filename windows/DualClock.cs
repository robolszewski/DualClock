// DualClock for Windows v2.2 - Analog clock showing Local (primary) and UTC (secondary) time.
// v1.3: UTC hands share the local hands' exact geometry (only color differs), so they are fully
//       hidden under the local hands wherever the times coincide. Local zone label on dial.
// v1.4: Local date on the dial - month (left of center) and 2-digit day (right of center).
// v1.5: Month and day framed in thin black date windows.
// v2.2: Feature parity with the Apple versions (macOS v1.9 / iOS v2.0 / watchOS v2.1):
//       - One app with a 12h | 12/24 | 24h switch in the lower-right corner (replaces the separate
//         "DualClock 12h" / "DualClock 24h" shortcuts).
//       - "12/24" mode: 12-hour dial with a smaller, faded inner 13-24 ring that swaps places with the
//         main numbers after noon (12 and 24 swap at 13:00); 24-hour readout.
//       - Wide windows put the readout beside the clock; tall windows center the clock vertically.
//       - Readout shrinks to fit narrow windows.
//       - "Two Hands" icon: built into DualClock.exe, and the taskbar icon is a live 12-hour clock.
//       - Drag anywhere to move the window. Screen readers get both times.
//       - 12h dial: sun (AM) / crescent moon (PM) beside the zone label, and beside UTC when it differs.
// Written in C# 5 so it compiles with the csc.exe that ships with Windows (.NET Framework 4.x).
//
// Controls:
//   12h | 12/24 | 24h switch ... click (lower right) to change dial mode
//   Right-click ................ menu (dial mode, second hand, digital readout, always on top, exit)
//   T .......................... cycle 12h -> 12/24 -> 24h
//   Double-click ............... toggle always on top
//   Drag anywhere .............. move the window
//   Esc ........................ exit
//   DualClock.exe /12 | /dual | /24 ... start in that mode (optional)
// Hidden hooks:
//   --render out.png [12|dual|24] [pm]   420x520 preview at a fixed time (11:28 AM, or 3:28 PM with pm)
//   --render-icon out.png SIZE [tile|full]  "Two Hands" icon (tile = Windows/macOS tile, full = iOS/watchOS square)
//   --make-icon DualClock.ico            multi-size .ico (used by Build.bat)

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace DualClock
{
    internal enum DialMode { Twelve = 0, Dual = 1, TwentyFour = 2 }

    internal static class Modes
    {
        public static readonly DialMode[] All = { DialMode.Twelve, DialMode.Dual, DialMode.TwentyFour };
        public static bool HandsUse24(DialMode m) { return m == DialMode.TwentyFour; }
        public static bool ReadoutUse24(DialMode m) { return m != DialMode.Twelve; }
        public static DialMode Next(DialMode m) { return (DialMode)(((int)m + 1) % 3); }
        public static string Label(DialMode m)
        {
            switch (m)
            {
                case DialMode.Dual: return "12/24";
                case DialMode.TwentyFour: return "24h";
                default: return "12h";
            }
        }
    }

    internal static class Program
    {
        [STAThread]
        private static void Main(string[] args)
        {
            if (args.Length >= 2 && args[0] == "--render")
            {
                DialMode m = DialMode.Twelve;
                bool pm = false;
                for (int i = 2; i < args.Length; i++)
                {
                    if (args[i] == "24") m = DialMode.TwentyFour;
                    else if (args[i] == "dual") m = DialMode.Dual;
                    else if (args[i] == "pm") pm = true;
                }
                RenderPreview(args[1], m, pm);
                return;
            }
            if (args.Length >= 3 && args[0] == "--render-icon")
            {
                int size = int.Parse(args[2]);
                bool full = args.Length >= 4 && args[3] == "full";
                using (Bitmap bmp = ClockRenderer.IconBitmap(size, ClockRenderer.IconUtc, ClockRenderer.IconOffset, !full, size >= 64))
                    bmp.Save(args[1], ImageFormat.Png);
                return;
            }
            if (args.Length >= 2 && args[0] == "--make-icon")
            {
                IconWriter.Write(args[1]);
                return;
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            int forced = -1;
            foreach (string a in args)
            {
                string x = a.TrimStart('/', '-').ToLowerInvariant();
                if (x == "12") forced = (int)DialMode.Twelve;
                else if (x == "dual" || x == "12/24") forced = (int)DialMode.Dual;
                else if (x == "24") forced = (int)DialMode.TwentyFour;
            }
            Application.Run(new ClockForm(forced));
        }

        private static void RenderPreview(string path, DialMode mode, bool pm)
        {
            using (Bitmap bmp = new Bitmap(420, 520))
            using (Graphics g = Graphics.FromImage(bmp))
            {
                DateTime utc = new DateTime(2026, 10, 15, pm ? 19 : 15, 28, 42, DateTimeKind.Utc);
                DateTime local = utc.AddHours(-4);
                ClockRenderer.Draw(g, new Rectangle(0, 0, 420, 520), local, utc, "EDT", mode, true, true);
                bmp.Save(path, ImageFormat.Png);
            }
        }
    }

    // MARK: Settings (%APPDATA%\DualClock\settings.ini)

    internal sealed class Settings
    {
        public DialMode Mode = DialMode.Twelve;
        public bool TopMost = false;
        public bool ShowSeconds = true;
        public bool ShowDigital = true;
        public int X = -1, Y = -1, W = 380, H = 480;

        private static string FilePath
        {
            get
            {
                string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DualClock");
                return Path.Combine(dir, "settings.ini");
            }
        }

        public static Settings Load()
        {
            Settings s = new Settings();
            try
            {
                string src = FilePath;
                if (!File.Exists(src)) // first run of v2.2: pick up the old 12h shortcut's settings (v1.5)
                    src = Path.Combine(Path.GetDirectoryName(FilePath), "settings-12.ini");
                if (!File.Exists(src)) return s;
                bool haveMode = false, use24 = false;
                foreach (string line in File.ReadAllLines(src))
                {
                    string[] kv = line.Split('=');
                    if (kv.Length != 2) continue;
                    string k = kv[0].Trim(), v = kv[1].Trim();
                    int n;
                    switch (k)
                    {
                        case "DialMode":
                            if (int.TryParse(v, out n) && n >= 0 && n <= 2) { s.Mode = (DialMode)n; haveMode = true; }
                            break;
                        case "Use24Hour": use24 = v == "1"; break; // carried over from v1.5
                        case "TopMost": s.TopMost = v == "1"; break;
                        case "ShowSeconds": s.ShowSeconds = v == "1"; break;
                        case "ShowDigital": s.ShowDigital = v == "1"; break;
                        case "X": if (int.TryParse(v, out n)) s.X = n; break;
                        case "Y": if (int.TryParse(v, out n)) s.Y = n; break;
                        case "W": if (int.TryParse(v, out n)) s.W = n; break;
                        case "H": if (int.TryParse(v, out n)) s.H = n; break;
                    }
                }
                if (!haveMode) s.Mode = use24 ? DialMode.TwentyFour : DialMode.Twelve;
            }
            catch { }
            return s;
        }

        public void Save()
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(FilePath));
                File.WriteAllLines(FilePath, new string[] {
                    "DialMode=" + (int)Mode,
                    "TopMost=" + (TopMost ? "1" : "0"),
                    "ShowSeconds=" + (ShowSeconds ? "1" : "0"),
                    "ShowDigital=" + (ShowDigital ? "1" : "0"),
                    "X=" + X, "Y=" + Y, "W=" + W, "H=" + H
                });
            }
            catch { }
        }
    }

    // MARK: Window

    internal sealed class ClockForm : Form
    {
        [DllImport("user32.dll")] private static extern bool ReleaseCapture();
        [DllImport("user32.dll")] private static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr hIcon);
        private const int WM_NCLBUTTONDOWN = 0xA1, HTCAPTION = 2;

        private readonly Settings _s;
        private readonly Timer _timer;
        private ToolStripMenuItem _mi12, _miDual, _mi24, _miTop, _miSec, _miDig;
        private Point _downAt;
        private bool _downOnFace;
        private Icon _liveIcon;
        private IntPtr _liveIconHandle = IntPtr.Zero;
        private int _iconSecond = -1;

        public ClockForm(int forced)
        {
            _s = Settings.Load();
            if (forced >= 0) _s.Mode = (DialMode)forced;

            Text = "Dual Clock - Local / UTC";
            BackColor = ClockRenderer.Background;
            DoubleBuffered = true;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            MinimumSize = new Size(220, 270);
            KeyPreview = true;
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            StartPosition = FormStartPosition.Manual;
            Size = new Size(_s.W, _s.H);
            Rectangle wa = Screen.PrimaryScreen.WorkingArea;
            Point p = new Point(_s.X, _s.Y);
            bool onScreen = false;
            foreach (Screen sc in Screen.AllScreens)
                if (sc.WorkingArea.Contains(new Point(p.X + 40, p.Y + 20))) onScreen = true;
            Location = onScreen ? p : new Point(wa.Right - Width - 20, wa.Top + 20);
            TopMost = _s.TopMost;

            BuildMenu();

            _timer = new Timer();
            _timer.Interval = 200;
            _timer.Tick += delegate { Invalidate(); UpdateLiveIcon(); };
            _timer.Start();
            UpdateLiveIcon();

            KeyDown += OnKey;
            MouseDown += OnMouseDown;
            MouseMove += OnMouseMove;
            MouseDoubleClick += delegate(object sender, MouseEventArgs e)
            {
                if (e.Button == MouseButtons.Left && ClockRenderer.SwitchHit(e.Location, ClientRectangle) < 0)
                    SetTopMost(!TopMost);
            };
            FormClosing += delegate
            {
                if (WindowState == FormWindowState.Normal)
                {
                    _s.X = Left; _s.Y = Top; _s.W = Width; _s.H = Height;
                }
                _s.Save();
                _timer.Stop();
            };
        }

        private void BuildMenu()
        {
            ContextMenuStrip m = new ContextMenuStrip();
            _mi12 = new ToolStripMenuItem("12-hour dial", null, delegate { SetMode(DialMode.Twelve); });
            _miDual = new ToolStripMenuItem("12-hour dial with 13-24 ring", null, delegate { SetMode(DialMode.Dual); });
            _mi24 = new ToolStripMenuItem("24-hour dial", null, delegate { SetMode(DialMode.TwentyFour); });
            _miTop = new ToolStripMenuItem("Always on top", null, delegate { SetTopMost(!TopMost); });
            _miSec = new ToolStripMenuItem("Show second hand", null, delegate { _s.ShowSeconds = !_s.ShowSeconds; Sync(); });
            _miDig = new ToolStripMenuItem("Show digital readout", null, delegate { _s.ShowDigital = !_s.ShowDigital; Sync(); });
            m.Items.Add(_mi12);
            m.Items.Add(_miDual);
            m.Items.Add(_mi24);
            m.Items.Add(new ToolStripSeparator());
            m.Items.Add(_miSec);
            m.Items.Add(_miDig);
            m.Items.Add(_miTop);
            m.Items.Add(new ToolStripSeparator());
            m.Items.Add(new ToolStripMenuItem("Exit", null, delegate { Close(); }));
            ContextMenuStrip = m;
            Sync();
        }

        private void Sync()
        {
            _mi12.Checked = _s.Mode == DialMode.Twelve;
            _miDual.Checked = _s.Mode == DialMode.Dual;
            _mi24.Checked = _s.Mode == DialMode.TwentyFour;
            _miTop.Checked = TopMost;
            _miSec.Checked = _s.ShowSeconds;
            _miDig.Checked = _s.ShowDigital;
            _s.TopMost = TopMost;
            _s.Save();
            _iconSecond = -1;
            Invalidate();
        }

        private void SetMode(DialMode m) { _s.Mode = m; Sync(); }
        private void SetTopMost(bool on) { TopMost = on; Sync(); }

        private void OnKey(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.T && !e.Control && !e.Alt) SetMode(Modes.Next(_s.Mode));
            else if (e.KeyCode == Keys.Escape) Close();
        }

        private void OnMouseDown(object sender, MouseEventArgs e)
        {
            _downOnFace = false;
            if (e.Button != MouseButtons.Left) return;
            int seg = ClockRenderer.SwitchHit(e.Location, ClientRectangle);
            if (seg >= 0) { SetMode(Modes.All[seg]); return; }
            _downAt = e.Location;
            _downOnFace = true;
        }

        // Drag anywhere to move the window. Starts only after the mouse actually moves, so clicks
        // and double-clicks behave normally.
        private void OnMouseMove(object sender, MouseEventArgs e)
        {
            bool overSwitch = ClockRenderer.SwitchHit(e.Location, ClientRectangle) >= 0;
            Cursor = overSwitch ? Cursors.Hand : Cursors.Default;
            if (!_downOnFace || e.Button != MouseButtons.Left) return;
            Size drag = SystemInformation.DragSize;
            if (Math.Abs(e.X - _downAt.X) < drag.Width && Math.Abs(e.Y - _downAt.Y) < drag.Height) return;
            _downOnFace = false;
            ReleaseCapture();
            SendMessage(Handle, WM_NCLBUTTONDOWN, (IntPtr)HTCAPTION, IntPtr.Zero);
        }

        // Live taskbar icon: the "Two Hands" clock, redrawn once a second.
        private void UpdateLiveIcon()
        {
            DateTime now = DateTime.UtcNow;
            if (now.Second == _iconSecond) return;
            _iconSecond = now.Second;
            try
            {
                using (Bitmap bmp = ClockRenderer.IconBitmap(64, now, TimeZoneInfo.Local.GetUtcOffset(now), true, true))
                {
                    IntPtr h = bmp.GetHicon();
                    Icon next = Icon.FromHandle(h);
                    Icon = next;
                    if (_liveIcon != null) _liveIcon.Dispose();
                    if (_liveIconHandle != IntPtr.Zero) DestroyIcon(_liveIconHandle);
                    _liveIcon = next;
                    _liveIconHandle = h;
                }
            }
            catch { }

            // Screen readers: both times
            DateTime local = now.ToLocalTime();
            bool use24 = Modes.ReadoutUse24(_s.Mode);
            AccessibleName = "Local " + ClockRenderer.Fmt(local, use24, false) + ", UTC " + ClockRenderer.Fmt(now, use24, false);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            DateTime utc = DateTime.UtcNow;
            DateTime local = utc.ToLocalTime();
            ClockRenderer.Draw(e.Graphics, ClientRectangle, local, utc,
                ClockRenderer.ZoneAbbrev(local), _s.Mode, _s.ShowSeconds, _s.ShowDigital);
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            base.OnFormClosed(e);
            if (_liveIconHandle != IntPtr.Zero) DestroyIcon(_liveIconHandle);
        }
    }

    // MARK: Renderer

    internal static class ClockRenderer
    {
        public static readonly Color Background = Color.FromArgb(244, 243, 239);
        private static readonly Color FaceFill = Color.White;
        private static readonly Color Rim = Color.FromArgb(40, 44, 52);
        private static readonly Color Ink = Color.FromArgb(28, 30, 36);          // local hands + numerals
        private static readonly Color SecondRed = Color.FromArgb(214, 48, 49);   // local second hand
        private static readonly Color UtcColor = Color.FromArgb(150, 92, 150, 214); // faded blue, ~60% opacity
        private static readonly Color UtcText = Color.FromArgb(92, 132, 190);
        private static readonly Color Tick = Color.FromArgb(120, 124, 132);
        private static readonly Color SoftNum = Color.FromArgb(90, 94, 102);
        private static readonly Color FadedNum = Color.FromArgb(150, 90, 94, 102); // 12/24 inner ring

        public static string ZoneAbbrev(DateTime local)
        {
            TimeZoneInfo tz = TimeZoneInfo.Local;
            string name = tz.IsDaylightSavingTime(local) ? tz.DaylightName : tz.StandardName;
            // "Eastern Daylight Time" -> "EDT"
            string abbr = "";
            foreach (string w in name.Split(' '))
                if (w.Length > 0 && char.IsLetter(w[0])) abbr += char.ToUpperInvariant(w[0]);
            return abbr.Length >= 2 && abbr.Length <= 5 ? abbr : "Local";
        }

        // MARK: 12h | 12/24 | 24h switch (lower-right corner, in a footer strip)

        private const float SegW = 44f, SwitchH = 22f, SwitchMargin = 10f;
        private static float SwitchW { get { return SegW * 3; } }
        private static float FooterH { get { return SwitchH + SwitchMargin; } }

        private static RectangleF SwitchRect(Rectangle b)
        {
            return new RectangleF(b.Right - SwitchW - SwitchMargin, b.Bottom - SwitchH - SwitchMargin, SwitchW, SwitchH);
        }

        // -1 = missed; otherwise index into Modes.All
        public static int SwitchHit(Point p, Rectangle b)
        {
            RectangleF r = SwitchRect(b);
            RectangleF hit = RectangleF.Inflate(r, 4, 4);
            if (!hit.Contains(p.X, p.Y)) return -1;
            int i = (int)((p.X - r.Left) / SegW);
            return Math.Max(0, Math.Min(2, i));
        }

        private static GraphicsPath Pill(RectangleF r)
        {
            GraphicsPath gp = new GraphicsPath();
            float d = r.Height;
            gp.AddArc(r.Left, r.Top, d, d, 90, 180);
            gp.AddArc(r.Right - d, r.Top, d, d, 270, 180);
            gp.CloseFigure();
            return gp;
        }

        private static void DrawSwitch(Graphics g, Rectangle b, DialMode mode)
        {
            RectangleF r = SwitchRect(b);
            using (GraphicsPath track = Pill(r))
            {
                using (SolidBrush fb = new SolidBrush(FaceFill)) g.FillPath(fb, track);
                int idx = (int)mode;
                RectangleF sel = new RectangleF(r.Left + SegW * idx + 2, r.Top + 2, SegW - 4, r.Height - 4);
                using (GraphicsPath sp = Pill(sel))
                using (SolidBrush ib = new SolidBrush(Ink)) g.FillPath(ib, sp);
                using (Pen pen = new Pen(Tick, 1f)) g.DrawPath(pen, track);
            }
            using (Font f = new Font("Segoe UI Semibold", 12f, FontStyle.Bold, GraphicsUnit.Pixel))
            using (SolidBrush on = new SolidBrush(FaceFill))
            using (SolidBrush off = new SolidBrush(SoftNum))
            using (StringFormat sf = Centered())
            {
                for (int i = 0; i < 3; i++)
                {
                    RectangleF cell = new RectangleF(r.Left + SegW * i, r.Top, SegW, r.Height);
                    g.DrawString(Modes.Label(Modes.All[i]), f, (int)mode == i ? on : off, cell, sf);
                }
            }
        }

        public static void Draw(Graphics g, Rectangle full, DateTime local, DateTime utc,
                                string zone, DialMode mode, bool showSeconds, bool showDigital)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            g.Clear(Background);
            DrawSwitch(g, full, mode);

            // Layout. Tall: clock above readout, both above the switch strip, centered vertically.
            // Wide: clock on the left at full height, readout centered in the right column.
            bool wide = full.Width > full.Height * 1.25f;
            PointF c;
            float R;
            RectangleF digitalArea = RectangleF.Empty;

            if (wide)
            {
                float cw = showDigital ? Math.Min(full.Width * 0.6f, full.Height) : full.Width;
                float colH = showDigital ? full.Height : full.Height - FooterH;
                RectangleF area = new RectangleF(full.Left, full.Top, cw, colH);
                float pad = Math.Max(10f, (float)Math.Floor(Math.Min(area.Width, area.Height) / 30f));
                float size = Math.Min(area.Width - 2 * pad, area.Height - 2 * pad);
                if (size < 50) return;
                R = size / 2f;
                c = new PointF(area.Left + area.Width / 2f, area.Top + area.Height / 2f);
                if (showDigital)
                {
                    RectangleF right = new RectangleF(full.Left + cw, full.Top, full.Width - cw, full.Height - FooterH);
                    float h = Math.Min(right.Height, Math.Max(60f, right.Width * 0.40f));
                    digitalArea = new RectangleF(right.Left + 8, right.Top + right.Height / 2f - h / 2f,
                                                 right.Width - 16 - SwitchMargin, h);
                }
            }
            else
            {
                RectangleF b = new RectangleF(full.Left, full.Top, full.Width, full.Height - FooterH);
                float digitalH = showDigital ? Math.Max(54f, (float)Math.Floor(b.Height / 7f)) : 0f;
                float pad = Math.Max(10f, (float)Math.Floor(Math.Min(b.Width, b.Height) / 30f));
                float size = Math.Min(b.Width - 2 * pad, b.Height - digitalH - 2 * pad);
                if (size < 50) return;
                R = size / 2f;
                float slack = Math.Max(0f, b.Height - (size + 2 * pad + digitalH));
                c = new PointF(b.Left + b.Width / 2f, b.Top + slack / 2f + pad + R);
                if (showDigital)
                    digitalArea = new RectangleF(b.Left + pad, c.Y + R + pad * 0.5f, b.Width - 2 * pad, digitalH);
            }

            DrawFace(g, c, R, mode, zone, local.Hour);
            if (mode == DialMode.Twelve) DrawMeridiem(g, c, R, zone, local.Hour, utc.Hour);
            DrawDate(g, c, R, local, mode == DialMode.Dual ? R * 0.33f : R * 0.38f); // pulled in to clear the inner ring

            // UTC hands first (underneath). Seconds are identical in every zone, so UTC gets no second hand.
            bool h24 = Modes.HandsUse24(mode);
            DrawHands(g, c, R, utc, h24, UtcColor, UtcColor, false);
            DrawHands(g, c, R, local, h24, Ink, SecondRed, showSeconds);

            // Center cap
            float cap = R * 0.045f;
            using (SolidBrush b = new SolidBrush(Ink)) g.FillEllipse(b, c.X - cap, c.Y - cap, cap * 2, cap * 2);
            if (showSeconds)
            {
                float cap2 = cap * 0.5f;
                using (SolidBrush b = new SolidBrush(SecondRed)) g.FillEllipse(b, c.X - cap2, c.Y - cap2, cap2 * 2, cap2 * 2);
            }

            if (showDigital && digitalArea.Width > 0)
                DrawDigital(g, digitalArea, local, utc, zone, Modes.ReadoutUse24(mode), showSeconds);
        }

        private static StringFormat Centered()
        {
            StringFormat sf = new StringFormat(StringFormatFlags.NoWrap);
            sf.Alignment = StringAlignment.Center;
            sf.LineAlignment = StringAlignment.Center;
            return sf;
        }

        private static PointF Polar(PointF c, float deg, float r)
        {
            double a = (deg - 90) * Math.PI / 180;
            return new PointF(c.X + (float)(r * Math.Cos(a)), c.Y + (float)(r * Math.Sin(a)));
        }

        // MARK: Face

        private static void DrawFace(Graphics g, PointF c, float R, DialMode mode, string zone, int hour)
        {
            // 12/24 dial: 1-11 swap with 13-23 at noon; the top pair (12 / 24) swaps at 13:00, so the outer
            // ring reads 12 while the hour hand is there (12:00-12:59) and 24 after that.
            bool pm = hour >= 12, topSwap = hour >= 13;
            bool is24 = mode == DialMode.TwentyFour; // the 12/24 dial uses the 12-hour face plus an inner ring
            bool dual = mode == DialMode.Dual;
            using (SolidBrush b = new SolidBrush(FaceFill)) g.FillEllipse(b, c.X - R, c.Y - R, 2 * R, 2 * R);
            using (Pen p = new Pen(Rim, Math.Max(2f, R * 0.035f))) g.DrawEllipse(p, c.X - R, c.Y - R, 2 * R, 2 * R);

            // Minute ticks (60)
            for (int i = 0; i < 60; i++)
            {
                bool five = !is24 && i % 5 == 0; // on the 24h dial, hour marks come from the loop below
                float len = five ? R * 0.09f : R * 0.04f;
                float w = five ? Math.Max(2f, R * 0.018f) : Math.Max(1f, R * 0.007f);
                DrawRadial(g, c, i * 6f, R * 0.94f - len, R * 0.94f, Tick, w);
            }

            if (is24)
            {
                for (int h = 0; h < 24; h++)
                {
                    bool major = h % 6 == 0;
                    float len = major ? R * 0.10f : R * 0.065f;
                    DrawRadial(g, c, h * 15f, R * 0.94f - len, R * 0.94f, major ? Ink : Tick,
                        Math.Max(major ? 2.5f : 1.5f, R * (major ? 0.022f : 0.012f)));
                }
            }

            // Numerals (12/24 dial: slightly smaller and further out to make room for the inner ring)
            int count = is24 ? 24 : 12;
            float fontPx = is24 ? R * 0.105f : (dual ? R * 0.14f : R * 0.16f);
            float rr = is24 ? R * 0.72f : (dual ? R * 0.745f : R * 0.73f);
            using (Font f = new Font("Segoe UI", Math.Max(6f, fontPx), FontStyle.Regular, GraphicsUnit.Pixel))
            using (Font fb = new Font("Segoe UI Semibold", Math.Max(6f, fontPx), FontStyle.Bold, GraphicsUnit.Pixel))
            using (SolidBrush ink = new SolidBrush(Ink))
            using (SolidBrush soft = new SolidBrush(SoftNum))
            using (StringFormat sf = Centered())
            {
                for (int i = 0; i < count; i++)
                {
                    // 12/24 dial after noon: 13-23 take the big outer ring; 24 joins them from 13:00.
                    int label = is24 ? i : (i == 0 ? (dual && topSwap ? 24 : 12) : (dual && pm ? i + 12 : i));
                    string txt = is24 ? label.ToString("00") : label.ToString();
                    bool major = is24 ? i % 6 == 0 : i % 3 == 0;
                    g.DrawString(txt, major ? fb : f, major ? ink : soft, Polar(c, i * 360f / count, rr), sf);
                }
            }

            // 12/24 dial: inner ring, smaller and faded, just inside each main numeral (railway-station style).
            // 13-23 in the morning, 1-11 after noon; 24 on top until 13:00, then 12.
            if (dual)
            {
                using (Font fi = new Font("Segoe UI", Math.Max(6f, R * 0.08f), FontStyle.Regular, GraphicsUnit.Pixel))
                using (SolidBrush faded = new SolidBrush(FadedNum))
                using (StringFormat sf = Centered())
                {
                    for (int i = 0; i < 12; i++)
                    {
                        string txt = (i == 0 ? (topSwap ? 12 : 24) : (pm ? i : i + 12)).ToString();
                        g.DrawString(txt, fi, faded, Polar(c, i * 30f, R * 0.58f), sf);
                    }
                }
            }

            // Legend on the dial
            using (Font f = new Font("Segoe UI Semibold", Math.Max(6f, R * 0.08f), FontStyle.Bold, GraphicsUnit.Pixel))
            using (StringFormat sf = new StringFormat())
            {
                sf.Alignment = StringAlignment.Center;
                using (SolidBrush b = new SolidBrush(Ink))
                    g.DrawString(zone, f, b, c.X, c.Y - R * 0.40f, sf);
                using (SolidBrush b = new SolidBrush(UtcText))
                    g.DrawString("UTC", f, b, c.X, c.Y + R * 0.30f, sf);
            }
        }

        // MARK: AM/PM symbols (12h dial only): sun = AM, crescent moon = PM, just right of the zone and UTC labels.
        // The UTC symbol only appears when UTC is on the other side of noon from local time.

        private static void DrawMeridiem(Graphics g, PointF c, float R, string zone, int localHour, int utcHour)
        {
            bool localPM = localHour >= 12, utcPM = utcHour >= 12;
            using (Font f = new Font("Segoe UI Semibold", Math.Max(6f, R * 0.08f), FontStyle.Bold, GraphicsUnit.Pixel))
            {
                float s = f.Size * 1.15f;                 // symbol box, a little larger than the label font
                float midOff = f.Size * 0.72f;            // label top -> cap-height center (Segoe UI)
                float wZone = g.MeasureString(zone, f).Width;
                SymbolAt(g, new PointF(c.X + wZone / 2 + s * 0.62f, c.Y - R * 0.40f + midOff), s, localPM, Ink);
                if (utcPM != localPM)
                {
                    float wUtc = g.MeasureString("UTC", f).Width;
                    SymbolAt(g, new PointF(c.X + wUtc / 2 + s * 0.62f, c.Y + R * 0.30f + midOff), s, utcPM, UtcText);
                }
            }
        }

        private static void SymbolAt(Graphics g, PointF p, float s, bool moon, Color col)
        {
            if (moon)
            {
                // Crescent: a disc with an offset disc cut out, horns pointing right
                using (GraphicsPath outer = new GraphicsPath())
                using (GraphicsPath cut = new GraphicsPath())
                using (Region rg = new Region())
                using (SolidBrush b = new SolidBrush(col))
                {
                    float r = s * 0.42f, rc = s * 0.36f;
                    outer.AddEllipse(p.X - r, p.Y - r, 2 * r, 2 * r);
                    cut.AddEllipse(p.X - rc + s * 0.22f, p.Y - rc - s * 0.12f, 2 * rc, 2 * rc);
                    rg.MakeEmpty();
                    rg.Union(outer);
                    rg.Exclude(cut);
                    g.FillRegion(b, rg);
                }
            }
            else
            {
                // Sun: small disc with 8 short rays
                float core = s * 0.21f;
                using (SolidBrush b = new SolidBrush(col)) g.FillEllipse(b, p.X - core, p.Y - core, 2 * core, 2 * core);
                using (Pen pen = new Pen(col, Math.Max(1f, s * 0.09f)))
                {
                    pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round;
                    for (int i = 0; i < 8; i++)
                        g.DrawLine(pen, Polar(p, i * 45f, s * 0.33f), Polar(p, i * 45f, s * 0.48f));
                }
            }
        }

        // MARK: Date windows (local date; drawn before the hands so the hands sweep over them)

        private static void DrawDate(Graphics g, PointF c, float R, DateTime local, float off)
        {
            string mon = local.ToString("MMM", System.Globalization.CultureInfo.InvariantCulture).ToUpperInvariant();
            string day = local.ToString("dd");
            using (Font f = new Font("Segoe UI Semibold", Math.Max(6f, R * 0.085f), FontStyle.Bold, GraphicsUnit.Pixel))
            using (SolidBrush b = new SolidBrush(Ink))
            using (StringFormat sf = Centered())
            {
                // Fixed-size windows (sized for "MMM" / "00") so the boxes never change size
                SizeF wMon = g.MeasureString("MMM", f);
                SizeF wDay = g.MeasureString("00", f);
                float h = f.Size * 1.35f, padX = R * 0.025f;
                RectangleF rMon = new RectangleF(c.X - off - wMon.Width / 2 - padX, c.Y - h / 2, wMon.Width + 2 * padX, h);
                RectangleF rDay = new RectangleF(c.X + off - wDay.Width / 2 - padX, c.Y - h / 2, wDay.Width + 2 * padX, h);
                using (Pen pen = new Pen(Ink, Math.Max(1f, R * 0.008f)))
                {
                    g.DrawRectangle(pen, rMon.X, rMon.Y, rMon.Width, rMon.Height);
                    g.DrawRectangle(pen, rDay.X, rDay.Y, rDay.Width, rDay.Height);
                }
                g.DrawString(mon, f, b, rMon, sf);
                g.DrawString(day, f, b, rDay, sf);
            }
        }

        // MARK: Hands

        private static void DrawHands(Graphics g, PointF c, float R, DateTime t, bool is24,
                                      Color handColor, Color secColor, bool showSec)
        {
            double sec = t.Second + t.Millisecond / 1000.0;
            double min = t.Minute + sec / 60.0;
            double hr = t.Hour + min / 60.0;

            float hourAngle = is24 ? (float)(hr * 15.0) : (float)((hr % 12) * 30.0);
            float minAngle = (float)(min * 6.0);

            DrawHand(g, c, hourAngle, R * 0.52f, R * 0.09f, Math.Max(3f, R * 0.055f), handColor);
            // Identical geometry for local and UTC, so the local hand fully covers the UTC one in whole-hour zones.
            DrawHand(g, c, minAngle, R * 0.80f, R * 0.11f, Math.Max(2f, R * 0.034f), handColor);

            if (showSec)
            {
                float sa = (float)(Math.Floor(sec) * 6.0); // ticking second hand
                DrawHand(g, c, sa, R * 0.86f, R * 0.18f, Math.Max(1f, R * 0.012f), secColor);
            }
        }

        private static void DrawHand(Graphics g, PointF c, float angleDeg, float length, float tail, float width, Color col)
        {
            using (Pen p = new Pen(col, width))
            {
                p.StartCap = LineCap.Round;
                p.EndCap = LineCap.Round;
                g.DrawLine(p, Polar(c, angleDeg, -tail), Polar(c, angleDeg, length));
            }
        }

        private static void DrawRadial(Graphics g, PointF c, float angleDeg, float r1, float r2, Color col, float w)
        {
            using (Pen p = new Pen(col, w))
                g.DrawLine(p, Polar(c, angleDeg, r1), Polar(c, angleDeg, r2));
        }

        // MARK: Digital readout

        public static string Fmt(DateTime t, bool is24, bool sec)
        {
            if (is24) return t.ToString(sec ? "HH:mm:ss" : "HH:mm", System.Globalization.CultureInfo.InvariantCulture);
            return t.ToString(sec ? "h:mm:ss tt" : "h:mm tt", System.Globalization.CultureInfo.InvariantCulture);
        }

        private static void DrawDigital(Graphics g, RectangleF area, DateTime local, DateTime utc,
                                        string zone, bool is24, bool sec)
        {
            string dayNote = "";
            int dd = (utc.Date - local.Date).Days;
            if (dd > 0) dayNote = "  +1d"; else if (dd < 0) dayNote = "  -1d";
            string top = zone + "  " + Fmt(local, is24, sec);
            string bot = "UTC  " + Fmt(utc, is24, sec) + dayNote;

            // Size to the area's height, then shrink if either line would overflow its width.
            float px = Math.Max(10f, area.Height * 0.36f);
            using (Font bigM = new Font("Segoe UI Semibold", px, FontStyle.Bold, GraphicsUnit.Pixel))
            using (Font smallM = new Font("Segoe UI", px * 0.78f, FontStyle.Regular, GraphicsUnit.Pixel))
            {
                float widest = Math.Max(g.MeasureString(top, bigM).Width, g.MeasureString(bot, smallM).Width);
                if (widest > area.Width && widest > 0) px = Math.Max(8f, px * area.Width / widest);
            }

            using (Font big = new Font("Segoe UI Semibold", px, FontStyle.Bold, GraphicsUnit.Pixel))
            using (Font small = new Font("Segoe UI", px * 0.78f, FontStyle.Regular, GraphicsUnit.Pixel))
            using (SolidBrush ink = new SolidBrush(Ink))
            using (SolidBrush faded = new SolidBrush(UtcText))
            using (StringFormat sf = Centered())
            {
                RectangleF rt = new RectangleF(area.X, area.Y, area.Width, area.Height * 0.55f);
                RectangleF rb = new RectangleF(area.X, area.Y + area.Height * 0.52f, area.Width, area.Height * 0.45f);
                g.DrawString(top, big, ink, rt, sf);
                g.DrawString(bot, small, faded, rb, sf);
            }
        }

        // MARK: "Two Hands" icon (dark tile, white face, ink + translucent-blue UTC hour hands)
        // Same design as the macOS app/Dock icon. tile = rounded tile with a transparent margin (Windows/macOS);
        // full = edge-to-edge opaque square (iOS and watchOS mask it themselves).

        // Fixed time for the static icon: 10:10:33 local, UTC five hours ahead (blue hand near 3)
        public static readonly DateTime IconUtc = new DateTime(2026, 1, 1, 15, 10, 33, DateTimeKind.Utc);
        public static readonly TimeSpan IconOffset = TimeSpan.FromHours(-5);

        private static GraphicsPath TilePath(float n, float frac)
        {
            // Superellipse ("squircle") tile, like macOS continuous corners
            float a = n * frac / 2f, cx = n / 2f, cy = n / 2f;
            const double e = 5.0;
            PointF[] pts = new PointF[360];
            for (int k = 0; k < 360; k++)
            {
                double t = 2 * Math.PI * k / 360;
                double ct = Math.Cos(t), st = Math.Sin(t);
                float x = cx + a * (float)(Math.Sign(ct) * Math.Pow(Math.Abs(ct), 2 / e));
                float y = cy + a * (float)(Math.Sign(st) * Math.Pow(Math.Abs(st), 2 / e));
                pts[k] = new PointF(x, y);
            }
            GraphicsPath gp = new GraphicsPath();
            gp.AddPolygon(pts);
            return gp;
        }

        public static Bitmap IconBitmap(int n, DateTime utcNow, TimeSpan localOffset, bool tile, bool showSeconds)
        {
            Bitmap bmp = new Bitmap(n, n, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.Clear(Color.Transparent);

                // Background: slate gradient, top lighter
                float R;
                using (LinearGradientBrush grad = new LinearGradientBrush(new PointF(0, -1), new PointF(0, n + 1),
                                                                           Color.FromArgb(52, 58, 70), Color.FromArgb(22, 24, 30)))
                {
                    if (tile)
                    {
                        // Small sizes get a fuller tile so the face stays legible in the taskbar
                        float frac = n <= 48 ? 0.96f : 0.88f;
                        using (GraphicsPath tp = TilePath(n, frac)) g.FillPath(grad, tp);
                        R = n * frac * 0.41f;
                    }
                    else
                    {
                        g.FillRectangle(grad, 0, 0, n, n);
                        R = n * 0.41f;
                    }
                }

                PointF c = new PointF(n / 2f, n / 2f);
                using (SolidBrush face = new SolidBrush(FaceFill)) g.FillEllipse(face, c.X - R, c.Y - R, 2 * R, 2 * R);

                // Hour ticks: bold ink at 12/3/6/9, light gray elsewhere
                for (int i = 0; i < 12; i++)
                {
                    bool major = i % 3 == 0;
                    DrawRadial(g, c, i * 30f, R * (major ? 0.74f : 0.82f), R * 0.92f,
                               major ? Ink : Color.FromArgb(150, 154, 162), Math.Max(1f, R * (major ? 0.075f : 0.04f)));
                }

                // Hands: UTC hour (translucent blue) under local hour + minute (ink), red second on top
                DateTime local = utcNow + localOffset;
                float utcHour = (float)(((utcNow.Hour % 12) + utcNow.Minute / 60.0 + utcNow.Second / 3600.0) * 30);
                float locHour = (float)(((local.Hour % 12) + local.Minute / 60.0 + local.Second / 3600.0) * 30);
                float minA = (float)((local.Minute + local.Second / 60.0) * 6);
                DrawHand(g, c, utcHour, R * 0.52f, R * 0.10f, Math.Max(2f, R * 0.10f), Color.FromArgb(170, 92, 150, 214));
                DrawHand(g, c, locHour, R * 0.50f, R * 0.10f, Math.Max(2f, R * 0.11f), Ink);
                DrawHand(g, c, minA, R * 0.80f, R * 0.12f, Math.Max(1.5f, R * 0.065f), Ink);
                if (showSeconds)
                    DrawHand(g, c, local.Second * 6f, R * 0.86f, R * 0.20f, Math.Max(1f, R * 0.025f), SecondRed);

                float cap = R * 0.07f, cap2 = cap * 0.5f;
                using (SolidBrush b = new SolidBrush(Ink)) g.FillEllipse(b, c.X - cap, c.Y - cap, cap * 2, cap * 2);
                using (SolidBrush b = new SolidBrush(SecondRed)) g.FillEllipse(b, c.X - cap2, c.Y - cap2, cap2 * 2, cap2 * 2);
            }
            return bmp;
        }
    }

    // Writes a multi-size .ico (PNG-compressed entries, supported since Windows Vista).
    internal static class IconWriter
    {
        public static void Write(string path)
        {
            int[] sizes = { 16, 24, 32, 48, 64, 128, 256 };
            List<byte[]> pngs = new List<byte[]>();
            foreach (int s in sizes)
            {
                using (Bitmap bmp = ClockRenderer.IconBitmap(s, ClockRenderer.IconUtc, ClockRenderer.IconOffset, true, s >= 64))
                using (MemoryStream ms = new MemoryStream())
                {
                    bmp.Save(ms, ImageFormat.Png);
                    pngs.Add(ms.ToArray());
                }
            }
            using (FileStream fs = File.Create(path))
            using (BinaryWriter w = new BinaryWriter(fs))
            {
                w.Write((short)0); w.Write((short)1); w.Write((short)sizes.Length);
                int offset = 6 + 16 * sizes.Length;
                for (int i = 0; i < sizes.Length; i++)
                {
                    int s = sizes[i];
                    w.Write((byte)(s >= 256 ? 0 : s)); w.Write((byte)(s >= 256 ? 0 : s));
                    w.Write((byte)0); w.Write((byte)0);
                    w.Write((short)1); w.Write((short)32);
                    w.Write(pngs[i].Length); w.Write(offset);
                    offset += pngs[i].Length;
                }
                foreach (byte[] p in pngs) w.Write(p);
            }
        }
    }
}
