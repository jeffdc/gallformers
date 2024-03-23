import axios from 'axios';
import * as O from 'fp-ts/lib/Option';
import { constant, pipe } from 'fp-ts/lib/function';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import { ParsedUrlQuery } from 'querystring';
import { useState } from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import { AsyncTypeahead, Typeahead } from 'react-bootstrap-typeahead';
import { Controller } from 'react-hook-form';
import UndescribedFlow, { UndescribedData } from '../../components/UndescribedFlow';
import AliasTable from '../../components/aliastable';
import useSpecies, { SpeciesFormFields, SpeciesNamingHelp, SpeciesProps } from '../../hooks/useSpecies';
import useAdmin from '../../hooks/useadmin';
import { extractQueryParam } from '../../libs/api/apipage';
import {
    AbundanceApi,
    AliasApi,
    DetachableApi,
    DetachableNone,
    Detachables,
    FilterField,
    GALL_FAMILY_TYPES,
    GallApi,
    GallPropertiesType,
    GallUpsertFields,
    HostSimple,
    TaxonCodeValues,
    TaxonomyEntry,
    TaxonomyTypeValues,
} from '../../libs/api/apitypes';
import {
    getAlignments,
    getCells,
    getColors,
    getForms,
    getLocations,
    getSeasons,
    getShapes,
    getTextures,
    getWalls,
} from '../../libs/db/filterfield';
import { gallById } from '../../libs/db/gall';
import { getAbundances } from '../../libs/db/species';
import { allFamilies, allGenera } from '../../libs/db/taxonomy';
import Admin from '../../libs/pages/admin';
import { mightFailWithArray } from '../../libs/utils/util';

type Props = SpeciesProps & {
    gall: GallApi[];
    locations: FilterField[];
    colors: FilterField[];
    seasons: FilterField[];
    shapes: FilterField[];
    textures: FilterField[];
    alignments: FilterField[];
    walls: FilterField[];
    cells: FilterField[];
    forms: FilterField[];
};

export type FormFields = SpeciesFormFields<GallApi> & GallPropertiesType;

const keyFieldName = 'name';

