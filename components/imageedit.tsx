import React, { useEffect, useState } from 'react';
import { Button, Col, Modal, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { ImageApi, SourceWithSpeciesSourceApi } from '../libs/api/apitypes';
import ControlledTypeahead from './controlledtypeahead';
import InfoTip from './infotip';
import { yupResolver } from '@hookform/resolvers/yup';

type Props = {
    image: ImageApi;
    speciesid: number;
    show: boolean;
    onSave: (image: ImageApi) => Promise<void>;
    onClose: () => void;
};

const NONE = '';
const CC0 = 'Public Domain / CC0';
const CCBY = 'CC-BY';
const ALLRIGHTS = 'All Rights Reserved';

type LicenseType = typeof NONE | typeof CC0 | typeof CCBY | typeof ALLRIGHTS;

const Schema = yup.object().shape({
    source: yup.array(),
    sourcelink: yup.string().required(),
    license: yup.string().required(),
    creator: yup.string().required(),
    licenselink: yup.string().when('license', {
        is: (l) => l === CCBY,
        then: yup.string().required(),
    }),
});

type FormFields = {
    default: boolean;
    creator: string;
    attribution: string;
    sourcelink: string;
    source: SourceWithSpeciesSourceApi[];
    license: LicenseType;
    licenselink: string;
};

const ImageEdit = ({ image, speciesid, show, onSave, onClose }: Props): JSX.Element => {
    const [img, setImg] = useState(image);
    const [sources, setSources] = useState<SourceWithSpeciesSourceApi[]>([]);

    const {
        handleSubmit,
        register,
        formState: { isDirty, dirtyFields },
        reset,
        errors,
        control,
        getValues,
    } = useForm<FormFields>({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
        defaultValues: {
            ...img,
            license: img.license as LicenseType,
            source: pipe(
                img.source,
                O.fold(constant(new Array<SourceWithSpeciesSourceApi>()), (s) => [s]),
            ),
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
                setSources((await res.json()) as SourceWithSpeciesSourceApi[]);
                console.log(`The sources:\n${JSON.stringify(sources, null, '  ')}`);
            } catch (e) {
                console.error(e);
            }
        };

        fetchData();
    }, [speciesid, sources]);

    const onSubmit = async (fields: FormFields) => {
        const newImg: ImageApi = {
            ...img,
            ...fields,
            source: O.fromNullable(fields.source[0]),
        };
        await onSave(newImg);
        setImg(newImg);
        onHide();
    };

    const onHide = () => {
        // reset(img);
        console.log(`isdirty = ${isDirty} / dirtyFields = ${JSON.stringify(dirtyFields)} after reset`);
        onClose();
    };

    return (
        <Modal show={show} onHide={onHide} size="lg">
            {`Errors: ${JSON.stringify(errors)}`}

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
                                <Col>Uploader:</Col>
                                <Col>{image.uploader}</Col>
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
                            <Row>
                                <Col xs={3}>Last Changed:</Col>
                                <Col>{image.lastchangedby}</Col>
                            </Row>
                            <hr />
                            <Row className="form-group">
                                <Col>If the image is from a publication start with this field:</Col>
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
                                        labelKey={(s: SourceWithSpeciesSourceApi) => s.title}
                                        clearButton
                                    />
                                </Col>
                            </Row>
                            <Row className="form-group">
                                <Col>
                                    <hr />
                                    {getValues(['source']).source?.length > 0
                                        ? ''
                                        : `If the image is from an observation on a site like iNat/Bugguide/etc. then start here:`}
                                </Col>
                            </Row>
                            <Row className="form-group">
                                <Col xs={3}>
                                    {getValues(['source']).source?.length > 0
                                        ? `Direct Link to Image in Publication:`
                                        : 'Observation Link:'}
                                    <InfoTip id="link" text="A URL that points to the image in the original publication." />
                                </Col>
                                <Col>
                                    <input type="text" name="sourcelink" className="form-control" ref={register} />
                                </Col>
                            </Row>
                            <Row className="form-group">
                                <Col>
                                    <hr />
                                    These fields should be filled out for both cases of source.
                                </Col>
                            </Row>
                            <Row className="form-group">
                                <Col xs={3}>
                                    License:
                                    <InfoTip
                                        id="license"
                                        text="The license for the image. Currently we can only accept images with one of the 2 licenses that are listed as options. You must verify that this license is in place."
                                    />
                                </Col>
                                <Col>
                                    <select name="license" className="form-control" ref={register}>
                                        <option>{CC0}</option>
                                        <option>{CCBY}</option>
                                        <option>{ALLRIGHTS}</option>
                                    </select>
                                    {errors.license && <span className="text-danger">You must select a license.</span>}
                                </Col>
                            </Row>
                            <Row className="form-group">
                                <Col xs={3}>
                                    License Link:
                                    <InfoTip id="licenselink" text="The link to the license. Mandatory if CC-BY is chosen." />
                                </Col>
                                <Col>
                                    <input type="text" name="licenselink" className="form-control" ref={register} />
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
                                    {errors.creator && <span className="text-danger">You must provide a creator.</span>}
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
