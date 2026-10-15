// DualClock v1.5 - Analog clock showing Local (primary) and UTC (secondary) time.
// v1.3: UTC hands share the local hands' exact geometry (only color differs), so they are fully
//       hidden under the local hands wherever the times coincide. Local zone label on dial.
// v1.4: Local date on the dial - month (left of center) and 2-digit day (right of center).
// v1.5: Month and day framed in thin black date windows.
//       Launch with /12 or /24 to open a dedicated 12- or 24-hour clock (separate saved settings).
// Written in C# 5 so it compiles with the csc.exe that ships with Windows (.NET Framework 4.x).
//
// Controls:
//   Right-click .......... menu (12/24-hour dial, always on top, seconds, digital readout, exit)
//   T ..................... toggle 12h / 24h
//   Double-click .......... toggle always on top
//   Esc ................... exit
//   DualClock.exe /12 ..... dedicated 12-hour clock;  DualClock.exe /24 ..... dedicated 24-hour clock

using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;
using System.Windows.Forms;

namespace DualClock
{
    internal static class Program
    {
        [STAThread]
        private static void Main(string[] args)
        {
            // Hidden test hook: DualClock.exe --render out.png [12|24]
            if (args.Length >= 2 && args[0] == "--render")
            {
                bool is24 = args.Length >= 3 && args[2] == "24";
                using (Bitmap bmp = new Bitmap(420, 520))
                using (Graphics g = Graphics.FromImage(bmp))
                {
                    DateTime utc = new DateTime(2026, 10, 15, 15, 28, 42, DateTimeKind.Utc);
                    DateTime local = utc.AddHours(-4);
                    ClockRenderer.Draw(g, new Rectangle(0, 0, 420, 520), local, utc, "EDT", is24, true, true);
                    bmp.Save(args[1], System.Drawing.Imaging.ImageFormat.Png);
                }
                return;
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            int forced = 0;
            foreach (string a in args)
            {
                string x = a.TrimStart('/', '-');
                if (x == "12") forced = 12; else if (x == "24") forced = 24;
            }
            if (forced != 0) Settings.Suffix = "-" + forced;
            Application.Run(new ClockForm(forced));
        }
    }

    internal sealed class Settings
    {
        public bool Use24Hour = false;
        public bool TopMost = false;
        public bool ShowSeconds = true;
        public bool ShowDigital = true;
        public int X = -1, Y = -1, W = 380, H = 470;

        public static string Suffix = "";

        private static string FilePath
        {
            get
            {
                string dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DualClock");
                return Path.Combine(dir, "settings" + Suffix + ".ini");
            }
        }

