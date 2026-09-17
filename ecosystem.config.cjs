/**
 * PM2 configuration for a binary placed next to this file.
 *
 * Usage:
 *   COPYBOARD_SECRET='replace-with-a-long-secret' \
 *   COPYBOARD_USERS='demo:change-me' \
 *   pm2 start ecosystem.config.cjs
 */
module.exports = {
  apps: [
    {
      name: "copyboard-lite",
      script: "./copyboard-lite",
      cwd: __dirname,
      interpreter: "none",
      exec_mode: "fork",
      autorestart: true,
      watch: false,
      time: true,
      env: {
        COPYBOARD_ADDR: "127.0.0.1:11030",
        COPYBOARD_DB: "./data/copyboard.redb",
        COPYBOARD_SECRET: process.env.COPYBOARD_SECRET || "",
        COPYBOARD_USERS: process.env.COPYBOARD_USERS || "",
      },
    },
  ],
};
