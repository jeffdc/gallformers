import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { useSession } from 'next-auth/client';
import Image from 'next/image';
import Link from 'next/link';
import { useRouter } from 'next/router';
import React, { useState } from 'react';
import {
    Button,
    ButtonGroup,
    ButtonToolbar,
    Carousel,
    CarouselItem,
    Col,
    Modal,
    OverlayTrigger,
    Popover,
    Row,
} from 'react-bootstrap';
import useWindowDimensions from '../hooks/usewindowdimension';
import { SpeciesApi } from '../libs/api/apitypes';

// Modal.setAppElement('#__next');

type Props = {
    species: SpeciesApi;
    type: 'gall' | 'host';
};

const Images = ({ species }: Props): JSX.Element => {
    const [showModal, setShowModal] = useState(false);
    const [currentImage, setCurrentImage] = useState(species.images.length > 0 ? species.images[0] : undefined);
    const [showInfo, setShowInfo] = useState(false);
    const { width } = useWindowDimensions();

    const router = useRouter();
    const session = useSession();

    const pad = 25;
    const hwRatio = 2 / 3;

    return species.images.length < 1 ? (
        <p className="p-2">No images yet...</p>
    ) : (
        <>
            <Modal show={showModal} onHide={() => setShowModal(false)} size="xl">
                <Modal.Header closeButton />
                <Modal.Body>
                    <Carousel interval={null} className="border-dark align-self-center p-2">
                        {species.images.map((image) => (
                            <CarouselItem key={image.id}>
                                <Image
                                    src={image.large}
                                    unoptimized
                                    alt={`photo of ${species.name}`}
                                    width={width - 2 * pad}
                                    height={(width - 2 * pad) * hwRatio}
                                    objectFit={'contain'}
                                />
                            </CarouselItem>
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
                                alt={`photo of ${species.name}`}
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
            <Carousel
                interval={null}
                className="border-dark align-self-center px-2 pt-1"
                onSelect={(i: number) => {
                    setCurrentImage(species.images[i]);
                }}
            >
                {species.images.map((image) => (
                    <CarouselItem key={image.id}>
                        <Image
                            src={image.small}
                            unoptimized
                            alt={`photo of ${species.name}`}
                            width={'300'}
                            height={'200'}
                            objectFit={'contain'}
                            onClick={() => {
                                setShowModal(true);
                            }}
                        />
                    </CarouselItem>
                ))}
            </Carousel>
            <ButtonToolbar className="row d-flex justify-content-center mt-2">
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
                            onClick={() => router.push(`/admin/images?speciesid=${species.id}`)}
                        >
                            ✎
                        </Button>
                    )}
                </ButtonGroup>
            </ButtonToolbar>
        </>
    );
};

export default Images;
