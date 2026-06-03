import { dirname } from "node:path";
import { fileURLToPath } from "node:url";

const projectRoot = dirname(fileURLToPath(import.meta.url));

/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // This repo is a monorepo with multiple lockfiles (root husky, mcp, web).
  // Pin Turbopack's root to this package so it doesn't infer the repo root.
  turbopack: {
    root: projectRoot,
  },
};

export default nextConfig;
