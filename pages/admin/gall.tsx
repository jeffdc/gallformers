import axios from 'axios';
import * as O from 'fp-ts/lib/Option';
import { constant, pipe } from 'fp-ts/lib/function';
import * as t from 'io-ts';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import { ParsedUrlQuery } from 'querystring';
import { useState } from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import { Controller } from 'react-hook-form';
import Typeahead, { AsyncTypeahead } from '../../components/Typeahead';
import UndescribedFlow, { UndescribedData } from '../../components/UndescribedFlow';
import AliasTable from '../../components/aliastable';
import useSpecies, { SpeciesNamingHelp, SpeciesProps, speciesFormFieldsSchema } from '../../hooks/useSpecies';
import useAdmin from '../../hooks/useadmin';
import { extractQueryParam } from '../../libs/api/apipage';
import { AbundanceApi, AliasApi, FilterField, GALL_FAMILY_TYPES, GallUpsertFields } from '../../libs/api/apitypes';
import {
    DetachableNone,
    Detachables,
    GallApi,
    GallApiSchema,
    GallPropertiesSchema,
    HostSimple,
    TaxonCodeValues,
    detachableFromString,
} from '../../libs/api/apitypes';
import { TaxonomyEntry, TaxonomyTypeValues } from '../../libs/api/apitypes';
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
import { hasProp, mightFailWithArray } from '../../libs/utils/util';

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

const schema = t.intersection([speciesFormFieldsSchema(GallApiSchema), GallPropertiesSchema]);

export type FormFields = t.TypeOf<typeof schema>;

