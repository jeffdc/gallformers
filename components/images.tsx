import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { useSession } from 'next-auth/client';
import Image from 'next/image';
import Link from 'next/link';
import { useRouter } from 'next/router';
import React, { useState } from 'react';
import { Button, ButtonGroup, ButtonToolbar, Col, Modal, OverlayTrigger, Popover, Row } from 'react-bootstrap';
import useWindowDimensions from '../hooks/usewindowdimension';
import { SpeciesApi } from '../libs/api/apitypes';
import Carousel from 'nuka-carousel';

type Props = {
    species: SpeciesApi;
    type: 'gall' | 'host';
};

const Images = ({ species }: Props): JSX.Element => {
    const [showModal, setShowModal] = useState(false);
    const [currentImage, setCurrentImage] = useState(species.images.length > 0 ? species.images[0] : undefined);
    const [imgIndex, setImgIndex] = useState(0);
    const [showInfo, setShowInfo] = useState(false);
    const { width } = useWindowDimensions();

    const router = useRouter();
    const session = useSession();

    const pad = 25;
    const hwRatio = 2 / 3;

    // sort so that the default image always is first
    species.images.sort((a) => (a.default ? -1 : 1));

    return species.images.length < 1 ? (
        <p className="p-2">
            <img src="/images/noimage.jpg" alt={`missing image of ${species.name}`} className="img-fluid d-block" />
        </p>
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
                                {image.sourcelink != undefined && image.sourcelink !== '' && (
                                    <a href={image.sourcelink} target="_blank" rel="noreferrer">
                                        Link to Original
                                    </a>
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
                            <Image
                                src={currentImage ? currentImage.small : ''}
                                unoptimized
                                alt={`image of ${species.name}`}
                                width={'300'}
                                height={'200'}
                                objectFit={'contain'}
                            />
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
                        </Col>
                    </Row>
                </Modal.Body>
            </Modal>
            <div className="border rounded pb-1">
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
                    heightMode="first"
                    beforeSlide={(c, e) => {
                        setCurrentImage(species.images[e]);
                        setImgIndex(e);
                    }}
                    wrapAround={true}
                >
                    {species.images.map((image) => (
                        <div
                            key={image.id}
                            style={{ display: 'flex', alignItems: 'center', height: '100%' }}
                            className="align-items-center"
                        >
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
                <ButtonToolbar className="row d-flex justify-content-center">
                    <ButtonGroup size="sm">
                        <OverlayTrigger
                            trigger="focus"
                            placement="bottom"
                            overlay={
                                <Popover id="copyright-popover">
                                    <Popover.Content>{`${
                                        currentImage?.license ? currentImage.license : 'No License'
                                    }`}</Popover.Content>
                                </Popover>
                            }
                        >
                            <Button variant="secondary" style={{ fontSize: '1.1em', fontWeight: 'lighter' }}>
                                ©
                            </Button>
                        </OverlayTrigger>
                        <Button variant="secondary" style={{ fontWeight: 'bold' }} onClick={() => setShowInfo(true)}>
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
