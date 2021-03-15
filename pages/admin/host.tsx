import { abundance } from '@prisma/client';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import { useRouter } from 'next/router';
import { ParsedUrlQuery } from 'querystring';
import React, { useState } from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import 'react-bootstrap-table-next/dist/react-bootstrap-table2.min.css';
import * as yup from 'yup';
import AliasTable from '../../components/aliastable';
import ControlledTypeahead from '../../components/controlledtypeahead';
import useAdmin from '../../hooks/useadmin';
import { AdminFormFields } from '../../hooks/useAPIs';
import { extractQueryParam } from '../../libs/api/apipage';
import { AbundanceApi, AliasApi, EmptyAbundance, HostApi, HOST_FAMILY_TYPES, SpeciesUpsertFields } from '../../libs/api/apitypes';
import { EMPTY_FGS, FGS, TaxonomyEntry } from '../../libs/api/taxonomy';
import { allHosts } from '../../libs/db/host';
import { abundances } from '../../libs/db/species';
import { allFamilies, allSections, taxonomyForSpecies } from '../../libs/db/taxonomy';
import Admin from '../../libs/pages/admin';
import { mightFail, mightFailWithArray } from '../../libs/utils/util';

type Props = {
    id: string;
    hs: HostApi[];
    fgs: FGS;
    families: TaxonomyEntry[];
    sections: TaxonomyEntry[];
    abundances: abundance[];
};

const extractGenus = (n: string): string => {
    return n.split(' ')[0];
};

