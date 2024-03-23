import * as O from 'fp-ts/lib/Option';
import { constant, pipe } from 'fp-ts/lib/function';
import { Badge, OverlayTrigger, Popover } from 'react-bootstrap';
import { ConfirmationOptions } from '../components/confirmationdialog';
import { RenameEvent } from '../components/editname';
import {
    AbundanceApi,
    AliasApi,
    EmptyAbundance,
    FGS,
    SCIENTIFIC_NAME,
    SpeciesApi,
    SpeciesUpsertFields,
    TaxonCodeValues,
    TaxonomyEntry,
    TaxonomyEntryNoParent,
    TaxonomyTypeValues,
} from '../libs/api/apitypes';
import { extractGenus } from '../libs/utils/util';
import { AdminFormFields } from './useadmin';

export const SpeciesNamingHelp = (): JSX.Element => (
    <OverlayTrigger
        placement="auto"
        trigger="click"
        rootClose
        overlay={
            <Popover id="help">
                <Popover.Header>Naming Species</Popover.Header>
                <Popover.Body>
                    <p>
                        All species must have a name that is in the standard binomial form{' '}
                        <mark>
                            <i>Genus species</i>
                        </mark>
                        . You can indicate hybrids by placing an &lsquo;x&rsquo; between the genus and the specific name. The
                        specific name can contain zero or more dashes &lsquo;-&rsquo;.
                    </p>
                    <p>
                        Optionally you can also differeniate between forms of the species by adding one or two additional elements
                        to the name. These elements must be placed in parentheses and separated by spaces.
                    </p>
                    <p>
                        For wasps it is useful to break out the sexual vs agamic generations. To do this create a name like:
                        <br />
                        <mark>
                            <i>Genus species (agamic/sexgen)</i>
                        </mark>
                        <br />
                        choosing either agamic or sexgen as appropriate.
                    </p>
                    <p>
                        For host variants name the gallformer like this:
                        <br />
                        <mark>
                            <i>Genus species (agamic/sexgen) (host)</i>
                        </mark>{' '}
                        <br />
                        The first parenthetical is optional. Host should be shortened as follows:
                        <i>
                            <mark>Quercus bicolor</mark>
                        </i>{' '}
                        becomes{' '}
                        <i>
                            <mark>q-bicolor</mark>
                        </i>
                    </p>
                    <p>Some examples:</p>
                    <i>
                        <ul>
                            <li>
                                <mark>Asimina triloba</mark>
                            </li>
                            <li>
                                <mark>Neuroterus quercusbatatus (agamic) (q-bicolor)</mark>
                            </li>
                            <li>
                                <mark>Quercus x leana</mark>
                            </li>
                            <li>
                                <mark>Unknown p-integrifolium-erineum-blisters</mark>
                            </li>
                        </ul>
                    </i>
                </Popover.Body>
            </Popover>
        }
    >
        <Badge bg="info" className="m-1 larger">
            ?
        </Badge>
    </OverlayTrigger>
);

export type SpeciesProps = {
    id: string;
    families: TaxonomyEntry[];
    genera: TaxonomyEntry[];
    abundances: AbundanceApi[];
};

export type SpeciesFormFields<T> = AdminFormFields<T> & {
    genus: TaxonomyEntryNoParent[];
    family: TaxonomyEntryNoParent[];
    abundance: AbundanceApi[];
    datacomplete: boolean;
    aliases: AliasApi[];
};

export type UseSpecies<T extends SpeciesApi, F extends SpeciesFormFields<T>> = {
    renameSpecies: (s: T, e: RenameEvent, confirm: (options: ConfirmationOptions) => Promise<void>) => Promise<T>;
    createNewSpecies: (name: string, taxon: TaxonCodeValues) => SpeciesApi;
    updatedSpeciesFormFields: (s: T | undefined) => SpeciesFormFields<T>;
    toSpeciesUpsertFields: (fields: F, name: string, id: number) => SpeciesUpsertFields;
};

