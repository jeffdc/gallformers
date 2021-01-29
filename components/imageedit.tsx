import React, { useEffect, useState } from 'react';
import { Button, Col, Modal, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import { ImageApi, SourceApi, SpeciesSourceApi } from '../libs/api/apitypes';
import ControlledTypeahead from './controlledtypeahead';
import InfoTip from './infotip';

type Props = {
    image: ImageApi;
    speciesid: number;
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
    sourcelink: string;
    source: SourceApi;
    license: string;
};

const ImageEdit = ({ image, speciesid, show, onSave, onClose }: Props): JSX.Element => {
    const [img, setImg] = useState(image);
    const [sources, setSources] = useState<SpeciesSourceApi[]>([]);

    const {
        handleSubmit,
        register,
        formState: { isDirty, dirtyFields },
        reset,
        control,
    } = useForm<FormFields>({
        mode: 'onBlur',
        // resolver: yupResolver(Schema),
        defaultValues: {
            ...img,
        },
    });

    useEffect(() => {
        const fetchData = async () => {
            try {
                const res = await fetch(`../api/source?speciesid=${speciesid}`, {
                    method: 'GET',
                });

                if (res.status !== 200) {
                    throw new Error(await res.text());
                }
                setSources((await res.json()) as SpeciesSourceApi[]);
            } catch (e) {
                console.error(e);
            }
        };

        fetchData();
    }, [speciesid]);

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
                                <Col xs={3}>
                                    Default:
                                    <InfoTip
                                        id="default"
                                        text="The default image is always the first one displayed. Only one image can be the default."
                                    />
                                </Col>
                                <Col>
                                    <input type="checkbox" name="default" className="form-control" ref={register} />
                                </Col>
                            </Row>
                            <Row className="form-group">
                                <Col xs={3}>
                                    Source:
                                    <InfoTip id="source" text="The source that the image came from." />
                                </Col>
                                <Col>
                                    <ControlledTypeahead
                                        control={control}
                                        name="source"
                                        options={sources}
                                        labelKey={(s) => s.source.title}
                                        clearButton
                                    />
                                </Col>
                            </Row>
                            <Row>
                                <Col className="">
                                    <hr />
                                    Generally you will only want one or the other of the above Source or the below fields.
                                    <hr />
                                </Col>
                            </Row>
                            <Row className="form-group">
                                <Col xs={3}>
                                    Source Link:
                                    <InfoTip id="link" text="A link (URL) to the original image." />
                                </Col>
                                <Col>
                                    <input type="text" name="sourcelink" className="form-control" ref={register} />
                                </Col>
                            </Row>
                            <Row className="form-group">
                                <Col xs={3}>
                                    Attribution Notes:
                                    <InfoTip id="attrib" text="Any additional attribution information." />
                                </Col>
                                <Col>
                                    <textarea name="attribution" className="form-control" ref={register} />
                                </Col>
                            </Row>
                            <Row className="form-group">
                                <Col xs={3}>
                                    Creator:
                                    <InfoTip
                                        id="creator"
                                        text="Who created the image. Usually a link to the individual. Please no emails!"
                                    />
                                </Col>
                                <Col>
                                    <input type="text" name="creator" className="form-control" ref={register} />
                                </Col>
                            </Row>
                            <Row className="form-group">
                                <Col xs={3}>
                                    License:
                                    <InfoTip id="license" text="The license (if known) for the image." />
                                </Col>
                                <Col>
                                    <textarea name="license" className="form-control" ref={register} />
                                </Col>
                            </Row>
                            <Row className="form-group">
                                <Col xs={3}>
                                    Uploader:
                                    <InfoTip id="uploader" text="The user that uploaded the image. This is not editable." />
                                </Col>
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
