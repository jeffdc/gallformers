import axios from 'axios';
import * as O from 'fp-ts/lib/Option';
import { constant } from 'fp-ts/lib/function';
import { GetServerSideProps } from 'next';
import { useState } from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import { RenameEvent } from '../../components/editname';
import useAdmin, { AdminFormFields } from '../../hooks/useadmin';
import { DeleteResult, FilterField, FilterFieldTypeValue, FilterFieldWithType, asFilterType } from '../../libs/api/apitypes';
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

type FormFields = AdminFormFields<FilterField> & {
    fieldType: string;
    description: string;
};

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

    const updatedFormFields = async (e: FilterField | undefined): Promise<FormFields> => {
        if (e != undefined) {
            return {
                mainField: [e],
                description: O.getOrElse(constant(''))(e.description),
                del: false,
                fieldType: fieldType,
            };
        }

        return {
            mainField: [],
            description: '',
            del: false,
            fieldType: '',
        };
    };

    const toUpsertFields = (fields: FormFields, field: string, id: number): FilterFieldWithType => {
        return {
            id: id,
            field: field,
            fieldType: fieldType,
            description: O.of(fields.description),
        };
    };

    const doDelete = async (fields: FormFields) => {
        if (fields.del) {
            axios
                .delete<DeleteResult>(`/api/filterfield/${fieldType}/${fields.mainField[0].id}`)
                .then((res) => {
                    setSelected(undefined);
                    adminForm.setDeleteResults(res.data);
                })
                .catch((e) => {
                    console.error(e.toString());
                    adminForm.setError(e.toString());
                });
        }
    };

    const { setData, selected, setSelected, renameCallback, nameExists, ...adminForm } = useAdmin(
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
            selected={selected}
            superAdmin={true}
            {...adminForm}
            deleteButton={adminForm.deleteButton('Caution. The filter field will deleted.', true, doDelete)}
            saveButton={adminForm.saveButton()}
        >
            <>
                <h4>Add/Edit Filter Fields</h4>
                <Row className="my-1">
                    <Col>
                        <select
                            {...adminForm.form.register('fieldType', {
                                onChange: (e) => {
                                    setSelected(undefined);
                                    setFieldType(asFilterType(e.currentTarget.value));
                                    setData(dataFromSelection(e.currentTarget.value));
                                },
                                required: 'You must select a field type.',
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
                <Row className="my-1">
                    <Col>
                        <Row>
                            <Col>Word:</Col>
                        </Row>
                        <Row>
                            <Col>{adminForm.mainField('Field')}</Col>
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
                            {adminForm.form.formState.errors.mainField && (
                                <span className="text-danger" title="mainField-error">
                                    {`The main field is invalid. Error: ${adminForm.form.formState.errors.mainField.message}`}
                                </span>
                            )}
                        </Row>
                    </Col>
                </Row>
                <Row className="my-1">
                    <Col>
                        Description (required):
                        <textarea
                            {...adminForm.form.register('description', {
                                onChange: (e) => {
                                    if (selected) {
                                        selected.description = O.some(e.currentTarget.value);
                                        setSelected({ ...selected });
                                        // form.setValue('description', e.currentTarget.value, { shouldDirty: true });
                                    }
                                },
                                required: true,
                                value: selected?.description ? O.getOrElse(constant(''))(selected.description) : '',
                                disabled: !selected,
                            })}
                            placeholder="description"
                            className="form-control"
                            rows={4}
                        />
                        {adminForm.form.formState.errors.description && (
                            <span className="text-danger" title="description-error">
                                You must provide the description. Even for color, even though it will not be saved for color.
                            </span>
                        )}
                    </Col>
                </Row>
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
