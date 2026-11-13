import type { NextConfig } from "next";

const config: NextConfig = {
  output: "export",
  trailingSlash: false,
  images: { unoptimized: true },
  env: { NEXT_PUBLIC_TRIAL_DAYS: process.env.TRIAL_DAYS ?? "" },
};

export default config;
