import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import { ParsedUrlQuery } from 'querystring';
import React, { useState } from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import { Controller } from 'react-hook-form';
import * as yup from 'yup';
import AliasTable from '../../components/aliastable';
import Typeahead from '../../components/Typeahead';
import UndescribedFlow, { UndescribedData } from '../../components/UndescribedFlow';
import useAdmin from '../../hooks/useadmin';
import useSpecies, { SpeciesFormFields, SpeciesProps } from '../../hooks/useSpecies';
import { extractQueryParam } from '../../libs/api/apipage';
import * as AT from '../../libs/api/apitypes';
import { FAMILY, GENUS, TaxonomyEntry } from '../../libs/api/taxonomy';
import { alignments, allGalls, cells, colors, locations, seasons, shapes, textures, walls } from '../../libs/db/gall';
import { allHostsSimple } from '../../libs/db/host';
import { abundances } from '../../libs/db/species';
import { allFamilies, allGenera } from '../../libs/db/taxonomy';
import Admin from '../../libs/pages/admin';
import { hasProp, mightFailWithArray } from '../../libs/utils/util';

type Props = SpeciesProps & {
    gs: AT.GallApi[];
    hosts: AT.HostSimple[];
    locations: AT.GallLocation[];
    colors: AT.ColorApi[];
    seasons: AT.SeasonApi[];
    shapes: AT.ShapeApi[];
    textures: AT.GallTexture[];
    alignments: AT.AlignmentApi[];
    walls: AT.WallsApi[];
    cells: AT.CellsApi[];
};

const schema = yup.object().shape({
    mainField: yup
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
    family: yup
        .array()
        .of(
            yup.object({
                name: yup.string().required(),
            }),
        )
        .required(),
    // only force hosts to be present when adding, not deleting.
    hosts: yup.array().when('del', {
        is: false,
        then: yup.array().min(1),
    }),
});

export type FormFields = SpeciesFormFields<AT.GallApi> & {
    hosts: AT.GallHost[];
    detachable: AT.DetachableValues;
    walls: AT.WallsApi[];
    cells: AT.CellsApi[];
    alignments: AT.AlignmentApi[];
    shapes: AT.ShapeApi[];
    colors: AT.ColorApi[];
    seasons: AT.SeasonApi[];
    locations: AT.GallLocation[];
    textures: AT.GallTexture[];
    undescribed: boolean;
};

