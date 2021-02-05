import { yupResolver } from '@hookform/resolvers/yup';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import React, { useEffect, useState } from 'react';
import { Button, Col, Modal, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import { ALLRIGHTS, CC0, CCBY, ImageApi, LicenseType, SourceWithSpeciesSourceApi } from '../libs/api/apitypes';
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
    source: yup.array(),
    sourcelink: yup.string().url().required('You must provide a link to the source.'),
    license: yup.string().required('You must select one a license.'),
    creator: yup.string().required('You must provide a reference to the creator.'),
    licenselink: yup
        .string()
        .url()
        .when('license', {
            is: (l) => l === CCBY,
            then: yup.string().url().required('The CC-BY license requires that you provide a link to the license.'),
        }),
    attribution: yup.string().when('license', {
        is: (l) => l === ALLRIGHTS,
        then: yup
            .string()
            .required('You must document proof that we are allowed to use the image when using an All Rights Reserved license.'),
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

const sourceFromOption = (so: O.Option<SourceWithSpeciesSourceApi>): SourceWithSpeciesSourceApi[] =>
    pipe(
        so,
        O.fold(constant(new Array<SourceWithSpeciesSourceApi>()), (s) => [s]),
    );

const formFromImage = (img: ImageApi): FormFields => ({
    ...img,
    license: img.license as LicenseType,
    source: sourceFromOption(img.source),
});

const ImageEdit = ({ image, speciesid, show, onSave, onClose }: Props): JSX.Element => {
    const [sources, setSources] = useState(new Array<SourceWithSpeciesSourceApi>());

    const {
        handleSubmit,
        register,
        formState: { isDirty, dirtyFields },
        errors,
        control,
        getValues,
        setValue,
    } = useForm<FormFields>({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
        defaultValues: formFromImage(image),
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
            } catch (e) {
                console.error(e);
            }
        };

        fetchData();
    }, [speciesid]);

    // I am not clear if this is the React way to deal with this or not.
    useEffect(() => {
        setValue('default', image.default);
        setValue('creator', image.creator);
        setValue('attribution', image.attribution);
        setValue('sourcelink', image.sourcelink);
        setValue('license', image.license as LicenseType);
        setValue('licenselink', image.licenselink);
        setValue('source', sourceFromOption(image.source));
    }, [image, setValue]);

    const onSubmit = async (fields: FormFields) => {
        console.log(`IMAGE: ${JSON.stringify(image, null, '  ')}`);
        console.log(`FIELDS: ${JSON.stringify(fields, null, '  ')}`);
        const newImg: ImageApi = {
            ...image,
            ...fields,
            source: O.fromNullable(fields.source[0]),
        };
        await onSave(newImg);
        onHide();
    };

    const onHide = () => {
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
                                    <input
                                        type="checkbox"
                                        key={image.id}
                                        name="default"
                                        className="form-control"
                                        ref={register}
                                    />
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
                                    {errors.sourcelink && <span className="text-danger">{errors.sourcelink.message}</span>}
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
                                    {errors.license && <span className="text-danger">{errors.license.message}</span>}
                                </Col>
                            </Row>
                            <Row className="form-group">
                                <Col xs={3}>
                                    License Link:
                                    <InfoTip id="licenselink" text="The link to the license. Mandatory if CC-BY is chosen." />
                                </Col>
                                <Col>
                                    <input type="text" name="licenselink" className="form-control" ref={register} />
                                    {errors.licenselink && <span className="text-danger">{errors.licenselink.message}</span>}
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
                                    {errors.creator && <span className="text-danger">{errors.creator.message}</span>}
                                </Col>
                            </Row>
                            <Row className="form-group">
                                <Col xs={3}>
                                    Attribution Notes:
                                    <InfoTip id="attrib" text="Any additional attribution information." />
                                </Col>
                                <Col>
                                    <textarea name="attribution" className="form-control" ref={register} />
                                    {errors.attribution && <span className="text-danger">{errors.attribution.message}</span>}
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
