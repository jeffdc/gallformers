"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const dotenv_1 = __importDefault(require("dotenv"));
class EnvLoader {
    constructor() {
        this.env = process.env.NODE_ENV || 'development';
        this.loadedVars = new Set();
    }
    load() {
        // Load shared environment variables first
        this.loadFile('.env.shared');
        // Load environment-specific variables
        this.loadFile(`.env.${this.env}`);
        // Load local overrides last
        if (fs_1.default.existsSync('.env.local')) {
            this.loadFile('.env.local');
        }
        this.validateRequired();
    }
    loadFile(filename) {
        const filePath = path_1.default.resolve(process.cwd(), filename);
        console.debug(`Attempting to load ${filename} from ${filePath}`);
        if (fs_1.default.existsSync(filePath)) {
            console.debug(`Found ${filename}`);
            const envConfig = dotenv_1.default.parse(fs_1.default.readFileSync(filePath));
            Object.entries(envConfig).forEach(([key, value]) => {
                // Only consider a variable as loaded if it has a non-empty value
                if (!this.loadedVars.has(key) || !process.env[key]) {
                    process.env[key] = value;
                    if (value) {
                        // Only mark as loaded if the value is non-empty
                        this.loadedVars.add(key);
                        console.debug(`Loaded ${key} = ${value.substring(0, 3)}...`);
                    }
                }
                else {
                    console.debug(`Skipped ${key} (already loaded with non-empty value)`);
                }
            });
        }
        else {
            console.debug(`File ${filename} not found`);
        }
    }
    validateRequired() {
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
exports.default = new EnvLoader();
