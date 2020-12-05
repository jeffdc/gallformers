import * as fc from 'fast-check';
import { mightBeNull } from '../../../libs/db/utils';

test('mightBeNull should never return null', () => {
    expect(mightBeNull(null)).toBe('');
    expect(mightBeNull(undefined)).toBe('');

    fc.assert(fc.property(fc.string(), (v) => expect(mightBeNull(v)).not.toBeNull()));
    fc.assert(fc.property(fc.array(fc.string()), (v) => expect(mightBeNull(v)).not.toBeNull()));
});
