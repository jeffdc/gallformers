import Image from 'next/image';
import React, { useState } from 'react';
import { Carousel, CarouselItem, Modal } from 'react-bootstrap';
import useWindowDimensions from '../hooks/usewindowdimension';
import { ImagePaths, SpeciesApi } from '../libs/api/apitypes';

// Modal.setAppElement('#__next');

type Props = {
    imagePaths: ImagePaths;
    species: SpeciesApi;
    type: 'gall' | 'host';
};

const Images = ({ imagePaths, species }: Props): JSX.Element => {
    const [showModal, setShowModal] = useState(false);
    const { width } = useWindowDimensions();

    const pad = 25;
    const hwRatio = 2 / 3;

    return imagePaths.small.length < 1 ? (
        <p className="p-2">No images yet...</p>
    ) : (
        <>
            <Modal show={showModal} onHide={() => setShowModal(false)} size="xl">
                <Modal.Header closeButton />
                <Modal.Body>
                    <Carousel interval={null} className="border-dark align-self-center p-2">
                        {imagePaths.large.map((path) => (
                            <CarouselItem key={path}>
                                <Image
                                    src={path.replaceAll('small', 'large')}
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
                {imagePaths.small.map((image) => (
                    <CarouselItem key={image}>
                        <Image
                            src={image}
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
