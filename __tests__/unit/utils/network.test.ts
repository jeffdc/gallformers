import { tryBackoff } from '../../../libs/utils/network.js';

let counter = 0;

beforeEach(() => {
    counter = 0;
});

test('tryBackoff must retry if an exception is thrown', async () => {
    expect(
        await tryBackoff(2, () => {
            counter += 1;
            if (counter <= 1) throw new Error('testing failure mode');
            return Promise.resolve(counter);
        }),
    ).toBe(2);
});
test('tryBackoff must retry if the predicate fails', async () => {
    expect(
        await tryBackoff(
            2,
            () => {
                counter += 1;
                return Promise.resolve(counter);
            },
            (t) => t > 1,
        ),
    ).toBe(2);
});

test('tryBackoff should fail if the predicate is true but an exception is thrown', async () => {
    await tryBackoff(
        1,
        () => {
            throw new Error('testing failure mode');
        },
        () => true,
    )
        .then(() => fail())
        .catch((e) => expect(e).toBeTruthy());
});

test('tryBackoff should keep trying until retries are exhausted', async () => {
    const numTries = 10;
    expect(
        await tryBackoff(
            numTries,
            () => {
                counter += 1;
                return Promise.resolve(counter);
            },
            (t) => t === numTries,
            1,
        ),
    ).toBe(numTries);
});
