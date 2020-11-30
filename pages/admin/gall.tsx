import { yupResolver } from '@hookform/resolvers/yup';
import { abundance, alignment, cells as cs, color, family, location, shape, species, texture, walls as ws } from '@prisma/client';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import { useRouter } from 'next/router';
import React, { useState } from 'react';
import { Col, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import Auth from '../../components/auth';
import ControlledTypeahead from '../../components/controlledtypeahead';
import { useWithLookup } from '../../hooks/useWithLookups';
import { DeleteResults, GallApi, GallUpsertFields, HostSimple } from '../../libs/apitypes';
import { allFamilies } from '../../libs/db/family';
import { alignments, allGalls, cells, colors, locations, shapes, textures, walls } from '../../libs/db/gall';
import { allHostsSimple } from '../../libs/db/host';
import { abundances } from '../../libs/db/species';
import { mightBeNull } from '../../libs/db/utils';
import { genOptions } from '../../libs/utils/forms';

//TODO factor out the species form and allow it to be extended with what is needed for a gall as this code violates DRY a lot!

type SpeciesFormFields = {
    name: string;
    commonnames: string;
    synonyms: string;
    family: string;
    abundance: string;
};

type GallFormFields = SpeciesFormFields & {
    hosts: string[];
    locations: string[];
    color: string;
    shape: string;
    textures: string[];
    alignment: string;
    walls: string;
    cells: string;
    detachable: string;
    delete?: boolean;
};

type Props = {
    galls: species[];
    abundances: abundance[];
    hosts: HostSimple[];
    locations: location[];
    colors: color[];
    shapes: shape[];
    textures: texture[];
    alignments: alignment[];
    walls: ws[];
    cells: cs[];
    families: family[];
};

const Schema = yup.object().shape({
    name: yup.string().matches(/([A-Z][a-z]+ [a-z]+$)/),
    family: yup.string().required(),
    hosts: yup.array().required(),
});

const extractGenus = (n: string): string => {
    return n.split(' ')[0];
};

type FormFields =
    | 'name'
    | 'genus'
    | 'family'
    | 'abundance'
    | 'commonnames'
    | 'synonmys'
    | 'hosts'
    | 'detachable'
    | 'walls'
    | 'cells'
    | 'alignment'
    | 'shape'
    | 'color'
    | 'locations'
    | 'textures';

const Gall = ({
    galls,
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
    const { register, handleSubmit, errors, control, setValue } = useForm({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });
    const router = useRouter();

    const [existing, setExisting] = useState(false);
    const [deleteResults, setDeleteResults] = useState<DeleteResults>();

    const { setValueForLookup } = useWithLookup<
        FormFields,
        ws | cs | alignment | color | shape | location | texture | HostSimple | family | abundance,
        string | number
    >(setValue);

    const setGallDetails = async (spid: number): Promise<void> => {
        try {
            const res = await fetch(`../api/gall?speciesid=${spid}`);
            const sp = (await res.json()) as GallApi;
            setValue('detachable', sp.gall.detachable);
            setValueForLookup('walls', [sp.gall.walls?.id], walls, 'walls');
            setValueForLookup('cells', [sp.gall.cells?.id], cells, 'cells');
            setValueForLookup('alignment', [sp.gall.alignment?.id], alignments, 'alignment');
            setValueForLookup('color', [sp.gall.color?.id], colors, 'color');
            setValueForLookup('shape', [sp.gall.shape?.id], shapes, 'shape');
            setValueForLookup(
                'locations',
                sp.gall.galllocation.map((l) => l.location?.id),
                locations,
                'location',
            );
            setValueForLookup(
                'textures',
                sp.gall.galltexture.map((t) => t.texture?.id),
                textures,
                'texture',
            );
            setValueForLookup(
                'hosts',
                sp.hosts.map((h) => h.id),
                hosts,
                'name',
            );
        } catch (e) {
            console.error(e);
        }
    };

    const onSubmit = async (data: GallFormFields) => {
        if (data.delete) {
            const id = galls.find((g) => g.name === data.name)?.id;
            console.log('FOOO :' + data);
            const res = await fetch(`../api/gall/${id}`, {
                method: 'DELETE',
            });

            if (res.status === 200) {
                setDeleteResults(await res.json());
                return;
            } else {
                throw new Error(await res.text());
            }
        }

        const species = galls.find((g) => g.name === data.name);

        const submitData: GallUpsertFields = {
            ...data,
            // i hate null... :( these should be safe since the text values came from the same place as the ids
            // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
            hosts: data.hosts.map((h) => hosts.find((hh) => hh.name === h)!.id),
            // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
            locations: data.locations.map((l) => locations.find((ll) => ll.location === l)!.id),
            // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
            textures: data.textures.map((t) => textures.find((tt) => tt.texture === t)!.id),
            id: species ? species.id : undefined,
        };
        try {
            const res = await fetch('../api/gall/upsert', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(submitData),
            });

            if (res.status === 200) {
                router.push(res.url);
            } else {
                throw new Error(await res.text());
            }
        } catch (e) {
            console.error(e);
        }
    };

    return (
        <Auth>
            <form onSubmit={handleSubmit(onSubmit)} className="m-4 pr-4">
                <h4>Add A Gall</h4>
                <p>
                    This is for all of the details about a Gall. To add a description (which must be referenced to a source) go
                    add <Link href="/admin/source">Sources</Link>, if they do not already exist, then go{' '}
                    <Link href="/admin/speciessource">map species to sources with description</Link>.
                </p>
                <Row className="form-group">
                    <Col>
                        Name (binomial):
                        <ControlledTypeahead
                            control={control}
                            name="name"
                            onChange={(e) => {
                                const f = galls.find((f) => f.name === e[0]);
                                setExisting(false);
                                if (f) {
                                    setExisting(true);
                                    setValueForLookup('family', [f.family_id], families, 'name');
                                    setValueForLookup('abundance', [f.abundance_id], abundances, 'abundance');
                                    setValue('commonnames', f.commonnames);
                                    setValue('synonyms', f.synonyms);
                                    setGallDetails(f.id);
                                }
                            }}
                            onBlur={(e) => {
                                if (!errors.name) {
                                    setValue('genus', extractGenus(e.target.value));
                                }
                            }}
                            placeholder="Name"
                            options={galls.map((f) => f.name)}
                            clearButton
                            isInvalid={!!errors.name}
                            newSelectionPrefix="Add a new Gall: "
                            allowNew={true}
                        />
                        {errors.name && (
                            <span className="text-danger">
                                Name is required and must be in standard binomial form, e.g., Andricus weldi
                            </span>
                        )}
                    </Col>
                    <Col>
                        Genus (filled automatically):
                        <input type="text" name="genus" className="form-control" readOnly tabIndex={-1} ref={register} />
                    </Col>
                    <Col>
                        Family:
                        <select name="family" className="form-control" ref={register}>
                            {genOptions(families.map((f) => mightBeNull(f.name)))}
                        </select>
                        {errors.family && (
                            <span className="text-danger">
                                The Family name is required. If it is not present in the list you will have to go add the family
                                first. :(
                            </span>
                        )}
                    </Col>
                    <Col>
                        Abundance:
                        <select name="abundance" className="form-control" ref={register}>
                            {genOptions(abundances.map((a) => mightBeNull(a.abundance)))}
                        </select>
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Common Names (comma-delimited):
                        <input
                            type="text"
                            placeholder="Common Names"
                            name="commonnames"
                            className="form-control"
                            ref={register}
                        />
                    </Col>
                    <Col>
                        Synonyms (comma-delimited):
                        <input type="text" placeholder="Synonyms" name="synonyms" className="form-control" ref={register} />
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Hosts:
                        <ControlledTypeahead
                            control={control}
                            name="hosts"
                            placeholder="Hosts"
                            options={hosts.map((h) => h.name)}
                            multiple
                            clearButton
                        />
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Detachable:
                        <input
                            type="checkbox"
                            placeholder="Detachable"
                            name="detachable"
                            className="form-control"
                            ref={register}
                        />
                    </Col>
                    <Col>
                        Walls:
                        <select name="walls" className="form-control" ref={register}>
                            {genOptions(walls.map((w) => mightBeNull(w.walls)))}
                        </select>
                    </Col>
                    <Col>
                        Cells:
                        <select name="cells" className="form-control" ref={register}>
                            {genOptions(cells.map((c) => mightBeNull(c.cells)))}
                        </select>
                    </Col>
                    <Col>
                        Alignment:
                        <select name="alignment" className="form-control" ref={register}>
                            {genOptions(alignments.map((a) => mightBeNull(a.alignment)))}
                        </select>
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Color:
                        <select name="color" className="form-control" ref={register}>
                            {genOptions(colors.map((c) => mightBeNull(c.color)))}
                        </select>
                    </Col>
                    <Col>
                        Shape:
                        <select name="shape" className="form-control" ref={register}>
                            {genOptions(shapes.map((s) => mightBeNull(s.shape)))}
                        </select>
                    </Col>{' '}
                </Row>
                <Row className="form-group">
                    <Col>
                        Location(s):
                        <ControlledTypeahead
                            control={control}
                            name="locations"
                            placeholder="Location(s)"
                            options={locations.map((l) => l.location)}
                            multiple
                            clearButton
                        />
                    </Col>
                    <Col>
                        Texture(s):
                        <ControlledTypeahead
                            control={control}
                            name="textures"
                            placeholder="Texture(s)"
                            options={textures.map((t) => t.texture)}
                            multiple
                            clearButton
                        />
                    </Col>
                </Row>
                <Row className="fromGroup" hidden={!existing}>
                    <Col xs="1">Delete?:</Col>
                    <Col className="mr-auto">
                        <input name="delete" type="checkbox" className="form-check-input" ref={register} />
                    </Col>
                </Row>
                <Row className="formGroup">
                    <Col>
                        <input type="submit" className="button" />
                    </Col>
                </Row>
                <Row hidden={!deleteResults}>
                    <Col>{`Deleted ${deleteResults?.name}.`}</Col>
                </Row>
            </form>
        </Auth>
    );
};

export const getServerSideProps: GetServerSideProps = async () => {
    return {
        props: {
            galls: await allGalls(),
            hosts: await allHostsSimple(),
            families: await allFamilies(),
            locations: await locations(),
            colors: await colors(),
            shapes: await shapes(),
            textures: await textures(),
            alignments: await alignments(),
            walls: await walls(),
            cells: await cells(),
            abundances: await abundances(),
        },
    };
};

export default Gall;
