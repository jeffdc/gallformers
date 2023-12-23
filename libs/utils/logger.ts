import * as C from 'fp-ts/lib/Console.js';
import { IO } from 'fp-ts/lib/IO.js';
import * as L from 'logging-ts/lib/IO.js';
import pino from 'pino';

export const logger = pino();

// WIP stuff below here:
type Level = 'Debug' | 'Info' | 'Warning' | 'Error';

interface Entry {
    message: string;
    time: Date;
    level: Level;
}

function showEntry(entry: Entry): string {
    return `[${entry.level}] ${entry.time.toLocaleString()} ${entry.message}`;
}

function getLoggerEntry(prefix: string): L.LoggerIO<Entry> {
    return (entry) => C.log(`${prefix}: ${showEntry(entry)}`);
}

const debugLogger = L.filter(getLoggerEntry('debug.log'), (e) => e.level === 'Debug');
const productionLogger = L.filter(getLoggerEntry('production.log'), (e) => e.level !== 'Debug');
export const flogger = L.getMonoid<Entry>().concat(debugLogger, productionLogger);

export const info =
    (message: string) =>
    (time: Date): IO<void> =>
        flogger({ message, time, level: 'Info' });
export const debug =
    (message: string) =>
    (time: Date): IO<void> =>
        flogger({ message, time, level: 'Debug' });