const useSpecies = <T extends SpeciesApi, F extends SpeciesFormFields<T>>(genera: TaxonomyEntry[]): UseSpecies<T, F> => {
    const fgsFromName = (name: string): FGS => {
        const genusName = extractGenus(name);
        const genus = genera.find((g) => g.name.localeCompare(genusName) == 0);
        const family = genus?.parent ? pipe(genus.parent, O.getOrElseW(constant(undefined))) : undefined;

        return {
            family: family ? family : { id: -1, description: '', name: '', type: TaxonomyTypeValues.FAMILY, parent: O.none },
            genus: genus
                ? { ...genus }
                : { id: -1, description: '', name: genusName, type: TaxonomyTypeValues.GENUS, parent: O.none },
            section: O.none,
        };
    };

    const createNewSpecies = (name: string, taxon: TaxonCodeValues): SpeciesApi => ({
        id: -1,
        name: name,
        abundance: O.none,
        aliases: [],
        datacomplete: false,
        description: O.none,
        fgs: fgsFromName(name),
        images: [],
        speciessource: [],
        taxoncode: taxon,
    });

    const renameSpecies = async (s: T, e: RenameEvent, confirm: (options: ConfirmationOptions) => Promise<void>): Promise<T> => {
        if (e.old == undefined) throw new Error('Trying to add rename but old name is missing?!');

        // have to check for genus rename
        const newGenus = extractGenus(e.new);
        if (newGenus.localeCompare(extractGenus(e.old)) != 0) {
            const g = genera.find((g) => g.name.localeCompare(newGenus) == 0);
            if (g == undefined) {
                return confirm({
                    variant: 'danger',
                    catchOnCancel: true,
                    title: 'Are you sure want to create a new genus?',
                    message: `Renaming the genus to ${newGenus} will create a new genus under the current family ${s.fgs.family.name}. Do you want to continue?`,
                })
                    .then(() => {
                        s.fgs.genus = {
                            id: -1,
                            description: '',
                            name: newGenus,
                            type: TaxonomyTypeValues.GENUS,
                            parent: O.of(s.fgs.family),
                        };
                        if (e.addAlias) {
                            if (e.old == undefined) throw new Error('Trying to add rename but old name is missing?!');
                            s.aliases.push({
                                id: -1,
                                name: e.old,
                                type: SCIENTIFIC_NAME,
                                description: 'Previous name',
                            });
                        }
                        s.name = e.new;

                        return s;
                    })
                    .catch(() => {
                        return s;
                    });
            } else {
                s.fgs.genus = g;
            }
        }

        if (e.addAlias) {
            s.aliases.push({
                id: -1,
                name: e.old,
                type: SCIENTIFIC_NAME,
                description: 'Previous name',
            });
        }
        s.name = e.new;
        return s;
    };

    // const stripParent = (te: TaxonomyEntry): TaxonomyEntryNoParent => ({
    //     id: te.id,
    //     name: te.name,
    //     type: te.type,
    //     description: te.description,
    // });

    const updatedSpeciesFormFields = (s: T | undefined): SpeciesFormFields<T> => {
        if (s != undefined) {
            return {
                mainField: [s],
                genus: [s.fgs?.genus],
                family: [s.fgs?.family],
                datacomplete: s.datacomplete,
                abundance: [pipe(s.abundance, O.getOrElse(constant(EmptyAbundance)))],
                del: false,
                aliases: s.aliases,
            };
        }

        return {
            mainField: [],
            genus: [],
            family: [],
            datacomplete: false,
            abundance: [EmptyAbundance],
            del: false,
            aliases: [],
        };
    };

    const toSpeciesUpsertFields = (fields: F, name: string, id: number): SpeciesUpsertFields => {
        const family: TaxonomyEntry = { ...fields.family[0], parent: O.none };
        const genus: TaxonomyEntry = { ...fields.genus[0], parent: O.of(family) };

        return {
            abundance: fields.abundance.length > 0 ? fields.abundance[0].abundance : undefined,
            aliases: fields.aliases,
            datacomplete: fields.datacomplete,
            fgs: {
                family: family,
                genus: genus,
                section: O.none,
            },
            id: id,
            name: name,
            // for now only Hosts have places so default to an empty array
            places: [],
        };
    };

    return {
        renameSpecies: renameSpecies,
        createNewSpecies: createNewSpecies,
        updatedSpeciesFormFields: updatedSpeciesFormFields,
        toSpeciesUpsertFields: toSpeciesUpsertFields,
    };
};

export default useSpecies;
