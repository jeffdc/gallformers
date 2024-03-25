import * as O from 'fp-ts/lib/Option';
import { useEffect, useState } from 'react';
import { Button, Col, Modal, Row } from 'react-bootstrap';
import { Controller, useForm } from 'react-hook-form';

import { Typeahead } from 'react-bootstrap-typeahead';
import { asImageLicense, ImageApi, ImageLicenseValues, SourceWithSpeciesSourceApi } from '../libs/api/apitypes';
import InfoTip from './infotip';

type Props = {
    image: ImageApi;
    show: boolean;
    onSave: (image: ImageApi) => Promise<void>;
    onClose: () => void;
};

type FormFields = ImageApi;

const formFromImage = (img: ImageApi): FormFields => ({
    ...img,
});

const ImageEdit = ({ image, show, onSave, onClose }: Props): JSX.Element => {
    const [sources, setSources] = useState(new Array<SourceWithSpeciesSourceApi>());
    const [selected, setSelected] = useState(image);

    const {
        handleSubmit,
        register,
        setValue,
        formState: { isDirty, errors },
        control,
    } = useForm<FormFields>({
        mode: 'onBlur',
        defaultValues: formFromImage(image),
    });

    useEffect(() => {
        const fetchData = async () => {
            try {
                const res = await fetch(`../api/source?speciesid=${selected.speciesid}`, {
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
        setValue('default', selected.default);
        setValue('creator', selected.creator);
        setValue('attribution', selected.attribution);
        setValue('sourcelink', selected.sourcelink);
        setValue('license', selected.license);
        setValue('licenselink', selected.licenselink);
        setValue('source', selected.source);
        setValue('caption', selected.caption);
    }, [selected, setValue]);

    useEffect(() => {
        setSelected(image);
    }, [image]);

    const onSubmit = async (fields: FormFields) => {
        const newImg: ImageApi = {
            ...image,
            ...fields,
            source: fields.source,
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
                    <Row className="">
                        <Col xs={4} className="">
                            <img src={selected.small} width="200px" />
                        </Col>
                        <Col xs={7} className="my-1">
                            <Row>
                                <Col>
                                    Default:
                                    <InfoTip
                                        id="default"
                                        text="The default image is always the first one displayed. Only one image can be the default. If you set this one to be the default, any previous default will be overridden once you save your changes."
                                    />
                                </Col>
                                <Col>
                                    <input {...register('default')} type="checkbox" key={selected.id} className="form-checkbox" />
                                </Col>
                            </Row>
                            <hr />
                            <Row className="my-1">
                                <Col>If the image is from a publication start with this field:</Col>
                            </Row>
                            <Row className="my-1">
                                <Col xs={3}>
                                    Source:
                                    <InfoTip
                                        id="source"
                                        text="The source that the image came from. This list will only show Sources that have already been mapped to the species."
                                    />
                                </Col>
                                <Col>
                                    <Controller
                                        name="source"
                                        control={control}
                                        render={() => (
                                            <Typeahead
                                                id="source"
                                                options={sources}
                                                labelKey={(s) => (s as SourceWithSpeciesSourceApi).title}
                                                clearButton
                                                selected={selected.source ? [selected.source] : []}
                                                onChange={(o) => {
                                                    const s = o[0] as SourceWithSpeciesSourceApi;
                                                    setSelected({
                                                        ...selected,
                                                        source: s,
                                                        license: s ? asImageLicense(s.license) : '',
                                                        // license: s.license,
                                                        licenselink: s ? s.licenselink : '',
                                                        creator: s ? s.author : '',
                                                    });
                                                }}
                                            />
                                        )}
                                    />
                                </Col>
                            </Row>
                            <Row className="my-1">
                                <Col>
                                    <hr />
                                    {O.some(selected.source)
                                        ? ''
                                        : `If the image is from an observation on a site like iNat/Bugguide/etc. then start here:`}
                                </Col>
                            </Row>
                            <Row className="my-1">
                                <Col xs={3}>
                                    {O.some(selected.source)
                                        ? `Direct Link to Image in Publication or Website:`
                                        : 'Observation Link:'}
                                    <InfoTip id="link" text="A URL that points to the image in the original publication." />
                                </Col>
                                <Col>
                                    <input {...register('sourcelink')} type="text" className="form-control" />
                                    {errors.sourcelink && <span className="text-danger">{errors.sourcelink.message}</span>}
                                </Col>
                            </Row>
                            <Row className="my-1">
                                <Col>
                                    <hr />
                                    These fields should be filled out regardless of the source type. If you select a Source the
                                    License info from the Source will pre-populate if it exists.
                                </Col>
                            </Row>
                            <Row className="my-1">
                                <Col xs={3}>
                                    License:
                                    <InfoTip
                                        id="license"
                                        text="The license for the image. Currently we can only accept images with one of the 3 licenses that are listed as options. You must verify that this license is in place."
                                    />
                                </Col>
                                <Col>
                                    <select {...register('license')} className="form-control">
                                        <option>{ImageLicenseValues.PUBLIC_DOMAIN}</option>
                                        <option>{ImageLicenseValues.CC_BY}</option>
                                        <option>{ImageLicenseValues.ALL_RIGHTS}</option>
                                    </select>
                                    {errors.license && <span className="text-danger">{errors.license.message}</span>}
                                </Col>
                            </Row>
                            <Row className="my-1">
                                <Col xs={3}>
                                    License Link:
                                    <InfoTip id="licenselink" text="The link to the license. Mandatory if CC-BY is chosen." />
                                </Col>
                                <Col>
                                    <input {...register('licenselink')} type="text" className="form-control" />
                                    {errors.licenselink && <span className="text-danger">{errors.licenselink.message}</span>}
                                </Col>
                            </Row>

                            <Row className="my-1">
                                <Col xs={3}>
                                    Creator:
                                    <InfoTip
                                        id="creator"
                                        text="Who created the image. Usually a link to the individual or their name. Please no emails!"
                                    />
                                </Col>
                                <Col>
                                    <input {...register('creator')} type="text" className="form-control" />
                                    {errors.creator && <span className="text-danger">{errors.creator.message}</span>}
                                </Col>
                            </Row>
                            <Row className="my-1">
                                <Col xs={3}>
                                    Attribution Notes:
                                    <InfoTip id="attrib" text="Any additional attribution information." />
                                </Col>
                                <Col>
                                    <textarea {...register('attribution')} className="form-control" />
                                    {errors.attribution && <span className="text-danger">{errors.attribution.message}</span>}
                                </Col>
                            </Row>
                            <Row className="my-1">
                                <Col xs={3}>
                                    Caption:
                                    <InfoTip id="caption" text="An optional caption to be displayed with the image." />
                                </Col>
                                <Col>
                                    <textarea {...register('caption')} className="form-control" />
                                </Col>
                            </Row>
                            <Row className="my-1">
                                <Col>Uploader: {selected.uploader}</Col>
                                <Col>Last Changed: {selected.lastchangedby}</Col>
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
