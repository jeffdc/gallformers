import axios from 'axios';
import * as O from 'fp-ts/lib/Option';
import { constant } from 'fp-ts/lib/function';
import * as t from 'io-ts';
import * as tt from 'io-ts-types';
import { GetServerSideProps } from 'next';
import { useState } from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import { Controller } from 'react-hook-form';
import { RenameEvent } from '../../components/editname';
import useAdmin, { AdminFormFields, adminFormFieldsSchema } from '../../hooks/useadmin';
import {
    DeleteResult,
    FilterField,
    FilterFieldSchema,
    FilterFieldTypeValue,
    FilterFieldWithType,
    asFilterType,
} from '../../libs/api/apitypes';
import {
    getAlignments,
    getCells,
    getColors,
    getForms,
    getLocations,
    getShapes,
    getTextures,
    getWalls,
} from '../../libs/db/filterfield';
import Admin from '../../libs/pages/admin';
import { mightFailWithArray } from '../../libs/utils/util';

type FormFields = AdminFormFields<FilterField> & Pick<FilterField, 'description'> & { fieldType: string };

const schema = t.intersection([
    adminFormFieldsSchema(FilterFieldSchema),
    t.type({
        description: tt.option(t.string),
        fieldType: t.string,
    }),
]);

export type Props = {
    alignments: FilterField[];
    cells: FilterField[];
    colors: FilterField[];
    forms: FilterField[];
    locations: FilterField[];
    shapes: FilterField[];
    textures: FilterField[];
    walls: FilterField[];
};

const renameField = async (s: FilterField, e: RenameEvent): Promise<FilterField> => ({
    ...s,
    field: e.new,
});

const updatedFormFields = async (e: FilterField | undefined): Promise<FormFields> => {
    if (e != undefined) {
        return {
            mainField: [e],
            description: e.description,
            del: false,
        };
    }

    return {
        mainField: [],
        description: O.none,
        del: false,
    };
};

const createNewFilterField = (field: string): FilterField => ({
    field: field,
    description: O.none,
    id: -1,
});

const keyFieldName = 'field';

