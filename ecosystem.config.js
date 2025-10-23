module.exports = {
  apps: [
    {
      name: "m2-web",
      cwd: process.cwd(),
      script: "bash",
      interpreter: "/bin/bash",
      args: [
        "-lc",
        // Preflight sjekker env (MAGENTO_*) og gjør en lett health-ping
        'source tools/preflight-env.sh; PORT=${PORT:-3100}; tools/next20 start -p ${PORT}'
      ],
      env: {
        NODE_ENV: "production"
      },
      env_production: {
        NODE_ENV: "production"
      },
      out_file: "logs/prod.out.log",
      error_file: "logs/prod.err.log",
      merge_logs: true,
      max_restarts: 10,
      autorestart: true,
      watch: false
    }
  ]
}
