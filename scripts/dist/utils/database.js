"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const child_process_1 = require("child_process");
const util_1 = require("util");
const execAsync = (0, util_1.promisify)(child_process_1.exec);
class Database {
    constructor() {
        this.dbPath = path_1.default.join(process.cwd(), 'gallformers.sqlite');
    }
    async backup(backupPath) {
        if (!fs_1.default.existsSync(this.dbPath)) {
            throw new Error('Database file not found');
        }
        // Create backup directory if it doesn't exist
        const backupDir = path_1.default.dirname(backupPath);
        if (!fs_1.default.existsSync(backupDir)) {
            fs_1.default.mkdirSync(backupDir, { recursive: true });
        }
        // Copy database file
        fs_1.default.copyFileSync(this.dbPath, backupPath);
        // Verify backup
        await this.verifyBackup(backupPath);
        return backupPath;
    }
    async restore(backupPath) {
        if (!fs_1.default.existsSync(backupPath)) {
            throw new Error('Backup file not found');
        }
        // Verify backup before restoring
        await this.verifyBackup(backupPath);
        // Stop any running processes that might be using the database
        await this.stopProcesses();
        // Restore database
        fs_1.default.copyFileSync(backupPath, this.dbPath);
        // Verify restored database
        await this.verifyBackup(this.dbPath);
    }
    async verifyBackup(dbPath) {
        try {
            const { stdout } = await execAsync(`sqlite3 "${dbPath}" "PRAGMA integrity_check;"`);
            if (stdout.trim() !== 'ok') {
                throw new Error(`Database integrity check failed: ${stdout}`);
            }
        }
        catch (error) {
            if (error instanceof Error) {
                throw new Error(`Failed to verify database: ${error.message}`);
            }
            else {
                throw new Error('Failed to verify database: Unknown error');
            }
        }
    }
    async stopProcesses() {
        try {
            // Stop PM2 processes if running
            await execAsync('pm2 stop all || true');
        }
        catch {
            // Ignore errors if PM2 is not installed or no processes are running
        }
    }
}
exports.default = new Database();
