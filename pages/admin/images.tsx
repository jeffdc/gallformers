import { yupResolver } from '@hookform/resolvers/yup';
import { species } from '@prisma/client';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import { useSession } from 'next-auth/client';
import Head from 'next/head';
import { ParsedUrlQuery } from 'querystring';
import React, { useEffect, useState } from 'react';
import { Col, Row, Table } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import AddImage from '../../components/addimage';
import Auth from '../../components/auth';
import ControlledTypeahead from '../../components/controlledtypeahead';
import ImageEdit from '../../components/imageedit';
import { extractQueryParam } from '../../libs/api/apipage';
import { ImageApi } from '../../libs/api/apitypes';
import { allSpecies } from '../../libs/db/species';
import { mightFailWithArray } from '../../libs/utils/util';

const Schema = yup.object().shape({});

type Props = {
    speciesid: string;
    species: species[];
};

type FormFields = {
    species: string;
    delete: [];
};

const Images = ({ speciesid, species }: Props): JSX.Element => {
    const sp = species.find((s) => s.id === parseInt(speciesid));
    const [selectedId, setSelectedId] = useState(sp ? sp.id : undefined);
    const [images, setImages] = useState<ImageApi[]>();
    const [edit, setEdit] = useState(false);
    const [currentImage, setCurrentImage] = useState<ImageApi>();

    const { handleSubmit, control, register, reset } = useForm<FormFields>({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
        defaultValues: {
            species: sp?.name,
        },
    });

    const [session] = useSession();

    useEffect(() => {
        const fetchNewSelection = async (id: number | undefined) => {
            try {
                if (!id) return;

                const res = await fetch(`../api/images?speciesid=${id}`, {
                    method: 'GET',
                });

                if (res.status === 200) {
                    const imgs = (await res.json()) as ImageApi[];
                    setImages(imgs);
                } else {
                    throw new Error(await res.text());
                }
            } catch (e) {
                console.error(e);
            }
        };
        fetchNewSelection(selectedId);
    }, [selectedId]);

    // i could not divine the incantation to get the form to track an array of checkboxes and propagate the id
    const toDelete = new Set<string>();

    const onSubmit = async () => {
        try {
            if (toDelete.size > 0) {
                const res = await fetch(`../api/images?speciesid=${selectedId}&imageids=${[...toDelete.values()]}`, {
                    method: 'DELETE',
                });

                if (res.status === 200) {
                    setImages(images?.filter((i) => !toDelete.has(i.id.toString())));
                } else {
                    throw new Error(await res.text());
                }

                reset({ delete: [], species: sp?.name });
                toDelete.clear();
            }
        } catch (e) {
            console.error(e);
        }
    };

    const addImages = async (newImages: ImageApi[]) => {
        //hack: add a delay here to hopefully give a chance for the image to be picked up by the CDN
        await new Promise((r) => setTimeout(r, 2000));

        setImages([...(images !== undefined ? images : []), ...newImages]);
    };

    const handleClose = () => setEdit(false);

    const editRow = (e: React.MouseEvent<HTMLTableRowElement, MouseEvent>): void => {
        const image = images?.find((i) => i.id == parseInt(e.currentTarget.id));
        setCurrentImage(image);
        setEdit(true);
    };

    const saveImage = async (image: ImageApi) => {
        try {
            image.lastchangedby = session ? session.user.name : 'UNKNOWN!';

            const res = await fetch(`../api/images`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(image),
            });

            if (res.status !== 200) {
                throw new Error(await res.text());
            }

            if (images) {
                setImages([image, ...images.filter((img) => img.id !== image.id)]);
            }

            setCurrentImage(image);
        } catch (e) {
            console.error(e);
        }
    };

    return (
        <Auth>
            <>
                <Head>
                    <title>Add/Edit Species Images</title>
                </Head>
                {/* <AddImage id={species.id} onChange={addImages} /> */}
                {currentImage && selectedId && (
                    // eslint-disable-next-line prettier/prettier
                    <ImageEdit 
                        image={currentImage}
                        speciesid={selectedId}
                        onSave={saveImage}
                        show={edit}
                        onClose={handleClose}
                    />
                )}

                <form onSubmit={handleSubmit(onSubmit)} className="m-4 pr-4">
                    <h4>Add/Edit Species Images</h4>
                    <Row className="form-group" xs={3}>
                        <Col xs={1} style={{ paddingTop: '5px' }}>
                            Species:
                        </Col>
                        <Col>
                            <ControlledTypeahead
                                control={control}
                                name="species"
                                options={species}
                                labelKey="name"
                                clearButton
                                onChange={(s: species[]) => {
                                    setSelectedId(s[0].id);
                                }}
                            />
                        </Col>
                        <Col>{selectedId && <AddImage id={selectedId} onChange={addImages} />}</Col>
                    </Row>
                    <Row className="">
                        <Col>
                            <input type="submit" className="button" value="Delete Selected" />
                        </Col>
                    </Row>
                    <div className="fixed-left mt-2 ml-2 mr-2">
                        <Table striped>
                            <thead>
                                <tr>
                                    <th></th>
                                    <th>image</th>
                                    <th>default</th>
                                    <th>source</th>
                                    <th>source link</th>
                                    <th>creator</th>
                                    <th>attribution</th>
                                    <th>license</th>
                                    <th>license link</th>
                                </tr>
                            </thead>
                            <tbody>
                                {images?.map((img) => (
                                    <tr key={img.path} id={img.id.toString()} onClick={editRow}>
                                        <td>
                                            <input
                                                type="checkbox"
                                                key={img.id}
                                                id={img.id.toString()}
                                                name="delete"
                                                ref={register}
                                                onClick={(e) => {
                                                    e.stopPropagation();
                                                    e.currentTarget.checked
                                                        ? toDelete.add(e.currentTarget.id)
                                                        : toDelete.delete(e.currentTarget.id);
                                                }}
                                            />
                                        </td>
                                        <td>
                                            <img src={img.small} width="100" />
                                        </td>
                                        <td>{img.default ? '✓' : ''}</td>
                                        <td>
                                            {pipe(
                                                img.source,
                                                O.fold(constant(<>{'External'}</>), (s) => (
                                                    <a
                                                        href={`/source/${s.id}`}
                                                        onClick={(e) => e.stopPropagation()}
                                                        target="_blank"
                                                        rel="noreferrer"
                                                    >
                                                        {s.title}
                                                    </a>
                                                )),
                                            )}
                                        </td>
                                        <td>
                                            <a
                                                href={img.sourcelink}
                                                onClick={(e) => e.stopPropagation()}
                                                target="_blank"
                                                rel="noreferrer"
                                            >
                                                {img.sourcelink}
                                            </a>
                                        </td>
                                        <td>{img.creator}</td>
                                        <td>{img.attribution}</td>
                                        <td>{img.license}</td>
                                        <td>
                                            <a
                                                href={img.licenselink}
                                                onClick={(e) => e.stopPropagation()}
                                                target="_blank"
                                                rel="noreferrer"
                                            >
                                                {img.licenselink}
                                            </a>
                                        </td>
                                    </tr>
                                ))}
                            </tbody>
                        </Table>
                        <style jsx>{`
                            table {
                                width: 100%;
                                border-collapse: collapse;
                            }

                            thead th {
                                text-align: left;
                                border-bottom: 2px solid black;
                            }

                            thead button {
                                border: 0;
                                border-radius: none;
                                font-family: inherit;
                                font-weight: 700;
                                font-size: inherit;
                                padding: 0.5em;
                                margin-bottom: 1px;
                            }

                            tbody td {
                                padding: 0.5em;
                                border-bottom: 1px solid #ccc;
                            }

                            tbody tr:hover {
                                background-color: #eee;
                            }
                        `}</style>
                    </div>
                </form>
            </>
        </Auth>
    );
};

export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery }) => {
    const queryParam = 'speciesid';
    // eslint-disable-next-line prettier/prettier
    const speciesid = pipe(
        extractQueryParam(context.query, queryParam),
        O.getOrElse(constant('')),
    );

    return {
        props: {
            speciesid: speciesid,
            species: await mightFailWithArray<species>()(allSpecies()),
        },
    };
};

export default Images;