// const schema: yup.ObjectSchema<FormFields> = yup.object({
//     mainField: yup
//         .array()
//         .of(
//             yup.object({
//                 name: yup.string().matches(SPECIES_NAME_REGEX).required(),
//             }),
//         )
//         .min(1)
//         .max(1),
//     family: yup
//         .array()
//         .of(
//             yup.object({
//                 name: yup.string().required(),
//             }),
//         )
//         .required(),
//     // only force hosts to be present when adding, not deleting.
//     hosts: yup.array().when('del', {
//         is: false,
//         then: () => yup.array().min(1),
//     }),
//     del: yup.boolean().required(),
//     detachable: yup.boolean(),
//     walls: yup.array(),
//     cells: yup.array(),
//     alignments: yup.array(),
//     shapes: yup.array(),
//     colors: yup.array(),
//     seasons: yup.array(),
//     locations: yup.array(),
//     textures: yup.array(),
//     forms: yup.array(),
//     undescribed: yup.boolean(),
//     genus: yup.mixed(),
//     datacomplete: yup.boolean(),
//     abundance: yup.mixed(),
//     aliases: yup.array(),
// });

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
            gallid: hasProp(fields.mainField[0], 'gall') ? (fields.mainField[0] as GallApi).gall_id : -1,
            alignments: fields.alignment.map((a) => a.id),
            cells: fields.cells.map((c) => c.id),
            colors: fields.color.map((c) => c.id),
            seasons: fields.season.map((c) => c.id),
            detachable: fields.detachable.value,
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

    const {
        selected,
        setSelected,
        showRenameModal,
        setShowRenameModal,
        error,
        isValid,
        setError,
        deleteResults,
        setDeleteResults,
        renameCallback,
        nameExists,
        confirm,
        form,
        formSubmit,
        mainField,
        deleteButton,
    } = useAdmin(
        'Gall',
        id,
        renameSpecies,
        toUpsertFields,
        {
            keyProp: 'name',
            delEndpoint: '../api/gall/',
            upsertEndpoint: '../api/gall/upsert',
            nameExistsEndpoint: (s: string) => `/api/species?name=${s}`,
        },
        schema,
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
            fields.genus = [{ id: -1, description: '', name: 'Unknown', type: TaxonomyTypeValues.GENUS }];
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

    return (
        <Admin
            type="Gall"
            keyField="name"
            editName={{
                getDefault: () => selected?.name,
                renameCallback: renameCallback,
                nameExistsCallback: nameExists,
            }}
            setShowModal={setShowRenameModal}
            showModal={showRenameModal}
            setError={setError}
            error={error}
            setDeleteResults={setDeleteResults}
            deleteResults={deleteResults}
            selected={selected}
        >
            <form onSubmit={form.handleSubmit(onSubmit)} className="m-4 pe-4">
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
                                {mainField('name', 'Gall', {
                                    searchEndpoint: (s: string) => `../api/gall?q=${s}`,
                                    promptText: 'Gall',
                                    searchText: 'Searching for Galls...',
                                })}
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
                <Row className="my-1">
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
                                    selected.fgs.genus = g[0] as TaxonomyEntry;
                                    setSelected({ ...selected });
                                }
                            }}
                            clearButton
                            multiple
                        />
                    </Col>
                    <Col>
                        Family (required):
                        <Typeahead
                            name="family"
                            control={form.control}
                            rules={{ required: true }}
                            placeholder="Family"
                            options={families}
                            labelKey="name"
                            selected={selected?.fgs?.family && selected.fgs.family.id >= 0 ? [selected.fgs.family] : []}
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
                                        setSelected({ ...selected, fgs: { ...selected.fgs, family: fam } });
                                    } else {
                                        selected.fgs = { ...selected.fgs, family: fam };
                                        setSelected({ ...selected });
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
                </Row>
                <Row className="my-1">
                    <Col>
                        Hosts (required):
                        <AsyncTypeahead
                            name="hosts"
                            control={form.control}
                            placeholder="Hosts"
                            options={hosts}
                            labelKey="name"
                            multiple
                            disabled={!selected}
                            selected={selected ? selected.hosts : []}
                            onChange={(h) => {
                                if (selected) {
                                    selected.hosts = h;
                                    setSelected({ ...selected });
                                }
                            }}
                            clearButton
                            isLoading={isLoading}
                            onSearch={handleSearch}
                        />
                        {form.formState.errors.hosts && (
                            <span className="text-danger">You must map this gall to at least one host.</span>
                        )}
                    </Col>
                </Row>
                <Row className="my-1">
                    <Col>
                        Detachable:
                        <Controller
                            control={form.control}
                            name="detachable"
                            render={({ field: { ref } }) => (
                                <select
                                    ref={ref}
                                    value={selected ? selected.detachable.value : DetachableNone.value}
                                    onChange={(e) => {
                                        if (selected) {
                                            selected.detachable = detachableFromString(e.currentTarget.value);
                                            setSelected({ ...selected });
                                        }
                                    }}
                                    placeholder="Detachable"
                                    className="form-control"
                                    disabled={areRequiredFieldsFilled()}
                                >
                                    {Detachables.map((d) => (
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
                            labelKey="field"
                            multiple
                            clearButton
                            disabled={areRequiredFieldsFilled()}
                            selected={selected ? selected.walls : []}
                            onChange={(w) => {
                                if (selected) {
                                    selected.walls = w as FilterField[];
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
                            labelKey="field"
                            multiple
                            clearButton
                            disabled={areRequiredFieldsFilled()}
                            selected={selected ? selected.cells : []}
                            onChange={(w) => {
                                if (selected) {
                                    selected.cells = w as FilterField[];
                                    setSelected({ ...selected });
                                }
                            }}
                        />
                    </Col>
                    <Col>
                        Alignment(s):
                        <Typeahead
                            name="alignment"
                            control={form.control}
                            options={alignments}
                            labelKey="field"
                            multiple
                            clearButton
                            disabled={areRequiredFieldsFilled()}
                            selected={selected ? selected.alignment : []}
                            onChange={(w) => {
                                if (selected) {
                                    selected.alignment = w as FilterField[];
                                    setSelected({ ...selected });
                                }
                            }}
                        />
                    </Col>
                </Row>
                <Row className="my-1">
                    <Col>
                        Color(s):
                        <Typeahead
                            name="color"
                            control={form.control}
                            options={colors}
                            labelKey="field"
                            multiple
                            clearButton
                            disabled={areRequiredFieldsFilled()}
                            selected={selected ? selected.color : []}
                            onChange={(w) => {
                                if (selected) {
                                    selected.color = w as FilterField[];
                                    setSelected({ ...selected });
                                }
                            }}
                        />
                    </Col>
                    <Col>
                        Shape(s):
                        <Typeahead
                            name="shape"
                            control={form.control}
                            options={shapes}
                            labelKey="field"
                            multiple
                            clearButton
                            disabled={areRequiredFieldsFilled()}
                            selected={selected ? selected.shape : []}
                            onChange={(w) => {
                                if (selected) {
                                    selected.shape = w as FilterField[];
                                    setSelected({ ...selected });
                                }
                            }}
                        />
                    </Col>
                    <Col>
                        Season(s):
                        <Typeahead
                            name="season"
                            control={form.control}
                            options={seasons}
                            labelKey="field"
                            multiple
                            clearButton
                            disabled={areRequiredFieldsFilled()}
                            selected={selected ? selected.season : []}
                            onChange={(w) => {
                                if (selected) {
                                    selected.season = w as FilterField[];
                                    setSelected({ ...selected });
                                }
                            }}
                        />
                    </Col>
                    <Col>
                        Form(s):
                        <Typeahead
                            name="form"
                            control={form.control}
                            options={forms}
                            labelKey="field"
                            multiple
                            clearButton
                            disabled={areRequiredFieldsFilled()}
                            selected={selected ? selected.form : []}
                            onChange={(w) => {
                                if (selected) {
                                    selected.form = w as FilterField[];
                                    setSelected({ ...selected });
                                }
                            }}
                        />
                    </Col>
                </Row>
                <Row className="my-1">
                    <Col>
                        Location(s):
                        <Typeahead
                            name="location"
                            control={form.control}
                            options={locations}
                            labelKey="field"
                            multiple
                            clearButton
                            disabled={areRequiredFieldsFilled()}
                            selected={selected ? selected.location : []}
                            onChange={(w) => {
                                if (selected) {
                                    selected.location = w as FilterField[];
                                    setSelected({ ...selected });
                                }
                            }}
                        />
                    </Col>
                    <Col>
                        Texture(s):
                        <Typeahead
                            name="texture"
                            control={form.control}
                            options={textures}
                            labelKey="field"
                            multiple
                            clearButton
                            disabled={areRequiredFieldsFilled()}
                            selected={selected ? selected.texture : []}
                            onChange={(w) => {
                                if (selected) {
                                    selected.texture = w as FilterField[];
                                    setSelected({ ...selected });
                                }
                            }}
                        />
                    </Col>
                    <Col>
                        Abundance:
                        <Typeahead
                            name="abundance"
                            control={form.control}
                            options={abundances}
                            labelKey="abundance"
                            disabled={areRequiredFieldsFilled()}
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
                                    selected.abundance = O.fromNullable(g[0] as AbundanceApi);
                                    setSelected({ ...selected });
                                }
                            }}
                            clearButton
                        />
                    </Col>
                </Row>
                <Row className="my-1">
                    <Col>
                        <Controller
                            control={form.control}
                            name="aliases"
                            render={() => (
                                <AliasTable
                                    data={selected?.aliases ?? []}
                                    setData={(aliases: AliasApi[]) => {
                                        if (selected) {
                                            selected.aliases = aliases;
                                            setSelected({ ...selected });
                                        }
                                    }}
                                    disabled={areRequiredFieldsFilled()}
                                />
                            )}
                        ></Controller>
                    </Col>
                </Row>
                <Row className="formGroup pb-1">
                    <Col className="me-auto">
                        <Controller
                            control={form.control}
                            name="datacomplete"
                            render={({ field: { ref } }) => (
                                <input
                                    ref={ref}
                                    type="checkbox"
                                    className="form-input-checkbox"
                                    checked={selected ? selected.datacomplete : false}
                                    disabled={areRequiredFieldsFilled()}
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
                    <Col className="me-auto">
                        <Controller
                            control={form.control}
                            name="undescribed"
                            render={({ field: { ref } }) => (
                                <input
                                    ref={ref}
                                    type="checkbox"
                                    className="form-input-checkbox"
                                    checked={selected ? selected.undescribed : false}
                                    disabled={areRequiredFieldsFilled()}
                                    onChange={(e) => {
                                        if (selected) {
                                            selected.undescribed = e.currentTarget.checked;
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
                        <input type="submit" className="button" value="Submit" disabled={!selected || !isValid} />
                    </Col>
                    <Col>{deleteButton('Caution. All data associated with this Gall will be deleted.')}</Col>
                </Row>
            </form>
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
