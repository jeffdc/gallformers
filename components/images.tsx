import { useSession } from 'next-auth/react';
import Image from 'next/image';
import Link from 'next/link';
import { useRouter } from 'next/router';
import { useState } from 'react';
import { Button, ButtonGroup, ButtonToolbar, Col, Modal, OverlayTrigger, Popover, Row } from 'react-bootstrap';
import useIsMounted from '../hooks/useIsMounted';
import useWindowDimensions from '../hooks/useWindowDimensions';
import { ImageApi, ImageLicenseValues, ImageNoSourceApi, SpeciesApi, TaxonCodeValues } from '../libs/api/apitypes';
import { hasProp } from '../libs/utils/util';
import NoImage from '../public/images/noimage.jpg';
import NoImageHost from '../public/images/noimagehost.jpg';
import ImageCarousel, { CarouselImage } from './ImageCarousel';

// type guard for dealing with possible Images without Source data. If this happens there is an upstream
// programming error so we will fail fast and hard.
const checkHasSource = (i: ImageApi | ImageNoSourceApi): i is ImageApi => hasProp(i, 'sourcelink');
const checkSource = (i: ImageApi | ImageNoSourceApi): ImageApi => {
    if (checkHasSource(i)) {
        return i;
    } else {
        throw new Error('Received an Image missing Source typings.');
    }
};

type Props = {
    sp: SpeciesApi;
    type: 'gall' | 'host';
};

