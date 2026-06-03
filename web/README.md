# gunk-web

The marketing site for **gunk** — _reinventing the trash can._

A single-page, minimalist landing page built with **Next.js (App Router) +
TypeScript**. Ported from the original `gunk.html` Claude-designed prototype.

## Develop

```bash
cd web
npm install
npm run dev      # http://localhost:3000
```

## Scripts

| Script          | What it does                          |
| --------------- | ------------------------------------- |
| `npm run dev`   | Start the dev server (hot reload).    |
| `npm run build` | Production build.                     |
| `npm run start` | Serve the production build.           |
| `npm run lint`  | ESLint for the web package.           |

## Structure

```
web/
├── app/
│   ├── layout.tsx     # metadata + pre-paint theme/intro script + globals
│   ├── page.tsx       # composes the one page
│   └── globals.css    # all styling (design tokens, light/dark, animations)
└── components/
    ├── Intro.tsx        # one-time trash-can intro overlay        (client)
    ├── SiteHeader.tsx   # sticky header + dark-mode toggle         (client)
    ├── SignupForm.tsx   # email capture (placeholder)             (client)
    ├── ScrollReveal.tsx # reveal-on-scroll enhancement            (client)
    ├── Hero.tsx
    ├── Problem.tsx
    ├── HowItWorks.tsx
    ├── WowMoment.tsx
    └── SiteFooter.tsx
```

## Things to wire before shipping

- **Email signup** is a placeholder. In `components/SignupForm.tsx`, point the
  form `action` at a real endpoint (Buttondown, ConvertKit, your own
  `/subscribe`) and remove the `preventDefault` in `onSubmit`.
- **GitHub links** point to `https://github.com`. Swap in the real repo URL in
  `SiteHeader.tsx` and `SiteFooter.tsx`.

## Notes

- Theme (light/dark) and whether the intro plays are decided **before paint**
  by a tiny inline script in `app/layout.tsx`, so there's no flash. State is
  stored in `localStorage` (`gunk-theme`) and `sessionStorage` (`gunk-intro`).
- Fully responsive, accessible (semantic HTML, focus states, reduced-motion
  support), and dependency-free beyond Next/React.