const Gall = ({
    id,
    gall,
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
    forms,
}: Props): JSX.Element => {
    const [showNewUndescribed, setShowNewUndescribed] = useState(false);
    const { renameSpecies, createNewSpecies, updatedSpeciesFormFields, toSpeciesUpsertFields } = useSpecies<GallApi, FormFields>(
        genera,
    );
    const [hosts, setHosts] = useState<HostSimple[]>([]);
    const [isLoading, setIsLoading] = useState(false);

    const toUpsertFields = (fields: FormFields, name: string, id: number): GallUpsertFields => {
        if (!selected) {
            throw new Error('Trying to submit with a null selection which seems impossible but here we are.');
        }

        return {
            ...toSpeciesUpsertFields(fields, name, id),
            gallid: fields.mainField[0].gall_id,
            alignments: fields.alignment.map((a) => a.id),
            cells: fields.cells.map((c) => c.id),
            colors: fields.color.map((c) => c.id),
            seasons: fields.season.map((c) => c.id),
            detachable: fields.detachable,
            fgs: selected.fgs,
            hosts: fields.hosts.map((h) => h.id),
            locations: fields.location.map((l) => l.id),
            shapes: fields.shape.map((s) => s.id),
            textures: fields.texture.map((t) => t.id),
            undescribed: fields.undescribed,
            walls: fields.walls.map((w) => w.id),
            forms: fields.form.map((f) => f.id),
        };
    };

    const updatedFormFields = async (s: GallApi | undefined): Promise<FormFields> => {
        const speciesFields = updatedSpeciesFormFields(s);

        if (s != undefined) {
            return {
                ...speciesFields,
                alignment: s.alignment,
                cells: s.cells,
                color: s.color,
                detachable: s.detachable,
                hosts: s.hosts,
                location: s.location,
                season: s.season,
                shape: s.shape,
                texture: s.texture,
                undescribed: s.undescribed,
                walls: s.walls,
                form: s.form,
            };
        }

        return {
            ...speciesFields,
            alignment: [],
            cells: [],
            color: [],
            detachable: DetachableNone,
            hosts: [],
            location: [],
            season: [],
            shape: [],
            texture: [],
            undescribed: false,
            walls: [],
            form: [],
        };
    };

    const createNewGall = (name: string): GallApi => ({
        ...createNewSpecies(name, TaxonCodeValues.GALL),
        detachable: DetachableNone,
        alignment: [],
        cells: [],
        color: [],
        location: [],
        season: [],
        shape: [],
        texture: [],
        walls: [],
        form: [],
        undescribed: false,
        id: -1,
        hosts: [],
        excludedPlaces: [],
        gall_id: -1,
    });

    const { selected, renameCallback, nameExists, confirm, ...adminForm } = useAdmin(
        'Gall',
        keyFieldName,
        id,
        renameSpecies,
        toUpsertFields,
        {
            delEndpoint: '../api/gall/',
            upsertEndpoint: '../api/gall/upsert',
            nameExistsEndpoint: (s: string) => `/api/species?name=${s}`,
        },
        updatedFormFields,
        true,
        createNewGall,
        gall,
    );

    const areRequiredFieldsFilled = () => {
        return !(selected && selected.fgs.family.id >= 0 && selected.hosts.length > 0);
    };

    const newUndescribedDone = (data: UndescribedData | undefined) => {
        setShowNewUndescribed(false);
        if (data != undefined) {
            const newG = createNewGall(data.name);
            newG.hosts = [{ ...data.host, places: [] }];
            newG.fgs.genus = data.genus;
            newG.fgs.family = data.family;
            newG.undescribed = true;
            adminForm.setSelected(newG);
        }
    };

    const onSubmit = async (fields: FormFields): Promise<void> => {
        if (!selected) {
            console.error(
                `Can not save. Looks like the genus and/or family are empty. We should not be in this pickle, yet here we are.`,
            );
            return;
        }

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
            fields.genus = [{ id: -1, description: '', name: 'Unknown', type: TaxonomyTypeValues.GENUS }];
        }

        // if either genus or family is Unknown and the undescribed box is not checked they are probably messing up
        if (!fields.undescribed && (genus.name.localeCompare('Unknown') == 0 || family.name.localeCompare('Unknown') == 0)) {
            return confirm({
                variant: 'danger',
                catchOnCancel: true,
                title: 'Unknown Genus/Family But Not Undescribed!',
                message: `The gall is assigned to an Unknown genus/family but it is not marked as undescribed. This is almost certainly an error. Do you really want to proceed?`,
            })
                .then(() => Promise.bind(adminForm.formSubmit(fields)))
                .catch(() => Promise.resolve()) as Promise<void>;
        }

        return adminForm.formSubmit(fields);
    };

    const handleSearch = (s: string) => {
        setIsLoading(true);

        axios
            .get<HostSimple[]>(`../api/host?q=${s}&simple`)
            .then((resp) => {
                setHosts(resp.data);
                setIsLoading(false);
            })
            .catch((e) => {
                console.error(e);
            });
    };

    const createGallPropertyField = (name: keyof FormFields, items: FilterField[], multiple = true) => (
        <Controller
            control={adminForm.form.control}
            name={name}
            render={() => (
                <Typeahead
                    id={name}
                    options={items}
                    labelKey="field"
                    multiple={multiple}
                    clearButton
                    {...adminForm.form.register(name, {
                        disabled: areRequiredFieldsFilled(),
                    })}
                    onChange={(x) => {
                        if (selected) {
                            // @ts-expect-error breaking type safety here as it is non-trivial (and not seemingly worth it)
                            // to pass the property name in a type safe manner
                            selected[name] = x as FilterField[];
                            adminForm.setSelected({ ...selected });
                        }
                    }}
                    // @ts-expect-error breaking type safety here as it is non-trivial (and not seemingly worth it)
                    // to pass the property name in a type safe manner
                    selected={selected ? selected[name] : []}
                />
            )}
        />
    );

    return (
        <Admin
            type="Gall"
            keyField="name"
            editName={{
                getDefault: () => selected?.name,
                renameCallback: renameCallback,
                nameExistsCallback: nameExists,
            }}
            selected={selected}
            {...adminForm}
            deleteButton={adminForm.deleteButton(
                'Caution. All data associated with this Gall will be PERMANENTLY deleted.',
                false,
            )}
            saveButton={adminForm.saveButton()}
            formSubmit={onSubmit}
        >
            <>
                <UndescribedFlow show={showNewUndescribed} onClose={newUndescribedDone} genera={genera} families={families} />
                <h4>Add/Edit Gallformers</h4>
                <p>
                    This is for all of the details about a Gall. To add a description (which must be referenced to a source) go
                    add <Link href="/admin/source">Sources</Link>, if they do not already exist, then go{' '}
                    <Link href="/admin/speciessource">map species to sources with description</Link>. To associate a gall with all
                    plants in a genus, add one species here first, then go to <Link href="./gallhost">Gall-Host Mappings</Link>.
                </p>
                <Row className="my-1">
                    <Col>
                        <Row hidden={!!selected} className="formGroup">
                            <Col>
                                <Button className="btn-sm" disabled={!!selected} onClick={() => setShowNewUndescribed(true)}>
                                    Add Undescribed
                                </Button>
                            </Col>
                        </Row>
                        <Row>
                            <Col xs={8}>
                                Name (binomial):
                                <SpeciesNamingHelp />
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                {/* // name: yup.string().matches(SPECIES_NAME_REGEX).required(), */}
                                {adminForm.mainField('Gall', {
                                    searchEndpoint: (s: string) => `../api/gall?q=${s}`,
                                    promptText: 'Gall',
                                    searchText: 'Searching for Galls...',
                                })}
                            </Col>
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
                        </Row>
                    </Col>
                </Row>
                <Row className="my-1">
                    <Col>
                        Genus (filled automatically):
                        <Controller
                            control={adminForm.form.control}
                            name="genus"
                            render={() => (
                                <Typeahead
                                    id="genus"
                                    placeholder="Genus"
                                    options={genera}
                                    labelKey="name"
                                    disabled={true}
                                    onChange={(g) => {
                                        if (selected) {
                                            selected.fgs.genus = g[0] as TaxonomyEntry;
                                            adminForm.setSelected({ ...selected });
                                        }
                                    }}
                                    selected={selected?.fgs?.genus ? [selected.fgs.genus] : []}
                                    clearButton
                                    multiple
                                />
                            )}
                        />
                    </Col>
                    <Col>
                        Family (required):
                        <Controller
                            control={adminForm.form.control}
                            name="genus"
                            render={() => (
                                <Typeahead
                                    id="family"
                                    placeholder="Family"
                                    options={families}
                                    labelKey="name"
                                    disabled={(selected && selected.id > 0) || !selected}
                                    onChange={(f) => {
                                        if (!selected) return;

                                        if (f && f.length > 0) {
                                            // handle the case when a new species is created
                                            // either the genus is new or is not
                                            const fam = f[0] as TaxonomyEntry;
                                            const genus = genera.find((gg) => gg.id === selected.fgs.genus.id);
                                            if (genus && O.isNone(genus.parent)) {
                                                genus.parent = O.some({ ...fam, parent: O.none });
                                                selected.fgs = { ...selected.fgs, genus: genus };
                                                adminForm.setSelected({ ...selected, fgs: { ...selected.fgs, family: fam } });
                                            } else {
                                                selected.fgs = { ...selected.fgs, family: fam };
                                                adminForm.setSelected({ ...selected });
                                            }
                                        } else {
                                            selected.fgs = {
                                                ...selected.fgs,
                                                family: {
                                                    name: '',
                                                    description: '',
                                                    id: -1,
                                                    type: TaxonomyTypeValues.FAMILY,
                                                    parent: O.none,
                                                },
                                            };
                                            adminForm.setSelected({ ...selected });
                                        }
                                    }}
                                    selected={selected?.fgs?.family && selected.fgs.family.id >= 0 ? [selected.fgs.family] : []}
                                    clearButton
                                />
                            )}
                        />
                        {adminForm.form.formState.errors.family && (
                            <span className="text-danger">
                                The Family name is required. If it is not present in the list you will have to go add the family
                                first. :(
                            </span>
                        )}
                    </Col>
                </Row>
                <Row className="my-1">
                    <Col>
                        Hosts (required):
                        <Controller
                            control={adminForm.form.control}
                            name="hosts"
                            render={() => (
                                <AsyncTypeahead
                                    id="hosts"
                                    placeholder="Hosts"
                                    options={hosts}
                                    labelKey="name"
                                    multiple
                                    disabled={!selected}
                                    onChange={(h) => {
                                        if (selected) {
                                            selected.hosts = h as HostSimple[];
                                            adminForm.setSelected({ ...selected });
                                        }
                                    }}
                                    selected={selected ? selected.hosts : []}
                                    clearButton
                                    isLoading={isLoading}
                                    onSearch={handleSearch}
                                />
                            )}
                        />
                        {adminForm.form.formState.errors.hosts && (
                            <span className="text-danger">You must map this gall to at least one host.</span>
                        )}
                    </Col>
                </Row>
                <Row className="my-1">
                    <Col>
                        Detachable:
                        <Controller
                            control={adminForm.form.control}
                            name="detachable"
                            render={() => (
                                <Typeahead
                                    id="detachable"
                                    options={Detachables}
                                    labelKey="value"
                                    disabled={areRequiredFieldsFilled()}
                                    onChange={(d) => {
                                        if (selected?.detachable) {
                                            selected.detachable = d[0] as DetachableApi;
                                            adminForm.setSelected({ ...selected });
                                        }
                                    }}
                                    aria-placeholder="Detachable"
                                    selected={selected ? [selected.detachable] : []}
                                    clearButton
                                />
                            )}
                        />
                        {/* <select
                            {...adminForm.form.register('detachable', {
                                disabled: areRequiredFieldsFilled(),
                                onChange: (e) => {
                                    if (selected) {
                                        selected.detachable = detachableFromString(e.currentTarget.value);
                                        adminForm.setSelected({ ...selected });
                                    }
                                },
                            })}
                            value={selected ? selected.detachable.value : DetachableNone.value}
                            aria-placeholder="Detachable"
                            className="form-control"
                        >
                            {Detachables.map((d) => (
                                <option key={d.id}>{d.value}</option>
                            ))}
                        </select> */}
                    </Col>
                    <Col>Walls:{createGallPropertyField('walls', walls)}</Col>
                    <Col>Cells: {createGallPropertyField('cells', cells)}</Col>
                    <Col>Alignment(s): {createGallPropertyField('alignment', alignments)}</Col>
                </Row>
                <Row className="my-1">
                    <Col>Color(s): {createGallPropertyField('color', colors)}</Col>
                    <Col>Shape(s): {createGallPropertyField('shape', shapes)}</Col>
                    <Col>Season(s): {createGallPropertyField('season', seasons)}</Col>
                    <Col>Form(s): {createGallPropertyField('form', forms)}</Col>
                </Row>
                <Row className="my-1">
                    <Col>Location(s): {createGallPropertyField('location', locations)}</Col>
                    <Col>Texture(s): {createGallPropertyField('texture', textures)}</Col>
                    <Col>
                        Abundance:
                        <Controller
                            control={adminForm.form.control}
                            name="abundance"
                            render={() => (
                                <Typeahead
                                    id="abundance"
                                    options={abundances}
                                    labelKey="abundance"
                                    disabled={areRequiredFieldsFilled()}
                                    onChange={(a) => {
                                        if (selected) {
                                            selected.abundance = O.fromNullable(a[0] as AbundanceApi);
                                            adminForm.setSelected({ ...selected });
                                        }
                                    }}
                                    selected={
                                        selected?.abundance
                                            ? pipe(
                                                  selected.abundance,
                                                  O.fold(constant([]), (a) => [a]),
                                              )
                                            : []
                                    }
                                    clearButton
                                />
                            )}
                        />
                    </Col>
                </Row>
                <Row className="my-1">
                    <Col>
                        <Controller
                            control={adminForm.form.control}
                            name="aliases"
                            render={() => (
                                <AliasTable
                                    data={selected?.aliases ?? []}
                                    setData={(aliases: AliasApi[]) => {
                                        if (selected) {
                                            selected.aliases = aliases;
                                            adminForm.setSelected({ ...selected });
                                        }
                                    }}
                                    disabled={areRequiredFieldsFilled()}
                                />
                            )}
                        />
                    </Col>
                </Row>
                <Row className="formGroup pb-1">
                    <Col className="me-auto">
                        <input
                            {...adminForm.form.register('datacomplete', {
                                disabled: areRequiredFieldsFilled(),
                                onChange: (e) => {
                                    if (selected) {
                                        selected.datacomplete = e.currentTarget.checked;
                                        adminForm.setSelected({ ...selected });
                                    }
                                },
                            })}
                            type="checkbox"
                            className="form-input-checkbox"
                            checked={selected ? selected.datacomplete : false}
                        />{' '}
                        All sources containing unique information relevant to this gall have been added and are reflected in its
                        associated data. However, filter criteria may not be comprehensive in every field.
                    </Col>
                </Row>
                <Row className="formGroup pb-1">
                    <Col className="me-auto">
                        <input
                            {...adminForm.form.register('undescribed', {
                                disabled: areRequiredFieldsFilled(),
                                onChange: (e) => {
                                    if (selected) {
                                        selected.undescribed = e.currentTarget.checked;
                                        adminForm.setSelected({ ...selected });
                                    }
                                },
                            })}
                            type="checkbox"
                            className="form-input-checkbox"
                            checked={selected ? selected.undescribed : false}
                        />{' '}
                        Undescribed?
                    </Col>
                </Row>
            </>
        </Admin>
    );
};

