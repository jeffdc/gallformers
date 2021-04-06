import { yupResolver } from '@hookform/resolvers/yup';
import { species } from '@prisma/client';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import { useSession } from 'next-auth/client';
import Head from 'next/head';
import { useRouter } from 'next/router';
import { ParsedUrlQuery } from 'querystring';
import React, { useEffect, useState } from 'react';
import { Alert, Button, Col, Modal, Row, Table } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import AddImage from '../../components/addimage';
import Auth from '../../components/auth';
import ControlledTypeahead from '../../components/controlledtypeahead';
import ImageEdit from '../../components/imageedit';
import ImageGrid from '../../components/imagegrid';
import { extractQueryParam } from '../../libs/api/apipage';
import { ImageApi } from '../../libs/api/apitypes';
import { allSpecies } from '../../libs/db/species';
import { mightFailWithArray, sessionUserOrUnknown } from '../../libs/utils/util';

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
    const [selectedId, setSelectedId] = useState(speciesid ? parseInt(speciesid) : undefined);
    const [selectedImages, setSelectedImages] = useState(new Set<number>());
    const [images, setImages] = useState<ImageApi[]>();
    const [edit, setEdit] = useState(false);
    const [currentImage, setCurrentImage] = useState<ImageApi>();
    const [showCopy, setShowCopy] = useState(false);
    const [error, setError] = useState('');
    const [selectedForCopy, setSelectedForCopy] = useState(new Set<number>());
    const [copySource, setCopySource] = useState<ImageApi>();

    const { handleSubmit, control, register, reset, setValue } = useForm<FormFields>({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
        defaultValues: {
            species: sp?.name,
        },
    });

    const [session] = useSession();
    const router = useRouter();

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
                setError(e);
            }
        };
        fetchNewSelection(selectedId);
    }, [selectedId]);

    const selectAll = (e: React.MouseEvent<HTMLInputElement, MouseEvent>) => {
        images?.forEach((i) => {
            setValue(`delete-${i.id}`, e.currentTarget.checked);
            if (e.currentTarget.checked) selectedImages.add(i.id);
        });
        setSelectedImages(selectedImages);
    };

    const onSubmit = async () => {
        try {
            if (selectedImages.size > 0) {
                const res = await fetch(`../api/images?speciesid=${selectedId}&imageids=${[...selectedImages.values()]}`, {
                    method: 'DELETE',
                });

                if (res.status === 200) {
                    setImages(images?.filter((i) => !selectedImages.has(i.id)));
                } else {
                    throw new Error(await res.text());
                }

                reset({ delete: [], species: sp?.name });
                selectedImages.clear();
                setSelectedImages(selectedImages);
            }
        } catch (e) {
            console.error(e);
            setError(e);
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

    const startCopy = () => {
        if (selectedImages.size === 1) {
            setError('');
            setCopySource(images?.find((i) => selectedImages.has(i.id)));
            setShowCopy(true);
        } else if (images && images.length < 2) {
            setError('There is only one image so you can not copy yet. Upload another image first.');
        } else {
            setError('You need to select one (and only one) image to begin a copy.');
        }
    };

    const saveImages = async (imgs: ImageApi[]) => {
        try {
            const updatedImages = imgs.map((i) => {
                i.lastchangedby = session && session.user.name ? session.user.name : 'UNKNOWN!';
                return i;
            });

            const res = await fetch(`../api/images`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(updatedImages),
            });

            if (res.status !== 200) {
                throw new Error(await res.text());
            }

            if (images) {
                const updatedImageIds = new Set(updatedImages.map((i) => i.id));
                setImages([...updatedImages, ...images.filter((img) => !updatedImageIds.has(img.id))]);
            }

            setCurrentImage(undefined);
        } catch (e) {
            console.error(e);
            setError(e);
        }
    };

    const doCopy = async () => {
        if (!copySource || !images) {
            console.error('Somehow the source and/or the images for the copy are undefined.');
            return;
        }

        await saveImages(
            images
                .filter((i) => selectedForCopy.has(i.id))
                .map<ImageApi>((i) => ({
                    ...i,
                    lastchangedby: sessionUserOrUnknown(session),
                    source: copySource.source,
                    sourcelink: copySource.sourcelink,
                    license: copySource.license,
                    licenselink: copySource.licenselink,
                    creator: copySource.creator,
                    attribution: copySource.attribution,
                })),
        ).catch((e: unknown) => setError(`Failed to save changes. ${e}.`));

        setShowCopy(false);
    };

    return (
        <Auth>
            <>
                <Head>
                    <title>Add/Edit Species Images</title>
                </Head>

                {error.length > 0 && (
                    <Alert variant="danger" onClose={() => setError('')} dismissible>
                        <Alert.Heading>Uh-oh</Alert.Heading>
                        <p>{error}</p>
                    </Alert>
                )}

                {currentImage && selectedId && (
                    // eslint-disable-next-line prettier/prettier
                    <ImageEdit 
                        image={currentImage}
                        speciesid={selectedId}
                        onSave={(i) => saveImages([i])}
                        show={edit}
                        onClose={handleClose}
                    />
                )}

                <Modal show={showCopy} onHide={() => setShowCopy(false)} size="lg">
                    <Modal.Header closeButton>
                        <Modal.Title>Copy Image Details</Modal.Title>
                    </Modal.Header>
                    <Modal.Body>
                        <p>Select the other images that you want to copy details to:</p>
                        {images && (
                            <ImageGrid
                                colCount={6}
                                images={images.filter((img) => !selectedImages.has(img.id))}
                                selected={selectedForCopy}
                                setSelected={setSelectedForCopy}
                            />
                        )}
                        <Button variant="primary" className="mt-4" onClick={doCopy}>
                            Copy
                        </Button>
                        <Button variant="secondary" className="mt-4 ml-2" onClick={() => setShowCopy(false)}>
                            Cancel
                        </Button>
                    </Modal.Body>
                </Modal>

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
                                    const id = s[0]?.id;
                                    setSelectedId(id);
                                    router.push(`?speciesid=${id}`, undefined, { shallow: true });
                                }}
                            />
                        </Col>
                        <Col>{selectedId && <AddImage id={selectedId} onChange={addImages} />}</Col>
                    </Row>
                    <Row className="">
                        <Col xs={2}>
                            <input type="submit" className="btn btn-secondary" value="Delete Selected" />
                        </Col>
                        <Col>
                            <Button variant="secondary" onClick={startCopy}>
                                Copy One to Others
                            </Button>
                        </Col>
                    </Row>
                    <div className="fixed-left mt-2 ml-2 mr-2">
                        <Table striped>
                            <thead>
                                <tr>
                                    <th>
                                        <input type="checkbox" key={speciesid} onClick={selectAll} />
                                    </th>
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
                                    <tr key={img.id} id={img.id.toString()} onClick={editRow}>
                                        <td>
                                            <input
                                                type="checkbox"
                                                key={img.id}
                                                id={img.id.toString()}
                                                name={`delete-${img.id}`}
                                                ref={register}
                                                onClick={(e) => {
                                                    e.stopPropagation();
                                                    e.currentTarget.checked
                                                        ? selectedImages.add(parseInt(e.currentTarget.id))
                                                        : selectedImages.delete(parseInt(e.currentTarget.id));
                                                    setSelectedImages(selectedImages);
                                                }}
                                            />
                                        </td>
                                        <td>
                                            <img src={img.small} width="100" />
                                        </td>
                                        <td>
                                            <span className="d-flex justify-content-center">{img.default ? '✓' : ''}</span>
                                        </td>
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
