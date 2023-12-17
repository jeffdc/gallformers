import axios from 'axios';
import * as O from 'fp-ts/lib/Option';
import { constant, pipe } from 'fp-ts/lib/function';
import * as t from 'io-ts';
import * as tt from 'io-ts-types';
import { GetServerSideProps } from 'next';
import { ParsedUrlQuery } from 'querystring';
import { useEffect, useState } from 'react';
import { Button, Col, Form, FormGroup, Row } from 'react-bootstrap';
import 'react-simple-tree-menu/dist/main.css';
import EditableDataTable, { EditableTableColumn } from '../../components/EditableDataTable';
import { RenameEvent } from '../../components/editname';
import MoveFamily, { MoveEvent } from '../../components/movefamily';
import { AdminFormFields, adminFormFieldsSchema } from '../../hooks/useAPIs';
import useAdmin from '../../hooks/useadmin';
import { extractQueryParam } from '../../libs/api/apipage';
import { ALL_FAMILY_TYPES } from '../../libs/api/apitypes';
import {
    EMPTY_GENUS,
    FamilyAPI,
    FamilyAPISchema,
    FamilyUpsertFields,
    GeneraMoveFields,
    Genus,
    TaxonomyTypeValues,
} from '../../libs/api/apitypes';
import { familyById } from '../../libs/db/taxonomy';
import Admin from '../../libs/pages/admin';
import { TABLE_CUSTOM_STYLES } from '../../libs/utils/DataTableConstants';
import { genOptions } from '../../libs/utils/forms';
import { mightFailWithArray } from '../../libs/utils/util';

type FormFields = AdminFormFields<FamilyAPI> & Pick<FamilyAPI, 'description' | 'genera'>;

const schema = t.intersection([
    adminFormFieldsSchema(FamilyAPISchema),
    t.type({
        description: tt.NonEmptyString,
    }),
]);

type Props = {
    id: string;
    fs: FamilyAPI[];
};

const renameFamily = async (s: FamilyAPI, e: RenameEvent) => ({
    ...s,
    name: e.new,
});

const updatedFormFields = async (fam: FamilyAPI | undefined): Promise<FormFields> => {
    if (fam != undefined) {
        return {
            mainField: [fam],
            description: fam.description,
            del: false,
            genera: fam.genera,
        };
    }

    return {
        mainField: [],
        description: '',
        del: false,
        genera: [],
    };
};

const toUpsertFields = (fields: FormFields, name: string, id: number): FamilyUpsertFields => {
    return {
        ...fields,
        name: name,
        type: TaxonomyTypeValues.FAMILY,
        id: id,
        description: fields.description ?? '',
        genera: fields.genera ?? [],
    };
};

const createNewFamily = (name: string): FamilyAPI => ({
    name: name,
    description: '',
    id: -1,
    type: TaxonomyTypeValues.FAMILY,
    genera: [],
});

const columns: EditableTableColumn<Genus>[] = [
    {
        id: 'name',
        name: 'Genus',
        selector: (row: Genus) => row.name,
        sortable: true,
        wrap: true,
        maxWidth: '300px',
        editKey: 'name',
    },
    {
        id: 'description',
        name: 'Friendly Name',
        selector: (row: Genus) => row.description,
        wrap: true,
        editKey: 'description',
    },
];

const DELETE_CONFIRMATION_MSG = `The selected genera, ALL of the species in the genera, and all related data will 
    be deleted. Are you sure you want to do this? The change will not be made and saved until you Submit the 
    changes on the main page.`;

