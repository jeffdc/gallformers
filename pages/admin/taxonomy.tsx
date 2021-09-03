import classNames from 'classnames';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import { ParsedUrlQuery } from 'querystring';
import React, { ReactNode } from 'react';
import { Button, Col, Form, FormGroup } from 'react-bootstrap';
import TreeMenu, {
    Item,
    ItemComponent,
    MatchSearchFunction,
    TreeMenuChildren,
    TreeMenuProps,
    TreeNodeInArray,
} from 'react-simple-tree-menu';
import 'react-simple-tree-menu/dist/main.css';
import * as yup from 'yup';
import { RenameEvent } from '../../components/editname';
import useAdmin from '../../hooks/useadmin';
import { AdminFormFields } from '../../hooks/useAPIs';
import { extractQueryParam } from '../../libs/api/apipage';
import { ALL_FAMILY_TYPES } from '../../libs/api/apitypes';
import { FAMILY, TaxonomyEntry, TaxonomyUpsertFields } from '../../libs/api/taxonomy';
import { allFamiliesWithGenera, FamilyWithGenera } from '../../libs/db/taxonomy';
import Admin from '../../libs/pages/admin';
import { genOptions } from '../../libs/utils/forms';
import { mightFailWithArray } from '../../libs/utils/util';

const schema = yup.object().shape({
    mainField: yup.mixed().required(),
    description: yup.string().required(),
});

// We have to remove the parent property as the Form library can not handle circular references in the data.
type TaxFamily = Omit<TaxonomyEntry, 'parent'>;

type FormFields = AdminFormFields<TaxFamily> & Omit<TaxFamily, 'id' | 'name' | 'type'>;

type Props = {
    id: string;
    fs: TreeNodeInArray[];
};

const renameFamily = async (s: TaxFamily, e: RenameEvent) => ({
    ...s,
    name: e.new,
});

const toUpsertFields = (fields: FormFields, name: string, id: number): TaxonomyUpsertFields => {
    return {
        ...fields,
        name: name,
        type: 'family',
        id: id,
        species: [],
        parent: O.none,
    };
};

const updatedFormFields = async (fam: TaxFamily | undefined): Promise<FormFields> => {
    if (fam != undefined) {
        return {
            mainField: [fam],
            description: fam.description,
            del: false,
        };
    }

    return {
        mainField: [],
        description: '',
        del: false,
    };
};

const createNewFamily = (name: string): TaxFamily => ({
    name: name,
    description: '',
    id: -1,
    type: FAMILY,
});

const DEFAULT_PADDING = 0.75;
const ICON_SIZE = 2;
const LEVEL_SPACE = 1.75;
const ToggleIcon = ({ on, openedIcon, closedIcon }: { on: boolean; openedIcon: ReactNode; closedIcon: ReactNode }) => (
    <div role="img" aria-label="Toggle" className="rstm-toggle-icon-symbol">
        {on ? openedIcon : closedIcon}
    </div>
);

