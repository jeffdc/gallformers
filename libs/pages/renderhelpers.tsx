import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { ImageApi, SpeciesApi } from '../api/apitypes';
import { truncateAtWord } from '../utils/util';

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
export const defaultSource = <T extends { useasdefault: number; source: { pubyear: string } }>(
    speciessource: T[],
): T | undefined => {
    if (speciessource && speciessource.length > 0) {
        // if there is one marked as default, use that
        const source = speciessource.find((s) => s.useasdefault !== 0);
        if (source) return source;

        // otherwise pick the one that has the oldest publication date
        return speciessource.reduce((acc, v) => (acc && acc.source.pubyear < v.source.pubyear ? acc : v), speciessource[0]);
    } else {
        return undefined;
    }
};

/**
 * Returns the default image for the species. If there is an image marked as default, that will be returned. If no
 * image is marked as default then an image will be returned but it is not necessarily determenisitc which one.
 * @param species
 */
export const defaultImage = <T extends SpeciesApi>(species: T): ImageApi | undefined => {
    let defaultImage = species.images.find((i) => i.default);
    if (!defaultImage && species.images.length > 0) defaultImage = species.images[0];

    return defaultImage;
};

/**
 * Given an Option<string> return the string truncated at the truncateAfterWord(nth) word if Some. If None an empty string.
 * @param description
 * @param truncateAfterWord
 */
export const truncateOptionString = (description: O.Option<string>, truncateAfterWord = 40): string => {
    // eslint-disable-next-line prettier/prettier
    return pipe(
        description,
        O.map(truncateAtWord(truncateAfterWord)),
        O.getOrElse(constant('')),
    )    
};

/**
 *
 * @param s
 */
export const sourceToDisplay = (s: { pubyear: string; title: string; author: string }): string =>
    `${s.pubyear}: ${s.title} - ${s.author}`;