const FamilyAdmin = ({ id, fs }: Props): JSX.Element => {
    const {
        data,
        setData,
        selected,
        setSelected,
        showRenameModal,
        setShowRenameModal,
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
        isSuperAdmin,
    } = useAdmin(
        'Family',
        id,
        renameFamily,
        toUpsertFields,
        {
            keyProp: 'name',
            delEndpoint: '/api/taxonomy/family/',
            upsertEndpoint: '/api/taxonomy/family/upsert',
            nameExistsEndpoint: (s: string) => `/api/taxonomy/family?name=${s}`,
        },
        schema,
        updatedFormFields,
        false,
        createNewFamily,
        fs,
    );

    const [genera, setGenera] = useState<Genus[]>([]);
    const [showMoveFamily, setShowMoveFamily] = useState(false);
    const [generaToMove, setGeneraToMove] = useState<Genus[]>([]);

    const updateGeneraFromTable = (genera: Genus[]) => {
        if (selected) {
            setSelected({ ...selected, genera: genera });
        }
    };

    const moveSelected = (genera: Genus[]) => {
        setGeneraToMove(genera);
        setShowMoveFamily(true);
    };

    const move = async (e: MoveEvent) => {
        if (!selected) return;

        const data: GeneraMoveFields = {
            oldFamilyId: selected.id,
            newFamilyId: e.new.id,
            genera: generaToMove.map((g) => g.id),
        };

        axios
            .post<FamilyAPI[]>('/api/taxonomy/genus/move', {
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(data),
            })
            .then((res) => {
                const families = res.data;
                setData(families);
                setSelected(families.find((f) => f.id === selected.id));
                setGeneraToMove([]);
            })
            .catch((e) => {
                console.error(e);
                throw new Error(
                    `Failed to move genera. Check the console and open a new issue in Github copying any errors seen in the console as well as info about what you were doing when this occurred.`,
                    e,
                );
            });
    };

    useEffect(() => {
        const updateGenera = async () => {
            if (selected) {
                if (!data.find((s) => s.id == selected.id)) {
                    return [];
                }

                return axios
                    .get<Genus[]>(`/api/taxonomy/genus?famid=${selected.id}`)
                    .then((res) => setGenera(res.data))
                    .catch((e) => {
                        console.error(e);
                        throw new Error('Failed to fetch species for the selected section. Check console.', e);
                    });
            }
        };

        updateGenera();
    }, [data, selected]);

    return (
        <>
            {showMoveFamily && selected && (
                <MoveFamily
                    genera={generaToMove}
                    families={data}
                    showModal={showMoveFamily}
                    setShowModal={setShowMoveFamily}
                    moveCallback={move}
                />
            )}

            <Admin
                type="Taxonomy"
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
                    <h4>Manage Taxonomy</h4>
                    <Row className="my-1">
                        <Col>
                            <Form.Label>Family Name:</Form.Label>
                            {mainField('name', 'Family', { searchEndpoint: (s) => `/api/taxonomy/family?q=${s}` })}
                        </Col>
                        <Col>
                            <Form.Label>Description:</Form.Label>
                            <select {...form.register('description')} className="form-control" disabled={!selected}>
                                {genOptions(ALL_FAMILY_TYPES)}
                            </select>
                            {form.formState.errors.description && (
                                <span className="text-danger">You must provide the description.</span>
                            )}
                        </Col>
                    </Row>
                    <Row>
                        {selected && (
                            <Col>
                                <Button variant="secondary" size="sm" className="button" onClick={() => setShowRenameModal(true)}>
                                    Rename
                                </Button>
                            </Col>
                        )}
                    </Row>
                    <Row className="my-1">
                        <Col>
                            <FormGroup as={Col}>
                                <Form.Label>Genera:</Form.Label>
                            </FormGroup>
                        </Col>
                    </Row>
                    <Row>
                        <EditableDataTable
                            keyField={'id'}
                            data={genera}
                            columns={columns}
                            striped
                            responsive={false}
                            defaultSortFieldId={'name'}
                            customStyles={TABLE_CUSTOM_STYLES}
                            createEmpty={() => EMPTY_GENUS}
                            update={updateGeneraFromTable}
                            customActions={[{ name: 'Move', onUpdate: moveSelected }]}
                            disabled={!selected}
                            deleteConfirmation={DELETE_CONFIRMATION_MSG}
                        />
                        <hr />
                    </Row>
                    <Row>
                        <Col xs={2} className="me-3">
                            <Button variant="primary" type="submit" value="Submit" disabled={!selected}>
                                Submit
                            </Button>
                        </Col>
                        <Col>
                            {isSuperAdmin
                                ? deleteButton(
                                      'Caution. If there are any species (galls or hosts) assigned to this Family they too will be deleted.',
                                  )
                                : 'If you need to delete a Family please contact Adam or Jeff on Slack.'}
                        </Col>
                    </Row>
                </form>
            </Admin>
        </>
    );
};

export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery }) => {
    const id = extractQueryParam(context.query, 'id');
    const fs = pipe(
        id,
        O.map(parseInt),
        O.map((id) => mightFailWithArray<FamilyAPI>()(familyById(id))),
        O.getOrElse(constant(Promise.resolve(Array<FamilyAPI>()))),
    );

    return {
        props: {
            fs: await fs,
            id: pipe(extractQueryParam(context.query, 'id'), O.getOrElse(constant(''))),
        },
    };
};

export default FamilyAdmin;