        public static Settings Load()
        {
            Settings s = new Settings();
            try
            {
                if (!File.Exists(FilePath)) return s;
                foreach (string line in File.ReadAllLines(FilePath))
                {
                    string[] kv = line.Split('=');
                    if (kv.Length != 2) continue;
                    string k = kv[0].Trim(), v = kv[1].Trim();
                    int n;
                    switch (k)
                    {
                        case "Use24Hour": s.Use24Hour = v == "1"; break;
                        case "TopMost": s.TopMost = v == "1"; break;
                        case "ShowSeconds": s.ShowSeconds = v == "1"; break;
                        case "ShowDigital": s.ShowDigital = v == "1"; break;
                        case "X": if (int.TryParse(v, out n)) s.X = n; break;
                        case "Y": if (int.TryParse(v, out n)) s.Y = n; break;
                        case "W": if (int.TryParse(v, out n)) s.W = n; break;
                        case "H": if (int.TryParse(v, out n)) s.H = n; break;
                    }
                }
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
                    "Use24Hour=" + (Use24Hour ? "1" : "0"),
                    "TopMost=" + (TopMost ? "1" : "0"),
                    "ShowSeconds=" + (ShowSeconds ? "1" : "0"),
                    "ShowDigital=" + (ShowDigital ? "1" : "0"),
                    "X=" + X, "Y=" + Y, "W=" + W, "H=" + H
                });
            }
            catch { }
        }
    }

    internal sealed class ClockForm : Form
    {
        private readonly Settings _s;
        private readonly Timer _timer;
        private ToolStripMenuItem _mi12, _mi24, _miTop, _miSec, _miDig;

        public ClockForm(int forced)
        {
            _s = Settings.Load();
            if (forced == 12) _s.Use24Hour = false;
            if (forced == 24) _s.Use24Hour = true;

            Text = "Dual Clock - Local / UTC";
            BackColor = ClockRenderer.Background;
            DoubleBuffered = true;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint |
                     ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            MinimumSize = new Size(220, 260);
            KeyPreview = true;

            StartPosition = FormStartPosition.Manual;
            Size = new Size(_s.W, _s.H);
            Rectangle wa = Screen.PrimaryScreen.WorkingArea;
            Point p = new Point(_s.X, _s.Y);
            bool onScreen = false;
            foreach (Screen sc in Screen.AllScreens)
                if (sc.WorkingArea.Contains(new Point(p.X + 40, p.Y + 20))) onScreen = true;
            int shift = forced == 24 ? Width + 10 : 0; // first run: place the 24h clock beside the 12h one
            Location = onScreen ? p : new Point(wa.Right - Width - 20 - shift, wa.Top + 20);
            TopMost = _s.TopMost;

            BuildMenu();

            _timer = new Timer();
            _timer.Interval = 200;
            _timer.Tick += delegate { Invalidate(); };
            _timer.Start();

            KeyDown += OnKey;
            DoubleClick += delegate { SetTopMost(!TopMost); };
            FormClosing += delegate
            {
                if (WindowState == FormWindowState.Normal)
                {
                    _s.X = Left; _s.Y = Top; _s.W = Width; _s.H = Height;
                }
                _s.Save();
            };
        }

        private void BuildMenu()
        {
            ContextMenuStrip m = new ContextMenuStrip();
            _mi12 = new ToolStripMenuItem("12-hour dial", null, delegate { SetFormat(false); });
            _mi24 = new ToolStripMenuItem("24-hour dial", null, delegate { SetFormat(true); });
            _miTop = new ToolStripMenuItem("Always on top", null, delegate { SetTopMost(!TopMost); });
            _miSec = new ToolStripMenuItem("Show second hand", null, delegate { _s.ShowSeconds = !_s.ShowSeconds; Sync(); });
            _miDig = new ToolStripMenuItem("Show digital readout", null, delegate { _s.ShowDigital = !_s.ShowDigital; Sync(); });
            m.Items.Add(_mi12);
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
            _mi12.Checked = !_s.Use24Hour;
            _mi24.Checked = _s.Use24Hour;
            _miTop.Checked = TopMost;
            _miSec.Checked = _s.ShowSeconds;
            _miDig.Checked = _s.ShowDigital;
            _s.TopMost = TopMost;
            _s.Save();
            Invalidate();
        }

        private void SetFormat(bool is24) { _s.Use24Hour = is24; Sync(); }
        private void SetTopMost(bool on) { TopMost = on; Sync(); }

        private void OnKey(object sender, KeyEventArgs e)
        {
            if (e.KeyCode == Keys.T) SetFormat(!_s.Use24Hour);
            else if (e.KeyCode == Keys.Escape) Close();
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            DateTime utc = DateTime.UtcNow;
            DateTime local = utc.ToLocalTime();
            ClockRenderer.Draw(e.Graphics, ClientRectangle, local, utc,
                ClockRenderer.ZoneAbbrev(local), _s.Use24Hour, _s.ShowSeconds, _s.ShowDigital);
        }
    }

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

        public static void Draw(Graphics g, Rectangle bounds, DateTime local, DateTime utc,
                                string zone, bool is24, bool showSeconds, bool showDigital)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            g.Clear(Background);

            int digitalH = showDigital ? Math.Max(54, bounds.Height / 7) : 0;
            int pad = Math.Max(10, Math.Min(bounds.Width, bounds.Height) / 30);
            int size = Math.Min(bounds.Width - 2 * pad, bounds.Height - digitalH - 2 * pad);
            if (size < 50) return;
            float R = size / 2f;
            PointF c = new PointF(bounds.Left + bounds.Width / 2f, bounds.Top + pad + R);

            DrawFace(g, c, R, is24, zone);
            DrawDate(g, c, R, local);

            // UTC hands first (underneath). Seconds are identical in every zone, so UTC gets no second hand.
            DrawHands(g, c, R, utc, is24, UtcColor, UtcColor, false, 1f);
            DrawHands(g, c, R, local, is24, Ink, SecondRed, showSeconds, 1f);

            // Center cap
            float cap = R * 0.045f;
            using (SolidBrush b = new SolidBrush(Ink)) g.FillEllipse(b, c.X - cap, c.Y - cap, cap * 2, cap * 2);
            if (showSeconds)
            {
                float cap2 = cap * 0.5f;
                using (SolidBrush b = new SolidBrush(SecondRed)) g.FillEllipse(b, c.X - cap2, c.Y - cap2, cap2 * 2, cap2 * 2);
            }

            if (showDigital)
            {
                RectangleF area = new RectangleF(bounds.Left, c.Y + R + pad * 0.5f, bounds.Width, digitalH);
                DrawDigital(g, area, local, utc, zone, is24, showSeconds);
            }
        }

        private static void DrawFace(Graphics g, PointF c, float R, bool is24, string zone)
        {
            using (SolidBrush b = new SolidBrush(FaceFill)) g.FillEllipse(b, c.X - R, c.Y - R, 2 * R, 2 * R);
            using (Pen p = new Pen(Rim, Math.Max(2f, R * 0.035f))) g.DrawEllipse(p, c.X - R, c.Y - R, 2 * R, 2 * R);

            // Minute ticks (60) - same on both dials
            for (int i = 0; i < 60; i++)
            {
                bool five = i % 5 == 0;
                if (is24) five = false; // on 24h dial, hour marks come from the hour loop below
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

            // Numerals
            int count = is24 ? 24 : 12;
            float fontPx = is24 ? R * 0.105f : R * 0.16f;
            using (Font f = new Font("Segoe UI", Math.Max(6f, fontPx), FontStyle.Regular, GraphicsUnit.Pixel))
            using (Font fb = new Font("Segoe UI Semibold", Math.Max(6f, fontPx), FontStyle.Bold, GraphicsUnit.Pixel))
            using (SolidBrush ink = new SolidBrush(Ink))
            using (SolidBrush soft = new SolidBrush(Color.FromArgb(90, 94, 102)))
            using (StringFormat sf = new StringFormat())
            {
                sf.Alignment = StringAlignment.Center;
                sf.LineAlignment = StringAlignment.Center;
                float rr = is24 ? R * 0.72f : R * 0.73f;
                for (int i = 0; i < count; i++)
                {
                    int label = is24 ? i : (i == 0 ? 12 : i);
                    string txt = is24 ? label.ToString("00") : label.ToString();
                    double a = (i * 360.0 / count - 90) * Math.PI / 180;
                    PointF pt = new PointF(c.X + (float)(rr * Math.Cos(a)), c.Y + (float)(rr * Math.Sin(a)));
                    bool major = is24 ? i % 6 == 0 : i % 3 == 0;
                    g.DrawString(txt, major ? fb : f, major ? ink : soft, pt, sf);
                }
            }

            // Small legend on the dial
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

        private static void DrawDate(Graphics g, PointF c, float R, DateTime local)
        {
            string mon = local.ToString("MMM", System.Globalization.CultureInfo.InvariantCulture).ToUpperInvariant();
            string day = local.ToString("dd");
            float off = R * 0.38f; // roughly halfway between center and the numerals
            using (Font f = new Font("Segoe UI Semibold", Math.Max(6f, R * 0.085f), FontStyle.Bold, GraphicsUnit.Pixel))
            using (SolidBrush b = new SolidBrush(Ink))
            using (StringFormat sf = new StringFormat())
            {
                sf.Alignment = StringAlignment.Center;
                sf.LineAlignment = StringAlignment.Center;
                // Fixed-size windows (sized for the widest month) so the boxes never change size
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

        private static void DrawHands(Graphics g, PointF c, float R, DateTime t, bool is24,
                                      Color handColor, Color secColor, bool showSec, float widthScale)
        {
            double sec = t.Second + t.Millisecond / 1000.0;
            double min = t.Minute + sec / 60.0;
            double hr = t.Hour + min / 60.0;

            float hourAngle = is24 ? (float)(hr * 15.0) : (float)((hr % 12) * 30.0);
            float minAngle = (float)(min * 6.0);

            DrawHand(g, c, hourAngle, R * 0.52f, R * 0.09f, Math.Max(3f, R * 0.055f * widthScale), handColor);
            // Minute hand: identical geometry for local and UTC so the local hand fully covers the UTC one
            // whenever the offset is a whole number of hours.
            DrawHand(g, c, minAngle, R * 0.80f, R * 0.11f, Math.Max(2f, R * 0.034f), handColor);

            if (showSec)
            {
                float sa = (float)(Math.Floor(sec) * 6.0); // ticking second hand
                DrawHand(g, c, sa, R * 0.86f, R * 0.18f, Math.Max(1f, R * 0.012f), secColor);
            }
        }

        private static void DrawHand(Graphics g, PointF c, float angleDeg, float length, float tail, float width, Color col)
        {
            double a = (angleDeg - 90) * Math.PI / 180;
            PointF tip = new PointF(c.X + (float)(length * Math.Cos(a)), c.Y + (float)(length * Math.Sin(a)));
            PointF back = new PointF(c.X - (float)(tail * Math.Cos(a)), c.Y - (float)(tail * Math.Sin(a)));
            using (Pen p = new Pen(col, width))
            {
                p.StartCap = LineCap.Round;
                p.EndCap = LineCap.Round;
                g.DrawLine(p, back, tip);
            }
        }

        private static void DrawRadial(Graphics g, PointF c, float angleDeg, float r1, float r2, Color col, float w)
        {
            double a = (angleDeg - 90) * Math.PI / 180;
            float cs = (float)Math.Cos(a), sn = (float)Math.Sin(a);
            using (Pen p = new Pen(col, w))
                g.DrawLine(p, c.X + r1 * cs, c.Y + r1 * sn, c.X + r2 * cs, c.Y + r2 * sn);
        }

        private static string Fmt(DateTime t, bool is24, bool sec)
        {
            if (is24) return t.ToString(sec ? "HH:mm:ss" : "HH:mm");
            return t.ToString(sec ? "h:mm:ss tt" : "h:mm tt", System.Globalization.CultureInfo.InvariantCulture);
        }

        private static void DrawDigital(Graphics g, RectangleF area, DateTime local, DateTime utc,
                                        string zone, bool is24, bool sec)
        {
            float px = Math.Max(10f, area.Height * 0.36f);
            string dayNote = "";
            int dd = (utc.Date - local.Date).Days;
            if (dd > 0) dayNote = "  +1d"; else if (dd < 0) dayNote = "  -1d";

            using (Font big = new Font("Segoe UI Semibold", px, FontStyle.Bold, GraphicsUnit.Pixel))
            using (Font small = new Font("Segoe UI", px * 0.78f, FontStyle.Regular, GraphicsUnit.Pixel))
            using (SolidBrush ink = new SolidBrush(Ink))
            using (SolidBrush faded = new SolidBrush(UtcText))
            using (StringFormat sf = new StringFormat())
            {
                sf.Alignment = StringAlignment.Center;
                sf.LineAlignment = StringAlignment.Center;
                RectangleF top = new RectangleF(area.X, area.Y, area.Width, area.Height * 0.55f);
                RectangleF bot = new RectangleF(area.X, area.Y + area.Height * 0.52f, area.Width, area.Height * 0.45f);
                g.DrawString(zone + "  " + Fmt(local, is24, sec), big, ink, top, sf);
                g.DrawString("UTC  " + Fmt(utc, is24, sec) + dayNote, small, faded, bot, sf);
            }
        }
    }
}
