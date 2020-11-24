export const genOptions = (opts: string[]): JSX.Element => {
    if (!opts) {
        throw new Error('Must have a valid list of options to render.');
    } else if (new Set(opts).size !== opts.length) {
        throw new Error('Passed in set of options contains duplicates and this is not allowed.');
    }

    return (
        <>
            <option key="none" value=""></option>
            {opts
                .filter((o) => o)
                .map((o) => {
                    return (
                        <option key={o} value={o}>
                            {o}
                        </option>
                    );
                })}
        </>
    );
};

export type SpeciesFormFields = {
    name: string;
    commonnames: string;
    synonyms: string;
    family: string;
    abundance: string;
    description: string;
};

export type GallFormFields = SpeciesFormFields & {
    hosts: string[];
    locations: string[];
    color: string;
    shape: string;
    textures: string[];
    alignment: string;
    walls: string;
    cells: string;
    detachable: string;
    delete?: boolean;
};
