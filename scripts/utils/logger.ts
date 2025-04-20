import * as fs from 'fs';
import * as path from 'path';

interface LogData {
    [key: string]: any;
}

class Logger {
    private logDir: string;

    constructor() {
        this.logDir = path.join(process.cwd(), 'logs');
        this.ensureLogDirectory();
    }

    private ensureLogDirectory(): void {
        if (!fs.existsSync(this.logDir)) {
            fs.mkdirSync(this.logDir, { recursive: true });
        }
    }

    private log(level: string, message: string, data: LogData = {}): void {
        const timestamp = new Date().toISOString();
        const logEntry = {
            timestamp,
            level,
            message,
            ...data,
        };

        // Console output
        console.log(JSON.stringify(logEntry));

        // File output
        const logFile = path.join(this.logDir, `${level}.log`);
        fs.appendFileSync(logFile, JSON.stringify(logEntry) + '\n');
    }

    info(message: string, data: LogData = {}): void {
        this.log('INFO', message, data);
    }

    error(message: string, data: LogData = {}): void {
        this.log('ERROR', message, data);
    }

    warn(message: string, data: LogData = {}): void {
        this.log('WARN', message, data);
    }
}

export default new Logger();
