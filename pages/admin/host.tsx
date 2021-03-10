import { yupResolver } from '@hookform/resolvers/yup';
import { abundance } from '@prisma/client';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import { useRouter } from 'next/router';
import { ParsedUrlQuery } from 'querystring';
import React, { useCallback, useEffect, useRef, useState } from 'react';
import { Alert, Button, Col, Row } from 'react-bootstrap';
import BootstrapTable, { ColumnDescription, SelectRowProps } from 'react-bootstrap-table-next';
import 'react-bootstrap-table-next/dist/react-bootstrap-table2.min.css';
import cellEditFactory, { CellEditFactoryProps } from 'react-bootstrap-table2-editor';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import Auth from '../../components/auth';
import ControlledTypeahead from '../../components/controlledtypeahead';
import { AdminFormFields, useAPIs } from '../../hooks/useAPIs';
import { extractQueryParam } from '../../libs/api/apipage';
import {
    AbundanceApi,
    AliasApi,
    DeleteResult,
    EmptyAbundance,
    EmptyAlias,
    HOST_FAMILY_TYPES,
    SpeciesApi,
    SpeciesUpsertFields,
} from '../../libs/api/apitypes';
import { EMPTY_FGS, FGS, TaxonomyEntry } from '../../libs/api/taxonomy';
import { allHosts } from '../../libs/db/host';
import { abundances } from '../../libs/db/species';
import { allFamilies, allSections, taxonomyForSpecies } from '../../libs/db/taxonomy';
import { mightFail, mightFailWithArray } from '../../libs/utils/util';

type Props = {
    id: string;
    hs: SpeciesApi[];
    fgs: FGS;
    families: TaxonomyEntry[];
    sections: TaxonomyEntry[];
    abundances: abundance[];
};

const extractGenus = (n: string): string => {
    return n.split(' ')[0];
};

const Schema = yup.object().shape({
    value: yup
        .array()
        .of(
            yup.object({
                name: yup
                    .string()
                    // maybe? add this back but allow select punctuation in species name?
                    // .matches(/([A-Z][a-z]+ [a-z]+$)/)
                    .required(),
            }),
        )
        .min(1)
        .max(1),
    family: yup.mixed().required(),
});

export type FormFields = AdminFormFields<SpeciesApi> & {
    genus: string;
    family: TaxonomyEntry[];
    section: TaxonomyEntry[];
    abundance: AbundanceApi[];
    datacomplete: boolean;
};

export const testables = {
    extractGenus: extractGenus,
    Schema: Schema,
};

const aliasColumns: ColumnDescription[] = [
    { dataField: 'name', text: 'Alias Name' },
    {
        dataField: 'type',
        text: 'Alias Type',
        editor: {
            type: 'select',
            options: [
                { value: 'common', label: 'common' },
                { value: 'scientific', label: 'scientific' },
            ],
        },
    },
    { dataField: 'description', text: 'Alias Description' },
];

const cellEditProps: CellEditFactoryProps<AliasApi> = {
    mode: 'click',
    blurToSave: true,
};

