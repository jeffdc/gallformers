import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import { ParsedUrlQuery } from 'querystring';
import React, { useState } from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import 'react-bootstrap-table-next/dist/react-bootstrap-table2.min.css';
import { Path } from 'react-hook-form';
import * as yup from 'yup';
import AliasTable from '../../components/aliastable';
import { RenameEvent } from '../../components/editname';
import Typeahead from '../../components/Typeahead';
import useAdmin from '../../hooks/useadmin';
import { AdminFormFields } from '../../hooks/useAPIs';
import { extractQueryParam } from '../../libs/api/apipage';
import {
    AbundanceApi,
    AliasApi,
    EmptyAbundance,
    HostApi,
    HostTaxon,
    HOST_FAMILY_TYPES,
    SpeciesUpsertFields,
} from '../../libs/api/apitypes';
import { FAMILY, FGS, GENUS, TaxonomyEntry } from '../../libs/api/taxonomy';
import { allHosts } from '../../libs/db/host';
import { abundances } from '../../libs/db/species';
import { allFamilies, allGenera, allSections } from '../../libs/db/taxonomy';
import Admin from '../../libs/pages/admin';
import { extractGenus, mightFailWithArray } from '../../libs/utils/util';

type TaxNoParent = Omit<TaxonomyEntry, 'parent'>;

type Props = {
    id: string;
    hs: HostApi[];
    families: TaxonomyEntry[];
    sections: TaxonomyEntry[];
    genera: TaxonomyEntry[];
    abundances: AbundanceApi[];
};

const schema = yup.object().shape({
    mainField: yup
        .array()
        .of(
            yup.object({
                name: yup
                    .string()
                    // maybe? add this back but allow select punctuation in species name?
                    // .matches(/([A-Z][a-z]+ [a-z]+$)/)
                    .required(),
            }),
        )
        .min(1)
        .max(1),
    family: yup.mixed().required(),
});

export type FormFields = AdminFormFields<HostApi> & {
    genus: TaxNoParent[];
    family: TaxNoParent[];
    section: TaxNoParent[];
    abundance: AbundanceApi[];
    datacomplete: boolean;
};

export const testables = {
    Schema: schema,
};

const updateHost = (s: HostApi, newValue: string): HostApi => ({
    ...s,
    name: newValue,
});

