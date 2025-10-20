/** @type {import('next').NextConfig} */
const config = {
  reactStrictMode: true,
  experimental: { reactCompiler: true },
  // Tving nytt build-katalognavn for å slippe gamle .next-manifester
  distDir: '.next-dev',
  webpack: (cfg, { dev }) => {
    if (dev) cfg.cache = false; // slå AV cache i dev
    return cfg;
  },
};
export default config;
