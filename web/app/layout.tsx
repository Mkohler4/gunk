import type { Metadata, Viewport } from "next";
import "./globals.css";

const FAVICON =
  "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Ctext y='26' font-size='26'%3E%F0%9F%97%91%EF%B8%8F%3C/text%3E%3C/svg%3E";

export const metadata: Metadata = {
  title: "gunk — reinventing the trash can",
  description:
    "gunk turns your dead side projects into context your AI actually uses.",
  icons: { icon: FAVICON },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
};

// Runs before paint: sets the theme and decides whether the intro plays,
// so there is no flash of the wrong theme or a stale intro overlay.
const PREPAINT = `(function(){
  var r = document.documentElement;
  try {
    var t = localStorage.getItem('gunk-theme');
    var d = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches;
    r.setAttribute('data-theme', t || (d ? 'dark' : 'light'));
  } catch (e) { r.setAttribute('data-theme', 'light'); }
  try {
    var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    var seen = sessionStorage.getItem('gunk-intro') === '1';
    r.setAttribute('data-intro', (seen || reduce) ? 'skip' : 'play');
  } catch (e) { r.setAttribute('data-intro', 'skip'); }
})();`;

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: PREPAINT }} />
        <noscript>
          {/* Without JS the intro never animates away — keep it hidden. */}
          <style>{`.intro{display:none !important;} html{overflow:auto !important;}`}</style>
        </noscript>
      </head>
      <body>{children}</body>
    </html>
  );
}
