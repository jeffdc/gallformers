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
import { Alert, Button, Col, Modal, Row } from 'react-bootstrap';
import BootstrapTable, { ColumnDescription, RowEventHandlerProps, SelectRowProps } from 'react-bootstrap-table-next';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import AddImage from '../../components/addimage';
import Auth from '../../components/auth';
import ImageEdit from '../../components/imageedit';
import ImageGrid from '../../components/imagegrid';
import Typeahead from '../../components/Typeahead';
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

const externalLinkFormatter = (link: string) => {
    return (
        <a href={link} target="_blank" rel="noreferrer">
            {link}
        </a>
    );
};
const imageFormatter = (cell: string, row: ImageApi) => {
    return <img src={row.small} width="100" />;
};

const sourceFormatter = (cell: string, row: ImageApi) => {
    return pipe(
        row.source,
        O.fold(constant(<span></span>), (s) => (
            <span>
                <a href={`/source/${s.id}`}>{s.title}</a>
            </span>
        )),
    );
};

const columns: ColumnDescription[] = [
    {
        dataField: 'small',
        text: 'image',
        sort: true,
        editable: false,
        formatter: imageFormatter,
    },
    {
        dataField: 'default',
        text: 'default',
        sort: true,
    },
    {
        dataField: 'source',
        text: 'source',
        sort: true,
        formatter: sourceFormatter,
    },
    {
        dataField: 'sourcelink',
        text: 'source link',
        sort: true,
        formatter: externalLinkFormatter,
    },
    {
        dataField: 'creator',
        text: 'creator',
        sort: true,
    },
    {
        dataField: 'license',
        text: 'license',
        sort: true,
    },
    {
        dataField: 'licenselink',
        text: 'license link',
        sort: true,
        formatter: externalLinkFormatter,
    },
    {
        dataField: 'attribution',
        text: 'attribution',
        sort: true,
    },
];

const Images = ({ speciesid, species }: Props): JSX.Element => {
    const sp = species.find((s) => s.id === parseInt(speciesid));
    const [selected, setSelected] = useState(species.find((s) => s.id === parseInt(speciesid)));
    const [selectedImages, setSelectedImages] = useState(new Set<number>());
    const [images, setImages] = useState<ImageApi[]>();
    const [edit, setEdit] = useState(false);
    const [currentImage, setCurrentImage] = useState<ImageApi>();
    const [showCopy, setShowCopy] = useState(false);
    const [error, setError] = useState('');
    const [selectedForCopy, setSelectedForCopy] = useState(new Set<number>());
    const [copySource, setCopySource] = useState<ImageApi>();

    const { handleSubmit, control, reset } = useForm<FormFields>({
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
        fetchNewSelection(selected?.id);
    }, [selected?.id]);

    // const selectAll = (e: React.MouseEvent<HTMLInputElement, MouseEvent>) => {
    //     images?.forEach((i) => {
    //         setValue(`delete-${i.id}`, e.currentTarget.checked);
    //         if (e.currentTarget.checked) selectedImages.add(i.id);
    //     });
    //     setSelectedImages(selectedImages);
    // };

    const onSubmit = async () => {
        try {
            if (selected && selectedImages.size > 0) {
                const res = await fetch(`../api/images?speciesid=${selected.id}&imageids=${[...selectedImages.values()]}`, {
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

    const rowEvents: RowEventHandlerProps<ImageApi> = {
        onClick: (e, row) => {
            const image = images?.find((i) => i.id === row.id);
            setCurrentImage(image);
            setEdit(true);
        },
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
                    lastchangedby: sessionUserOrUnknown(session?.user.name),
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

    const selectRow: SelectRowProps<ImageApi> = {
        mode: 'checkbox',
        clickToSelect: false,
        onSelect: (row) => {
            const selection = new Set(selectedImages);
            selection.has(row.id) ? selection.delete(row.id) : selection.add(row.id);
            setSelectedImages(selection);
        },
        onSelectAll: (isSelect) => {
            if (isSelect) {
                setSelectedImages(new Set(images?.map((a) => a.id)));
            } else {
                setSelectedImages(new Set());
            }
        },
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

                {currentImage && (
                    // eslint-disable-next-line prettier/prettier
                    <ImageEdit 
                        image={currentImage}
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
                            <Typeahead
                                name="species"
                                control={control}
                                options={species}
                                labelKey="name"
                                clearButton
                                selected={selected ? [selected] : []}
                                onChange={(s: species[]) => {
                                    if (selected) {
                                        setSelected(s[0]);
                                        router.push(`?speciesid=${selected?.id}`, undefined, { shallow: true });
                                    }
                                }}
                            />
                        </Col>
                        <Col>{selected?.id && <AddImage id={selected.id} onChange={addImages} />}</Col>
                    </Row>
                    <Row className="form-group">
                        <Col xs={2}>
                            <input type="submit" className="btn btn-secondary" value="Delete Selected" />
                        </Col>
                        <Col>
                            <Button variant="secondary" onClick={startCopy}>
                                Copy One to Others
                            </Button>
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            <BootstrapTable
                                keyField={'id'}
                                data={images ? images : []}
                                columns={columns}
                                bootstrap4
                                striped
                                headerClasses="table-header"
                                rowEvents={rowEvents}
                                // cellEdit={cellEditFactory(cellEditProps)}
                                selectRow={selectRow}
                                defaultSorted={[
                                    {
                                        dataField: 'default',
                                        order: 'desc',
                                    },
                                ]}
                            />
                        </Col>
                    </Row>
                    {/* <div className="fixed-left mt-2 ml-2 mr-2">
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
                                                {...register(`delete-${img.id}`)}
                                                type="checkbox"
                                                key={img.id}
                                                id={img.id.toString()}
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
                    </div> */}
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