const FilterTerms = ({ alignments, cells, colors, forms, locations, shapes, textures, walls }: Props): JSX.Element => {
    const [fieldType, setFieldType] = useState(FilterFieldTypeValue.ALIGNMENTS);

    const dataFromSelection = (field: string): FilterField[] => {
        switch (field) {
            case 'alignments':
                return alignments;
            case 'cells':
                return cells;
            case 'colors':
                return colors;
            case 'forms':
                return forms;
            case 'locations':
                return locations;
            case 'shapes':
                return shapes;
            case 'textures':
                return textures;
            case 'walls':
                return walls;
            default:
                return [];
        }
    };

    const toUpsertFields = (fields: FormFields, field: string, id: number): FilterFieldWithType => {
        return {
            ...fields,
            id: id,
            field: field,
            fieldType: fieldType,
        };
    };

    const doDelete = async (fields: FormFields) => {
        if (fields.del) {
            axios
                .delete<DeleteResult>(`/api/filterfield/${fieldType}/${fields.mainField[0].id}`)
                .then((res) => {
                    setSelected(undefined);
                    setDeleteResults(res.data);
                })
                .catch((e) => {
                    console.error(e.toString());
                    setError(e.toString());
                });
        }
    };

    const {
        setData,
        selected,
        setSelected,
        showRenameModal: showModal,
        setShowRenameModal: setShowModal,
        isValid,
        error,
        errors,
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
        'Filter Fields',
        keyFieldName,
        '',
        renameField,
        toUpsertFields,
        {
            delEndpoint: `/api/filterfield/${fieldType}`,
            upsertEndpoint: '/api/filterfield/upsert',
            nameExistsEndpoint: (s: string) => `/api/filterfield/${fieldType}?name=${s}`,
        },
        schema,
        updatedFormFields,
        false,
        createNewFilterField,
        alignments,
    );

    return (
        <Admin
            type="FilterTerms"
            keyField={keyFieldName}
            editName={{ getDefault: () => selected?.field, renameCallback: renameCallback, nameExistsCallback: nameExists }}
            setShowModal={setShowModal}
            showModal={showModal}
            setError={setError}
            error={error}
            setDeleteResults={setDeleteResults}
            deleteResults={deleteResults}
            selected={selected}
            superAdmin={true}
        >
            <>
                <form className="m-4 pe-4">
                    <h4>Add/Edit Filter Fields</h4>
                    <Row className="my-1">
                        <Col>
                            <select
                                {...form.register('fieldType', {
                                    onChange: (e) => {
                                        setSelected(undefined);
                                        setFieldType(asFilterType(e.currentTarget.value));
                                        setData(dataFromSelection(e.currentTarget.value));
                                    },
                                })}
                                title="fieldType"
                                className="form-control"
                            >
                                {/* Do not show seasons since they are fixed. */}
                                {Object.values(FilterFieldTypeValue)
                                    .filter((ff) => ff.localeCompare('seasons'))
                                    .map((ff) => (
                                        <option key={ff}>{ff}</option>
                                    ))}
                            </select>
                        </Col>
                    </Row>
                </form>
                <form onSubmit={form.handleSubmit(formSubmit)} className="m-4 pe-4">
                    <Row className="my-1">
                        <Col>
                            <Row>
                                <Col>Word:</Col>
                            </Row>
                            <Row>
                                <Col>{mainField('Field')}</Col>
                                {selected && (
                                    <Col xs={1}>
                                        <Button variant="secondary" className="btn-sm" onClick={() => setShowModal(true)}>
                                            Rename
                                        </Button>
                                    </Col>
                                )}
                                {errors.mainField && (
                                    <span className="text-danger" title="mainField-error">
                                        {`The main field is invalid. Error: ${errors.mainField.message}`}
                                    </span>
                                )}
                            </Row>
                        </Col>
                    </Row>
                    <Row className="my-1">
                        <Col>
                            Description:
                            <Controller
                                control={form.control}
                                name="description"
                                rules={{ required: true }}
                                render={({ field: { ref } }) => (
                                    <textarea
                                        title="description"
                                        placeholder="description"
                                        ref={ref}
                                        className="form-control"
                                        rows={4}
                                        disabled={!selected}
                                        value={selected?.description ? O.getOrElse(constant(''))(selected.description) : ''}
                                        onChange={(e) => {
                                            if (selected) {
                                                selected.description = O.some(e.currentTarget.value);
                                                setSelected({ ...selected });
                                            }
                                        }}
                                    />
                                )}
                            />
                            {errors.description && (
                                <span className="text-danger" title="description-error">
                                    You must provide the definition. Even for color, even though it will not be saved for color.
                                </span>
                            )}
                        </Col>
                    </Row>
                    <Row className="form-input">
                        <Col>
                            <Button variant="primary" type="submit" value="Save Changes" disabled={!selected || !isValid}>
                                Save Changes
                            </Button>
                        </Col>
                        <Col>{deleteButton('Caution. The filter field will deleted.', doDelete)}</Col>
                    </Row>
                </form>
            </>
        </Admin>
    );
};

export const getServerSideProps: GetServerSideProps = async () => {
    return {
        props: {
            alignments: await mightFailWithArray<FilterField>()(getAlignments()),
            cells: await mightFailWithArray<FilterField>()(getCells()),
            colors: await mightFailWithArray<FilterField>()(getColors()),
            forms: await mightFailWithArray<FilterField>()(getForms()),
            locations: await mightFailWithArray<FilterField>()(getLocations()),
            shapes: await mightFailWithArray<FilterField>()(getShapes()),
            textures: await mightFailWithArray<FilterField>()(getTextures()),
            walls: await mightFailWithArray<FilterField>()(getWalls()),
        },
    };
};
export default FilterTerms;
