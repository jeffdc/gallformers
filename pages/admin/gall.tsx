import { yupResolver } from '@hookform/resolvers/yup';
import { abundance, alignment, color, location, shape, texture, walls as ws, cells as cs, family } from '@prisma/client';
import { GetServerSideProps } from 'next';
import { useRouter } from 'next/router';
import React from 'react';
import { Col, Row } from 'react-bootstrap';
import { Typeahead } from 'react-bootstrap-typeahead';
import { Controller, useForm } from 'react-hook-form';
import * as yup from 'yup';
import Auth from '../../components/auth';
import { GallUpsertFields } from '../../libs/apitypes';
import { allFamilies } from '../../libs/db/family';
import { alignments, cells, colors, locations, shapes, textures, walls } from '../../libs/db/gall';
import { allHosts } from '../../libs/db/host';
import { abundances } from '../../libs/db/species';
import { mightBeNull } from '../../libs/db/utils';
import { GallFormFields, genOptions, normalizeToArray } from '../../libs/utils/forms';

//TODO factor out the species form and allow it to be extended with what is needed for a gall as this code violates DRY a lot!
type Host = {
    id: number;
    name: string;
    commonnames: string;
};

type Props = {
    abundances: abundance[];
    hosts: Host[];
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
    description: yup.string().required(),
    hosts: yup.array().required(),
});

const extractGenus = (n: string): string => {
    return n.split(' ')[0];
};

const Gall = ({
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

    const onSubmit = async (data: GallFormFields) => {
        const submitData: GallUpsertFields = {
            ...data,
            // i hate null... :( these should be safe since the text values came from the same place as the ids
            // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
            hosts: data.hosts.map((h) => hosts.find((hh) => hh.name === h)!.id),
            // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
            locations: data.locations.map((l) => locations.find((ll) => ll.location === l)!.id),
            // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
            textures: data.textures.map((t) => textures.find((tt) => tt.texture === t)!.id),
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
            console.log(e);
        }
    };

    return (
        <Auth>
            <form onSubmit={handleSubmit(onSubmit)} className="m-4 pr-4">
                <h4>Add A Gall</h4>
                <Row className="form-group">
                    <Col>
                        Name (binomial):
                        <input
                            type="text"
                            placeholder="Name"
                            name="name"
                            className="form-control"
                            onBlur={(e) => (!errors.name ? setValue('genus', extractGenus(e.target.value)) : undefined)}
                            ref={register}
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
                        <Controller
                            control={control}
                            name="hosts"
                            defaultValue={[]}
                            render={({ value, onChange, onBlur }) => (
                                <Typeahead
                                    onChange={(e: string | string[]) => {
                                        onChange(e);
                                    }}
                                    onBlur={onBlur}
                                    selected={normalizeToArray(value)}
                                    placeholder="Hosts"
                                    id="Hosts"
                                    options={hosts.map((h) => h.name)}
                                    multiple
                                    clearButton
                                    isInvalid={!!errors.hosts}
                                />
                            )}
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
                        <Controller
                            control={control}
                            name="locations"
                            defaultValue={[]}
                            render={({ value, onChange }) => (
                                <Typeahead
                                    onChange={(e: string | string[]) => {
                                        onChange(e);
                                    }}
                                    selected={normalizeToArray(value)}
                                    placeholder="Location(s)"
                                    id="Locations"
                                    options={locations.map((l) => l.location)}
                                    multiple
                                    clearButton
                                />
                            )}
                        />
                    </Col>
                    <Col>
                        Texture(s):
                        <Controller
                            control={control}
                            name="textures"
                            defaultValue={[]}
                            render={({ value, onChange }) => (
                                <Typeahead
                                    onChange={(e: string | string[]) => {
                                        onChange(e);
                                    }}
                                    selected={normalizeToArray(value)}
                                    placeholder="Texture(s)"
                                    id="Textures"
                                    options={textures.map((t) => t.texture)}
                                    multiple
                                    clearButton
                                />
                            )}
                        />
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Description:
                        <textarea name="description" className="form-control" ref={register} />
                        {errors.description && (
                            <span className="text-danger">
                                You must provide a description. You can add source references separately.
                            </span>
                        )}
                    </Col>
                </Row>
                <input type="submit" className="button" />
            </form>
        </Auth>
    );
};

export const getServerSideProps: GetServerSideProps = async () => {
    const h = await allHosts();
    const hosts: Host[] = h
        .map((h) => {
            return {
                name: h.name,
                id: h.id,
                commonnames: mightBeNull(h.commonnames),
            };
        })
        .sort((a, b) => a.name?.localeCompare(b.name));

    return {
        props: {
            hosts: hosts,
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
