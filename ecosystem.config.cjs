module.exports = {
  apps: [{
    name: 'm2-web',
    cwd: '/Users/litebrygg/Documents/M2',
    script: 'tools/start-prod.sh',
    interpreter: '/bin/bash',
    env: { NODE_ENV: 'production', PORT: 3100, HOST: '0.0.0.0' }
  }]
}
