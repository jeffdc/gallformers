/**
 * Calls @work, backing off exponentially as a factor of @delay at most @retries times if @predicate fails
 * or an exception is caught.
 * @param retries number of times to retry work before giving up
 * @param work the work that may fail
 * @param predicate a test to determine pass or failure of @work if no predicate is passed then it will always be
 * true and rely on an excpetion being thrown to retry.
 * @param delay the time dealy in ms to start with, default 500
 */
export const tryBackoff = async <T>(
    retries: number,
    work: () => Promise<T>,
    predicate: (t: T) => boolean = () => true,
    delay = 500,
): Promise<T> => {
    const retry = async (e?: Error) => {
        if (retries > 1) {
            await new Promise((r) => setTimeout(r, delay));
            return tryBackoff(retries - 1, work, predicate, delay * 2);
        } else {
            throw e ? e : new Error('Backoff retries exhausted.');
        }
    };

    try {
        const t = await work();
        if (predicate(t)) {
            return t;
        } else {
            console.log(`Predicate failed and will retry in ${delay} ms.`);
            return await retry();
        }
    } catch (e) {
        console.log(`Attempt threw (${e}). Will retry in ${delay} ms.`);
        return await retry(e as Error);
    }
};
