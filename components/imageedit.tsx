import { useSession } from 'next-auth/client';
import React, { useState } from 'react';
import { Button, Col, Modal, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import { ImageApi } from '../libs/api/apitypes';
import { yupResolver } from '@hookform/resolvers/yup';

type Props = {
    image: ImageApi;
    show: boolean;
    onSave: (image: ImageApi) => Promise<void>;
    onClose: () => void;
};

const Schema = yup.object().shape({
    // attribution: yup.string().required(),
    // source: yup.string().required(),
});

type FormFields = {
    default: boolean;
    creator: string;
    attribution: string;
    source: string;
    license: string;
};

const ImageEdit = ({ image, show, onSave, onClose }: Props): JSX.Element => {
    const [img, setImg] = useState(image);
    const {
        handleSubmit,
        register,
        formState: { isDirty, dirtyFields },
        reset,
    } = useForm<FormFields>({
        mode: 'onBlur',
        // resolver: yupResolver(Schema),
        defaultValues: {
            ...img,
        },
    });

    const [session] = useSession();
    if (!session) return <></>;

    const onSubmit = async (fields: FormFields) => {
        const newImg: ImageApi = {
            ...img,
            ...fields,
        };
        await onSave(newImg);
        setImg(newImg);
        onHide();
    };

    const onHide = () => {
        reset(img);
        console.log(`isdirty = ${isDirty} / dirtyFields = ${JSON.stringify(dirtyFields)} after reset`);
        onClose();
    };

    return (
        <Modal show={show} onHide={onHide} size="lg">
            <form onSubmit={handleSubmit(onSubmit)}>
                <Modal.Header closeButton>
                    <Modal.Title>Edit Image Details</Modal.Title>
                </Modal.Header>
                <Modal.Body>
                    <Row>
                        <Col xs={3} className="">
                            <img src={image.small} width="150" />
                        </Col>
                        <Col className="form-group">
                            <Row className="form-group">
                                <Col xs={3}>Default?</Col>
                                <Col>
                                    <input type="checkbox" name="default" className="form-control" ref={register} />
                                </Col>
                            </Row>
                            <Row className="form-group">
                                <Col xs={3}>Attribution:</Col>
                                <Col>
                                    <textarea name="attribution" className="form-control" ref={register} />
                                </Col>
                            </Row>
                            <Row className="form-group">
                                <Col xs={3}>Creator:</Col>
                                <Col>
                                    <input type="text" name="creator" className="form-control" ref={register} />
                                </Col>
                            </Row>
                            <Row className="form-group">
                                <Col xs={3}>Source:</Col>
                                <Col>
                                    <textarea name="source" className="form-control" ref={register} />
                                </Col>
                            </Row>
                            <Row className="form-group">
                                <Col xs={3}>License:</Col>
                                <Col>
                                    <textarea name="license" className="form-control" ref={register} />
                                </Col>
                            </Row>
                            <Row className="form-group">
                                <Col xs={3}>Uploader:</Col>
                                <Col>{image.uploader}</Col>
                            </Row>
                        </Col>
                    </Row>
                </Modal.Body>
                <Modal.Footer>
                    <Button variant="secondary" onClick={onHide}>
                        {isDirty ? 'Discard Changes' : 'Close'}
                    </Button>
                    <Button variant="primary" type="submit" disabled={!isDirty}>
                        Save Changes
                    </Button>
                </Modal.Footer>
            </form>
        </Modal>
    );
};

export default ImageEdit;
