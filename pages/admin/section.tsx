import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import { useRouter } from 'next/router';
import { ParsedUrlQuery } from 'querystring';
import React from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import * as yup from 'yup';
import ControlledTypeahead from '../../components/controlledtypeahead';
import useAdmin from '../../hooks/useadmin';
import { AdminFormFields } from '../../hooks/useAPIs';
import { extractQueryParam } from '../../libs/api/apipage';
import { HostApi, HostTaxon, SimpleSpecies } from '../../libs/api/apitypes';
import { TaxonomyEntry, TaxonomyUpsertFields } from '../../libs/api/taxonomy';
import { allHosts } from '../../libs/db/host';
import { allGenera, allSections } from '../../libs/db/taxonomy';
import Admin from '../../libs/pages/admin';
import { extractGenus, hasProp, mightFailWithArray } from '../../libs/utils/util';

const SpeciesSchema = yup.object({
    id: yup.number(),
    taxoncode: yup.string(),
    name: yup.string(),
});

const schema = yup.object().shape({
    value: yup.array().required('A name is required.'),
    description: yup.string().required('A description is required.'),
    species: yup
        .array()
        .required('At least one species must be selected.')
        .of(SpeciesSchema)
        .test('same genus', 'All species must be of the same genus', (v) => {
            return new Set(v?.map((s) => extractGenus(s?.name))).size === 1;
        }),
});

type Props = {
    id: string;
    sections: TaxonomyEntry[];
    genera: TaxonomyEntry[];
    hosts: HostApi[];
};

type FormFields = (AdminFormFields<TaxonomyEntry> & Omit<TaxonomyEntry, 'id' | 'name' | 'type' | 'parent'>) & {
    species: SimpleSpecies[];
};

const updateSection = (s: TaxonomyEntry, newValue: string) => ({
    ...s,
    name: newValue,
});

const fetchSectionSpecies = async (sec: TaxonomyEntry): Promise<SimpleSpecies[]> => {
    const res = await fetch(`../api/taxonomy/section/${sec.id}`);
    if (res.status === 200) {
        return (await res.json()) as SimpleSpecies[];
    } else {
        console.error(await res.text());
        throw new Error('Failed to fetch species for the selected section. Check console.');
    }
};

const Section = ({ id, sections, genera, hosts }: Props): JSX.Element => {
    const toUpsertFields = (fields: FormFields, name: string, id: number): TaxonomyUpsertFields => {
        return {
            name: name,
            description: fields.description,
            type: 'section',
            id: id,
            species: fields.species.map((s) => s.id),
            parent: O.fromNullable(genera.find((g) => g.name.localeCompare(extractGenus(fields.species[0].name)) == 0)),
        };
    };

    const updatedFormFields = async (sec: TaxonomyEntry | undefined): Promise<FormFields> => {
        if (sec != undefined) {
            const s = await fetchSectionSpecies(sec);
            return {
                ...sec,
                del: false,
                value: [sec],
                species: s,
            };
        }

        return {
            value: [],
            description: '',
            del: false,
            species: [],
        };
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
        renameCallback,
        form,
        formSubmit,
    } = useAdmin(
        'Section',
        id,
        sections,
        updateSection,
        toUpsertFields,
        { keyProp: 'name', delEndpoint: '../api/taxonomy/', upsertEndpoint: '../api/taxonomy/upsert' },
        schema,
        updatedFormFields,
    );

    const router = useRouter();

    return (
        <Admin
            type="Section"
            keyField="name"
            editName={{ getDefault: () => selected?.name, renameCallback: renameCallback(formSubmit) }}
            setShowModal={setShowRenameModal}
            showModal={showRenameModal}
            setError={setError}
            error={error}
            setDeleteResults={setDeleteResults}
            deleteResults={deleteResults}
        >
            <form onSubmit={form.handleSubmit(formSubmit)} className="m-4 pr-4">
                <h4>Add or Edit a Section</h4>
                <p>This is only for host sections. Currently we do not support sections for gallmakers.</p>
                <Row className="form-group">
                    <Col>
                        <Row>
                            <Col xs={8}>Name:</Col>
                        </Row>
                        <Row>
                            <Col>
                                <ControlledTypeahead
                                    control={form.control}
                                    name="value"
                                    placeholder="Name"
                                    options={data}
                                    labelKey="name"
                                    clearButton
                                    isInvalid={!!form.errors.value}
                                    newSelectionPrefix="Add a new Section: "
                                    allowNew={true}
                                    onChangeWithNew={(e, isNew) => {
                                        if (isNew || !e[0]) {
                                            setSelected(undefined);
                                            router.replace(``, undefined, { shallow: true });
                                        } else {
                                            setSelected(e[0]);
                                            router.replace(`?id=${e[0].id}`, undefined, { shallow: true });
                                        }
                                    }}
                                />
                                {form.errors.value && hasProp(form.errors.value, 'message') && (
                                    <span className="text-danger">{form.errors.value.message as string}</span>
                                )}
                            </Col>
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
                        Description:
                        <textarea
                            name="description"
                            placeholder="A short friendly name/description, e.g., Red Oaks"
                            className="form-control"
                            ref={form.register}
                            rows={1}
                        />
                        {form.errors.description && <span className="text-danger">{form.errors.description.message}</span>}
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Species:
                        <ControlledTypeahead
                            control={form.control}
                            name="species"
                            placeholder="Mapped Species"
                            options={hosts}
                            labelKey="name"
                            clearButton
                            multiple
                        />
                        {form.errors.species && hasProp(form.errors.species, 'message') && (
                            <span className="text-danger">{form.errors.species.message as string}</span>
                        )}
                        <p>
                            The species that you add should all be from the same genus. If they are not then you will not be able
                            to save. If this is a new Section, then the correct Genus will be assigned based on the species that
                            have been added.
                        </p>
                    </Col>
                </Row>
                <Row className="form-group" hidden={!selected}>
                    <Col xs="1">Delete?:</Col>
                    <Col className="mr-auto">
                        <input name="del" type="checkbox" className="form-check-input" ref={form.register} />
                    </Col>
                </Row>
                <Row className="form-input">
                    <Col>
                        <input type="submit" className="button" value="Submit" />
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
            sections: await mightFailWithArray<TaxonomyEntry>()(allSections()),
            genera: await mightFailWithArray<TaxonomyEntry>()(allGenera(HostTaxon)),
            hosts: await mightFailWithArray<HostApi>()(allHosts()),
        },
    };
};
export default Section;
