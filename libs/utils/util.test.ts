import * as fc from 'fast-check';
import { Maybe } from 'true-myth';
import { handleFailure, hasProp, randInt } from './util';

test('randInt should always return a number within the bounds', () => {
    fc.assert(
        fc.property(
            fc.tuple(fc.integer(), fc.integer()).filter((t) => t[0] < t[1]),
            (t) => {
                const [lower, upper] = t;
                const x = randInt(lower, upper);
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
            expect(randInt(lower, upper)).toThrow();
        },
    );
});

test('hasProp should detect props', () => {
    fc.property(fc.object(), (o) => {
        for (const p in o) {
            expect(hasProp(o, p)).toBeTruthy();
        }
        fc.property(
            fc.string().filter((s) => !hasProp(o, s)),
            (p) => {
                expect(hasProp(o, p)).toBeFalsy();
            },
        );
    });
});

test('handleFailure must throw', () => {
    expect(() => handleFailure(new Error('fail'))).toThrow();
});
