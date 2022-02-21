import { constant, constFalse, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import React, { useState } from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import { Controller } from 'react-hook-form';
import * as yup from 'yup';
import { RenameEvent } from '../../components/editname';
import useAdmin from '../../hooks/useadmin';
import { AdminFormFields } from '../../hooks/useAPIs';
import {
    asFilterFieldType,
    FilterField,
    FilterFieldWithType,
    FILTER_FIELD_ALIGNMENTS,
    FILTER_FIELD_TYPES,
} from '../../libs/api/apitypes';
import { getAlignments, getCells, getForms, getLocations, getShapes, getTextures, getWalls } from '../../libs/db/filterfield';
import Admin from '../../libs/pages/admin';
import { mightFailWithArray } from '../../libs/utils/util';

const schema = yup.object().shape({
    mainField: yup.mixed().required(),
    description: yup.mixed().test('definition', 'must not be empty', (value: O.Option<string>) => {
        return (
            value &&
            pipe(
                value,
                O.fold(constFalse, (d) => !!d && d.length > 0),
            )
        );
    }),
});

type Props = {
    alignments: FilterField[];
    cells: FilterField[];
    forms: FilterField[];
    locations: FilterField[];
    shapes: FilterField[];
    textures: FilterField[];
    walls: FilterField[];
};

type FormFields = AdminFormFields<FilterField> & Pick<FilterField, 'description'>;

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

const FilterTerms = ({ alignments, cells, forms, locations, shapes, textures, walls }: Props): JSX.Element => {
    const [fieldType, setFieldType] = useState(FILTER_FIELD_ALIGNMENTS);

    const dataFromSelection = (field: string): FilterField[] => {
        switch (field) {
            case 'alignments':
                return alignments;
            case 'cells':
                return cells;
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
            fieldType: asFilterFieldType(fieldType),
        };
    };

    const doDelete = async (fields: FormFields) => {
        try {
            if (fields.del) {
                const res = await fetch(`../api/filterfield?id=${fields.mainField[0].id}&fieldType=${fieldType}`, {
                    method: 'DELETE',
                });

                if (res.status === 200) {
                    setSelected(undefined);
                    const dr = await res.json();
                    setDeleteResults(dr);
                    return;
                } else {
                    throw new Error(await res.text());
                }
            }
        } catch (e) {
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            const err: any = e;
            console.error(err);
            setError(err.toString());
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
        setError,
        deleteResults,
        setDeleteResults,
        renameCallback,
        form,
        formSubmit,
        mainField,
        deleteButton,
    } = useAdmin(
        'Filter Fields',
        '',
        alignments,
        renameField,
        toUpsertFields,
        { keyProp: 'field', delEndpoint: '../api/filterfield/', upsertEndpoint: '../api/filterfield/upsert' },
        schema,
        updatedFormFields,
        false,
        createNewFilterField,
    );

    return (
        <Admin
            type="Place"
            keyField="word"
            editName={{ getDefault: () => selected?.field, renameCallback: renameCallback }}
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
                                className="form-control"
                                onChange={(e) => {
                                    setSelected(undefined);
                                    setFieldType(e.currentTarget.value);
                                    setData(dataFromSelection(e.currentTarget.value));
                                }}
                            >
                                {FILTER_FIELD_TYPES.filter((ff) => ff.localeCompare('seasons')).map((ff) => (
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
                                <Col>{mainField('field', 'Field')}</Col>
                                {selected && (
                                    <Col xs={1}>
                                        <Button variant="secondary" className="btn-sm" onClick={() => setShowModal(true)}>
                                            Rename
                                        </Button>
                                    </Col>
                                )}
                            </Row>
                        </Col>
                    </Row>
                    <Row className="my-1">
                        <Col>
                            Definition (required):
                            <Controller
                                control={form.control}
                                name="description"
                                rules={{ required: true }}
                                render={({ field: { ref } }) => (
                                    <textarea
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
                            {form.formState.errors.description && (
                                <span className="text-danger">You must provide the defintion.</span>
                            )}
                        </Col>
                    </Row>
                    <Row className="form-input">
                        <Col>
                            <input type="submit" className="button" value="Submit" disabled={!selected || !isValid} />
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
            forms: await mightFailWithArray<FilterField>()(getForms()),
            locations: await mightFailWithArray<FilterField>()(getLocations()),
            shapes: await mightFailWithArray<FilterField>()(getShapes()),
            textures: await mightFailWithArray<FilterField>()(getTextures()),
            walls: await mightFailWithArray<FilterField>()(getWalls()),
        },
    };
};
export default FilterTerms;
