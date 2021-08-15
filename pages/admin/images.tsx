import { yupResolver } from '@hookform/resolvers/yup';
import { species } from '@prisma/client';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import { useSession } from 'next-auth/client';
import { useRouter } from 'next/router';
import { ParsedUrlQuery } from 'querystring';
import React, { useCallback, useEffect, useMemo, useState } from 'react';
import { Button, Col, Modal, Row } from 'react-bootstrap';
import DataTable from 'react-data-table-component';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import AddImage from '../../components/addimage';
import ImageEdit from '../../components/imageedit';
import ImageGrid from '../../components/imagegrid';
import Typeahead from '../../components/Typeahead';
import { useConfirmation } from '../../hooks/useconfirmation';
import { extractQueryParam } from '../../libs/api/apipage';
import { ImageApi } from '../../libs/api/apitypes';
import { allSpecies } from '../../libs/db/species';
import Admin from '../../libs/pages/admin';
import { TABLE_CUSTOM_STYLES } from '../../libs/utils/DataTableConstants';
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

const linkFormatter = (link: string) => {
    return (
        <a href={link} target="_blank" rel="noreferrer">
            {link}
        </a>
    );
};

const imageFormatter = (row: ImageApi) => {
    return <img data-tag="allowRowEvents" src={row.small} width="100" />;
};

const sourceFormatter = (row: ImageApi) => {
    return pipe(
        row.source,
        O.fold(constant(<span></span>), (s) => (
            <span>
                <a href={`/source/${s.id}`}>{s.title}</a>
            </span>
        )),
    );
};

const defaultFieldFormatter = (img: ImageApi) => {
    return <span>{img.default ? '✓' : ''}</span>;
};

