/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  transpilePackages: ["@geo/shared"],
  experimental: {
    typedRoutes: false,
  },
};

export default nextConfig;
