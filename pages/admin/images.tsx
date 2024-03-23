import { species } from '@prisma/client';
import axios from 'axios';
import * as O from 'fp-ts/lib/Option';
import { constant, pipe } from 'fp-ts/lib/function';
import { GetServerSideProps } from 'next';
import { useSession } from 'next-auth/react';
import { useRouter } from 'next/router';
import { ParsedUrlQuery } from 'querystring';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { Button, Col, Modal, Row } from 'react-bootstrap';
import { AsyncTypeahead } from 'react-bootstrap-typeahead';
import DataTable, { TableColumn } from 'react-data-table-component';
import { Controller, useForm } from 'react-hook-form';
import AddImage from '../../components/addImage';
import ImageEdit from '../../components/imageEdit';
import ImageGrid from '../../components/imageGrid';
import { useConfirmation } from '../../hooks/useConfirmation';
import { extractQueryParam } from '../../libs/api/apipage';
import { ImageApi } from '../../libs/api/apitypes';
import { speciesById } from '../../libs/db/species';
import Admin from '../../libs/pages/admin';
import { TABLE_CUSTOM_STYLES } from '../../libs/utils/DataTableConstants';
import { mightFailWithArray, sessionUserOrUnknown } from '../../libs/utils/util';

type Props = {
    sp: species[];
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
    return (
        // I tried to use Next/Image but it chokes in production with non-static images for some reason.
        // eslint-disable-next-line @next/next/no-img-element
        <img data-tag="allowRowEvents" src={row.small} width="100" />
        // <div className={'image-container'}>
        //     <Image data-tag="allowRowEvents" src={row.small} layout="fill" className={'image'} />
        // </div>
    );
};

const sourceFormatter = (row: ImageApi) => {
    return row.source ? (
        <span>
            <a href={`/source/${row.source.id}`}>{row.source.title}</a>
        </span>
    ) : (
        <span></span>
    );
    // return pipe(
    //     row.source,
    //     O.fold(constant(<span></span>), (s) => (
    //         <span>
    //             <a href={`/source/${s.id}`}>{s.title}</a>
    //         </span>
    //     )),
    // );
};

const defaultFieldFormatter = (img: ImageApi) => {
    return <span>{img ? '✓' : ''}</span>;
};

