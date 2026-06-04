import { dirname } from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = dirname(fileURLToPath(import.meta.url));

/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // Fully static marketing site (no API routes, no server components needing a
  // runtime). Export to plain HTML/CSS/JS so Netlify can serve it as static
  // files — no Next.js runtime/adapter required.
  output: "export",
  images: { unoptimized: true },
  // This repo is a monorepo with multiple lockfiles (root husky, mcp, web).
  // Pin Turbopack's root to this package so it doesn't infer the repo root.
  turbopack: {
    root: projectRoot,
  },
};

export default nextConfig;
