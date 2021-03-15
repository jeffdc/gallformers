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
import useAdmin from '../../hooks/useadmin';
import { AdminFormFields } from '../../hooks/useAPIs';
import { extractQueryParam } from '../../libs/api/apipage';
import * as AT from '../../libs/api/apitypes';
import { EMPTY_FGS, FGS, TaxonomyEntry } from '../../libs/api/taxonomy';
import { alignments, allGalls, cells, colors, locations, shapes, textures, walls } from '../../libs/db/gall';
import { allHostsSimple } from '../../libs/db/host';
import { abundances } from '../../libs/db/species';
import { allFamilies, taxonomyForSpecies } from '../../libs/db/taxonomy';
import Admin from '../../libs/pages/admin';
import { mightFail, mightFailWithArray } from '../../libs/utils/util';

type Props = {
    id: string;
    gs: AT.GallApi[];
    fgs: FGS;
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

const extractGenus = (n: string): string => {
    return n.split(' ')[0];
};

export type FormFields = AdminFormFields<AT.GallApi> & {
    genus: string;
    family: TaxonomyEntry[];
    section: TaxonomyEntry[];
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

const emptyForm = {
    value: [],
    genus: '',
    // family: [AT.EmptyFamily],
    abundance: [AT.EmptyAbundance],
    commonnames: '',
    synonyms: '',
    detachable: AT.DetachableNone.value,
    walls: [],
    cells: [],
    alignments: [],
    colors: [],
    shapes: [],
    locations: [],
    textures: [],
    hosts: [],
};

const convertToFields = (fgs: FGS) => (s: AT.GallApi): FormFields => ({
    value: [s],
    genus: extractGenus(s.name),
    family: fgs.family != null ? [fgs.family] : [],
    section: pipe(
        fgs.section,
        O.fold(constant([]), (s) => [s]),
    ),
    abundance: [pipe(s.abundance, O.getOrElse(constant(AT.EmptyAbundance)))],
    datacomplete: s.datacomplete,
    alignments: s.gall.gallalignment,
    cells: s.gall.gallcells,
    colors: s.gall.gallcolor,
    detachable: s.gall.detachable.value,
    hosts: [], //TODO
    locations: s.gall.galllocation,
    shapes: s.gall.gallshape,
    textures: s.gall.galltexture,
    walls: s.gall.gallwalls,
    del: false,
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
    fgs,
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
}: Props): JSX.Element => {
    const [theFGS, setTheFGS] = useState(fgs);
    const [aliasData, setAliasData] = useState<Array<AT.AliasApi>>([]);

    const toUpsertFields = (fields: FormFields, name: string, id: number): AT.GallUpsertFields => {
        return {
            abundance: fields.abundance[0].abundance,
            aliases: [], //TODO
            alignments: fields.alignments.map((a) => a.id),
            cells: fields.cells.map((c) => c.id),
            colors: fields.colors.map((c) => c.id),
            datacomplete: fields.datacomplete,
            detachable: fields.detachable,
            fgs: theFGS,
            hosts: fields.hosts.map((h) => h.id),
            id: id,
            locations: fields.locations.map((l) => l.id),
            name: name,
            shapes: fields.shapes.map((s) => s.id),
            textures: fields.textures.map((t) => t.id),
            walls: fields.walls.map((w) => w.id),
        };
    };

    const onDataChangeCallback = async (s: AT.GallApi | undefined): Promise<AT.GallApi | undefined> => {
        if (s == undefined) {
            setAliasData([]);
        } else {
            if (selected && extractGenus(s.name) === extractGenus(selected.name)) {
                console.log('genus change');
                // name change as usual
                // also need to update the taxonomy, possibly adding a new Genus
                // also need to think about family change
            }
            setTheFGS(await fetchFGS(s));
            setAliasData(s.aliases);
        }
        return s;
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
        renameWithNewValue,
        form,
        formSubmit,
    } = useAdmin(
        'Gall',
        id,
        gs,
        updateGall,
        convertToFields(theFGS),
        toUpsertFields,
        { keyProp: 'name', delEndpoint: '../api/gall/', upsertEndpoint: '../api/gall/upsert' },
        schema,
        emptyForm,
        onDataChangeCallback,
    );

    const router = useRouter();

    const onSubmit = async (fields: FormFields) => {
        formSubmit(fields);
    };

    return (
        <Admin
            type="Gall"
            keyField="name"
            editName={{ getDefault: () => selected?.name, setNewValue: renameWithNewValue(onSubmit) }}
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
                            {selected && (
                                <Col xs={1}>
                                    <Button variant="secondary" className="btn-sm" onClick={() => setShowRenameModal(true)}>
                                        Rename
                                    </Button>
                                </Col>
                            )}
                        </Row>
                        <Row>
                            <Col>
                                <ControlledTypeahead
                                    control={form.control}
                                    name="value"
                                    onChangeWithNew={(e, isNew) => {
                                        if (isNew || !e[0]) {
                                            setSelected(undefined);
                                            router.replace(``, undefined, { shallow: true });
                                        } else {
                                            const gall: AT.GallApi = e[0];
                                            setSelected(gall);
                                            router.replace(`?id=${gall.id}`, undefined, { shallow: true });
                                        }
                                    }}
                                    onBlurT={(e) => {
                                        if (!form.errors.value) {
                                            form.setValue('genus', extractGenus(e.target.value));
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
                        </Row>
                    </Col>
                    <Col>
                        Genus (filled automatically):
                        <input type="text" name="genus" className="form-control" readOnly tabIndex={-1} ref={form.register} />
                    </Col>
                    <Col>
                        Family:
                        <ControlledTypeahead
                            control={form.control}
                            name="family"
                            placeholder="Family"
                            options={families}
                            labelKey="name"
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
                        <input name="datacomplete" type="checkbox" className="form-input-checkbox" ref={form.register} /> Are all
                        known sources entered for this gall?
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

    const fgs = id === '' ? EMPTY_FGS : await mightFail(constant(EMPTY_FGS))(taxonomyForSpecies(parseInt(id)));

    return {
        props: {
            id: id,
            gs: await mightFailWithArray<AT.GallApi>()(allGalls()),
            fgs: fgs,
            hosts: await mightFailWithArray<AT.HostSimple>()(allHostsSimple()),
            families: await mightFailWithArray<TaxonomyEntry>()(allFamilies(AT.GALL_FAMILY_TYPES)),
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
