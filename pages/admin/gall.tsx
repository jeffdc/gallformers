import { yupResolver } from '@hookform/resolvers/yup';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import { useRouter } from 'next/router';
import React, { useState } from 'react';
import { Col, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import Auth from '../../components/auth';
import ControlledTypeahead from '../../components/controlledtypeahead';
import { AdminFormFields, useAPIs } from '../../hooks/useAPIs';
import * as AT from '../../libs/api/apitypes';
import { allFamilies } from '../../libs/db/family';
import { alignments, allGalls, cells, colors, locations, shapes, textures, walls } from '../../libs/db/gall';
import { allHostsSimple } from '../../libs/db/host';
import { abundances } from '../../libs/db/species';
import { mightFailWithArray } from '../../libs/utils/util';

//TODO factor out the species form and allow it to be extended with what is needed for a gall as this code violates DRY a lot!

type Props = {
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
    families: AT.FamilyApi[];
};

const Schema = yup.object().shape({
    value: yup
        .array()
        .of(
            yup.object({
                name: yup
                    .string()
                    .matches(/([A-Z][a-z]+ [a-z]+$)/)
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
    family: AT.FamilyApi[];
    abundance: AT.AbundanceApi[];
    commonnames: string;
    synonyms: string;
    hosts: AT.HostSimple[];
    detachable: string;
    walls: AT.WallsApi[];
    cells: AT.CellsApi[];
    alignment: AT.AlignmentApi[];
    shape: AT.ShapeApi[];
    color: AT.ColorApi[];
    locations: AT.GallLocation[];
    textures: AT.GallTexture[];
};

const Gall = ({
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
}: Props): JSX.Element => {
    const { register, handleSubmit, errors, control, reset, setValue } = useForm<FormFields>({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });
    const router = useRouter();

    const [existing, setExisting] = useState(false);
    const [deleteResults, setDeleteResults] = useState<AT.DeleteResult>();
    const [galls, setGalls] = useState(gs);

    const setGallDetails = async (spid: number): Promise<void> => {
        try {
            const res = await fetch(`../api/gall?speciesid=${spid}`);
            const s = (await res.json()) as AT.GallApi[];
            const sp = s[0];
            setValue(
                'detachable',
                pipe(
                    sp.gall.detachable,
                    O.fold(
                        () => '',
                        (d) => (d === 0 ? 'no' : 'yes'),
                    ),
                ),
            );
            setValue('walls', [pipe(sp.gall.walls, O.getOrElse(constant(AT.EmptyWalls)))]);
            setValue('cells', [pipe(sp.gall.cells, O.getOrElse(constant(AT.EmptyCells)))]);
            setValue('alignment', [pipe(sp.gall.alignment, O.getOrElse(constant(AT.EmptyAlignment)))]);
            setValue('color', [pipe(sp.gall.color, O.getOrElse(constant(AT.EmptyColor)))]);
            setValue('shape', [pipe(sp.gall.shape, O.getOrElse(constant(AT.EmptyShape)))]);
            setValue('locations', sp.gall.galllocation);
            setValue('textures', sp.gall.galltexture);
            setValue('hosts', sp.hosts);
        } catch (e) {
            console.error(e);
        }
    };

    const { doDeleteOrUpsert } = useAPIs<AT.GallApi, AT.GallUpsertFields>('name', '../api/gall/', '../api/gall/upsert');

    const onSubmit = async (data: FormFields) => {
        const postDelete = (id: number | string, result: AT.DeleteResult) => {
            setGalls(galls.filter((s) => s.id !== id));
            setDeleteResults(result);
        };

        const postUpdate = (res: Response) => {
            router.push(res.url);
        };

        const convertFormFieldsToUpsert = (fields: FormFields, name: string, id: number): AT.GallUpsertFields => ({
            abundance: fields.abundance[0].abundance,
            alignment: fields.alignment[0].alignment,
            cells: fields.cells[0].cells,
            color: fields.color[0].color,
            commonnames: fields.commonnames,
            detachable: fields.detachable,
            family: fields.family[0].name,
            hosts: fields.hosts.map((h) => h.id),
            id: id,
            locations: fields.locations.map((l) => l.id),
            name: name,
            shape: fields.shape[0].shape,
            synonyms: fields.synonyms,
            textures: fields.textures.map((t) => t.id),
            walls: fields.walls[0].walls,
        });

        await doDeleteOrUpsert(data, postDelete, postUpdate, convertFormFieldsToUpsert);
        reset();
    };

    return (
        <Auth>
            <>
                <Head>
                    <title>Add/Edit Gallformers</title>
                </Head>

                <form onSubmit={handleSubmit(onSubmit)} className="m-4 pr-4">
                    <h4>Add/Edit Gallformers</h4>
                    <p>
                        This is for all of the details about a Gall. To add a description (which must be referenced to a source)
                        go add <Link href="/admin/source">Sources</Link>, if they do not already exist, then go{' '}
                        <Link href="/admin/speciessource">map species to sources with description</Link>.
                    </p>
                    <Row className="form-group">
                        <Col>
                            Name (binomial):
                            <ControlledTypeahead
                                control={control}
                                name="value"
                                onChangeWithNew={(e, isNew) => {
                                    setExisting(!isNew);
                                    if (isNew || !e[0]) {
                                        setValue('genus', extractGenus(e[0] ? e[0].name : ''));
                                        setValue('family', [AT.EmptyFamily]);
                                        setValue('abundance', [AT.EmptyAbundance]);
                                        setValue('commonnames', '');
                                        setValue('synonyms', '');
                                        setValue('detachable', '');
                                        setValue('walls', [AT.EmptyWalls]);
                                        setValue('cells', [AT.EmptyCells]);
                                        setValue('alignment', [AT.EmptyAlignment]);
                                        setValue('color', [AT.EmptyColor]);
                                        setValue('shape', [AT.EmptyShape]);
                                        setValue('locations', []);
                                        setValue('textures', []);
                                        setValue('hosts', []);
                                    } else {
                                        const gall: AT.GallApi = e[0];
                                        setValue('family', [gall.family]);
                                        setValue('abundance', [pipe(gall.abundance, O.getOrElse(constant(AT.EmptyAbundance)))]);
                                        setValue('commonnames', pipe(gall.commonnames, O.getOrElse(constant(''))));
                                        setValue('synonyms', pipe(gall.synonyms, O.getOrElse(constant(''))));
                                        setGallDetails(gall.id);
                                    }
                                }}
                                onBlurT={(e) => {
                                    if (!errors.value) {
                                        setValue('genus', extractGenus(e.target.value));
                                    }
                                }}
                                placeholder="Name"
                                options={galls}
                                labelKey="name"
                                clearButton
                                isInvalid={!!errors.value}
                                newSelectionPrefix="Add a new Gall: "
                                allowNew={true}
                            />
                            {errors.value && (
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
                            <ControlledTypeahead
                                control={control}
                                name="family"
                                placeholder="Family"
                                options={families}
                                labelKey="name"
                            />
                            {errors.family && (
                                <span className="text-danger">
                                    The Family name is required. If it is not present in the list you will have to go add the
                                    family first. :(
                                </span>
                            )}
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
                            Common Names (comma-delimited):
                            <input type="text" placeholder="" name="commonnames" className="form-control" ref={register} />
                        </Col>
                        <Col>
                            Synonyms (comma-delimited):
                            <input type="text" placeholder="" name="synonyms" className="form-control" ref={register} />
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            Hosts:
                            <ControlledTypeahead
                                control={control}
                                name="hosts"
                                placeholder="Hosts"
                                options={hosts}
                                labelKey="name"
                                multiple
                                clearButton
                            />
                            {errors.hosts && <span className="text-danger">You must map this gall to at least one host.</span>}
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
                            <ControlledTypeahead
                                control={control}
                                name="walls"
                                placeholder=""
                                options={walls}
                                labelKey="walls"
                                clearButton
                            />
                        </Col>
                        <Col>
                            Cells:
                            <ControlledTypeahead
                                control={control}
                                name="cells"
                                placeholder=""
                                options={cells}
                                labelKey="cells"
                                clearButton
                            />
                        </Col>
                        <Col>
                            Alignment:
                            <ControlledTypeahead
                                control={control}
                                name="alignment"
                                placeholder=""
                                options={alignments}
                                labelKey="alignment"
                                clearButton
                            />
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            Color:
                            <ControlledTypeahead
                                control={control}
                                name="color"
                                placeholder=""
                                options={colors}
                                labelKey="color"
                                clearButton
                            />
                        </Col>
                        <Col>
                            Shape:
                            <ControlledTypeahead
                                control={control}
                                name="shape"
                                placeholder=""
                                options={shapes}
                                labelKey="shape"
                                clearButton
                            />
                        </Col>{' '}
                    </Row>
                    <Row className="form-group">
                        <Col>
                            Location(s):
                            <ControlledTypeahead
                                control={control}
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
                                control={control}
                                name="textures"
                                placeholder=""
                                options={textures}
                                labelKey="tex"
                                multiple
                                clearButton
                            />
                        </Col>
                    </Row>
                    <Row className="fromGroup" hidden={!existing}>
                        <Col xs="1">Delete?:</Col>
                        <Col className="mr-auto">
                            <input name="del" type="checkbox" className="form-check-input" ref={register} />
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
                </form>
            </>
        </Auth>
    );
};

export const getServerSideProps: GetServerSideProps = async () => {
    return {
        props: {
            gs: await mightFailWithArray<AT.GallApi>()(allGalls()),
            hosts: await mightFailWithArray<AT.HostSimple>()(allHostsSimple()),
            families: await mightFailWithArray<AT.FamilyApi>()(allFamilies(AT.GALL_FAMILY_TYPES)),
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