const Host = ({ id, hs, genera, families, sections, abundances }: Props): JSX.Element => {
    const [aliasData, setAliasData] = useState<AliasApi[]>([]);

    const toUpsertFields = (fields: FormFields, name: string, id: number): SpeciesUpsertFields => {
        const family = { ...fields.family[0], parent: O.none };
        const genus = { ...fields.genus[0], parent: O.of(family) };
        const section = O.fromNullable({ ...fields.section[0], parent: O.of(genus) });

        return {
            abundance: fields.abundance.length > 0 ? fields.abundance[0].abundance : undefined,
            aliases: aliasData,
            datacomplete: fields.datacomplete,
            fgs: {
                family: family,
                genus: genus,
                section: section,
            },
            id: id,
            name: name,
        };
    };

    const updatedFormFields = async (s: HostApi | undefined): Promise<FormFields> => {
        if (s != undefined) {
            setAliasData(s?.aliases);
            return {
                mainField: [s],
                genus: [s.fgs?.genus],
                family: [s.fgs?.family],
                section: pipe(
                    s.fgs?.section,
                    O.fold(constant([]), (sec) => [sec]),
                ),
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
            section: [],
            datacomplete: false,
            abundance: [EmptyAbundance],
            del: false,
        };
    };

    const fgsFromName = (name: string): FGS => {
        const genusName = extractGenus(name);
        const genus = genera.find((g) => g.name.localeCompare(genusName) == 0);
        const family = genus?.parent ? pipe(genus.parent, O.getOrElseW(constant(undefined))) : undefined;
        // if (!family) throw new Error('The selected Genus is missing its Family.');

        return {
            family: family ? family : { id: -1, description: '', name: '', type: FAMILY },
            genus: genus ? { ...genus } : { id: -1, description: '', name: genusName, type: GENUS },
            section: O.none,
        };
    };

    const createNewHost = (name: string): HostApi => ({
        name: name,
        abundance: O.none,
        aliases: [],
        datacomplete: false,
        description: O.none,
        fgs: fgsFromName(name),
        galls: [],
        id: -1,
        images: [],
        speciessource: [],
        taxoncode: HostTaxon,
    });

    const {
        selected,
        setSelected,
        showRenameModal,
        setShowRenameModal,
        error,
        setError,
        deleteResults,
        setDeleteResults,
        renameCallback,
        form,
        confirm,
        formSubmit,
        mainField,
        deleteButton,
    } = useAdmin(
        'Host',
        id,
        hs,
        updateHost,
        toUpsertFields,
        { keyProp: 'name', delEndpoint: '../api/host/', upsertEndpoint: '../api/host/upsert' },
        schema,
        updatedFormFields,
        createNewHost,
    );

    const rename = async (fields: FormFields, e: RenameEvent) => {
        if (e.old == undefined) throw new Error('Trying to add rename but old name is missing?!');

        if (e.addAlias) {
            aliasData.push({
                id: -1,
                name: e.old,
                type: 'scientific',
                description: 'Previous name',
            });
        }

        // have to check for genus rename
        const newGenus = extractGenus(e.new);
        if (newGenus.localeCompare(extractGenus(e.old)) != 0) {
            const g = genera.find((g) => g.name.localeCompare(newGenus) == 0);
            if (g == undefined) {
                return confirm({
                    variant: 'danger',
                    catchOnCancel: true,
                    title: 'Are you sure want to create a new genus?',
                    message: `Renaming the genus to ${newGenus} will create a new genus under the current family ${fields.family[0].name}. Do you want to continue?`,
                }).then(() => {
                    fields.genus[0] = {
                        id: -1,
                        description: '',
                        name: newGenus,
                        type: GENUS,
                        // parent: O.of(fields.family[0]),
                    };
                    return Promise.bind(onSubmit(fields));
                });
            } else {
                fields.genus[0] = g;
            }
        }

        return onSubmit(fields);
    };

    const onSubmit = async (fields: FormFields) => {
        formSubmit(fields);
    };

    return (
        <Admin
            type="Host"
            keyField="name"
            editName={{ getDefault: () => selected?.name, renameCallback: renameCallback(rename) }}
            setShowModal={setShowRenameModal}
            showModal={showRenameModal}
            setError={setError}
            error={error}
            setDeleteResults={setDeleteResults}
            deleteResults={deleteResults}
            selected={selected}
        >
            <form onSubmit={form.handleSubmit(onSubmit)} className="m-4 pr-4">
                <h4>Add/Edit Hosts</h4>
                <p>
                    This is for all of the details about a Host. To add a description (which must be referenced to a source) go
                    add <Link href="/admin/source">Sources</Link>, if they do not already exist, then go{' '}
                    <Link href="/admin/speciessource">map species to sources with description</Link>. If you want to assign a{' '}
                    <Link href="/admin/family">Family</Link> or <Link href="/admin/section">Section</Link> then you will need to
                    have created them first if they do not exist.
                </p>
                <Row className="form-group">
                    <Col>
                        <Row>
                            <Col xs={8}>Name (binomial):</Col>
                        </Row>
                        <Row>
                            <Col>{mainField('name', 'Host')}</Col>
                            {selected && (
                                <Col xs={1}>
                                    <Button variant="secondary" className="btn-sm" onClick={() => setShowRenameModal(true)}>
                                        Rename
                                    </Button>
                                </Col>
                            )}
                        </Row>
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Genus (filled automatically):
                        <Typeahead
                            name="genus"
                            control={form.control}
                            placeholder="Genus"
                            options={genera}
                            labelKey="name"
                            selected={selected?.fgs?.genus ? [selected.fgs.genus] : []}
                            disabled={true}
                            onChange={(g) => {
                                if (selected) selected.fgs.genus = g[0];
                                form.setValue('genus' as Path<FormFields>, g);
                            }}
                            clearButton
                            multiple
                        />
                    </Col>
                    <Col>
                        Family:
                        <Typeahead
                            name="family"
                            control={form.control}
                            placeholder="Family"
                            options={families}
                            labelKey="name"
                            selected={selected?.fgs?.family ? [selected.fgs.family] : []}
                            disabled={selected && selected.id > 0}
                            onChange={(f) => {
                                if (selected) {
                                    // handle the case when a new species is created
                                    const g = form.getValues().genus[0];
                                    const genus = genera.find((gg) => gg.id === g.id);
                                    if (genus && O.isNone(genus.parent)) {
                                        genus.parent = O.some({ ...f[0], parent: O.none });
                                        setSelected({ ...selected, fgs: { ...selected.fgs, genus: genus } });
                                    }
                                }
                            }}
                            clearButton
                        />
                        {form.formState.errors.family && (
                            <span className="text-danger">
                                The Family name is required. If it is not present in the list you will have to go add the family
                                first. :(
                            </span>
                        )}
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Section:
                        <Typeahead
                            name="section"
                            control={form.control}
                            placeholder="Section"
                            options={sections}
                            labelKey="name"
                            selected={
                                selected?.fgs?.section
                                    ? pipe(
                                          selected.fgs.section,
                                          O.fold(constant([]), (s) => [s]),
                                      )
                                    : []
                            }
                            onChange={(g) => {
                                if (selected) {
                                    selected.fgs.section = O.fromNullable(g[0]);
                                    setSelected({ ...selected });
                                }
                            }}
                            disabled={!selected}
                            clearButton
                        />
                    </Col>
                    <Col>
                        Abundance:
                        <Typeahead
                            name="abundance"
                            control={form.control}
                            placeholder=""
                            options={abundances}
                            labelKey="abundance"
                            disabled={!selected}
                            selected={
                                selected?.abundance
                                    ? pipe(
                                          selected.abundance,
                                          O.fold(constant([]), (a) => [a]),
                                      )
                                    : []
                            }
                            onChange={(g) => {
                                if (selected) {
                                    selected.abundance = O.fromNullable(g[0]);
                                    setSelected({ ...selected });
                                }
                            }}
                            clearButton
                        />
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        <AliasTable data={aliasData} setData={setAliasData} />
                    </Col>
                </Row>
                <Row className="formGroup pb-1">
                    <Col className="mr-auto">
                        <input {...form.register('datacomplete')} type="checkbox" className="form-input-checkbox" /> All galls
                        known to occur on this plant have been added to the database, and can be filtered by Location and
                        Detachable. However, sources and images for galls associated with this host may be incomplete or absent,
                        and other filters may not have been entered comprehensively or at all.
                    </Col>
                </Row>
                <Row className="formGroup">
                    <Col>
                        <input type="submit" className="button" value="Submit" />
                    </Col>
                    <Col>{deleteButton('Caution. All data associated with this Host will be deleted.')}</Col>
                </Row>
                <Row hidden={!selected}>
                    <Col>
                        <br />
                        <Link href={`./images?speciesid=${selected?.id}`}>Add/Edit Images for this Host</Link>
                    </Col>
                </Row>
            </form>
        </Admin>
    );
};

export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery }) => {
    const queryParam = 'id';
    // eslint-disable-next-line prettier/prettier
    const id = pipe(
        extractQueryParam(context.query, queryParam),
        O.getOrElse(constant('')),
    );

    return {
        props: {
            id: id,
            hs: await mightFailWithArray<HostApi>()(allHosts()),
            families: await mightFailWithArray<TaxonomyEntry>()(allFamilies(HOST_FAMILY_TYPES)),
            genera: await mightFailWithArray<TaxonomyEntry>()(allGenera(HostTaxon)),
            sections: await mightFailWithArray<TaxonomyEntry>()(allSections()),
            abundances: await mightFailWithArray<AbundanceApi>()(abundances()),
        },
    };
};

export default Host;
