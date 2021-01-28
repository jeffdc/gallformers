import { yupResolver } from '@hookform/resolvers/yup';
import { species } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Head from 'next/head';
import { ParsedUrlQuery } from 'querystring';
import React, { useState } from 'react';
import { Button, Col, Modal, Row, Table } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import AddImage from '../../components/addimage';
import Auth from '../../components/auth';
import ControlledTypeahead from '../../components/controlledtypeahead';
import ImageEdit from '../../components/imageedit';
import { extractQueryParam } from '../../libs/api/apipage';
import { ImageApi, ImagePaths } from '../../libs/api/apitypes';
import { allSpecies } from '../../libs/db/species';
import { mightFailWithArray } from '../../libs/utils/util';

const Schema = yup.object().shape({
    value: yup.mixed().required(),
    author: yup.string().required(),
    pubyear: yup.string().matches(/([12][0-9]{3})/),
    citation: yup.string().required(),
});

type Props = {
    speciesid: string;
    species: species[];
};

type FormFields = {
    species: string;
};

const Images = ({ speciesid, species }: Props): JSX.Element => {
    const sp = species.find((s) => s.id === parseInt(speciesid));
    const [selected, setSelected] = useState(sp);
    const [images, setImages] = useState<ImageApi[]>();
    const [edit, setEdit] = useState(false);
    const [currentImage, setCurrentImage] = useState<ImageApi>();

    const { handleSubmit, control, reset } = useForm<FormFields>({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
        defaultValues: {
            species: sp?.name,
        },
    });

    const onSubmit = async (data: FormFields) => {
        reset();
    };

    const changeSelected = async (species: species[]) => {
        try {
            const sp = species[0];
            if (!sp) return;

            const res = await fetch(`../api/images?speciesid=${sp.id}`, {
                method: 'GET',
            });

            if (res.status === 200) {
                const imgs = (await res.json()) as ImageApi[];
                setImages(imgs);
                setSelected(sp);
            } else {
                throw new Error(await res.text());
            }
        } catch (e) {
            console.error(e);
        }
    };

    const addImages = async (imagePaths: ImagePaths) => {
        // this seems kludgy but it prevents having to make another call to the server to get the paths
        // imagePaths.small.push(...images.small);
        // imagePaths.medium.push(...images.medium);
        // imagePaths.large.push(...images.large);
        // imagePaths.original.push(...images.original);
        // // add a delay here to hopefully give a chance for the image to be picked up by the CDN
        // await new Promise((r) => setTimeout(r, 2000));
        // setImages(imagePaths);
    };

    const handleClose = () => setEdit(false);

    const editRow = (e: React.MouseEvent<HTMLTableRowElement, MouseEvent>): void => {
        const image = images?.find((i) => i.id == parseInt(e.currentTarget.id));
        setCurrentImage(image);
        setEdit(true);
    };

    const saveImage = async (image: ImageApi) => {
        try {
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

                {currentImage && selected && (
                    <ImageEdit
                        image={currentImage}
                        speciesid={selected.id}
                        onSave={saveImage}
                        show={edit}
                        onClose={handleClose}
                    />
                )}

                <form onSubmit={handleSubmit(onSubmit)} className="m-4 pr-4">
                    <h4>Add/Edit Species Images</h4>
                    <Row className="form-group" xs={3}>
                        <Col>
                            Species:
                            <ControlledTypeahead
                                control={control}
                                name="species"
                                options={species}
                                labelKey="name"
                                clearButton
                                onChange={changeSelected}
                            />
                        </Col>
                    </Row>
                    <Row className="">
                        <Col>
                            <input type="button" className="button" value="Delete Selected" />
                        </Col>
                    </Row>
                    <Row>
                        <Col>{selected && <AddImage id={selected.id} onChange={addImages} />}</Col>
                    </Row>
                    <div className="fixed-left mt-2 ml-2 mr-2">
                        <Table striped>
                            <thead>
                                <tr>
                                    <th className="thead-dark"></th>
                                    <th>default</th>
                                    <th>image</th>
                                    <th>creator</th>
                                    <th>attribution</th>
                                    <th>source</th>
                                    <th>license</th>
                                    <th>uploader</th>
                                </tr>
                            </thead>
                            <tbody>
                                {images?.map((img) => (
                                    <tr key={img.path} id={img.id.toString()} onClick={editRow}>
                                        <td>
                                            <input type="checkbox" />
                                        </td>
                                        <td>{img.default ? '✓' : ''}</td>
                                        <td>
                                            <img src={img.small} width="100" />
                                        </td>
                                        <td>{img.creator}</td>
                                        <td>{img.attribution}</td>
                                        <td>{img.source}</td>
                                        <td>{img.license}</td>
                                        <td>{img.uploader}</td>
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
    const speciesid = pipe(
        extractQueryParam(context.query, queryParam),
        O.getOrElse(() => ''),
    );

    return {
        props: {
            speciesid: speciesid,
            species: await mightFailWithArray<species>()(allSpecies()),
        },
    };
};

export default Images;
