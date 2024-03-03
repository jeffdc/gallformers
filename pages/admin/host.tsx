import * as O from 'fp-ts/lib/Option';
import { constant, pipe } from 'fp-ts/lib/function';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import { ParsedUrlQuery } from 'querystring';
import { useState } from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import { Controller } from 'react-hook-form';
import { ComposableMap, Geographies, Geography, ProjectionConfig, ZoomableGroup } from 'react-simple-maps';
import { Tooltip } from 'react-tooltip';
import Typeahead from '../../components/Typeahead';
import AliasTable from '../../components/aliastable';
import useSpecies, { SpeciesFormFields, SpeciesNamingHelp, SpeciesProps } from '../../hooks/useSpecies';
import useAdmin from '../../hooks/useadmin';
import { extractQueryParam } from '../../libs/api/apipage';
import {
    AbundanceApi,
    AliasApi,
    HOST_FAMILY_TYPES,
    HostApi,
    PlaceNoTreeApi,
    SpeciesUpsertFields,
    TaxonCodeValues,
    TaxonomyEntry,
    TaxonomyEntryNoParent,
    TaxonomyTypeValues,
} from '../../libs/api/apitypes';
import { hostById } from '../../libs/db/host';
import { getPlaces } from '../../libs/db/place.ts';
import { getAbundances } from '../../libs/db/species';
import { allFamilies, allGenera, allSections } from '../../libs/db/taxonomy';
import Admin from '../../libs/pages/admin';
import { mightFailWithArray } from '../../libs/utils/util';

const projConfig: ProjectionConfig = {
    center: [-4, 48],
    parallels: [29.5, 45.5],
    rotate: [96, 0, 0],
    scale: 750,
};

type Props = SpeciesProps & {
    host: HostApi[];
    sections: TaxonomyEntry[];
    places: PlaceNoTreeApi[];
};

// const schema = yup.object().shape({
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
// });

export type FormFields = SpeciesFormFields<HostApi> & {
    section: TaxonomyEntryNoParent[];
    places: PlaceNoTreeApi[];
};

export const testables = {
    // Schema: schema,
};

