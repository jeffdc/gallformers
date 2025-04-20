import * as fs from 'fs';
import * as path from 'path';
class Logger {
    logDir;
    constructor() {
        this.logDir = path.join(process.cwd(), 'logs');
        this.ensureLogDirectory();
    }
    ensureLogDirectory() {
        if (!fs.existsSync(this.logDir)) {
            fs.mkdirSync(this.logDir, { recursive: true });
        }
    }
    log(level, message, data = {}) {
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
    info(message, data = {}) {
        this.log('INFO', message, data);
    }
    error(message, data = {}) {
        this.log('ERROR', message, data);
    }
    warn(message, data = {}) {
        this.log('WARN', message, data);
    }
}
export default new Logger();
