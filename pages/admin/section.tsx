import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import { ParsedUrlQuery } from 'querystring';
import React, { useState } from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import { Path } from 'react-hook-form';
import * as yup from 'yup';
import { RenameEvent } from '../../components/editname';
import Typeahead from '../../components/Typeahead';
import useAdmin from '../../hooks/useadmin';
import { AdminFormFields } from '../../hooks/useAPIs';
import { extractQueryParam } from '../../libs/api/apipage';
import { HostApi, HostTaxon, SimpleSpecies } from '../../libs/api/apitypes';
import { SECTION, TaxonomyEntry, TaxonomyUpsertFields } from '../../libs/api/taxonomy';
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
    mainField: yup.array().required('A name is required.'),
    description: yup.string().required('A description is required.'),
    species: yup
        .array()
        .required('At least one species must be selected.')
        .of(SpeciesSchema)
        .test('same genus', 'All species must be of the same genus', (v) => {
            return new Set(v?.map((s) => (s.name ? extractGenus(s?.name) : undefined))).size === 1;
        }),
});

type TaxSection = Omit<TaxonomyEntry, 'parent'> & {
    species: SimpleSpecies[];
};

type Props = {
    id: string;
    sections: TaxonomyEntry[];
    genera: TaxonomyEntry[];
    hosts: HostApi[];
};

type FormFields = AdminFormFields<TaxSection> & Omit<TaxSection, 'id' | 'name' | 'type'>;

const renameSection = async (s: TaxSection, e: RenameEvent) => ({
    ...s,
    name: e.new,
});

const Section = ({ id, sections: unconvertedSections, genera, hosts }: Props): JSX.Element => {
    const sections: TaxSection[] = unconvertedSections.map((s) => ({
        ...s,
        species: [],
    }));

    const [species, setSpecies] = useState<Array<SimpleSpecies>>([]);

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

    const fetchSectionSpecies = async (sec: TaxSection): Promise<SimpleSpecies[]> => {
        if (!sections.find((s) => s.id == sec.id)) {
            return [];
        }

        const res = await fetch(`../api/taxonomy/section/${sec.id}`);
        if (res.status === 200) {
            return (await res.json()) as SimpleSpecies[];
        } else {
            console.error(await res.text());
            throw new Error('Failed to fetch species for the selected section. Check console.');
        }
    };

    const updatedFormFields = async (sec: TaxSection | undefined): Promise<FormFields> => {
        if (sec != undefined) {
            const s = await fetchSectionSpecies(sec);
            setSpecies(s);
            return {
                ...sec,
                del: false,
                mainField: [sec],
                species: s,
            };
        }

        setSpecies([]);
        return {
            mainField: [],
            description: '',
            del: false,
            species: [],
        };
    };

    const createNewSection = (name: string): TaxSection => ({
        name: name,
        description: '',
        id: -1,
        species: [],
        type: SECTION,
    });

    const {
        selected,
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
        'Section',
        id,
        sections,
        renameSection,
        toUpsertFields,
        { keyProp: 'name', delEndpoint: '../api/taxonomy/', upsertEndpoint: '../api/taxonomy/upsert' },
        schema,
        updatedFormFields,
        false,
        createNewSection,
    );

    return (
        <Admin
            type="Section"
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
            <form onSubmit={form.handleSubmit(formSubmit)} className="m-4 pr-4">
                <h4>Add or Edit a Section</h4>
                <p>This is only for host sections. Currently we do not support sections for gallmakers.</p>
                <Row className="form-group">
                    <Col>
                        <Row>
                            <Col xs={8}>Name:</Col>
                        </Row>
                        <Row>
                            <Col>{mainField('name', 'Section')}</Col>
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
                            {...form.register('description')}
                            placeholder="A short friendly name/description, e.g., Red Oaks"
                            className="form-control"
                            rows={1}
                        />
                        {form.formState.errors.description && (
                            <span className="text-danger">{form.formState.errors.description.message}</span>
                        )}
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Species:
                        <Typeahead
                            name="species"
                            control={form.control}
                            options={hosts}
                            labelKey="name"
                            placeholder="Mapped Species"
                            clearButton
                            multiple
                            isInvalid={!!form.formState.errors.species}
                            selected={species ? species : []}
                            onChange={(s) => {
                                setSpecies(s);
                                form.setValue('species' as Path<FormFields>, s);
                            }}
                        />
                        {form.formState.errors.species && hasProp(form.formState.errors.species, 'message') && (
                            <span className="text-danger">{form.formState.errors.species.message as string}</span>
                        )}
                        <p>
                            The species that you add should all be from the same genus. If they are not then you will not be able
                            to save. If this is a new Section, then the correct Genus will be assigned based on the species that
                            have been added.
                        </p>
                    </Col>
                </Row>
                <Row className="form-input">
                    <Col>
                        <input type="submit" className="button" value="Submit" disabled={!selected} />
                    </Col>
                    <Col>{deleteButton('Caution. The Section will be deleted.')}</Col>
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
