import { yupResolver } from '@hookform/resolvers/yup';
import { species } from '@prisma/client';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import { useSession } from 'next-auth/client';
import Head from 'next/head';
import Link from 'next/link';
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
import { useConfirmation } from '../../hooks/useconfirmation';
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
    const confirm = useConfirmation();

    useEffect(() => {
        const fetchNewSelection = async (id: number | undefined) => {
            try {
                if (!id) {
                    setImages(undefined);
                    return;
                }

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

        // clear out any selections from previous work
        setSelectedImages(new Set<number>());
        setCurrentImage(undefined);
        setError('');
        setSelectedForCopy(new Set<number>());
        setCopySource(undefined);

        fetchNewSelection(selected?.id);
    }, [selected?.id]);

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

    const saveImage = async (img: ImageApi) => {
        try {
            const res = await fetch(`../api/images`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(img),
            });

            if (res.status == 200) {
                const imgs = (await res.json()) as ImageApi[];
                if (imgs) {
                    setImages(imgs);
                }
            } else {
                throw new Error(await res.text());
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

        return confirm({
            variant: 'danger',
            catchOnCancel: true,
            title: 'Are you sure want to copy?',
            message: `This will copy all of the metadata (source, source link, license, license link, creator, and attribution) from the original selected image to ${
                selectedForCopy.size > 1 ? `ALL ${selectedForCopy.size} of the other selected images` : `the other selected image`
            }. Do you want to continue?`,
        })
            .then(() => {
                setShowCopy(false);
                Promise.all(
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
                        }))
                        .map((i) => saveImage(i)),
                ).catch((e: unknown) => setError(`Failed to save changes. ${e}.`));
            })
            .catch(() => {
                setShowCopy(false);
                Promise.resolve();
            })
            .finally(() => setSelectedForCopy(new Set<number>()));
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
                        onSave={saveImage}
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
                                    if (s.length > 0) {
                                        setSelected(s[0]);
                                        router.push(`?speciesid=${s[0]?.id}`, undefined, { shallow: true });
                                    } else {
                                        setSelected(undefined);
                                        router.push(``, undefined, { shallow: true });
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
                    <Row hidden={!selected} className="formGroup">
                        <Col>
                            <br />
                            <div>
                                <Link href={`./gall?id=${selected?.id}`}>Edit the Gall</Link>
                            </div>
                            <div>
                                <Link href={`./speciessource?id=${selected?.id}`}>Add/Edit Sources for this Gall</Link>
                            </div>
                        </Col>
                    </Row>
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