const Family = ({ id, fs }: Props): JSX.Element => {
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
        'Family',
        id,
        fs,
        renameFamily,
        toUpsertFields,
        { keyProp: 'name', delEndpoint: '../api/family/', upsertEndpoint: '../api/family/upsert' },
        schema,
        updatedFormFields,
        false,
        createNewFamily,
    );

    const onClickItem = (props: Item) => {
        console.log(`JDC: ${JSON.stringify(props, null, '  ')}`);
    };

    const customSearch: MatchSearchFunction = ({ label, searchTerm, childLabels }) => {
        const lowerSearch = searchTerm.toLocaleLowerCase();
        const labelMatch = label.toLocaleLowerCase().includes(lowerSearch);

        return labelMatch || (childLabels ? childLabels.includes(lowerSearch) : labelMatch);
    };

    return (
        <Admin
            type="Taxonomy"
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
                <h4>Manage Taxonomy</h4>
                <TreeMenu data={fs} onClickItem={onClickItem} matchSearch={customSearch}>
                    {({ items, search }) => {
                        const onSearch = (e: React.ChangeEvent<HTMLInputElement>) => {
                            const { value } = e.target;
                            search && search(value);
                        };
                        return (
                            <>
                                {search && (
                                    <input
                                        className="rstm-search"
                                        aria-label="Type and search"
                                        type="search"
                                        placeholder="Type and search"
                                        onChange={onSearch}
                                    />
                                )}
                                <ul className="rstm-tree-item-group">
                                    {items.map(({ key, ...props }) => {
                                        // console.log(`JDC: ${JSON.stringify(props, null, '  ')}`);
                                        return (
                                            // <ItemComponent {...props} key={key} />
                                            <li
                                                key={key}
                                                className={classNames(
                                                    'rstm-tree-item',
                                                    `rstm-tree-item-level${props.level}`,
                                                    { 'rstm-tree-item--active': props.active },
                                                    { 'rstm-tree-item--focused': props.focused },
                                                )}
                                                style={{
                                                    paddingLeft: `${
                                                        DEFAULT_PADDING +
                                                        ICON_SIZE * (props.hasNodes ? 0 : 1) +
                                                        props.level * LEVEL_SPACE
                                                    }rem`,
                                                    ...props.style,
                                                }}
                                                role="button"
                                                aria-pressed={props.active}
                                                onClick={props.onClick}
                                            >
                                                {props.hasNodes && (
                                                    <div
                                                        className="rstm-toggle-icon"
                                                        onClick={(e) => {
                                                            props.hasNodes && props.toggleNode && props.toggleNode();
                                                            e.stopPropagation();
                                                        }}
                                                    >
                                                        <ToggleIcon on={props.isOpen} openedIcon={'-'} closedIcon={'+'} />
                                                    </div>
                                                )}
                                                {props.label}
                                            </li>
                                        );
                                    })}
                                </ul>
                            </>
                        );
                    }}
                </TreeMenu>

                <Form.Row>
                    <FormGroup as={Col}>
                        <Form.Label>Name:</Form.Label>
                        {mainField('name', 'Family')}
                    </FormGroup>
                    <FormGroup as={Col}>
                        <Form.Label>Description:</Form.Label>
                        <select {...form.register('description')} className="form-control">
                            {genOptions(ALL_FAMILY_TYPES)}
                        </select>
                        {form.formState.errors.description && (
                            <span className="text-danger">You must provide the description.</span>
                        )}
                    </FormGroup>
                </Form.Row>
                <Form.Row>
                    <Col xs={2} className="mr-3">
                        <Button variant="primary" type="submit" value="Submit" disabled={!selected}>
                            Submit
                        </Button>
                    </Col>
                    {selected && (
                        <Col>
                            <Button variant="secondary" className="button" onClick={() => setShowRenameModal(true)}>
                                Rename
                            </Button>
                        </Col>
                    )}
                    <Col>
                        {deleteButton(
                            'Caution. If there are any species (galls or hosts) assigned to this Family they too will be deleted.',
                        )}
                    </Col>
                </Form.Row>
            </form>
        </Admin>
    );
};

const toTree = (fwg: readonly FamilyWithGenera[]): TreeNodeInArray[] =>
    fwg.map((f) => {
        return {
            key: f.id.toString(),
            label: `${f.name} - ${f.description}`,
            data: f,
            childLabels: f.taxonomytaxonomy.map((c) => c.child.name.toLocaleLowerCase()).join(' '),
            nodes: f.taxonomytaxonomy
                .sort((a, b) => a.child.name.localeCompare(b.child.name))
                .map((tt) => ({
                    key: tt.child.id.toString(),
                    label: `${tt.child.name} - ${tt.child.description}`,
                    data: tt.child,
                })),
        };
    });

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
            fs: toTree(await mightFailWithArray<FamilyWithGenera>()(allFamiliesWithGenera())),
        },
    };
};

export default Family;
