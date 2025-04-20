export default {
    apps: [
        {
            name: 'gallformers',
            script: 'yarn',
            args: 'start',
            env: {
                NODE_ENV: 'production',
                PORT: 3000,
                DATABASE_URL: 'file:./gallformers.sqlite',
                API_URL: 'https://www.gallformers.org',
                NEXTAUTH_URL: 'https://www.gallformers.org',
                AWS_REGION: 'us-east-2',
            },
            max_memory_restart: '1G',
            autorestart: true,
            watch: false,
            log_date_format: 'YYYY-MM-DD HH:mm:ss',
            error_file: 'logs/error.log',
            out_file: 'logs/out.log',
            merge_logs: true,
            instances: 1,
            exec_mode: 'fork',
        },
    ],
};
