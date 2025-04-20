import * as fs from 'fs';
import * as path from 'path';
import * as dotenv from 'dotenv';

class EnvLoader {
    private env: string;
    private loadedVars: Set<string>;

    constructor() {
        this.env = process.env.NODE_ENV || 'development';
        this.loadedVars = new Set();
    }

    load(): void {
        // Load shared environment variables first
        this.loadFile('.env.shared');

        // Load environment-specific variables
        this.loadFile(`.env.${this.env}`);

        // Load local overrides last
        if (fs.existsSync('.env.local')) {
            this.loadFile('.env.local');
        }

        this.validateRequired();
    }

    private loadFile(filename: string): void {
        const filePath = path.resolve(process.cwd(), filename);
        console.debug(`Attempting to load ${filename} from ${filePath}`);
        if (fs.existsSync(filePath)) {
            console.debug(`Found ${filename}`);
            const envConfig = dotenv.parse(fs.readFileSync(filePath));
            Object.entries(envConfig).forEach(([key, value]) => {
                // Only consider a variable as loaded if it has a non-empty value
                if (!this.loadedVars.has(key) || !process.env[key]) {
                    process.env[key] = value;
                    if (value) {
                        // Only mark as loaded if the value is non-empty
                        this.loadedVars.add(key);
                        console.debug(`Loaded ${key} = ${value.substring(0, 3)}...`);
                    }
                } else {
                    console.debug(`Skipped ${key} (already loaded with non-empty value)`);
                }
            });
        } else {
            console.debug(`File ${filename} not found`);
        }
    }

    private validateRequired(): void {
        const required = [
            'DATABASE_URL',
            'AWS_REGION',
            'AWS_ACCESS_KEY_ID',
            'AWS_SECRET_ACCESS_KEY',
            'S3_BUCKET',
            'S3_PUT_AWS_ACCESS_KEY_ID',
            'S3_PUT_AWS_SECRET_ACCESS_KEY',
            'S3_BACKUP_PATH',
            'EMAIL_TO',
            'AUTH0_CLIENT_ID',
            'AUTH0_SECRET',
            'AUTH0_DOMAIN',
            'NEXTAUTH_SECRET',
            'SECRET',
            'MONITOR_EMAIL',
            'APP_PATH',
            'BACKUP_PATH',
            'LOG_PATH',
            'DB_PATH',
        ];

        const missing = required.filter((key) => !process.env[key]);
        if (missing.length > 0) {
            throw new Error(`Missing required environment variables: ${missing.join(', ')}`);
        }
    }
}

export default new EnvLoader();
