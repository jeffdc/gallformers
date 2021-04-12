import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import { ParsedUrlQuery } from 'querystring';
import React, { useState } from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import * as yup from 'yup';
import AliasTable from '../../components/aliastable';
import { RenameEvent } from '../../components/editname';
import Typeahead from '../../components/Typeahead';
import UndescribedFlow, { UndescribedData } from '../../components/UndescribedFlow';
import useAdmin from '../../hooks/useadmin';
import { AdminFormFields } from '../../hooks/useAPIs';
import { useConfirmation } from '../../hooks/useconfirmation';
import { extractQueryParam } from '../../libs/api/apipage';
import * as AT from '../../libs/api/apitypes';
import { FAMILY, FGS, GENUS, TaxonomyEntry, TaxonomyEntryNoParent } from '../../libs/api/taxonomy';
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
    family: yup.array().required(),
    // only force hosts to be present when adding, not deleting.
    hosts: yup.array().when('del', {
        is: false,
        then: yup.array().required(),
    }),
});

export type FormFields = AdminFormFields<AT.GallApi> & {
    genus: TaxonomyEntryNoParent[];
    family: TaxonomyEntryNoParent[];
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
    undescribed: boolean;
};

const updateGall = (s: AT.GallApi, newValue: string): AT.GallApi => ({
    ...s,
    name: newValue,
});

// const fetchFGS = async (h: AT.GallApi): Promise<FGS> => {
//     const res = await fetch(`../api/taxonomy?id=${h.id}`);
//     if (res.status === 200) {
//         return await res.json();
//     } else {
//         console.error(await res.text());
//         throw new Error('Failed to fetch taxonomy for the selected species. Check console.');
//     }
// };

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
    const [showNewUndescribed, setShowNewUndescribed] = useState(false);

    const toUpsertFields = (fields: FormFields, name: string, id: number): AT.GallUpsertFields => {
        return {
            gallid: hasProp(fields.mainField[0], 'gall') ? fields.mainField[0].gall.id : -1,
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
            undescribed: fields.undescribed,
            walls: fields.walls.map((w) => w.id),
        };
    };

    const updatedFormFields = async (s: AT.GallApi | undefined): Promise<FormFields> => {
        if (s != undefined) {
            setAliasData(s?.aliases);
            return {
                mainField: [s],
                genus: [s.fgs.genus],
                family: [s.fgs.family],
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
                undescribed: s.gall.undescribed,
                del: false,
            };
        }

        setAliasData([]);
        return {
            mainField: [],
            genus: [],
            family: [],
            abundance: [AT.EmptyAbundance],
            datacomplete: false,
            detachable: AT.DetachableNone.value,
            undescribed: false,
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

    const fgsFromName = (name: string): FGS => {
        const genusName = extractGenus(name);
        const genus = genera.find((g) => g.name.localeCompare(genusName) == 0);
        const family = genus?.parent ? pipe(genus.parent, O.getOrElseW(constant(undefined))) : undefined;

        return {
            family: family ? family : { id: -1, description: '', name: '', type: FAMILY },
            genus: genus ? { ...genus } : { id: -1, description: '', name: genusName, type: GENUS },
            section: O.none,
        };
    };

    const createNewGall = (name: string): AT.GallApi => ({
        name: name,
        abundance: O.none,
        aliases: [],
        datacomplete: false,
        description: O.none,
        fgs: fgsFromName(name),
        id: -1,
        images: [],
        speciessource: [],
        taxoncode: AT.GallTaxon,
        gall: {
            detachable: AT.DetachableNone,
            gallalignment: [],
            gallcells: [],
            gallcolor: [],
            galllocation: [],
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
        form,
        formSubmit,
        mainField,
    } = useAdmin(
        'Gall',
        id,
        gs,
        updateGall,
        toUpsertFields,
        { keyProp: 'name', delEndpoint: '../api/gall/', upsertEndpoint: '../api/gall/upsert' },
        schema,
        updatedFormFields,
        createNewGall,
    );

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
                    };
                    return Promise.bind(onSubmit(fields));
                });
            } else {
                fields.genus[0] = g;
            }
        }

        return onSubmit(fields);
    };

    const newUndescribedDone = (data: UndescribedData | undefined) => {
        setShowNewUndescribed(false);
        if (data != undefined) {
            const newG = createNewGall(data.name);
            newG.hosts = [data.host];
            newG.fgs.genus = data.genus;
            newG.fgs.family = data.family;
            newG.gall.undescribed = true;
            // form.setValue(mainField.name as Path<FormFields>, [
            //     { customOption: true, id: '-1', name: data.name } as TypeaheadCustomOption,
            // ]);
            // form.setValue('genus', [data.genus]);
            // form.setValue('family', [data.family]);
            // form.setValue('hosts', [data.host]);
            // form.setValue('undescribed', true);
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
            editName={{ getDefault: () => selected?.name, renameCallback: renameCallback(rename) }}
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
                            {/* 
                                    onChangeWithNew={(e, isNew) => {
                                        if (isNew || !e[0]) {
                                            setSelected(undefined);
                                            const g = genera.find((g) => g.name.localeCompare(e[0]?.name) == 0);
                                            form.setValue(
                                                'genus',
                                                g
                                                    ? [g]
                                                    : [
                                                          {
                                                              id: -1,
                                                              name: e[0] ? extractGenus(e[0].name) : '',
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
                                */}
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
                                if (selected) {
                                    // handle the case when a new species is created
                                    const genus = genera.find((gg) => gg.id === selected.fgs.genus.id);
                                    if (genus && O.isNone(genus.parent)) {
                                        genus.parent = O.some({ ...f[0], parent: O.none });
                                        setSelected({ ...selected, fgs: { ...selected.fgs, genus: genus } });
                                    }
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
                        <select {...form.register('detachable')} placeholder="Detachable" className="form-control">
                            {AT.Detachables.map((d) => (
                                <option key={d.id}>{d.value}</option>
                            ))}
                        </select>
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
                        <input {...form.register('datacomplete')} type="checkbox" className="form-input-checkbox" /> All sources
                        containing unique information relevant to this gall have been added and are reflected in its associated
                        data. However, filter criteria may not be comprehensive in every field.
                    </Col>
                </Row>
                <Row className="formGroups pb-1">
                    <Col className="mr-auto">
                        <input {...form.register('undescribed')} type="checkbox" className="form-input-checkbox" /> Undescribed?
                    </Col>
                </Row>
                <Row className="fromGroup pb-1" hidden={!selected}>
                    <Col className="mr-auto">
                        <input {...form.register('del')} type="checkbox" className="form-input-checkbox" /> Delete?
                    </Col>
                </Row>
                <Row className="formGroup pb-1">
                    <Col>
                        <input type="submit" className="button" value="Submit" />
                    </Col>
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