const Gall = ({
    id,
    gs,
    hosts,
    locations,
    colors,
    seasons,
    shapes,
    textures,
    alignments,
    walls,
    cells,
    abundances,
    families,
    genera,
}: Props): JSX.Element => {
    const [showNewUndescribed, setShowNewUndescribed] = useState(false);

    const {
        renameSpecies,
        createNewSpecies,
        updatedSpeciesFormFields,
        toSpeciesUpsertFields,
        aliasData,
        setAliasData,
    } = useSpecies<AT.GallApi>(genera);

    const toUpsertFields = (fields: FormFields, name: string, id: number): AT.GallUpsertFields => {
        if (!selected) {
            throw new Error('Trying to submit with a null selection which seems impossible but here we are.');
        }

        return {
            ...toSpeciesUpsertFields(fields, name, id),
            gallid: hasProp(fields.mainField[0], 'gall') ? fields.mainField[0].gall.id : -1,
            aliases: aliasData,
            alignments: fields.alignments.map((a) => a.id),
            cells: fields.cells.map((c) => c.id),
            colors: fields.colors.map((c) => c.id),
            seasons: fields.seasons.map((c) => c.id),
            detachable: fields.detachable,
            fgs: selected.fgs,
            hosts: fields.hosts.map((h) => h.id),
            locations: fields.locations.map((l) => l.id),
            shapes: fields.shapes.map((s) => s.id),
            textures: fields.textures.map((t) => t.id),
            undescribed: fields.undescribed,
            walls: fields.walls.map((w) => w.id),
        };
    };

    const updatedFormFields = async (s: AT.GallApi | undefined): Promise<FormFields> => {
        const speciesFields = updatedSpeciesFormFields(s);

        if (s != undefined) {
            return {
                ...speciesFields,
                alignments: s.gall.gallalignment,
                cells: s.gall.gallcells,
                colors: s.gall.gallcolor,
                detachable: s.gall.detachable.value,
                hosts: s.hosts,
                locations: s.gall.galllocation,
                seasons: s.gall.gallseason,
                shapes: s.gall.gallshape,
                textures: s.gall.galltexture,
                undescribed: s.gall.undescribed,
                walls: s.gall.gallwalls,
            };
        }

        return {
            ...speciesFields,
            alignments: [],
            cells: [],
            colors: [],
            detachable: AT.DetachableNone.value,
            hosts: [],
            locations: [],
            seasons: [],
            shapes: [],
            textures: [],
            undescribed: false,
            walls: [],
        };
    };

    const createNewGall = (name: string): AT.GallApi => ({
        ...createNewSpecies(name, AT.GallTaxon),
        gall: {
            detachable: AT.DetachableNone,
            gallalignment: [],
            gallcells: [],
            gallcolor: [],
            galllocation: [],
            gallseason: [],
            gallshape: [],
            galltexture: [],
            gallwalls: [],
            undescribed: false,
            id: -1,
        },
        hosts: [],
    });

    const {
        selected,
        setSelected,
        showRenameModal,
        setShowRenameModal,
        error,
        setError,
        deleteResults,
        setDeleteResults,
        renameCallback,
        confirm,
        form,
        formSubmit,
        mainField,
        deleteButton,
    } = useAdmin(
        'Gall',
        id,
        gs,
        renameSpecies,
        toUpsertFields,
        { keyProp: 'name', delEndpoint: '../api/gall/', upsertEndpoint: '../api/gall/upsert' },
        schema,
        updatedFormFields,
        createNewGall,
    );

    const newUndescribedDone = (data: UndescribedData | undefined) => {
        setShowNewUndescribed(false);
        if (data != undefined) {
            const newG = createNewGall(data.name);
            newG.hosts = [data.host];
            newG.fgs.genus = data.genus;
            newG.fgs.family = data.family;
            newG.gall.undescribed = true;
            setSelected(newG);
        }
    };

    const onSubmit = async (fields: FormFields) => {
        // see if a new Unknown Genus is needed - we are hiding this complexity from the user
        const genus = fields.genus[0];
        const family = fields.family[0];

        const newGenusNeeded = pipe(
            O.fromNullable(genera.find((g) => g.name.localeCompare(genus.name) == 0)),
            O.chain((g) => g.parent),
            O.map((p) => p.id != family.id),
            O.fold(constant(false), (b) => b && genus.name.localeCompare('Unknown') == 0),
        );

        if (newGenusNeeded) {
            fields.genus = [{ id: -1, description: '', name: 'Unknown', type: GENUS }];
        }

        // if either genus or family is Unknown and the undescribed box is not checked they are probably messing up
        if (
            !fields.undescribed &&
            (fields.genus[0].name.localeCompare('Unknown') == 0 || fields.family[0].name.localeCompare('Unknown') == 0)
        ) {
            return confirm({
                variant: 'danger',
                catchOnCancel: true,
                title: 'Unknown Genus/Family But Not Undescribed!',
                message: `The gall is assigned to an Unknown genus/family but it is not marked as undescribed. This is almost certainly an error. Do you really want to proceed?`,
            })
                .then(() => Promise.bind(formSubmit(fields)))
                .catch(() => Promise.resolve());
        }
        formSubmit(fields);
    };

    return (
        <Admin
            type="Gall"
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
            <form onSubmit={form.handleSubmit(onSubmit)} className="m-4 pr-4">
                <UndescribedFlow
                    show={showNewUndescribed}
                    onClose={newUndescribedDone}
                    hosts={hosts}
                    genera={genera}
                    families={families}
                />
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
                        <Row hidden={!!selected} className="formGroup">
                            <Col>
                                <Button className="btn-sm" disabled={!!selected} onClick={() => setShowNewUndescribed(true)}>
                                    Add Undescribed
                                </Button>
                            </Col>
                        </Row>
                        <Row>
                            <Col xs={8}>Name (binomial):</Col>
                        </Row>
                        <Row>
                            <Col>{mainField('name', 'Gall')}</Col>
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
                        <Typeahead
                            name="genus"
                            control={form.control}
                            placeholder="Genus"
                            options={genera}
                            labelKey="name"
                            selected={selected?.fgs?.genus ? [selected.fgs.genus] : []}
                            disabled={true}
                            onChange={(g) => {
                                if (selected) {
                                    selected.fgs.genus = g[0];
                                    setSelected({ ...selected });
                                }
                            }}
                            clearButton
                            multiple
                        />
                    </Col>
                    <Col>
                        Family:
                        <Typeahead
                            name="family"
                            control={form.control}
                            placeholder="Family"
                            options={families}
                            labelKey="name"
                            selected={selected?.fgs?.family ? [selected.fgs.family] : []}
                            disabled={selected && selected.id > 0}
                            onChange={(f) => {
                                if (f && f.length > 0 && selected) {
                                    // handle the case when a new species is created
                                    // either the genus is new or is not
                                    const genus = genera.find((gg) => gg.id === selected.fgs.genus.id);
                                    if (genus && O.isNone(genus.parent)) {
                                        genus.parent = O.some({ ...f[0], parent: O.none });
                                        selected.fgs = { ...selected.fgs, genus: genus };
                                        setSelected({ ...selected, fgs: { ...selected.fgs, family: f[0] } });
                                    } else {
                                        selected.fgs = { ...selected.fgs, family: f[0] };
                                        setSelected({ ...selected });
                                    }
                                } else if (selected) {
                                    selected.fgs = {
                                        ...selected.fgs,
                                        family: { name: '', description: '', id: -1, type: FAMILY },
                                    };
                                    setSelected({ ...selected });
                                }
                            }}
                            clearButton
                        />
                        {form.formState.errors.family && (
                            <span className="text-danger">
                                The Family name is required. If it is not present in the list you will have to go add the family
                                first. :(
                            </span>
                        )}
                    </Col>
                    <Col>
                        Abundance:
                        <Typeahead
                            name="abundance"
                            control={form.control}
                            options={abundances}
                            labelKey="abundance"
                            disabled={!selected}
                            selected={
                                selected?.abundance
                                    ? pipe(
                                          selected.abundance,
                                          O.fold(constant([]), (a) => [a]),
                                      )
                                    : []
                            }
                            onChange={(g) => {
                                if (selected) {
                                    selected.abundance = O.fromNullable(g[0]);
                                    setSelected({ ...selected });
                                }
                            }}
                            clearButton
                        />
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Hosts:
                        <Typeahead
                            name="hosts"
                            control={form.control}
                            placeholder="Hosts"
                            options={hosts}
                            labelKey="name"
                            multiple
                            selected={selected ? selected.hosts : []}
                            onChange={(h) => {
                                if (selected) {
                                    selected.hosts = h;
                                    setSelected({ ...selected });
                                }
                            }}
                            clearButton
                        />
                        {form.formState.errors.hosts && (
                            <span className="text-danger">You must map this gall to at least one host.</span>
                        )}
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Detachable:
                        <Controller
                            control={form.control}
                            name="detachable"
                            render={({ field: { ref } }) => (
                                <select
                                    ref={ref}
                                    value={selected ? selected.gall.detachable.value : AT.DetachableNone.value}
                                    onChange={(e) => {
                                        if (selected) {
                                            selected.gall.detachable = AT.detachableFromString(e.currentTarget.value);
                                            setSelected({ ...selected });
                                        }
                                    }}
                                    placeholder="Detachable"
                                    className="form-control"
                                >
                                    {AT.Detachables.map((d) => (
                                        <option key={d.id}>{d.value}</option>
                                    ))}
                                </select>
                            )}
                        />
                    </Col>
                    <Col>
                        Walls:
                        <Typeahead
                            name="walls"
                            control={form.control}
                            options={walls}
                            labelKey="walls"
                            multiple
                            clearButton
                            selected={selected ? selected.gall.gallwalls : []}
                            onChange={(w) => {
                                if (selected) {
                                    selected.gall.gallwalls = w;
                                    setSelected({ ...selected });
                                }
                            }}
                        />
                    </Col>
                    <Col>
                        Cells:
                        <Typeahead
                            name="cells"
                            control={form.control}
                            options={cells}
                            labelKey="cells"
                            multiple
                            clearButton
                            selected={selected ? selected.gall.gallcells : []}
                            onChange={(w) => {
                                if (selected) {
                                    selected.gall.gallcells = w;
                                    setSelected({ ...selected });
                                }
                            }}
                        />
                    </Col>
                    <Col>
                        Alignment(s):
                        <Typeahead
                            name="alignments"
                            control={form.control}
                            options={alignments}
                            labelKey="alignment"
                            multiple
                            clearButton
                            selected={selected ? selected.gall.gallalignment : []}
                            onChange={(w) => {
                                if (selected) {
                                    selected.gall.gallalignment = w;
                                    setSelected({ ...selected });
                                }
                            }}
                        />
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Color(s):
                        <Typeahead
                            name="colors"
                            control={form.control}
                            options={colors}
                            labelKey="color"
                            multiple
                            clearButton
                            selected={selected ? selected.gall.gallcolor : []}
                            onChange={(w) => {
                                if (selected) {
                                    selected.gall.gallcolor = w;
                                    setSelected({ ...selected });
                                }
                            }}
                        />
                    </Col>
                    <Col>
                        Shape(s):
                        <Typeahead
                            name="shapes"
                            control={form.control}
                            options={shapes}
                            labelKey="shape"
                            multiple
                            clearButton
                            selected={selected ? selected.gall.gallshape : []}
                            onChange={(w) => {
                                if (selected) {
                                    selected.gall.gallshape = w;
                                    setSelected({ ...selected });
                                }
                            }}
                        />
                    </Col>
                    <Col>
                        Season(s):
                        <Typeahead
                            name="seasons"
                            control={form.control}
                            options={seasons}
                            labelKey="season"
                            multiple
                            clearButton
                            selected={selected ? selected.gall.gallseason : []}
                            onChange={(w) => {
                                if (selected) {
                                    selected.gall.gallseason = w;
                                    setSelected({ ...selected });
                                }
                            }}
                        />
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Location(s):
                        <Typeahead
                            name="locations"
                            control={form.control}
                            options={locations}
                            labelKey="loc"
                            multiple
                            clearButton
                            selected={selected ? selected.gall.galllocation : []}
                            onChange={(w) => {
                                if (selected) {
                                    selected.gall.galllocation = w;
                                    setSelected({ ...selected });
                                }
                            }}
                        />
                    </Col>
                    <Col>
                        Texture(s):
                        <Typeahead
                            name="textures"
                            control={form.control}
                            options={textures}
                            labelKey="tex"
                            multiple
                            clearButton
                            selected={selected ? selected.gall.galltexture : []}
                            onChange={(w) => {
                                if (selected) {
                                    selected.gall.galltexture = w;
                                    setSelected({ ...selected });
                                }
                            }}
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
                        <Controller
                            control={form.control}
                            name="datacomplete"
                            render={({ field: { ref } }) => (
                                <input
                                    ref={ref}
                                    type="checkbox"
                                    className="form-input-checkbox"
                                    checked={selected ? selected.datacomplete : false}
                                    onChange={(e) => {
                                        if (selected) {
                                            selected.datacomplete = e.currentTarget.checked;
                                            setSelected({ ...selected });
                                        }
                                    }}
                                />
                            )}
                        />{' '}
                        All sources containing unique information relevant to this gall have been added and are reflected in its
                        associated data. However, filter criteria may not be comprehensive in every field.
                    </Col>
                </Row>
                <Row className="formGroup pb-1">
                    <Col className="mr-auto">
                        <Controller
                            control={form.control}
                            name="undescribed"
                            render={({ field: { ref } }) => (
                                <input
                                    ref={ref}
                                    type="checkbox"
                                    className="form-input-checkbox"
                                    checked={selected ? selected.gall.undescribed : false}
                                    onChange={(e) => {
                                        if (selected) {
                                            selected.gall.undescribed = e.currentTarget.checked;
                                            setSelected({ ...selected });
                                        }
                                    }}
                                />
                            )}
                        />{' '}
                        Undescribed?
                    </Col>
                </Row>
                <Row className="formGroup pb-1">
                    <Col>
                        <input type="submit" className="button" value="Submit" />
                    </Col>
                    <Col>{deleteButton('Caution. All data associated with this Gall will be deleted.')}</Col>
                </Row>
                <Row hidden={!selected} className="formGroup">
                    <Col>
                        <br />
                        <div>
                            <Link href={`./images?speciesid=${selected?.id}`}>Add/Edit Images for this Gall</Link>
                        </div>
                        <div>
                            <Link href={`./speciessource?id=${selected?.id}`}>Add/Edit Sources for this Gall</Link>
                        </div>
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
            seasons: await mightFailWithArray<AT.SeasonApi>()(seasons()),
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
