export const genOptions = (opts: string[]): JSX.Element => {
    if (opts == undefined || opts == null) {
        throw new Error('Must have a valid list of options to render.');
    }
    return (
        <>
            <option value=""></option>
            {opts.map((o) => {
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
};
