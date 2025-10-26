export default {
  apps: [{
    name: 'oldies-api',
    script: './dist/server/index.js',
    cwd: '/home/ubuntu/oldies-server',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '500M',
    env: {
      NODE_ENV: 'production',
      PORT: 5000,
      DATABASE_URL: 'postgresql://neondb_owner:npg_D25sTdkbJxjf@ep-young-voice-ady0hrfd-pooler.c-2.us-east-1.aws.neon.tech/neondb?sslmode=require'
    },
    error_file: './logs/err.log',
    out_file: './logs/out.log',
    log_file: './logs/combined.log',
    time: true
  }]
};
