import * as fc from 'fast-check';
import * as U from './util';
import * as E from 'fp-ts/lib/Either';
import * as TE from 'fp-ts/lib/TaskEither';
import { pipe } from 'fp-ts/lib/function';

test('randInt should always return a number within the bounds', () => {
    fc.assert(
        fc.property(
            fc.tuple(fc.integer(), fc.integer()).filter((t) => t[0] < t[1]),
            (t) => {
                const [lower, upper] = t;
                const x = U.randInt(lower, upper);
                expect(x).toBeLessThanOrEqual(upper);
                expect(x).toBeGreaterThanOrEqual(lower);
            },
        ),
    );
});

test('randInt should fail with invalid inputs', () => {
    fc.property(
        fc.tuple(fc.integer(), fc.integer()).filter((t) => t[0] >= t[1]),
        (t) => {
            const [lower, upper] = t;
            expect(U.randInt(lower, upper)).toThrow();
        },
    );
});

test('hasProp should detect props', () => {
    fc.property(fc.object(), (o) => {
        for (const p in o) {
            expect(U.hasProp(o, p)).toBeTruthy();
        }
        fc.property(
            fc.string().filter((s) => !U.hasProp(o, s)),
            (p) => {
                expect(U.hasProp(o, p)).toBeFalsy();
            },
        );
    });
});

const anError = new Error('this is an expected test exception, it does not mean anything went awry!');

test('mightFail should return an empty array on failure', async () => {
    // eslint-disable-next-line prettier/prettier
    const r = await pipe(
        TE.left<Error, unknown[]>(anError),
        U.mightFail,
    );

    expect(r.length).toBe(0);
});

test('errorThrow should always throw', () => {
    expect(() => U.errorThrow(anError)).toThrow();
});

test('handleFailure should convert to an Error', () => {
    expect(U.handleError('foo').message).toBe('foo');
});
