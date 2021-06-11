import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import { ParsedUrlQuery } from 'querystring';
import React from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import 'react-bootstrap-table-next/dist/react-bootstrap-table2.min.css';
import { Controller } from 'react-hook-form';
import * as yup from 'yup';
import AliasTable from '../../components/aliastable';
import Typeahead from '../../components/Typeahead';
import useAdmin from '../../hooks/useadmin';
import useSpecies, { SpeciesFormFields, SpeciesProps } from '../../hooks/useSpecies';
import { extractQueryParam } from '../../libs/api/apipage';
import { AbundanceApi, HostApi, HostTaxon, HOST_FAMILY_TYPES, SpeciesUpsertFields } from '../../libs/api/apitypes';
import { FAMILY, TaxonomyEntry, TaxonomyEntryNoParent } from '../../libs/api/taxonomy';
import { allHosts } from '../../libs/db/host';
import { abundances } from '../../libs/db/species';
import { allFamilies, allGenera, allSections } from '../../libs/db/taxonomy';
import Admin from '../../libs/pages/admin';
import { mightFailWithArray } from '../../libs/utils/util';

type Props = SpeciesProps & {
    hs: HostApi[];
    sections: TaxonomyEntry[];
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
    family: yup
        .array()
        .of(
            yup.object({
                name: yup.string().required(),
            }),
        )
        .required(),
});

export type FormFields = SpeciesFormFields<HostApi> & {
    section: TaxonomyEntryNoParent[];
};

export const testables = {
    Schema: schema,
};

const Host = ({ id, hs, genera, families, sections, abundances }: Props): JSX.Element => {
    const {
        renameSpecies,
        createNewSpecies,
        updatedSpeciesFormFields,
        toSpeciesUpsertFields,
        aliasData,
        setAliasData,
    } = useSpecies<HostApi>(genera);

    const toUpsertFields = (fields: FormFields, name: string, id: number): SpeciesUpsertFields => {
        if (!selected) {
            throw new Error('Trying to submit with a null selection which seems impossible but here we are.');
        }

        return {
            ...toSpeciesUpsertFields(fields, name, id),
            fgs: { ...selected.fgs },
        };
    };

    const updatedFormFields = async (s: HostApi | undefined): Promise<FormFields> => {
        const speciesFields = updatedSpeciesFormFields(s);
        if (s != undefined) {
            return {
                ...speciesFields,
                section: pipe(
                    s.fgs?.section,
                    O.fold(constant([]), (sec) => [sec]),
                ),
            };
        }

        return {
            ...speciesFields,
            section: [],
        };
    };

    const createNewHost = (name: string): HostApi => ({
        ...createNewSpecies(name, HostTaxon),
        galls: [],
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
        formSubmit,
        mainField,
        deleteButton,
    } = useAdmin(
        'Host',
        id,
        hs,
        renameSpecies,
        toUpsertFields,
        { keyProp: 'name', delEndpoint: '../api/host/', upsertEndpoint: '../api/host/upsert' },
        schema,
        updatedFormFields,
        true,
        createNewHost,
    );

    const onSubmit = async (fields: FormFields) => {
        formSubmit(fields);
    };

    return (
        <Admin
            type="Host"
            keyField="name"
            editName={{ getDefault: () => selected?.name, renameCallback: renameCallback }}
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
                                if (selected) {
                                    selected.fgs.genus = g[0];
                                    setSelected({ ...selected });
                                }
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
                            selected={selected?.fgs?.family && selected.fgs.family.id >= 0 ? [selected.fgs.family] : []}
                            disabled={selected && selected.id > 0}
                            onChange={(f) => {
                                if (!selected) return;

                                if (f && f.length > 0) {
                                    // handle the case when a new species is created
                                    // either the genus is new or is not
                                    const genus = genera.find((gg) => gg.id === selected.fgs.genus.id);
                                    if (genus && O.isNone(genus.parent)) {
                                        genus.parent = O.some({ ...f[0], parent: O.none });
                                        selected.fgs = { ...selected.fgs, genus: genus };
                                        setSelected({ ...selected, fgs: { ...selected.fgs, family: f[0] } });
                                    } else {
                                        selected.fgs = { ...selected.fgs, family: f[0] };
                                        setSelected({ ...selected });
                                    }
                                } else {
                                    selected.fgs = {
                                        ...selected.fgs,
                                        family: { name: '', description: '', id: -1, type: FAMILY },
                                    };
                                    setSelected({ ...selected });
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
                        <Controller
                            control={form.control}
                            name="datacomplete"
                            render={({ field: { ref } }) => (
                                <input
                                    ref={ref}
                                    type="checkbox"
                                    className="form-input-checkbox"
                                    checked={selected ? selected.datacomplete : false}
                                    onChange={(e) => {
                                        if (selected) {
                                            selected.datacomplete = e.currentTarget.checked;
                                            setSelected({ ...selected });
                                        }
                                    }}
                                />
                            )}
                        />{' '}
                        All galls known to occur on this plant have been added to the database, and can be filtered by Location
                        and Detachable. However, sources and images for galls associated with this host may be incomplete or
                        absent, and other filters may not have been entered comprehensively or at all.
                    </Col>
                </Row>
                <Row className="formGroup">
                    <Col>
                        <input type="submit" className="button" value="Submit" disabled={!selected} />
                    </Col>
                    <Col>{deleteButton('Caution. All data associated with this Host will be deleted.')}</Col>
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