const Host = ({ id, hs, fgs, families, sections, abundances }: Props): JSX.Element => {
    const [existingId, setExistingId] = useState<number | undefined>(id && id !== '' ? parseInt(id) : undefined);
    const [deleteResults, setDeleteResults] = useState<DeleteResult>();
    const [hosts, setHosts] = useState(hs);
    const [theFGS, setTheFGS] = useState(fgs);
    const [error, setError] = useState('');
    const [aliasData, setAliasData] = useState<Array<AliasApi>>([]);
    const [aliasSelected, setAliasSelected] = useState(new Set<number>());

    const { register, handleSubmit, setValue, errors, control, reset } = useForm<FormFields>({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });

    const router = useRouter();

    const onHostChange = useCallback(
        async (spid: number | undefined) => {
            if (spid == undefined) {
                reset({
                    value: [],
                    genus: '',
                    family: [],
                    abundance: [EmptyAbundance],
                });
                setAliasData([]);
            } else {
                try {
                    const sp = hosts.find((h) => h.id === spid);
                    if (sp == undefined) {
                        throw new Error(`Somehow we have a host selection that does not exist?! hostid: ${spid}`);
                    }

                    // TODO: use a hook and figure out how to deal with state dependencies not causing infinite loop of updates
                    const res = await fetch(`../api/taxonomy?id=${sp.id}`);
                    if (res.status === 200) {
                        setTheFGS(await res.json());
                    } else {
                        console.error(await res.text());
                        setError('Failed to fetch taxonomy for the selected species. Check console.');
                    }
                    reset({
                        value: [sp],
                        genus: extractGenus(sp.name),
                        family: theFGS.family != null ? [theFGS.family] : [],
                        section: pipe(
                            theFGS.section,
                            O.fold(constant([]), (s) => [s]),
                        ),
                        abundance: [pipe(sp.abundance, O.getOrElse(constant(EmptyAbundance)))],
                        datacomplete: sp.datacomplete,
                    });
                    setAliasData(sp.aliases);
                } catch (e) {
                    console.error(e);
                    setError(e);
                }
            }
        },
        [reset, hosts, theFGS],
    );

    useEffect(() => {
        onHostChange(existingId);
    }, [existingId, onHostChange]);

    const { doDeleteOrUpsert } = useAPIs<SpeciesApi, SpeciesUpsertFields>('name', '../api/host/', '../api/host/upsert');

    const onSubmit = async (data: FormFields) => {
        const postDelete = (id: number | string, result: DeleteResult) => {
            setHosts(hosts.filter((s) => s.id !== id));
            setDeleteResults(result);
        };

        const postUpdate = (res: Response) => {
            router.push(res.url);
        };

        const convertFormFieldsToUpsert = (fields: FormFields, name: string, id: number): SpeciesUpsertFields => ({
            abundance: fields.abundance[0].abundance,
            aliases: aliasData,
            datacomplete: fields.datacomplete,
            fgs: {
                // family: fields.family[0],
                // genus: ,
                // section: ,
            },
            id: id,
            name: name,
        });

        await doDeleteOrUpsert(data, postDelete, postUpdate, convertFormFieldsToUpsert)
            .then(() => reset())
            .catch((e) => setError(`Failed to save changes. ${e}.`));
    };

    const selectRow: SelectRowProps<AliasApi> = {
        mode: 'checkbox',
        clickToSelect: false,
        clickToEdit: true,
        onSelect: (row) => {
            const selection = new Set(aliasSelected);
            selection.has(row.id) ? selection.delete(row.id) : selection.add(row.id);
            setAliasSelected(selection);
        },
        onSelectAll: (isSelect) => {
            if (isSelect) {
                setAliasSelected(new Set(aliasData.map((a) => a.id)));
            } else {
                setAliasSelected(new Set());
            }
        },
    };

    const addAlias = () => {
        aliasData.push(EmptyAlias);
        setAliasData([...aliasData]);
    };

    const deleteAliases = () => {
        setAliasData(aliasData.filter((a) => !aliasSelected.has(a.id)));
        setAliasSelected(new Set());
    };

    return (
        <Auth>
            <>
                <Head>
                    <title>Add/Edit Hosts</title>
                </Head>

                {error.length > 0 && (
                    <Alert variant="danger" onClose={() => setError('')} dismissible>
                        <Alert.Heading>Uh-oh</Alert.Heading>
                        <p>{error}</p>
                    </Alert>
                )}

                <form onSubmit={handleSubmit(onSubmit)} className="m-4 pr-4">
                    <h4>Add/Edit Hosts</h4>
                    <p>
                        This is for all of the details about a Host. To add a description (which must be referenced to a source)
                        go add <Link href="/admin/source">Sources</Link>, if they do not already exist, then go{' '}
                        <Link href="/admin/speciessource">map species to sources with description</Link>. If you want to assign a
                        Family or Section then you will need to have created them first if they do not exist.
                    </p>
                    <Row className="form-group">
                        <Col>
                            Name (binomial):
                            <ControlledTypeahead
                                control={control}
                                name="value"
                                onChangeWithNew={(e, isNew) => {
                                    if (isNew || !e[0]) {
                                        setExistingId(undefined);
                                        router.replace(``, undefined, { shallow: true });
                                    } else {
                                        const host: SpeciesApi = e[0];
                                        setExistingId(host.id);
                                        router.replace(`?id=${host.id}`, undefined, { shallow: true });
                                    }
                                }}
                                onBlurT={(e) => {
                                    if (!errors.value) {
                                        setValue('genus', extractGenus(e.target.value));
                                    }
                                }}
                                placeholder="Name"
                                options={hosts}
                                labelKey="name"
                                clearButton
                                isInvalid={!!errors.value}
                                newSelectionPrefix="Add a new Host: "
                                allowNew={true}
                            />
                            {errors.value && (
                                <span className="text-danger">
                                    Name is required and must be in standard binomial form, e.g., Gallus gallus
                                </span>
                            )}
                        </Col>
                        <Col>
                            Genus (filled automatically):
                            <input type="text" name="genus" className="form-control" readOnly tabIndex={-1} ref={register} />
                        </Col>
                        <Col>
                            Family:
                            <ControlledTypeahead
                                control={control}
                                name="family"
                                placeholder="Family"
                                options={families}
                                labelKey="name"
                                clearButton
                            />
                            {errors.family && (
                                <span className="text-danger">
                                    The Family name is required. If it is not present in the list you will have to go add the
                                    family first. :(
                                </span>
                            )}
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            Section:
                            <ControlledTypeahead
                                control={control}
                                name="section"
                                placeholder=""
                                options={sections}
                                labelKey="name"
                                clearButton
                            />
                        </Col>
                        <Col>
                            Abundance:
                            <ControlledTypeahead
                                control={control}
                                name="abundance"
                                placeholder=""
                                options={abundances}
                                labelKey="abundance"
                                clearButton
                            />
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            <BootstrapTable
                                keyField={'id'}
                                data={aliasData}
                                columns={aliasColumns}
                                bootstrap4
                                striped
                                headerClasses="table-header"
                                cellEdit={cellEditFactory(cellEditProps)}
                                selectRow={selectRow}
                            />
                            <Button variant="secondary" className="btn-sm mr-2" onClick={addAlias}>
                                Add Alias
                            </Button>
                            <Button
                                variant="secondary"
                                className="btn-sm"
                                disabled={aliasSelected.size == 0}
                                onClick={deleteAliases}
                            >
                                Delete Selected Alias(es)
                            </Button>
                            <p className="font-italic small">
                                Changes to the aliases will not be saved until you save the whole form by clicking
                                &lsquo;Submit&rsquo; below.
                            </p>
                        </Col>
                    </Row>
                    <Row className="formGroup pb-1">
                        <Col className="mr-auto">
                            <input name="datacomplete" type="checkbox" className="form-input-checkbox" ref={register} /> Are all
                            known galls submitted for this host?
                        </Col>
                    </Row>
                    <Row className="fromGroup pb-1" hidden={!existingId}>
                        <Col className="mr-auto">
                            <input name="del" type="checkbox" className="form-input-checkbox" ref={register} /> Delete?
                        </Col>
                    </Row>
                    <Row className="formGroup">
                        <Col>
                            <input type="submit" className="button" value="Submit" />
                        </Col>
                    </Row>
                    <Row hidden={!deleteResults}>
                        <Col>{`Deleted ${deleteResults?.name}.`}</Col>
                    </Row>
                    <Row hidden={!existingId}>
                        <Col>
                            <br />
                            <Link href={`./images?speciesid=${existingId}`}>Add/Edit Images for this Host</Link>
                        </Col>
                    </Row>
                </form>
            </>
        </Auth>
    );
};

export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery }) => {
    const queryParam = 'id';
    // eslint-disable-next-line prettier/prettier
    const id = pipe(
        extractQueryParam(context.query, queryParam),
        O.getOrElse(constant('')),
    );

    const fgs = id === '' ? EMPTY_FGS : await mightFail(constant(EMPTY_FGS))(taxonomyForSpecies(parseInt(id)));
    return {
        props: {
            id: id,
            hs: await mightFailWithArray<SpeciesApi>()(allHosts()),
            fgs: fgs,
            families: await mightFailWithArray<TaxonomyEntry>()(allFamilies(HOST_FAMILY_TYPES)),
            sections: await mightFailWithArray<TaxonomyEntry>()(allSections()),
            abundances: await mightFailWithArray<AbundanceApi>()(abundances()),
        },
    };
};

export default Host;