export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery }) => {
    const id = extractQueryParam(context.query, 'id');
    const gall = pipe(
        id,
        O.map(parseInt),
        O.map((id) => mightFailWithArray<GallApi>()(gallById(id))),
        O.getOrElse(constant(Promise.resolve(Array<GallApi>()))),
    );
    return {
        props: {
            id: O.getOrElseW(constant(null))(id),
            gall: await gall,
            families: await mightFailWithArray<TaxonomyEntry>()(allFamilies(GALL_FAMILY_TYPES)),
            genera: await mightFailWithArray<TaxonomyEntry>()(allGenera(TaxonCodeValues.GALL, true)),
            locations: await mightFailWithArray<FilterField>()(getLocations()),
            colors: await mightFailWithArray<FilterField>()(getColors()),
            seasons: await mightFailWithArray<FilterField>()(getSeasons()),
            shapes: await mightFailWithArray<FilterField>()(getShapes()),
            textures: await mightFailWithArray<FilterField>()(getTextures()),
            alignments: await mightFailWithArray<FilterField>()(getAlignments()),
            walls: await mightFailWithArray<FilterField>()(getWalls()),
            cells: await mightFailWithArray<FilterField>()(getCells()),
            abundances: await mightFailWithArray<AbundanceApi>()(getAbundances()),
            forms: await mightFailWithArray<FilterField>()(getForms()),
        },
    };
};

export default Gall;
