import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { ConfirmationOptions } from '../components/confirmationdialog';
import { RenameEvent } from '../components/editname';
import { AdminFormFields } from './useAPIs';
import {
    AbundanceApi,
    SpeciesApi,
    GallTaxon,
    HostTaxon,
    EmptyAbundance,
    AliasApi,
    SpeciesUpsertFields,
} from '../libs/api/apitypes';
import { FAMILY, FGS, GENUS, TaxonomyEntry, TaxonomyEntryNoParent } from '../libs/api/taxonomy';
import { extractGenus } from '../libs/utils/util';
import React, { Dispatch, SetStateAction, useState } from 'react';
import { Badge, OverlayTrigger, Popover } from 'react-bootstrap';

export const SpeciesNamingHelp = (): JSX.Element => (
    <OverlayTrigger
        placement="auto"
        trigger="click"
        rootClose
        overlay={
            <Popover id="help">
                <Popover.Title>Naming Species</Popover.Title>
                <Popover.Content>
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
                </Popover.Content>
            </Popover>
        }
    >
        <Badge variant="info" className="m-1 larger">
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
};

export type UseSpecies<T extends SpeciesApi> = {
    renameSpecies: (s: T, e: RenameEvent, confirm: (options: ConfirmationOptions) => Promise<void>) => Promise<T>;
    createNewSpecies: (name: string, taxon: typeof HostTaxon | typeof GallTaxon) => SpeciesApi;
    updatedSpeciesFormFields: (s: T | undefined) => SpeciesFormFields<T>;
    toSpeciesUpsertFields: (fields: SpeciesFormFields<T>, name: string, id: number) => SpeciesUpsertFields;
    aliasData: AliasApi[];
    setAliasData: Dispatch<SetStateAction<AliasApi[]>>;
};

const useSpecies = <T extends SpeciesApi>(genera: TaxonomyEntry[]): UseSpecies<T> => {
    const [aliasData, setAliasData] = useState<AliasApi[]>([]);

    const fgsFromName = (name: string): FGS => {
        const genusName = extractGenus(name);
        const genus = genera.find((g) => g.name.localeCompare(genusName) == 0);
        const family = genus?.parent ? pipe(genus.parent, O.getOrElseW(constant(undefined))) : undefined;

        return {
            family: family ? family : { id: -1, description: '', name: '', type: FAMILY },
            genus: genus ? { ...genus } : { id: -1, description: '', name: genusName, type: GENUS },
            section: O.none,
        };
    };

    const createNewSpecies = (name: string, taxon: typeof HostTaxon | typeof GallTaxon): SpeciesApi => ({
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
                            type: GENUS,
                        };
                        if (e.addAlias) {
                            if (e.old == undefined) throw new Error('Trying to add rename but old name is missing?!');
                            s.aliases.push({
                                id: -1,
                                name: e.old,
                                type: 'scientific',
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
                type: 'scientific',
                description: 'Previous name',
            });
        }
        s.name = e.new;
        return s;
    };

    const updatedSpeciesFormFields = (s: T | undefined): SpeciesFormFields<T> => {
        if (s != undefined) {
            setAliasData(s.aliases ? s.aliases : []);
            return {
                mainField: [s],
                genus: [s.fgs?.genus],
                family: [s.fgs?.family],
                datacomplete: s.datacomplete,
                abundance: [pipe(s.abundance, O.getOrElse(constant(EmptyAbundance)))],
                del: false,
            };
        }

        setAliasData([]);
        return {
            mainField: [],
            genus: [],
            family: [],
            datacomplete: false,
            abundance: [EmptyAbundance],
            del: false,
        };
    };

    const toSpeciesUpsertFields = (fields: SpeciesFormFields<T>, name: string, id: number): SpeciesUpsertFields => {
        const family = { ...fields.family[0], parent: O.none };
        const genus = { ...fields.genus[0], parent: O.of(family) };

        return {
            abundance: fields.abundance.length > 0 ? fields.abundance[0].abundance : undefined,
            aliases: aliasData,
            datacomplete: fields.datacomplete,
            fgs: {
                family: family,
                genus: genus,
                section: O.none,
            },
            id: id,
            name: name,
        };
    };

    return {
        renameSpecies: renameSpecies,
        createNewSpecies: createNewSpecies,
        updatedSpeciesFormFields: updatedSpeciesFormFields,
        toSpeciesUpsertFields: toSpeciesUpsertFields,
        aliasData: aliasData,
        setAliasData: setAliasData,
    };
};

export default useSpecies;