const Images = ({ sp }: Props): JSX.Element => {
    const [selected, setSelected] = useState(sp && sp.length > 0 ? sp[0] : undefined);
    const [selectedImages, setSelectedImages] = useState(new Array<ImageApi>());
    const [toggleCleared, setToggleCleared] = useState(false);
    const [images, setImages] = useState<ImageApi[]>();
    const [edit, setEdit] = useState(false);
    const [currentImage, setCurrentImage] = useState<ImageApi>();
    const [showCopy, setShowCopy] = useState(false);
    const [error, setError] = useState('');
    const [selectedForCopy, setSelectedForCopy] = useState(new Set<number>());
    const [copySource, setCopySource] = useState<ImageApi>();
    const [isLoading, setIsLoading] = useState(false);
    const [species, setSpecies] = useState<species[]>(sp ?? []);

    const form = useForm<FormFields>({
        mode: 'onBlur',
        defaultValues: {
            species: sp[0]?.name,
        },
    });

    const { data: session } = useSession();
    const router = useRouter();
    const confirm = useConfirmation();

    const columns = useMemo<TableColumn<ImageApi>[]>(
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
                // this is needed because the ReactDataTable component changed the contract and is trying to be overly clever with its types
                // eslint-disable-next-line @typescript-eslint/ban-ts-comment
                // @ts-ignore
                selector: (row: ImageApi) => row,
                name: 'Default',
                sortable: true,
                maxWidth: '100px',
                format: defaultFieldFormatter,
            },
            {
                id: 'source',
                // this is needed because the ReactDataTable component changed the contract and is trying to be overly clever with its types
                // eslint-disable-next-line @typescript-eslint/ban-ts-comment
                // @ts-ignore
                selector: (g: ImageApi) => g.source,
                name: 'Source',
                sortable: true,
                wrap: true,
                format: sourceFormatter,
            },
            {
                id: 'sourcelink',
                selector: (g: ImageApi) => g.sourcelink,
                name: 'Source Link',
                sortable: true,
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
                sortable: true,
            },
            {
                id: 'license',
                selector: (g: ImageApi) => g.license,
                maxWidth: '100px',
                wrap: true,
                name: 'License',
                sortable: true,
            },
            {
                id: 'licenselink',
                selector: (g: ImageApi) => g.licenselink,
                name: 'License Link',
                maxWidth: '200px',
                wrap: true,
                sortable: true,
                format: (img: ImageApi) => linkFormatter(img.licenselink),
            },
            {
                id: 'attribution',
                selector: (g: ImageApi) => g.attribution,
                name: 'Attribution',
                wrap: true,
                sortable: true,
            },
            {
                id: 'caption',
                selector: (g: ImageApi) => g.caption,
                name: 'Caption',
                wrap: true,
                sortable: true,
            },
        ],
        [],
    );

    useEffect(() => {
        const fetchNewSelection = async (id: number | undefined) => {
            if (!id) {
                setImages(undefined);
                return;
            }

            axios
                .get<ImageApi[]>(`/api/images?speciesid=${id}`)
                .then((res) => {
                    setImages(res.data);
                })
                .catch((e) => {
                    console.error(e);
                    setError(e.toString());
                });
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
        setImages([...(images !== undefined ? images : []), ...newImages]);
    };

    const handleClose = () => setEdit(false);

    const handleRowClick = (img: ImageApi) => {
        const image = images?.find((i) => i.id === img.id);
        setCurrentImage(image);
        setEdit(true);
    };

    const saveImage = async (img: ImageApi) => {
        const body = {
            ...img,
            lastchangedby: sessionUserOrUnknown(session?.user?.name),
        };

        axios
            .post<ImageApi[]>(`/api/images`, body)
            .then((res) => setImages(res.data))
            .catch((e) => {
                const msg = `Error while trying to update image.\n${JSON.stringify(img)}\n${e}`;
                console.error(msg);
                setError(msg);
            });
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
            message: `This will copy all of the metadata (source, source link, license, license link, creator, attribution, and caption) from the original selected image to ${
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
                        .map((i) => {
                            saveImage(i);
                        }),
                ).catch((e: unknown) => setError(`Failed to save changes. ${e}.`));
            })
            .catch(() => {
                setShowCopy(false);
                Promise.resolve();
            })
            .finally(() => {
                setCurrentImage(undefined);
                setSelectedForCopy(new Set<number>());
                setToggleCleared(!toggleCleared);
            });
    };

    const handleRowSelected = useCallback((state: { allSelected: boolean; selectedCount: number; selectedRows: ImageApi[] }) => {
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
                            axios
                                .delete(
                                    `/api/images?speciesid=${selected.id}&imageids=${[
                                        ...selectedImages.map((img) => img.id).values(),
                                    ]}`,
                                )
                                .then(() => setImages(images?.filter((i) => !selectedImages.find((oi) => oi.id === i.id))));

                            form.reset({ delete: [], species: selected.name });
                            setToggleCleared(!toggleCleared);
                        })
                        .catch(() => Promise.resolve());
                }
            } catch (e) {
                // eslint-disable-next-line @typescript-eslint/no-explicit-any
                const err: any = e;
                console.error(err);
                setError(err.toString());
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

    const handleSearch = (s: string) => {
        setIsLoading(true);

        axios
            .get<species[]>(`/api/species?q=${s}`)
            .then((resp) => {
                setSpecies(resp.data);
                setIsLoading(false);
            })
            .catch((e) => {
                console.error(e);
            });
    };

    return (
        <Admin type="Images" keyField="name" selected={selected} form={form} setError={setError} error={error}>
            <>
                {currentImage && <ImageEdit image={currentImage} onSave={saveImage} show={edit} onClose={handleClose} />}

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
                        <Button variant="secondary" className="mt-4 ms-2" onClick={() => setShowCopy(false)}>
                            Cancel
                        </Button>
                    </Modal.Body>
                </Modal>
                <>
                    <h4>Add/Edit Species Images</h4>
                    <Row className="my-1" xs={3}>
                        <Col xs={1} style={{ paddingTop: '5px' }}>
                            Species:
                        </Col>
                        <Col>
                            <Controller
                                name="species"
                                control={form.control}
                                render={() => (
                                    <AsyncTypeahead
                                        id="species"
                                        options={species}
                                        labelKey="name"
                                        clearButton
                                        selected={selected ? [selected] : []}
                                        {...form.register('species')}
                                        onChange={(s: species[]) => {
                                            if (s.length > 0) {
                                                setSelected(s[0]);
                                                router.push(`?speciesid=${s[0]?.id}`, undefined, { shallow: true });
                                            } else {
                                                setSelected(undefined);
                                                router.push(``, undefined, { shallow: true });
                                            }
                                        }}
                                        isLoading={isLoading}
                                        onSearch={handleSearch}
                                        filterBy={() => true}
                                        minLength={1}
                                    />
                                )}
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
                    <Row className="my-1">
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
                </>
            </>
        </Admin>
    );
};

export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery }) => {
    const sp = pipe(
        extractQueryParam(context.query, 'speciesid'),
        O.map(parseInt),
        O.map((id) => mightFailWithArray<species>()(speciesById(id))),
        O.getOrElse(constant(Promise.resolve(new Array<species>()))),
    );

    return {
        props: {
            sp: await sp,
        },
    };
};

export default Images;