const Images = ({ sp }: Props): JSX.Element => {
    const species = {
        ...sp,
        // move the default image so it is 1st (never know what the caller is handing us).
        // also group the images by source.
        // also do the type conversion to make sure we were not handed Sources with no Images
        images: sp.images
            .sort((a, b) => {
                // First, prioritize default images
                if (a.default && !b.default) return -1;
                if (!a.default && b.default) return 1;

                // Then group by source title, handling null sources
                const sourceA = a.source?.title ?? '';
                const sourceB = b.source?.title ?? '';

                if (sourceA < sourceB) return -1;
                if (sourceA > sourceB) return 1;

                // If same source, maintain original order
                return 0;
            })
            .map((i) => checkSource(i)),
    };
    const [showInfo, setShowInfo] = useState(false);
    const [currentImage, setCurrentImage] = useState(species.images.length > 0 ? species.images[0] : undefined);
    const { width, height } = useWindowDimensions();
    const mounted = useIsMounted();
    const router = useRouter();
    const session = useSession();

    const pad = 25;

    // Convert species images to the format expected by ImageCarousel
    const carouselImages: CarouselImage[] = species.images.map(
        (image) =>
            ({
                id: image.id,
                src: image.original,
                alt: `image of ${species.name}`,
                original: image.original,
                caption: image.caption,
                sourcelink: image.sourcelink,
                creator: image.creator,
                license: image.license,
                licenselink: image.licenselink,
            }) as CarouselImage,
    );

    // Render content for the carousel
    const renderImageForCarousel = (image: CarouselImage, isModal = false, handleImageClick?: (index: number) => void) => {
        return (
            <div className="p-1">
                <Image
                    src={image.original}
                    alt={`image of ${species.name}`}
                    unoptimized
                    width={width - 2 * pad}
                    height={height - 2 * pad}
                    style={{
                        objectFit: 'contain',
                        maxHeight: '70vh',
                        maxWidth: '100%',
                        width: 'auto',
                        height: 'auto',
                    }}
                    className="d-block"
                    onClick={
                        !isModal && handleImageClick
                            ? () => handleImageClick(carouselImages.findIndex((img) => img.id === image.id))
                            : undefined
                    }
                />
                <p>{image.caption}</p>

                {image.sourcelink != undefined && image.sourcelink !== '' && (
                    <span>
                        <a href={image.sourcelink} target="_blank" rel="noreferrer">
                            Image
                        </a>{' '}
                        by {image.creator}
                        {' © '}
                        {image.license === ImageLicenseValues.ALL_RIGHTS ? (
                            image.license
                        ) : (
                            <a href={image.licenselink} target="_blank" rel="noreferrer">
                                {image.license}
                            </a>
                        )}
                    </span>
                )}
            </div>
        );
    };

    return species.images.length < 1 ? (
        <div className="p-2">
            <Image
                src={species.taxoncode === TaxonCodeValues.GALL ? NoImage : NoImageHost}
                alt={`missing image of ${species.name}`}
                className="img-fluid d-block"
                width={300}
                height={200}
            />
            {session && (
                <ButtonToolbar className="row d-flex justify-content-center">
                    <ButtonGroup size="sm">
                        <Button
                            variant="secondary"
                            style={{ fontSize: '1.0em' }}
                            onMouseDown={(e) => {
                                if (e.button === 1 || e.ctrlKey || e.metaKey) {
                                    //  middle/command/ctrl click
                                    window.open(`/admin/images?speciesid=${species.id}`, '_blank');
                                } else {
                                    void router.push(`/admin/images?speciesid=${species.id}`);
                                }
                            }}
                        >
                            ✎
                        </Button>
                    </ButtonGroup>
                </ButtonToolbar>
            )}
        </div>
    ) : (
        <>
            <Modal
                show={showInfo}
                onHide={() => setShowInfo(false)}
                size="xl"
                dialogClassName="modal-fit-viewport"
                style={{ padding: '20px' }}
            >
                <Modal.Header closeButton>
                    <Modal.Title>Image Details</Modal.Title>
                </Modal.Header>
                <Modal.Body style={{ padding: '20px' }}>
                    <Row>
                        <Col className="p-0 m-0 border" xs={4}>
                            <div className="image-container">
                                {}
                                <img
                                    src={currentImage ? currentImage.original : ''}
                                    alt={`image of ${species.name}`}
                                    width={250}
                                    className={'image'}
                                />
                            </div>
                        </Col>
                        <Col>
                            <Row>
                                <Col>
                                    <b>Source:</b>{' '}
                                    {currentImage ? (
                                        currentImage.source ? (
                                            <Link href={`/source/${currentImage.source.id}`} target="_blank" rel="noreferrer">
                                                {currentImage.source.title}
                                            </Link>
                                        ) : (
                                            <a href={currentImage.sourcelink} target="_blank" rel="noreferrer">
                                                {currentImage.sourcelink}
                                            </a>
                                        )
                                    ) : (
                                        <></>
                                    )}
                                </Col>
                            </Row>
                            <Row>
                                <Col>
                                    <b>License:</b>{' '}
                                    <a href={currentImage?.licenselink} target="_blank" rel="noreferrer">
                                        {currentImage?.license}
                                    </a>
                                </Col>
                            </Row>
                            <Row>
                                <Col>
                                    <b>Attribution Info:</b> {currentImage?.attribution}
                                </Col>
                            </Row>
                            <Row>
                                <Col>
                                    <b>Creator:</b> {currentImage?.creator}
                                </Col>
                            </Row>
                            <Row>
                                <Col>
                                    <b>Uploader:</b> {currentImage?.uploader}
                                </Col>
                                <Col>
                                    <b>Last Modified:</b> {currentImage?.lastchangedby}
                                </Col>
                            </Row>
                            <Row>
                                <Col>
                                    <b>Caption: </b>
                                    {currentImage?.caption}
                                </Col>
                            </Row>
                        </Col>
                    </Row>
                </Modal.Body>
            </Modal>
            <div className="border rounded pb-1">
                <ImageCarousel
                    images={carouselImages}
                    onImageClick={(index, image) => {
                        // Only update if the image is different
                        if (currentImage?.id !== image.id) {
                            setCurrentImage(image);
                        }
                    }}
                    onSlideChange={(index, image) => {
                        // Only update if the image is different
                        if (currentImage?.id !== image.id) {
                            setCurrentImage(image);
                        }
                    }}
                    renderContent={renderImageForCarousel}
                />
                <ButtonToolbar className="pt-1 d-flex justify-content-center">
                    <ButtonGroup size="sm">
                        <OverlayTrigger
                            trigger="focus"
                            placement="bottom"
                            overlay={
                                <Popover id="copyright-popover">
                                    <Popover.Body>{`${
                                        currentImage?.license ? currentImage.license : 'No License'
                                    }`}</Popover.Body>
                                </Popover>
                            }
                        >
                            <Button variant="secondary" style={{ fontSize: '1.1em', fontWeight: 'lighter' }}>
                                ©
                            </Button>
                        </OverlayTrigger>
                        <Button
                            variant="secondary"
                            style={{ fontWeight: 'bold' }}
                            onClick={() => {
                                setShowInfo(true);
                            }}
                        >
                            ⓘ
                        </Button>
                        {mounted && session && (
                            <Button
                                variant="secondary"
                                style={{ fontSize: '1.0em' }}
                                onMouseDown={(e) => {
                                    if (e.button === 1 || e.ctrlKey || e.metaKey) {
                                        //  middle/command/ctrl click
                                        window.open(`/admin/images?speciesid=${species.id}`, '_blank');
                                    } else {
                                        void router.push(`/admin/images?speciesid=${species.id}`);
                                    }
                                }}
                            >
                                ✎
                            </Button>
                        )}
                    </ButtonGroup>
                </ButtonToolbar>
            </div>
        </>
    );
};

export default Images;
