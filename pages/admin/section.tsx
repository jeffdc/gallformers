import axios from 'axios';
import * as O from 'fp-ts/lib/Option.js';
import { constant, pipe } from 'fp-ts/lib/function.js';
import * as t from 'io-ts';
import { GetServerSideProps } from 'next';
import { ParsedUrlQuery } from 'querystring';
import { useCallback, useEffect, useState } from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import { Path } from 'react-hook-form';
import { AsyncTypeahead } from '../../components/Typeahead.js';
import { RenameEvent } from '../../components/editname.js';
import { AdminFormFields, adminFormFieldsSchema } from '../../hooks/useAPIs.js';
import useAdmin from '../../hooks/useadmin.js';
import { extractQueryParam } from '../../libs/api/apipage.js';
import {
    SimpleSpecies,
    TaxSection,
    TaxSectionSchema,
    TaxonCodeValues,
    TaxonomyEntry,
    TaxonomyTypeValues,
    TaxonomyUpsertFields,
} from '../../libs/api/apitypes.js';
import { allGenera, allSections } from '../../libs/db/taxonomy.js';
import Admin from '../../libs/pages/admin.js';
import { extractGenus, hasProp, mightFailWithArray } from '../../libs/utils/util.js';

const schema = t.intersection([adminFormFieldsSchema(TaxSectionSchema), TaxSectionSchema]);

// const schema = yup.object().shape({
//     mainField: yup.array().required('A name is required.'),
//     description: yup.string().required('A description is required.'),
//     species: yup
//         .array()
//         .required('At least one species must be selected.')
//         .of(SpeciesSchema)
//         .test('same genus', 'You must select at least one species and all selected species must be of the same genus', (v) => {
//             return new Set(v?.map((s) => (s.name ? extractGenus(s?.name) : undefined))).size === 1;
//         }),
// });

type Props = {
    id: string;
    sections: TaxonomyEntry[];
    genera: TaxonomyEntry[];
    // hosts: HostApi[];
};

type FormFields = AdminFormFields<TaxSection> & Omit<TaxSection, 'id' | 'name' | 'type'>;

const renameSection = async (s: TaxSection, e: RenameEvent) => ({
    ...s,
    name: e.new,
});

const Section = ({ id, sections, genera }: Props): JSX.Element => {
    const [species, setSpecies] = useState<SimpleSpecies[]>([]);
    const [hosts, setHosts] = useState<SimpleSpecies[]>([]);
    const [isLoading, setIsLoading] = useState(false);

    const toUpsertFields = (fields: FormFields, name: string, id: number): TaxonomyUpsertFields => {
        return {
            name: name,
            description: fields.description,
            type: TaxonomyTypeValues.SECTION,
            id: id,
            species: fields.species.map((s) => s.id),
            parent: O.fromNullable(genera.find((g) => g.name.localeCompare(extractGenus(fields.species[0].name)) == 0)),
        };
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
        type: TaxonomyTypeValues.SECTION,
    });

    const {
        data,
        selected,
        showRenameModal,
        setShowRenameModal,
        isValid,
        error,
        setError,
        deleteResults,
        setDeleteResults,
        renameCallback,
        nameExists,
        form,
        formSubmit,
        mainField,
        deleteButton,
    } = useAdmin(
        'Section',
        id,
        renameSection,
        toUpsertFields,
        {
            keyProp: 'name',
            delEndpoint: '/api/taxonomy/',
            upsertEndpoint: '/api/taxonomy/upsert',
            nameExistsEndpoint: (s: string) => `/api/taxonomy/section?name=${s}`,
        },
        schema,
        updatedFormFields,
        false,
        createNewSection,
        // hack for now until I figure out how to switch away from the TaxSection type.
        sections as unknown as unknown as TaxSection[],
    );

    const fetchSectionSpecies = useCallback(
        async (sec: TaxSection): Promise<SimpleSpecies[]> => {
            if (!data.find((s) => s.id == sec.id)) {
                return [];
            }

            return axios
                .get<SimpleSpecies[]>(`/api/taxonomy/section/${sec.id}`)
                .then((res) => res.data)
                .catch((e) => {
                    console.error(e);
                    throw new Error('Failed to fetch species for the selected section. Check console.', e);
                });
        },
        [data],
    );

    useEffect(() => {
        const updateSpecies = async () => {
            if (selected) {
                setSpecies(await fetchSectionSpecies(selected));
            }
        };
        updateSpecies();
    }, [fetchSectionSpecies, selected]);

    const handleSearch = (s: string) => {
        setIsLoading(true);

        axios
            .get<SimpleSpecies[]>(`/api/host?q=${s}&simple`)
            .then((resp) => {
                // filter out ones that are already selected since this is multi-select
                const d = resp.data.filter((s) => !species.find((sp) => sp.id === s.id));
                setHosts(d);
                setIsLoading(false);
            })
            .catch((e) => {
                console.error(e);
            });
    };

    return (
        <Admin
            type="Section"
            keyField="name"
            editName={{ getDefault: () => selected?.name, renameCallback: renameCallback, nameExistsCallback: nameExists }}
            setShowModal={setShowRenameModal}
            showModal={showRenameModal}
            setError={setError}
            error={error}
            setDeleteResults={setDeleteResults}
            deleteResults={deleteResults}
            selected={selected}
        >
            <form onSubmit={form.handleSubmit(formSubmit)} className="m-4 pe-4">
                <h4>Add or Edit a Section</h4>
                <p>This is only for host sections. Currently we do not support sections for gallformers.</p>
                <Row className="my-1">
                    <Col>
                        <Row>
                            <Col xs={8}>Name:</Col>
                        </Row>
                        <Row>
                            <Col>{mainField('name', 'Section', { searchEndpoint: (s) => `../api/taxonomy/section?q=${s}` })}</Col>
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
                <Row className="my-1">
                    <Col>
                        Description (required):
                        <textarea
                            {...form.register('description')}
                            placeholder="A short friendly name/description, e.g., Red Oaks"
                            className="form-control"
                            rows={1}
                            disabled={!selected}
                        />
                        {form.formState.errors.description && (
                            <span className="text-danger">{form.formState.errors.description.message}</span>
                        )}
                    </Col>
                </Row>
                <Row className="my-1">
                    <Col>
                        Species (required):
                        <AsyncTypeahead
                            name="species"
                            control={form.control}
                            options={hosts}
                            labelKey="name"
                            placeholder="Mapped Species"
                            clearButton
                            multiple
                            rules={{ required: true }}
                            isInvalid={!!form.formState.errors.species}
                            selected={species ? species : []}
                            onChange={(s) => {
                                setSpecies(s);
                                form.setValue('species' as Path<FormFields>, s);
                            }}
                            disabled={!selected}
                            isLoading={isLoading}
                            onSearch={handleSearch}
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
                        <input type="submit" className="button" value="Submit" disabled={!selected && !isValid} />
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
    const id = pipe(extractQueryParam(context.query, queryParam), O.getOrElse(constant('')));

    return {
        props: {
            id: id,
            sections: await mightFailWithArray<TaxonomyEntry>()(allSections()),
            genera: await mightFailWithArray<TaxonomyEntry>()(allGenera(TaxonCodeValues.PLANT)),
            // hosts: await mightFailWithArray<HostApi>()(allHosts()),
        },
    };
};
export default Section;
