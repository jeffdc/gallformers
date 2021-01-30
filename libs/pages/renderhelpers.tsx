import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GallApi, SpeciesSourceApi } from '../api/apitypes';

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

/**
 * Get the default source for the passed in species. The default is undefined if there are no sources or if the passed
 * in species is itself undefined/null. Otherwise the default will be the source that is marked as default or if there
 * are not sources marked as default, then the source with the oldest publication year will be used.
 * @param species
 */
export const defaultSource = (species: GallApi): SpeciesSourceApi | undefined => {
    if (species && species.speciessource.length > 1) {
        // if there is one marked as default, use that
        const source = species.speciessource.find((s) => s.useasdefault !== 0);
        if (source) return source;

        // otherwise pick the one that has the oldest publication date
        return species.speciessource.reduce(
            (acc, v) => (acc && acc.source.pubyear < v.source.pubyear ? acc : v),
            species.speciessource[0],
        );
    } else {
        return undefined;
    }
};
