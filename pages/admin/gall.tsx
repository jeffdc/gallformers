import { yupResolver } from '@hookform/resolvers/yup';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Head from 'next/head';
import Link from 'next/link';
import { useRouter } from 'next/router';
import { ParsedUrlQuery } from 'querystring';
import React, { useCallback, useEffect, useState } from 'react';
import { Alert, Col, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import Auth from '../../components/auth';
import ControlledTypeahead from '../../components/controlledtypeahead';
import { AdminFormFields, useAPIs } from '../../hooks/useAPIs';
import { extractQueryParam } from '../../libs/api/apipage';
import * as AT from '../../libs/api/apitypes';
import { allFamilies } from '../../libs/db/family';
import { alignments, allGalls, cells, colors, locations, shapes, textures, walls } from '../../libs/db/gall';
import { allHostsSimple } from '../../libs/db/host';
import { abundances } from '../../libs/db/species';
import { mightFailWithArray } from '../../libs/utils/util';

//TODO factor out the species form and allow it to be extended with what is needed for a gall as this code violates DRY a lot!

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
    hosts: AT.GallHost[];
    detachable: AT.DetachableValues;
    walls: AT.WallsApi[];
    cells: AT.CellsApi[];
    alignments: AT.AlignmentApi[];
    shapes: AT.ShapeApi[];
    colors: AT.ColorApi[];
    locations: AT.GallLocation[];
    textures: AT.GallTexture[];
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
}: Props): JSX.Element => {
    const [existingId, setExistingId] = useState<number | undefined>(id && id !== '' ? parseInt(id) : undefined);
    const [deleteResults, setDeleteResults] = useState<AT.DeleteResult>();
    const [galls, setGalls] = useState(gs);
    const [error, setError] = useState('');

    const { register, handleSubmit, errors, control, reset, setValue } = useForm<FormFields>({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });

    const router = useRouter();

    const onGallChange = useCallback(
        async (spid: number | undefined): Promise<void> => {
            if (spid == undefined) {
                setValue('genus', '');
                setValue('family', [AT.EmptyFamily]);
                setValue('abundance', [AT.EmptyAbundance]);
                setValue('commonnames', '');
                setValue('synonyms', '');
                setValue('detachable', AT.DetachableNone.value);
                setValue('walls', []);
                setValue('cells', []);
                setValue('alignments', []);
                setValue('colors', []);
                setValue('shapes', []);
                setValue('locations', []);
                setValue('textures', []);
                setValue('hosts', []);
            } else {
                try {
                    const res = await fetch(`../api/gall?speciesid=${spid}`);
                    const s = (await res.json()) as AT.GallApi[];
                    const sp = s[0];
                    setValue('value', s);
                    setValue('genus', sp.genus);
                    setValue('family', [sp.family]);
                    setValue('abundance', [pipe(sp.abundance, O.getOrElse(constant(AT.EmptyAbundance)))]);
                    setValue('commonnames', pipe(sp.commonnames, O.getOrElse(constant(''))));
                    setValue('synonyms', pipe(sp.synonyms, O.getOrElse(constant(''))));
                    setValue('detachable', sp.gall.detachable.value);
                    setValue('walls', sp.gall.gallwalls);
                    setValue('cells', sp.gall.gallcells);
                    setValue('alignments', sp.gall.gallalignment);
                    setValue('colors', sp.gall.gallcolor);
                    setValue('shapes', sp.gall.gallshape);
                    setValue('locations', sp.gall.galllocation);
                    setValue('textures', sp.gall.galltexture);
                    setValue('hosts', sp.hosts);
                } catch (e) {
                    console.error(e);
                    setError(e);
                }
            }
        },
        [setValue],
    );

    useEffect(() => {
        onGallChange(existingId);
    }, [existingId, onGallChange]);

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
            alignments: fields.alignments.map((a) => a.id),
            cells: fields.cells.map((c) => c.id),
            colors: fields.colors.map((c) => c.id),
            commonnames: fields.commonnames,
            detachable: fields.detachable,
            family: fields.family[0].name,
            hosts: fields.hosts.map((h) => h.id),
            id: id,
            locations: fields.locations.map((l) => l.id),
            name: name,
            shapes: fields.shapes.map((s) => s.id),
            synonyms: fields.synonyms,
            textures: fields.textures.map((t) => t.id),
            walls: fields.walls.map((w) => w.id),
        });

        await doDeleteOrUpsert(data, postDelete, postUpdate, convertFormFieldsToUpsert)
            .then(() => reset())
            .catch((e: unknown) => setError(`Failed to save changes. ${e}.`));
    };

    return (
        <Auth>
            <>
                <Head>
                    <title>Add/Edit Gallformers</title>
                </Head>

                {error.length > 0 && (
                    <Alert variant="danger" onClose={() => setError('')} dismissible>
                        <Alert.Heading>Uh-oh</Alert.Heading>
                        <p>{error}</p>
                    </Alert>
                )}

                <form onSubmit={handleSubmit(onSubmit)} className="m-4 pr-4">
                    <h4>Add/Edit Gallformers</h4>
                    <p>
                        This is for all of the details about a Gall. To add a description (which must be referenced to a source)
                        go add <Link href="/admin/source">Sources</Link>, if they do not already exist, then go{' '}
                        <Link href="/admin/speciessource">map species to sources with description</Link>. To associate a gall with
                        all plants in a genus, add one species here first, then go to{' '}
                        <Link href="./gallhost">
                            <a>Gall-Host Mappings</a>
                        </Link>
                        .
                    </p>
                    <Row className="form-group">
                        <Col>
                            Name (binomial):
                            <ControlledTypeahead
                                control={control}
                                name="value"
                                onChangeWithNew={(e, isNew) => {
                                    if (isNew || !e[0]) {
                                        setExistingId(undefined);
                                        router.replace(``, undefined, { shallow: true });
                                    } else {
                                        const gall: AT.GallApi = e[0];
                                        setExistingId(gall.id);
                                        router.replace(`?id=${gall.id}`, undefined, { shallow: true });
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
                                    Name is required and must be in standard binomial form, e.g., Gallus gallus
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
                            <select placeholder="Detachable" name="detachable" className="form-control" ref={register}>
                                {AT.Detachables.map((d) => (
                                    <option key={d.id}>{d.value}</option>
                                ))}
                            </select>
                        </Col>
                        <Col>
                            Walls:
                            <ControlledTypeahead
                                control={control}
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
                                control={control}
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
                                control={control}
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
                                control={control}
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
                                control={control}
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
                    <Row className="fromGroup" hidden={!existingId}>
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
                    <Row hidden={!existingId}>
                        <Col>
                            <br />
                            <Link href={`./images?speciesid=${existingId}`}>Add/Edit Images for this Gall</Link>
                        </Col>
                    </Row>
                </form>
            </>
        </Auth>
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