const Host = ({ id, host, genera, families, sections, abundances, places }: Props): JSX.Element => {
    const [tooltipContent, setTooltipContent] = useState('');
    const { renameSpecies, createNewSpecies, updatedSpeciesFormFields, toSpeciesUpsertFields } = useSpecies<HostApi, FormFields>(
        genera,
    );

    const toUpsertFields = (fields: FormFields, name: string, id: number): SpeciesUpsertFields => {
        if (!selected) {
            throw new Error('Trying to submit with a null selection which seems impossible but here we are.');
        }

        return {
            ...toSpeciesUpsertFields(fields, name, id),
            fgs: { ...selected.fgs },
            places: selected.places,
        };
    };

    const updatedFormFields = async (s: HostApi | undefined): Promise<FormFields> => {
        const speciesFields = updatedSpeciesFormFields(s);
        if (s != undefined) {
            return {
                ...speciesFields,
                section: pipe(
                    s.fgs?.section,
                    O.fold(constant([]), (sec) => [sec]),
                ),
                places: s.places,
            };
        }

        return {
            ...speciesFields,
            section: [],
            places: [],
        };
    };

    const createNewHost = (name: string): HostApi => ({
        ...createNewSpecies(name, TaxonCodeValues.PLANT),
        galls: [],
        places: [],
    });

    const keyFieldName = 'name';

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
        nameExists,
        form,
        formSubmit,
        mainField,
        deleteButton,
        saveButton,
    } = useAdmin(
        'Host',
        keyFieldName,
        id,
        renameSpecies,
        toUpsertFields,
        {
            delEndpoint: '../api/host/',
            upsertEndpoint: '../api/host/upsert',
            nameExistsEndpoint: (s: string) => `/api/species?name=${s}`,
        },
        updatedFormFields,
        true,
        createNewHost,
        host,
    );

    const onSubmit = async (fields: FormFields) => {
        formSubmit(fields);
    };

    const selectAll = () => {
        if (selected) {
            selected.places = places;
            setSelected({ ...selected });
        }
    };

    const deselectAll = () => {
        if (selected) {
            selected.places = [];
            setSelected({ ...selected });
        }
    };

    const isInRange = (code: string): boolean => !!selected?.places.find((p) => p.code === code);

    return (
        <Admin
            type="Host"
            keyField={keyFieldName}
            editName={{ getDefault: () => selected?.name, renameCallback: renameCallback, nameExistsCallback: nameExists }}
            setShowModal={setShowRenameModal}
            showModal={showRenameModal}
            setError={setError}
            error={error}
            setDeleteResults={setDeleteResults}
            deleteResults={deleteResults}
            selected={selected}
            deleteButton={deleteButton('Caution. All data associated with this Host will be deleted.', false)}
            saveButton={saveButton()}
        >
            <form onSubmit={form.handleSubmit(onSubmit)} className="m-4 pe-4">
                <h4>Add/Edit Hosts</h4>
                <p>
                    This is for all of the details about a Host. To add a description (which must be referenced to a source) go
                    add <Link href="/admin/source">Sources</Link>, if they do not already exist, then go{' '}
                    <Link href="/admin/speciessource">map species to sources with description</Link>. If you want to assign a{' '}
                    <Link href="/admin/taxonomy">Family</Link> or <Link href="/admin/section">Section</Link> then you will need to
                    have created them first if they do not exist.
                </p>
                <Row className="my-1">
                    <Col>
                        <Row>
                            <Col xs={8}>
                                Name (binomial):
                                <SpeciesNamingHelp />
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                {mainField('Host', {
                                    searchEndpoint: (s) => `../api/host?q=${s}`,
                                    promptText: 'Type in a Host name.',
                                    searchText: 'Searching for Hosts...',
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
                            placeholder="Family"
                            options={families}
                            labelKey="name"
                            selected={selected?.fgs?.family && selected.fgs.family.id >= 0 ? [selected.fgs.family] : []}
                            disabled={!selected || (selected && selected.id > 0)}
                            onChange={(f) => {
                                if (!selected) return;

                                if (f && f.length > 0) {
                                    // handle the case when a new species is created
                                    // either the genus is new or is not
                                    const genus = genera.find((gg) => gg.id === selected.fgs.genus.id);
                                    const fam = f[0] as TaxonomyEntry;
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
                        Section:
                        <Typeahead
                            name="section"
                            control={form.control}
                            placeholder="Section"
                            options={sections}
                            labelKey="name"
                            selected={
                                selected?.fgs?.section
                                    ? pipe(
                                          selected.fgs.section,
                                          O.fold(constant([]), (s) => [s]),
                                      )
                                    : []
                            }
                            onChange={(g) => {
                                if (selected) {
                                    selected.fgs.section = O.fromNullable(g[0] as TaxonomyEntry);
                                    setSelected({ ...selected });
                                }
                            }}
                            disabled={!selected}
                            clearButton
                        />
                    </Col>
                    <Col>
                        Abundance:
                        <Typeahead
                            name="abundance"
                            control={form.control}
                            placeholder=""
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
                                    selected.abundance = O.fromNullable(g[0] as AbundanceApi);
                                    setSelected({ ...selected });
                                }
                            }}
                            clearButton
                        />
                    </Col>
                </Row>
                <Row className="m-1 border">
                    <Col xs={2}>
                        <Row className="my-2">
                            <Col>Legend:</Col>
                        </Row>
                        <Row className="p-1">
                            <Col
                                className="border d-flex justify-content-center"
                                style={{ fontWeight: 'bold', borderRadius: '5px', backgroundColor: 'ForestGreen' }}
                            >
                                In Range
                            </Col>
                        </Row>
                        <Row className="p-1">
                            <Col
                                className="border d-flex justify-content-center"
                                style={{ fontWeight: 'bold', borderRadius: '5px', backgroundColor: 'White' }}
                            >
                                Out of Range
                            </Col>
                        </Row>
                        <Row>
                            <Col className="my-2">Map Actions:</Col>
                        </Row>
                        <Row className="my-2">
                            <Col>
                                <Button variant="outline-secondary" size="sm" className="me-2" onClick={selectAll}>
                                    Select All
                                </Button>
                                <Button variant="outline-secondary" size="sm" onClick={deselectAll}>
                                    De-select All
                                </Button>
                            </Col>
                        </Row>
                    </Col>
                    <Col>
                        Range:
                        <ComposableMap
                            className="border"
                            projection="geoConicEqualArea"
                            projectionConfig={projConfig}
                            data-tip=""
                        >
                            <ZoomableGroup zoom={1} minZoom={0.75}>
                                <Geographies geography="../usa-can-topo.json">
                                    {({ geographies }) =>
                                        geographies.map((geo) => {
                                            const code = geo.properties.postal;
                                            return (
                                                <Geography
                                                    key={geo.rsmKey}
                                                    geography={geo}
                                                    stroke={'DarkSlateGray'}
                                                    // fill={inRange.has(code) ? 'ForestGreen' : 'White'}
                                                    fill={isInRange(code) ? 'ForestGreen' : 'White'}
                                                    style={{
                                                        default: { outline: 'none' },
                                                        hover: { outline: 'none' },
                                                        pressed: { outline: 'none' },
                                                    }}
                                                    onClick={() => {
                                                        if (selected && isInRange(code)) {
                                                            selected.places = selected.places.filter((p) => p.code !== code);
                                                            setSelected({ ...selected });
                                                        } else if (selected) {
                                                            const p = places.find((p) => p.code === code);
                                                            if (p) {
                                                                selected?.places.push(p);
                                                                setSelected({ ...selected });
                                                            }
                                                        }
                                                    }}
                                                    onMouseEnter={() => setTooltipContent(`${code} - ${geo.properties.name}`)}
                                                    onMouseLeave={() => setTooltipContent('')}
                                                />
                                            );
                                        })
                                    }
                                </Geographies>
                            </ZoomableGroup>
                        </ComposableMap>
                        <Tooltip>{tooltipContent}</Tooltip>
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
                                    disabled={!selected}
                                    onChange={(e) => {
                                        if (selected) {
                                            selected.datacomplete = e.currentTarget.checked;
                                            setSelected({ ...selected });
                                        }
                                    }}
                                />
                            )}
                        />{' '}
                        All galls known to occur on this plant have been added to the database, and can be filtered by Location
                        and Detachable. However, sources and images for galls associated with this host may be incomplete or
                        absent, and other filters may not have been entered comprehensively or at all.
                    </Col>
                </Row>
            </form>
        </Admin>
    );
};

export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery }) => {
    const id = extractQueryParam(context.query, 'id');
    const host = pipe(
        id,
        O.map(parseInt),
        O.map((id) => mightFailWithArray<HostApi>()(hostById(id))),
        O.getOrElse(constant(Promise.resolve(Array<HostApi>()))),
    );

    return {
        props: {
            id: pipe(extractQueryParam(context.query, 'id'), O.getOrElse(constant(''))),
            host: await host,
            families: await mightFailWithArray<TaxonomyEntry>()(allFamilies(HOST_FAMILY_TYPES)),
            genera: await mightFailWithArray<TaxonomyEntry>()(allGenera(TaxonCodeValues.PLANT, true)),
            sections: await mightFailWithArray<TaxonomyEntry>()(allSections()),
            abundances: await mightFailWithArray<AbundanceApi>()(getAbundances()),
            places: await mightFailWithArray<PlaceNoTreeApi>()(getPlaces()),
        },
    };
};

export default Host;
