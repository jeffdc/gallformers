import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import { useRouter } from 'next/router';
import { ParsedUrlQuery } from 'querystring';
import React, { useState } from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import * as yup from 'yup';
import ControlledTypeahead from '../../components/controlledtypeahead';
import useAdmin from '../../hooks/useadmin';
import { AdminFormFields } from '../../hooks/useAPIs';
import { extractQueryParam } from '../../libs/api/apipage';
import { SimpleSpecies } from '../../libs/api/apitypes';
import { TaxonomyEntry, TaxonomyUpsertFields } from '../../libs/api/taxonomy';
import { allSpeciesSimple } from '../../libs/db/species';
import { allSections, getAllSpeciesForSection } from '../../libs/db/taxonomy';
import Admin from '../../libs/pages/admin';
import { mightFailWithArray } from '../../libs/utils/util';

const schema = yup.object().shape({
    value: yup.mixed().required(),
    description: yup.string().required(),
});

type Props = {
    id: string;
    sectSpecies: SimpleSpecies[];
    sections: TaxonomyEntry[];
    allSpecies: SimpleSpecies[];
};

type FormFields = (AdminFormFields<TaxonomyEntry> & Omit<TaxonomyEntry, 'id' | 'name'>) & { species: SimpleSpecies[] };

const updateSection = (s: TaxonomyEntry, newValue: string) => ({
    ...s,
    name: newValue,
});

const emptyForm = {
    value: [],
    description: '',
};

const convertToFields = (sp: SimpleSpecies[]) => (s: TaxonomyEntry): FormFields => ({
    ...s,
    del: false,
    value: [s],
    species: sp,
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

const toUpsertFields = (fields: FormFields, name: string, id: number): TaxonomyUpsertFields => {
    return {
        ...fields,
        name: name,
        type: 'section',
        id: id,
        species: fields.species.map((s) => s.id),
    };
};

const Section = ({ id, sectSpecies, sections, allSpecies }: Props): JSX.Element => {
    const [selectedSpecies, setSelectedSpecies] = useState(sectSpecies);
    const onDataChangeCallback = async (sec: TaxonomyEntry | undefined): Promise<TaxonomyEntry | undefined> => {
        if (sec != undefined) {
            const s = await fetchSectionSpecies(sec);
            setSelectedSpecies(s);
        }
        return sec;
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
        convertToFields(selectedSpecies),
        toUpsertFields,
        { keyProp: 'name', delEndpoint: '../api/taxonomy/', upsertEndpoint: '../api/taxonomy/upsert' },
        schema,
        emptyForm,
        onDataChangeCallback,
    );

    const router = useRouter();

    const onSubmit = async (fields: FormFields) => {
        await formSubmit(fields);
    };

    return (
        <Admin
            type="Section"
            keyField="name"
            editName={{ getDefault: () => selected?.name, renameCallback: renameCallback(onSubmit) }}
            setShowModal={setShowRenameModal}
            showModal={showRenameModal}
            setError={setError}
            error={error}
            setDeleteResults={setDeleteResults}
            deleteResults={deleteResults}
        >
            <form onSubmit={form.handleSubmit(onSubmit)} className="m-4 pr-4">
                <h4>Add or Edit a Section</h4>
                <Row className="form-group">
                    <Col>
                        <Row>
                            <Col>Name:</Col>
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
                                {form.errors.value && <span className="text-danger">The Name is required.</span>}
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
                        <textarea name="description" className="form-control" ref={form.register} rows={1} />
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Species:
                        <ControlledTypeahead
                            control={form.control}
                            name="species"
                            placeholder="Mapped Species"
                            options={allSpecies}
                            labelKey="name"
                            clearButton
                            multiple
                        />
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
    const { id, sectSpecies } = await pipe(
        extractQueryParam(context.query, queryParam),
        O.map(parseInt),
        O.map((id) => {
            const species = getAllSpeciesForSection(id);
            return { id: id, sectSpecies: species };
        }),
        O.map(async ({ id, sectSpecies }) => ({
            id: id.toString(),
            sectSpecies: await mightFailWithArray<SimpleSpecies>()(sectSpecies),
        })),
        O.getOrElse(constant(Promise.resolve({ id: '', sectSpecies: new Array<SimpleSpecies>() }))),
    );

    return {
        props: {
            id: id,
            sectSpecies: sectSpecies,
            sections: await mightFailWithArray<TaxonomyEntry>()(allSections()),
            allSpecies: await mightFailWithArray<SimpleSpecies>()(allSpeciesSimple()),
        },
    };
};
export default Section;
