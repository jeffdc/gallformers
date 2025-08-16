import { readFileSync, readdirSync, statSync } from 'fs';
import { join, relative, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = join(__filename, '..');

const EXTENSIONS = ['.ts', '.tsx'];
const IMPORT_REGEX = /import\s+(?:{[^}]*}|\*\s+as\s+\w+|\w+)\s+from\s+['"]([^'"]+)['"]/g;

function findFiles(dir, fileList = []) {
    const files = readdirSync(dir);
    
    files.forEach(file => {
        const filePath = join(dir, file);
        const stat = statSync(filePath);
        
        if (stat.isDirectory() && !filePath.includes('node_modules') && !filePath.includes('.git')) {
            findFiles(filePath, fileList);
        } else if (EXTENSIONS.includes(file.slice(-3)) || EXTENSIONS.includes(file.slice(-4))) {
            fileList.push(filePath);
        }
    });
    
    return fileList;
}

function resolveImportPath(importPath, filePath) {
    if (importPath.startsWith('@/')) {
        // Handle @/ alias imports
        return join(process.cwd(), importPath.slice(2));
    } else if (importPath.startsWith('.')) {
        // Handle relative imports
        return join(dirname(filePath), importPath);
    }
    return null;
}

function checkPathCaseSensitivity(path) {
    const parts = path.split('/');
    let currentPath = process.cwd();
    
    for (const part of parts) {
        if (!part) continue;
        
        try {
            const entries = readdirSync(currentPath);
            const matchingEntry = entries.find(entry => entry.toLowerCase() === part.toLowerCase());
            
            if (matchingEntry && matchingEntry !== part) {
                return {
                    expected: part,
                    actual: matchingEntry
                };
            }
            
            currentPath = join(currentPath, matchingEntry || part);
        } catch (error) {
            // If we can't read the directory, the path doesn't exist
            return null;
        }
    }
    
    return null;
}

function checkImports(filePath) {
    const content = readFileSync(filePath, 'utf8');
    const imports = [...content.matchAll(IMPORT_REGEX)].map(match => match[1]);
    const errors = [];

    imports.forEach(importPath => {
        const resolvedPath = resolveImportPath(importPath, filePath);
        if (resolvedPath) {
            const caseError = checkPathCaseSensitivity(resolvedPath);
            if (caseError) {
                const relativeImportPath = relative(process.cwd(), resolvedPath);
                errors.push({
                    file: relative(process.cwd(), filePath),
                    import: importPath,
                    path: relativeImportPath,
                    expected: caseError.expected,
                    actual: caseError.actual
                });
            }
        }
    });

    return errors;
}

function main() {
    const rootDir = join(__dirname, '..');
    const files = findFiles(rootDir);
    let hasErrors = false;

    console.log(`Scanning ${files.length} TypeScript/TSX files for case sensitivity issues...`);

    files.forEach(file => {
        const errors = checkImports(file);
        if (errors.length > 0) {
            hasErrors = true;
            console.error(`\nCase sensitivity issues found in ${file}:`);
            errors.forEach(error => {
                console.error(`  Import: ${error.import}`);
                console.error(`  Path: ${error.path}`);
                console.error(`  Expected case: ${error.expected}`);
                console.error(`  Actual case: ${error.actual}`);
            });
        }
    });

    if (!hasErrors) {
        console.log('No case sensitivity issues found!');
    } else {
        console.error('\nPlease fix the case sensitivity issues above before committing.');
        process.exit(1);
    }
}

main(); 