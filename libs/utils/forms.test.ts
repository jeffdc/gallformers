import * as fc from 'fast-check';
import { render, screen } from '@testing-library/react';
import { genOptions } from './forms';

describe('The Forms Util genOptions()', () => {
    it('should render valid options with an empty array as input', () => {
        expect(genOptions([])).toBeTruthy();
    });

    it('should throw when given an options input that contains duplicates', () => {
        // must be in function for the throw check to work
        expect(() => {
            genOptions(['a', 'a']);
        }).toThrow();
    });

    it('should render valid options given valid options input', () => {
        fc.assert(
            fc.property(fc.set(fc.unicodeString({ minLength: 1 })), (values) => {
                render(genOptions(values));
                values.forEach((v) => {
                    screen.queryAllByText(v).forEach((d) => expect(d).toBeInTheDocument());
                });
            }),
        );
    });

    it('should not include an empty option when told not to', () => {
        const opts = render(genOptions(['a'], false));
        // expect it to be 2, since the body and the div will show as empty text.
        expect(screen.queryAllByText('').length).toBe(2);
        opts.unmount();

        // now it should be 4 to account for the empty option: body, empty div (fragment), div, option
        render(genOptions(['a'], true));
        expect(screen.queryAllByText('').length).toBe(4);
    });
});
