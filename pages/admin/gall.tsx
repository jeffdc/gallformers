import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import { useRouter } from 'next/router';
import { ParsedUrlQuery } from 'querystring';
import React, { useState } from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import * as yup from 'yup';
import AliasTable from '../../components/aliastable';
import ControlledTypeahead from '../../components/controlledtypeahead';
import { RenameEvent } from '../../components/editname';
import useAdmin from '../../hooks/useadmin';
import { AdminFormFields } from '../../hooks/useAPIs';
import { useConfirmation } from '../../hooks/useconfirmation';
import { extractQueryParam } from '../../libs/api/apipage';
import * as AT from '../../libs/api/apitypes';
import { FGS, GENUS, TaxonomyEntry } from '../../libs/api/taxonomy';
import { alignments, allGalls, cells, colors, locations, shapes, textures, walls } from '../../libs/db/gall';
import { allHostsSimple } from '../../libs/db/host';
import { abundances } from '../../libs/db/species';
import { allFamilies, allGenera } from '../../libs/db/taxonomy';
import Admin from '../../libs/pages/admin';
import { extractGenus, hasProp, mightFailWithArray } from '../../libs/utils/util';

type Props = {
    id: string;
    gs: AT.GallApi[];
    abundances: AT.AbundanceApi[];
    hosts: AT.HostSimple[];
    locations: AT.GallLocation[];
    colors: AT.ColorApi[];
    shapes: AT.ShapeApi[];
    textures: AT.GallTexture[];
    alignments: AT.AlignmentApi[];
    walls: AT.WallsApi[];
    cells: AT.CellsApi[];
    families: TaxonomyEntry[];
    genera: TaxonomyEntry[];
};

const schema = yup.object().shape({
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
    family: yup.array().required(),
    // only force hosts to be present when adding, not deleting.
    hosts: yup.array().when('del', {
        is: false,
        then: yup.array().required(),
    }),
});

export type FormFields = AdminFormFields<AT.GallApi> & {
    genus: TaxonomyEntry[];
    family: TaxonomyEntry[];
    abundance: AT.AbundanceApi[];
    hosts: AT.GallHost[];
    detachable: AT.DetachableValues;
    walls: AT.WallsApi[];
    cells: AT.CellsApi[];
    alignments: AT.AlignmentApi[];
    shapes: AT.ShapeApi[];
    colors: AT.ColorApi[];
    locations: AT.GallLocation[];
    textures: AT.GallTexture[];
    datacomplete: boolean;
};

const updateGall = (s: AT.GallApi, newValue: string): AT.GallApi => ({
    ...s,
    name: newValue,
});

const fetchFGS = async (h: AT.GallApi): Promise<FGS> => {
    const res = await fetch(`../api/taxonomy?id=${h.id}`);
    if (res.status === 200) {
        return await res.json();
    } else {
        console.error(await res.text());
        throw new Error('Failed to fetch taxonomy for the selected species. Check console.');
    }
};

