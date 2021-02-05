import Image from 'next/image';
import React, { useState } from 'react';
import { Carousel, CarouselItem, Modal } from 'react-bootstrap';
import useWindowDimensions from '../hooks/usewindowdimension';
import { SpeciesApi } from '../libs/api/apitypes';

// Modal.setAppElement('#__next');

type Props = {
    species: SpeciesApi;
    type: 'gall' | 'host';
};

const Images = ({ species }: Props): JSX.Element => {
    const [showModal, setShowModal] = useState(false);
    const { width } = useWindowDimensions();

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

            <Carousel interval={null} className="border-dark align-self-center p-2">
                {species.images.map((image) => (
                    <CarouselItem key={image.id}>
                        <Image
                            src={image.small}
                            unoptimized
                            alt={`photo of ${species.name}`}
                            width={'300'}
                            height={'200'}
                            objectFit={'contain'}
                            onClick={() => setShowModal(true)}
                        />
                    </CarouselItem>
                ))}
            </Carousel>
        </>
    );
};

export default Images;