const schema = yup.object().shape({
    value: yup
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
    genus: string;
    family: TaxonomyEntry[];
    section: TaxonomyEntry[];
    abundance: AbundanceApi[];
    datacomplete: boolean;
};

export const testables = {
    extractGenus: extractGenus,
    Schema: schema,
};

const updateHost = (s: HostApi, newValue: string): HostApi => ({
    ...s,
    name: newValue,
});

const emptyForm = {
    value: [],
    genus: '',
    family: [],
    abundance: [EmptyAbundance],
};

const convertToFields = (fgs: FGS) => (s: HostApi): FormFields => ({
    value: [s],
    genus: extractGenus(s.name),
    family: fgs.family != null ? [fgs.family] : [],
    section: pipe(
        fgs.section,
        O.fold(constant([]), (s) => [s]),
    ),
    abundance: [pipe(s.abundance, O.getOrElse(constant(EmptyAbundance)))],
    datacomplete: s.datacomplete,
    del: false,
});

const fetchFGS = async (h: HostApi): Promise<FGS> => {
    const res = await fetch(`../api/taxonomy?id=${h.id}`);
    if (res.status === 200) {
        return await res.json();
    } else {
        console.error(await res.text());
        throw new Error('Failed to fetch taxonomy for the selected species. Check console.');
    }
};

const Host = ({ id, hs, fgs, families, sections, abundances }: Props): JSX.Element => {
    const [theFGS, setTheFGS] = useState(fgs);
    const [aliasData, setAliasData] = useState<AliasApi[]>([]);

    const toUpsertFields = (fields: FormFields, name: string, id: number): SpeciesUpsertFields => {
        return {
            abundance: fields.abundance[0].abundance,
            aliases: aliasData,
            datacomplete: fields.datacomplete,
            fgs: theFGS,
            id: id,
            name: name,
        };
    };

    const onDataChangeCallback = async (s: HostApi | undefined): Promise<HostApi | undefined> => {
        if (s == undefined) {
            setAliasData([]);
        } else {
            if (selected && extractGenus(s.name) === extractGenus(selected.name)) {
                console.log('genus change');
                // name change as usual
                // also need to update the taxonomy, possibly adding a new Genus
                // also need to think about family change
            }
            setTheFGS(await fetchFGS(s));
            setAliasData(s.aliases);
        }
        return s;
    };

    const {
        data,
        selected,
        setSelected,
        showRenameModal,
        setShowRenameModal,
        error,
        setError,
        deleteResults,
        setDeleteResults,
        renameWithNewValue,
        form,
        formSubmit,
    } = useAdmin(
        'Host',
        id,
        hs,
        updateHost,
        convertToFields(theFGS),
        toUpsertFields,
        { keyProp: 'name', delEndpoint: '../api/host/', upsertEndpoint: '../api/host/upsert' },
        schema,
        emptyForm,
        onDataChangeCallback,
    );

    const router = useRouter();

    const onSubmit = async (fields: FormFields) => {
        formSubmit(fields);
    };

    return (
        <Admin
            type="Host"
            keyField="name"
            editName={{ getDefault: () => selected?.name, setNewValue: renameWithNewValue(onSubmit) }}
            setShowModal={setShowRenameModal}
            showModal={showRenameModal}
            setError={setError}
            error={error}
            setDeleteResults={setDeleteResults}
            deleteResults={deleteResults}
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
                            {selected && (
                                <Col xs={1}>
                                    <Button variant="secondary" className="btn-sm" onClick={() => setShowRenameModal(true)}>
                                        Rename
                                    </Button>
                                </Col>
                            )}
                        </Row>
                        <Row>
                            <Col>
                                <ControlledTypeahead
                                    control={form.control}
                                    name="value"
                                    onChangeWithNew={(e, isNew) => {
                                        if (isNew || !e[0]) {
                                            setSelected(undefined);
                                            router.replace(``, undefined, { shallow: true });
                                        } else {
                                            const host: HostApi = e[0];
                                            console.log(`selected: ${selected?.id} // host: ${host.id}`);
                                            if (selected?.id !== host.id) {
                                                setSelected(host);
                                                router.replace(`?id=${host.id}`, undefined, { shallow: true });
                                            }
                                        }
                                    }}
                                    onBlurT={(e) => {
                                        if (!form.errors.value) {
                                            form.setValue('genus', extractGenus(e.target.value));
                                        }
                                    }}
                                    placeholder="Name"
                                    options={data}
                                    labelKey="name"
                                    clearButton
                                    isInvalid={!!form.errors.value}
                                    newSelectionPrefix="Add a new Host: "
                                    allowNew={true}
                                />
                                {form.errors.value && (
                                    <span className="text-danger">
                                        Name is required and must be in standard binomial form, e.g., Gallus gallus
                                    </span>
                                )}
                            </Col>
                        </Row>
                    </Col>
                    <Col>
                        Genus (filled automatically):
                        <input type="text" name="genus" className="form-control" readOnly tabIndex={-1} ref={form.register} />
                    </Col>
                    <Col>
                        Family:
                        <ControlledTypeahead
                            control={form.control}
                            name="family"
                            placeholder="Family"
                            options={families}
                            labelKey="name"
                            clearButton
                        />
                        {form.errors.family && (
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
                        <ControlledTypeahead
                            control={form.control}
                            name="section"
                            placeholder=""
                            options={sections}
                            labelKey="name"
                            clearButton
                        />
                    </Col>
                    <Col>
                        Abundance:
                        <ControlledTypeahead
                            control={form.control}
                            name="abundance"
                            placeholder=""
                            options={abundances}
                            labelKey="abundance"
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
                        <input name="datacomplete" type="checkbox" className="form-input-checkbox" ref={form.register} /> Are all
                        known galls submitted for this host?
                    </Col>
                </Row>
                <Row className="fromGroup pb-1" hidden={!selected}>
                    <Col className="mr-auto">
                        <input name="del" type="checkbox" className="form-input-checkbox" ref={form.register} /> Delete?
                    </Col>
                </Row>
                <Row className="formGroup">
                    <Col>
                        <input type="submit" className="button" value="Submit" />
                    </Col>
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

    const fgs = id === '' ? EMPTY_FGS : await mightFail(constant(EMPTY_FGS))(taxonomyForSpecies(parseInt(id)));
    return {
        props: {
            id: id,
            hs: await mightFailWithArray<HostApi>()(allHosts()),
            fgs: fgs,
            families: await mightFailWithArray<TaxonomyEntry>()(allFamilies(HOST_FAMILY_TYPES)),
            sections: await mightFailWithArray<TaxonomyEntry>()(allSections()),
            abundances: await mightFailWithArray<AbundanceApi>()(abundances()),
        },
    };
};

export default Host;
