"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
class Logger {
    constructor() {
        this.logDir = path_1.default.join(process.cwd(), 'logs');
        this.ensureLogDirectory();
    }
    ensureLogDirectory() {
        if (!fs_1.default.existsSync(this.logDir)) {
            fs_1.default.mkdirSync(this.logDir, { recursive: true });
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
        const logFile = path_1.default.join(this.logDir, `${level}.log`);
        fs_1.default.appendFileSync(logFile, JSON.stringify(logEntry) + '\n');
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
exports.default = new Logger();
