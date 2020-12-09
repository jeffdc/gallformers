import { renderCommonNames } from '../../../../libs/pages/renderhelpers';
import * as O from 'fp-ts/lib/Option';
import fc from 'fast-check';

describe('renderCommonNames tests', () => {
    test('should not blow up with empty data', () => {
        expect(renderCommonNames(O.none)).toBe('');
        expect(renderCommonNames(O.of(''))).toBe('');
    });

    fc.assert(
        fc.property(fc.unicodeString({ minLength: 1 }), (s) => {
            expect(renderCommonNames(O.of(s))).toBe(`(${s})`);
        }),
    );
});
