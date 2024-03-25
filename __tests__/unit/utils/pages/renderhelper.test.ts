import { truncateOptionString } from '../../../../libs/pages/renderhelpers';
import * as O from 'fp-ts/lib/Option';
// import fc from 'fast-check';

describe('truncateOptionString tests', () => {
    test('should not blow up with empty data', () => {
        expect(truncateOptionString(O.none)).toBe('');
        expect(truncateOptionString(O.of(''))).toBe('');
    });

    //TODO generate strings that can be truncated and test them
    // fc.assert(
    //     fc.property(fc.unicodeString({ minLength: 1 }), (s) => {
    //         expect(truncateOptionString(O.of(s))).toBe(`(${s})`);
    //     }),
    // );
});
