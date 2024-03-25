import axios from 'axios';
import * as O from 'fp-ts/lib/Option';
import { constant, pipe } from 'fp-ts/lib/function';
import { GetServerSideProps } from 'next';
import { ParsedUrlQuery } from 'querystring';
import { useCallback, useEffect, useState } from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import { Controller, Path } from 'react-hook-form';
import { RenameEvent } from '../../components/editname';
import useAdmin, { AdminFormFields } from '../../hooks/useadmin';
import { extractQueryParam } from '../../libs/api/apipage';
import {
    SimpleSpecies,
    TaxSection,
    TaxonCodeValues,
    TaxonomyEntry,
    TaxonomyTypeValues,
    TaxonomyUpsertFields,
} from '../../libs/api/apitypes';
import { allGenera, allSections } from '../../libs/db/taxonomy';
import Admin from '../../libs/pages/admin';
import { extractGenus, hasProp, mightFailWithArray } from '../../libs/utils/util';
import { AsyncTypeahead } from 'react-bootstrap-typeahead';

type Props = {
    id: string;
    sections: TaxonomyEntry[];
    genera: TaxonomyEntry[];
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

    const keyFieldName = 'name';

    const { data, selected, renameCallback, nameExists, ...adminForm } = useAdmin(
        'Section',
        keyFieldName,
        id,
        renameSection,
        toUpsertFields,
        {
            delEndpoint: '/api/taxonomy/',
            upsertEndpoint: '/api/taxonomy/upsert',
            nameExistsEndpoint: (s: string) => `/api/taxonomy/section?name=${s}`,
        },
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
            selected={selected}
            {...adminForm}
            deleteButton={adminForm.deleteButton('Caution. The Section will be deleted.', true)}
            saveButton={adminForm.saveButton()}
        >
            <>
                <h4>Add or Edit a Section</h4>
                <p>This is only for host sections. Currently we do not support sections for gallformers.</p>
                <Row className="my-1">
                    <Col>
                        <Row>
                            <Col xs={8}>Name:</Col>
                        </Row>
                        <Row>
                            <Col>
                                {adminForm.mainField('Section', { searchEndpoint: (s) => `../api/taxonomy/section?q=${s}` })}
                            </Col>
                            {selected && (
                                <Col xs={1}>
                                    <Button
                                        variant="secondary"
                                        className="btn-sm"
                                        onClick={() => adminForm.setShowRenameModal(true)}
                                    >
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
                            {...adminForm.form.register('description', {
                                required: 'A description is required.',
                                disabled: !selected,
                            })}
                            placeholder="A short friendly name/description, e.g., Red Oaks"
                            className="form-control"
                            rows={1}
                        />
                        {adminForm.form.formState.errors.description && (
                            <span className="text-danger">{adminForm.form.formState.errors.description.message}</span>
                        )}
                    </Col>
                </Row>
                <Row className="my-1">
                    <Col>
                        Species (required):
                        <Controller
                            control={adminForm.form.control}
                            name="species"
                            rules={{
                                validate: (s) => {
                                    console.log(`JDC: ${JSON.stringify(s, null, '  ')}`);
                                    return s.length > 0 ? true : 'At least one species is required.';
                                },
                            }}
                            // rules={ minLength: { value: 1, message: 'At least one species is required.' } }
                            render={() => (
                                <AsyncTypeahead
                                    id="species"
                                    options={hosts}
                                    labelKey="name"
                                    placeholder="Mapped Species"
                                    clearButton
                                    disabled={!selected}
                                    multiple
                                    onChange={(s) => {
                                        setSpecies(s as SimpleSpecies[]);
                                        adminForm.form.setValue('species' as Path<FormFields>, s as SimpleSpecies[]);
                                    }}
                                    selected={species ? species : []}
                                    isLoading={isLoading}
                                    onSearch={handleSearch}
                                />
                            )}
                        />
                        {adminForm.form.formState.errors.species &&
                            hasProp(adminForm.form.formState.errors.species, 'message') && (
                                <span className="text-danger">{adminForm.form.formState.errors.species.message}</span>
                            )}
                        <p>
                            The species that you add should all be from the same genus. If they are not then you will not be able
                            to save. If this is a new Section, then the correct Genus will be assigned based on the species that
                            have been added.
                        </p>
                    </Col>
                </Row>
            </>
        </Admin>
    );
};

export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery }) => {
    const queryParam = 'id';
    const id = pipe(extractQueryParam(context.query, queryParam), O.getOrElse(constant('')));

    return {
        props: {
            id: id,
            sections: await mightFailWithArray<TaxonomyEntry>()(allSections()),
            genera: await mightFailWithArray<TaxonomyEntry>()(allGenera(TaxonCodeValues.PLANT)),
        },
    };
};
export default Section;
