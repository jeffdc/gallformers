import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';

/**
 * Simple helper to render the commonnames in the UI.
 * @param commonnames
 */
export const renderCommonNames = (commonnames: O.Option<string>): string => {
    // eslint-disable-next-line prettier/prettier
    return pipe(
        commonnames,
        O.map((c) => (c.length === 0 ? '' : `(${c})`)),
        O.getOrElse(constant('')),
    );
};

/**
 * Renders the given string input with line breaks for any embedded new lines.
 * @param p
 */
export const renderParagraph = (p: string): React.ReactNode => {
    const [firstLine, ...rest] = p.split('\n');

    return (
        <p>
            {firstLine}
            {rest.map((line) => (
                <>
                    <br />
                    {line}
                </>
            ))}
        </p>
    );
};