const Images = ({ speciesid, species }: Props): JSX.Element => {
    const sp = species.find((s) => s.id === parseInt(speciesid));
    const [selected, setSelected] = useState(species.find((s) => s.id === parseInt(speciesid)));
    const [selectedImages, setSelectedImages] = useState(new Array<ImageApi>());
    const [toggleCleared, setToggleCleared] = useState(false);
    const [images, setImages] = useState<ImageApi[]>();
    const [edit, setEdit] = useState(false);
    const [currentImage, setCurrentImage] = useState<ImageApi>();
    const [showCopy, setShowCopy] = useState(false);
    const [error, setError] = useState('');
    const [selectedForCopy, setSelectedForCopy] = useState(new Set<number>());
    const [copySource, setCopySource] = useState<ImageApi>();

    const { control, reset } = useForm<FormFields>({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
        defaultValues: {
            species: sp?.name,
        },
    });

    const [session] = useSession();
    const router = useRouter();
    const confirm = useConfirmation();

    const columns = useMemo(
        () => [
            {
                id: 'small',
                selector: (row: ImageApi) => row.small,
                name: 'Image',
                sortable: true,
                format: imageFormatter,
            },
            {
                id: 'default',
                selector: (row: ImageApi) => row.default,
                name: 'Default',
                sortable: true,
                maxWidth: '100px',
                format: defaultFieldFormatter,
            },
            {
                id: 'source',
                selector: (g: ImageApi) => g.source,
                name: 'Source',
                sort: true,
                wrap: true,
                format: sourceFormatter,
            },
            {
                id: 'sourcelink',
                selector: (g: ImageApi) => g.sourcelink,
                name: 'Source Link',
                sort: true,
                maxWidth: '200px',
                wrap: true,
                format: (img: ImageApi) => linkFormatter(img.sourcelink),
            },
            {
                id: 'creator',
                selector: (g: ImageApi) => g.creator,
                name: 'Creator',
                maxWidth: '100px',
                wrap: true,
                sort: true,
            },
            {
                id: 'license',
                selector: (g: ImageApi) => g.license,
                maxWidth: '100px',
                wrap: true,
                name: 'License',
                sort: true,
            },
            {
                id: 'licenselink',
                selector: (g: ImageApi) => g.licenselink,
                name: 'License Link',
                maxWidth: '200px',
                wrap: true,
                sort: true,
                format: (img: ImageApi) => linkFormatter(img.licenselink),
            },
            {
                id: 'attribution',
                selector: (g: ImageApi) => g.attribution,
                name: 'Attribution',
                wrap: true,
                sort: true,
            },
            {
                id: 'caption',
                selector: (g: ImageApi) => g.caption,
                name: 'Caption',
                wrap: true,
                sort: true,
            },
        ],
        [],
    );

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
        setSelectedImages([]);
        setCurrentImage(undefined);
        setError('');
        setSelectedForCopy(new Set<number>());
        setCopySource(undefined);
        setEdit(false);

        fetchNewSelection(selected?.id);
    }, [selected?.id]);

    const addImages = async (newImages: ImageApi[]) => {
        //hack: add a delay here to hopefully give a chance for the image to be picked up by the CDN
        await new Promise((r) => setTimeout(r, 2000));

        setImages([...(images !== undefined ? images : []), ...newImages]);
    };

    const handleClose = () => setEdit(false);

    const handleRowClick = (img: ImageApi) => {
        const image = images?.find((i) => i.id === img.id);
        setCurrentImage(image);
        setEdit(true);
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
                            lastchangedby: sessionUserOrUnknown(session?.user?.name),
                            source: copySource.source,
                            sourcelink: copySource.sourcelink,
                            license: copySource.license,
                            licenselink: copySource.licenselink,
                            creator: copySource.creator,
                            attribution: copySource.attribution,
                            caption: copySource.caption,
                        }))
                        .map((i) => saveImage(i)),
                ).catch((e: unknown) => setError(`Failed to save changes. ${e}.`));
            })
            .catch(() => {
                setShowCopy(false);
                Promise.resolve();
            })
            .finally(() => {
                setSelectedForCopy(new Set<number>());
                setToggleCleared(!toggleCleared);
            });
    };

    const handleRowSelected = useCallback((state) => {
        setSelectedImages(state.selectedRows);
    }, []);

    const contextActions = useMemo(() => {
        const handleDelete = () => {
            try {
                if (selected && selectedImages.length > 0) {
                    confirm({
                        variant: 'danger',
                        catchOnCancel: true,
                        title: 'Are you sure want to delete?',
                        message: `This will delete ALL ${selectedImages.length} currently selected images. Do you want to continue?`,
                    })
                        .then(async () => {
                            const res = await fetch(
                                `../api/images?speciesid=${selected.id}&imageids=${[
                                    ...selectedImages.map((img) => img.id).values(),
                                ]}`,
                                {
                                    method: 'DELETE',
                                },
                            );

                            if (res.status === 200) {
                                setImages(images?.filter((i) => !selectedImages.find((oi) => oi.id === i.id)));
                            } else {
                                throw new Error(await res.text());
                            }

                            reset({ delete: [], species: sp?.name });
                            setToggleCleared(!toggleCleared);
                        })
                        .catch(() => Promise.resolve());
                }
            } catch (e) {
                console.error(e);
                setError(e);
            }
        };

        const handleCopy = () => {
            if (selectedImages.length === 1) {
                setError('');
                setCopySource(images?.find((i) => selectedImages.find((oi) => oi.id === i.id)));
                setShowCopy(true);
            } else if (images && images.length < 2) {
                setError('There is only one image so you can not copy yet. Upload another image first.');
            } else {
                setError('You need to select one (and only one) image to begin a copy.');
            }
        };

        return (
            <>
                <Button key="add" onClick={handleCopy} variant="primary" disabled={selectedImages.length > 1}>
                    Copy One to Others
                </Button>
                &nbsp;
                <Button key="delete" onClick={handleDelete} variant="danger">
                    Delete
                </Button>
            </>
        );
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [selectedImages, toggleCleared]);

    return (
        <Admin type="Images" keyField="name" setError={setError} error={error} selected={selected}>
            <>
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
                                images={images.filter((img) => !selectedImages.find((oi) => oi.id === img.id))}
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
                <form className="m-4 pr-4">
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
                        <Col xs={7}>
                            {selected?.id && (
                                <>
                                    <AddImage id={selected.id} onChange={addImages} />{' '}
                                    <span className="text-danger">
                                        Currently you are limited to uploading at most 4 images at a time.
                                    </span>
                                </>
                            )}
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            <DataTable
                                keyField={'id'}
                                data={images ? images : []}
                                columns={columns}
                                striped
                                selectableRows
                                actions={<></>}
                                contextActions={contextActions}
                                onSelectedRowsChange={handleRowSelected}
                                clearSelectedRows={toggleCleared}
                                onRowClicked={handleRowClick}
                                responsive={false}
                                defaultSortFieldId="default"
                                defaultSortAsc={false}
                                customStyles={TABLE_CUSTOM_STYLES}
                            />
                        </Col>
                    </Row>
                </form>
            </>
        </Admin>
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