const Gall = ({
    id,
    gs,
    hosts,
    locations,
    colors,
    shapes,
    textures,
    alignments,
    walls,
    cells,
    abundances,
    families,
    genera,
}: Props): JSX.Element => {
    const [aliasData, setAliasData] = useState<Array<AT.AliasApi>>([]);

    const toUpsertFields = (fields: FormFields, name: string, id: number): AT.GallUpsertFields => {
        return {
            gallid: hasProp(fields.value[0], 'gall') ? fields.value[0].gall.id : -1,
            abundance: fields.abundance[0].abundance,
            aliases: aliasData,
            alignments: fields.alignments.map((a) => a.id),
            cells: fields.cells.map((c) => c.id),
            colors: fields.colors.map((c) => c.id),
            datacomplete: fields.datacomplete,
            detachable: fields.detachable,
            fgs: { family: fields.family[0], genus: fields.genus[0], section: O.none },
            hosts: fields.hosts.map((h) => h.id),
            id: id,
            locations: fields.locations.map((l) => l.id),
            name: name,
            shapes: fields.shapes.map((s) => s.id),
            textures: fields.textures.map((t) => t.id),
            walls: fields.walls.map((w) => w.id),
        };
    };

    const updatedFormFields = async (s: AT.GallApi | undefined): Promise<FormFields> => {
        if (s != undefined) {
            setAliasData(s?.aliases);
            const newFGS = await fetchFGS(s);

            return {
                value: [s],
                genus: [newFGS.genus],
                family: [newFGS.family],
                abundance: [pipe(s.abundance, O.getOrElse(constant(AT.EmptyAbundance)))],
                datacomplete: s.datacomplete,
                alignments: s.gall.gallalignment,
                cells: s.gall.gallcells,
                colors: s.gall.gallcolor,
                detachable: s.gall.detachable.value,
                hosts: s.hosts,
                locations: s.gall.galllocation,
                shapes: s.gall.gallshape,
                textures: s.gall.galltexture,
                walls: s.gall.gallwalls,
                del: false,
            };
        }

        setAliasData([]);
        return {
            value: [],
            genus: [],
            family: [],
            abundance: [AT.EmptyAbundance],
            datacomplete: false,
            detachable: AT.DetachableNone.value,
            walls: [],
            cells: [],
            alignments: [],
            colors: [],
            shapes: [],
            locations: [],
            textures: [],
            hosts: [],
            del: false,
        };
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
        'Gall',
        id,
        gs,
        updateGall,
        toUpsertFields,
        { keyProp: 'name', delEndpoint: '../api/gall/', upsertEndpoint: '../api/gall/upsert' },
        schema,
        updatedFormFields,
    );

    const router = useRouter();
    const confirm = useConfirmation();

    const rename = async (fields: FormFields, e: RenameEvent) => {
        if (e.old == undefined) throw new Error('Trying to add rename but old name is missing?!');

        if (e.addAlias) {
            aliasData.push({
                id: -1,
                name: e.old,
                type: 'scientific',
                description: 'Previous name',
            });
        }

        // have to check for genus rename
        const newGenus = extractGenus(e.new);
        if (newGenus.localeCompare(extractGenus(e.old)) != 0) {
            const g = genera.find((g) => g.name.localeCompare(newGenus) == 0);
            if (g == undefined) {
                return confirm({
                    variant: 'danger',
                    catchOnCancel: true,
                    title: 'Are you sure want to create a new genus?',
                    message: `Renaming the genus to ${newGenus} will create a new genus under the current family ${fields.family[0].name}. Do you want to continue?`,
                }).then(() => {
                    fields.genus[0] = {
                        id: -1,
                        description: '',
                        name: newGenus,
                        type: GENUS,
                        parent: O.of(fields.family[0]),
                    };
                    return Promise.bind(onSubmit(fields));
                });
            } else {
                fields.genus[0] = g;
            }
        }

        return onSubmit(fields);
    };

    const onSubmit = async (fields: FormFields) => {
        formSubmit(fields);
    };

    return (
        <Admin
            type="Gall"
            keyField="name"
            editName={{ getDefault: () => selected?.name, renameCallback: renameCallback(rename) }}
            setShowModal={setShowRenameModal}
            showModal={showRenameModal}
            setError={setError}
            error={error}
            setDeleteResults={setDeleteResults}
            deleteResults={deleteResults}
        >
            <form onSubmit={form.handleSubmit(onSubmit)} className="m-4 pr-4">
                <h4>Add/Edit Gallformers</h4>
                <p>
                    This is for all of the details about a Gall. To add a description (which must be referenced to a source) go
                    add <Link href="/admin/source">Sources</Link>, if they do not already exist, then go{' '}
                    <Link href="/admin/speciessource">map species to sources with description</Link>. To associate a gall with all
                    plants in a genus, add one species here first, then go to{' '}
                    <Link href="./gallhost">
                        <a>Gall-Host Mappings</a>
                    </Link>
                    .
                </p>
                <Row className="form-group">
                    <Col>
                        <Row>
                            <Col xs={8}>Name (binomial):</Col>
                        </Row>
                        <Row>
                            <Col>
                                <ControlledTypeahead
                                    control={form.control}
                                    name="value"
                                    onChangeWithNew={(e, isNew) => {
                                        if (isNew || !e[0]) {
                                            setSelected(undefined);
                                            const g = genera.find((g) => g.name.localeCompare(e[0].name) == 0);
                                            form.setValue(
                                                'genus',
                                                g
                                                    ? [g]
                                                    : [
                                                          {
                                                              id: -1,
                                                              name: extractGenus(e[0].name),
                                                              description: '',
                                                              type: GENUS,
                                                              parent: O.none,
                                                          },
                                                      ],
                                            );
                                            router.replace(``, undefined, { shallow: true });
                                        } else {
                                            const gall: AT.GallApi = e[0];
                                            setSelected(gall);
                                            router.replace(`?id=${gall.id}`, undefined, { shallow: true });
                                        }
                                    }}
                                    placeholder="Name"
                                    options={data}
                                    labelKey="name"
                                    clearButton
                                    isInvalid={!!form.errors.value}
                                    newSelectionPrefix="Add a new Gall: "
                                    allowNew={true}
                                />
                                {form.errors.value && (
                                    <span className="text-danger">
                                        Name is required and must be in standard binomial form, e.g., Gallus gallus
                                    </span>
                                )}
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
                        Genus (filled automatically):
                        <ControlledTypeahead
                            control={form.control}
                            name="genus"
                            options={genera}
                            labelKey="name"
                            disabled={true}
                        />
                    </Col>
                    <Col>
                        Family:
                        <ControlledTypeahead
                            control={form.control}
                            name="family"
                            placeholder="Family"
                            options={families}
                            labelKey="name"
                            disabled={!!selected}
                            onChange={(f) => {
                                // handle the case when a new species is created
                                const g = form.getValues().genus[0];
                                if (O.isNone(g.parent)) {
                                    g.parent = O.some(f[0]);
                                    form.setValue('genus', [g]);
                                }
                            }}
                        />
                        {form.errors.family && (
                            <span className="text-danger">
                                The Family name is required. If it is not present in the list you will have to go add the family
                                first. :(
                            </span>
                        )}
                    </Col>
                    <Col>
                        Abundance:
                        <ControlledTypeahead
                            control={form.control}
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
                        Hosts:
                        <ControlledTypeahead
                            control={form.control}
                            name="hosts"
                            placeholder="Hosts"
                            options={hosts}
                            labelKey="name"
                            multiple
                            clearButton
                        />
                        {form.errors.hosts && <span className="text-danger">You must map this gall to at least one host.</span>}
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Detachable:
                        <select placeholder="Detachable" name="detachable" className="form-control" ref={form.register}>
                            {AT.Detachables.map((d) => (
                                <option key={d.id}>{d.value}</option>
                            ))}
                        </select>
                    </Col>
                    <Col>
                        Walls:
                        <ControlledTypeahead
                            control={form.control}
                            name="walls"
                            placeholder=""
                            options={walls}
                            labelKey="walls"
                            multiple
                            clearButton
                        />
                    </Col>
                    <Col>
                        Cells:
                        <ControlledTypeahead
                            control={form.control}
                            name="cells"
                            placeholder=""
                            options={cells}
                            labelKey="cells"
                            multiple
                            clearButton
                        />
                    </Col>
                    <Col>
                        Alignment(s):
                        <ControlledTypeahead
                            control={form.control}
                            name="alignments"
                            placeholder=""
                            options={alignments}
                            labelKey="alignment"
                            multiple
                            clearButton
                        />
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Color(s):
                        <ControlledTypeahead
                            control={form.control}
                            name="colors"
                            placeholder=""
                            options={colors}
                            labelKey="color"
                            multiple
                            clearButton
                        />
                    </Col>
                    <Col>
                        Shape(s):
                        <ControlledTypeahead
                            control={form.control}
                            name="shapes"
                            placeholder=""
                            options={shapes}
                            labelKey="shape"
                            multiple
                            clearButton
                        />
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Location(s):
                        <ControlledTypeahead
                            control={form.control}
                            name="locations"
                            placeholder=""
                            options={locations}
                            labelKey="loc"
                            multiple
                            clearButton
                        />
                    </Col>
                    <Col>
                        Texture(s):
                        <ControlledTypeahead
                            control={form.control}
                            name="textures"
                            placeholder=""
                            options={textures}
                            labelKey="tex"
                            multiple
                            clearButton
                        />
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        <AliasTable data={aliasData} setData={setAliasData} />
                    </Col>
                </Row>
                <Row className="formGroup pb-1">
                    <Col className="mr-auto">
                        <input name="datacomplete" type="checkbox" className="form-input-checkbox" ref={form.register} /> All
                        sources containing unique information relevant to this gall have been added and are reflected in its
                        associated data. However, filter criteria may not be comprehensive in every field.
                    </Col>
                </Row>
                <Row className="fromGroup pb-1" hidden={!selected}>
                    <Col className="mr-auto">
                        <input name="del" type="checkbox" className="form-input-checkbox" ref={form.register} /> Delete?
                    </Col>
                </Row>
                <Row className="formGroup">
                    <Col>
                        <input type="submit" className="button" value="Submit" />
                    </Col>
                </Row>
                <Row hidden={!selected}>
                    <Col>
                        <br />
                        <Link href={`./images?speciesid=${selected?.id}`}>Add/Edit Images for this Gall</Link>
                    </Col>
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
            gs: await mightFailWithArray<AT.GallApi>()(allGalls()),
            hosts: await mightFailWithArray<AT.HostSimple>()(allHostsSimple()),
            families: await mightFailWithArray<TaxonomyEntry>()(allFamilies(AT.GALL_FAMILY_TYPES)),
            genera: await mightFailWithArray<TaxonomyEntry>()(allGenera(AT.GallTaxon)),
            locations: await mightFailWithArray<AT.GallLocation>()(locations()),
            colors: await mightFailWithArray<AT.ColorApi>()(colors()),
            shapes: await mightFailWithArray<AT.ShapeApi>()(shapes()),
            textures: await mightFailWithArray<AT.GallTexture>()(textures()),
            alignments: await mightFailWithArray<AT.AlignmentApi>()(alignments()),
            walls: await mightFailWithArray<AT.WallsApi>()(walls()),
            cells: await mightFailWithArray<AT.CellsApi>()(cells()),
            abundances: await mightFailWithArray<AT.AbundanceApi>()(abundances()),
        },
    };
};

export default Gall;
