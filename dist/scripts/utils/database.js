import * as fs from 'fs';
import * as path from 'path';
import { exec } from 'child_process';
import { promisify } from 'util';
const execAsync = promisify(exec);
class Database {
    dbPath;
    constructor() {
        this.dbPath = path.join(process.cwd(), 'gallformers.sqlite');
    }
    async backup(backupPath) {
        if (!fs.existsSync(this.dbPath)) {
            throw new Error('Database file not found');
        }
        // Create backup directory if it doesn't exist
        const backupDir = path.dirname(backupPath);
        if (!fs.existsSync(backupDir)) {
            fs.mkdirSync(backupDir, { recursive: true });
        }
        // Copy database file
        fs.copyFileSync(this.dbPath, backupPath);
        // Verify backup
        await this.verifyBackup(backupPath);
        return backupPath;
    }
    async restore(backupPath) {
        if (!fs.existsSync(backupPath)) {
            throw new Error('Backup file not found');
        }
        // Verify backup before restoring
        await this.verifyBackup(backupPath);
        // Stop any running processes that might be using the database
        await this.stopProcesses();
        // Restore database
        fs.copyFileSync(backupPath, this.dbPath);
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
export default new Database();
