import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { useSession } from 'next-auth/react';
import Image from 'next/image';
import Link from 'next/link';
import { useRouter } from 'next/router';
import Carousel from 'nuka-carousel';
import React, { useState } from 'react';
import { Button, ButtonGroup, ButtonToolbar, Col, Modal, OverlayTrigger, Popover, Row } from 'react-bootstrap';
import useWindowDimensions from '../hooks/usewindowdimension';
import { ALLRIGHTS, GallTaxon, ImageApi, ImageNoSourceApi, SpeciesApi } from '../libs/api/apitypes';
import { hasProp } from '../libs/utils/util';
import NoImage from '../public/images/noimage.jpg';
import NoImageHost from '../public/images/noimagehost.jpg';

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
        // move the default image so it is 1st (never know what the caller is handing us)
        // also do the type conversion to make sure we were not handed Sources with no Images
        images: sp.images.sort((a, b) => (a.default ? -1 : 0)).map((i) => checkSource(i)),
    };
    const [showModal, setShowModal] = useState(false);
    const [currentImage, setCurrentImage] = useState(species.images.length > 0 ? species.images[0] : undefined);
    const [imgIndex, setImgIndex] = useState(0);
    const [showInfo, setShowInfo] = useState(false);
    const { width } = useWindowDimensions();

    const router = useRouter();
    const session = useSession();

    const pad = 25;
    const hwRatio = 2 / 3;

    return species.images.length < 1 ? (
        <div className="p-2">
            <Image
                src={species.taxoncode === GallTaxon ? NoImage : NoImageHost}
                alt={`missing image of ${species.name}`}
                className="img-fluid d-block"
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
                                    router.push(`/admin/images?speciesid=${species.id}`);
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
            <Modal show={showModal} onHide={() => setShowModal(false)} centered dialogClassName="modal-90w">
                <Modal.Header closeButton />
                <Modal.Body>
                    <Carousel
                        renderCenterLeftControls={({ previousSlide }) => (
                            <Button variant="secondary" size="sm" onClick={previousSlide} className="m-1">
                                {'<'}
                            </Button>
                        )}
                        renderCenterRightControls={({ nextSlide }) => (
                            <Button variant="secondary" size="sm" onClick={nextSlide} className="m-1">
                                {'>'}
                            </Button>
                        )}
                        className="p-1"
                        heightMode="max"
                        slideIndex={imgIndex}
                        wrapAround={true}
                        transitionMode="fade"
                    >
                        {species.images.map((image) => (
                            <div key={image.id}>
                                <Image
                                    //TODO when all images have XL versions show those here rather than the original
                                    src={image.original}
                                    alt={`image of ${species.name}`}
                                    unoptimized
                                    width={width - 2 * pad}
                                    height={(width - 2 * pad) * hwRatio}
                                    objectFit={'contain'}
                                    className="d-block"
                                />
                                <p>{image.caption}</p>
                                {image.sourcelink != undefined && image.sourcelink !== '' && (
                                    <span>
                                        <a href={image.sourcelink} target="_blank" rel="noreferrer">
                                            Image
                                        </a>{' '}
                                        by {image.creator}
                                        {' © '}
                                        {image.license === ALLRIGHTS ? (
                                            image.license
                                        ) : (
                                            <a href={image.licenselink} target="_blank" rel="noreferrer">
                                                {image.license}
                                            </a>
                                        )}
                                    </span>
                                )}
                            </div>
                        ))}
                    </Carousel>
                </Modal.Body>
            </Modal>

            <Modal show={showInfo} onHide={() => setShowInfo(false)} size="xl">
                <Modal.Header closeButton>
                    <Modal.Title>Image Details</Modal.Title>
                </Modal.Header>
                <Modal.Body>
                    <Row>
                        <Col className="p-0 m-0 border" xs={4}>
                            <div className="image-container">
                                {/* eslint-disable-next-line @next/next/no-img-element */}
                                <img
                                    src={currentImage ? currentImage.small : ''}
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
                                    {pipe(
                                        currentImage ? currentImage.source : O.none,
                                        O.fold(
                                            constant(
                                                <a href={currentImage?.sourcelink} target="_blank" rel="noreferrer">
                                                    {currentImage?.sourcelink}
                                                </a>,
                                            ),
                                            (s) => (
                                                <Link href={`/source/${s.id}`}>
                                                    <a target="_blank" rel="noreferrer">
                                                        {s.title}
                                                    </a>
                                                </Link>
                                            ),
                                        ),
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
                <Carousel
                    renderCenterLeftControls={({ previousSlide }) => (
                        <Button variant="secondary" size="sm" onClick={previousSlide} className="ms-1">
                            {'<'}
                        </Button>
                    )}
                    renderCenterRightControls={({ nextSlide }) => (
                        <Button variant="secondary" size="sm" onClick={nextSlide} className="me-1">
                            {'>'}
                        </Button>
                    )}
                    className="p-1"
                    heightMode="first"
                    // beforeSlide={(c, e) => {
                    //     setCurrentImage(species.images[e]);
                    //     setImgIndex(e);
                    // }}
                    afterSlide={(c) => {
                        setCurrentImage(species.images[c]);
                        setImgIndex(c);
                    }}
                    wrapAround={true}
                    transitionMode="fade"
                    // t, r, b, l
                    framePadding="0px 10px 0px 10px"
                >
                    {species.images.map((image) => (
                        <div
                            key={image.id}
                            style={{ display: 'flex', alignItems: 'center', height: '100%' }}
                            className="align-items-center"
                        >
                            {/* the Carousel and next.js Image do not play well together and layout becomes an issue */}
                            {/* eslint-disable-next-line @next/next/no-img-element */}
                            <img
                                src={image.medium}
                                alt={`image of ${species.name}`}
                                className="img-fluid d-block"
                                onClick={() => {
                                    setShowModal(true);
                                }}
                            />
                        </div>
                    ))}
                </Carousel>
                <ButtonToolbar className="d-flex justify-content-center">
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
                        {session && (
                            <Button
                                variant="secondary"
                                style={{ fontSize: '1.0em' }}
                                onMouseDown={(e) => {
                                    if (e.button === 1 || e.ctrlKey || e.metaKey) {
                                        //  middle/command/ctrl click
                                        window.open(`/admin/images?speciesid=${species.id}`, '_blank');
                                    } else {
                                        router.push(`/admin/images?speciesid=${species.id}`);
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
