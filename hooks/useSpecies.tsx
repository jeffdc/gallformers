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
import { Dispatch, SetStateAction, useState } from 'react';

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
