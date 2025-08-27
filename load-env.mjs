import { readFileSync, existsSync } from 'fs';
import { join } from 'path';

/**
 * Load environment variables from env/ directory in the correct order
 * Mimics the Python env loader behavior for Next.js
 */
export function loadEnvFiles() {
    const rootDir = process.cwd();
    const envDir = join(rootDir, 'env');
    
    // Get NODE_ENV, default to development
    const nodeEnv = process.env.NODE_ENV || 'development';
    
    // Files to load in order (later files override earlier ones)
    const envFiles = [
        join(envDir, '.env.shared'),
        join(envDir, `.env.${nodeEnv}`),
        join(envDir, '.env.local')
    ];
    
    const envVars = {};
    
    for (const filePath of envFiles) {
        if (existsSync(filePath)) {
            console.log(`Loading env from: ${filePath}`);
            const content = readFileSync(filePath, 'utf8');
            
            // Parse .env file content
            const lines = content.split('\n');
            for (const line of lines) {
                // Skip empty lines and comments
                if (!line.trim() || line.trim().startsWith('#')) {
                    continue;
                }
                
                // Parse KEY=VALUE format
                const equalIndex = line.indexOf('=');
                if (equalIndex > 0) {
                    const key = line.slice(0, equalIndex).trim();
                    let value = line.slice(equalIndex + 1).trim();
                    
                    // Remove quotes if present
                    if ((value.startsWith('"') && value.endsWith('"')) || 
                        (value.startsWith("'") && value.endsWith("'"))) {
                        value = value.slice(1, -1);
                    }
                    
                    envVars[key] = value;
                }
            }
        } else {
            console.log(`Env file not found (skipping): ${filePath}`);
        }
    }
    
    // Expand environment variable references (like $PWD)
    for (const [key, value] of Object.entries(envVars)) {
        if (typeof value === 'string' && value.includes('$')) {
            // Simple variable expansion - replace $VAR with process.env.VAR or envVars[VAR]
            let expandedValue = value;
            const matches = value.match(/\$(\w+)/g);
            if (matches) {
                for (const match of matches) {
                    const varName = match.slice(1); // Remove $
                    const replacement = process.env[varName] || envVars[varName] || '';
                    expandedValue = expandedValue.replace(match, replacement);
                }
                envVars[key] = expandedValue;
            }
        }
    }
    
    // Set environment variables
    for (const [key, value] of Object.entries(envVars)) {
        // Only set if not already set (allows override from actual env vars)
        if (!process.env[key]) {
            process.env[key] = value;
        }
    }
    
    console.log(`Loaded ${Object.keys(envVars).length} environment variables from env/ directory`);
    
    return envVars;
}