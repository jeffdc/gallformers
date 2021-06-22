import { useSession } from 'next-auth/client';
import React, { ChangeEvent, useState } from 'react';
import { Col, ProgressBar, Row } from 'react-bootstrap';
import axios from 'axios';
import { ImageApi } from '../libs/api/apitypes';
import * as O from 'fp-ts/lib/Option';
import { sessionUserOrUnknown } from '../libs/utils/util';
import toast from 'react-hot-toast';

type Props = {
    id: number;
    onChange: (images: ImageApi[]) => void;
};

const AddImage = ({ id, onChange }: Props): JSX.Element => {
    const [uploading, setUploading] = useState(false);
    const [progress, setProgress] = useState(0);

    const [session] = useSession();
    if (!session) return <></>;

    const selectFiles = async (e: ChangeEvent<HTMLInputElement>) => {
        e.preventDefault();

        if (e.target.files == null) return;

        if (e.target.files.length > 4) {
            toast.error('You can currently only upload 4 or fewer images at one time.');
            return;
        }

        setProgress(0);
        setUploading(true);

        const files = e.target.files;
        const images = new Array<ImageApi>();

        for (const file of files) {
            // get presigned URL from server so that we can upload without needing secrets
            const d = new Date();
            const t = `${d.getUTCFullYear()}${
                d.getUTCMonth() + 1
            }${d.getUTCDate()}${d.getUTCHours()}${d.getUTCMinutes()}${d.getUTCMilliseconds()}`;
            const ext = file.name.split('.').pop();
            const path = `gall/${id}/${id}_${t}_original.${ext}`;
            const res = await fetch(`../api/images/uploadurl?path=${path}&mime=${file.type}`);
            const url = await res.text();

            // upload file
            const resp = await axios
                .put<Response>(url, file, {
                    headers: {
                        'Content-Type': file.type,
                    },
                    onUploadProgress: (e) => setProgress(Math.round((100 * e.loaded) / e.total)),
                })
                .catch((e) => console.error(`Image upload failed with error: ${JSON.stringify(e, null, ' ')}`));

            if (resp) {
                images.push({
                    id: -1,
                    attribution: '',
                    creator: '',
                    license: '',
                    licenselink: '',
                    path: path,
                    sourcelink: '',
                    source: O.none,
                    uploader: sessionUserOrUnknown(session?.user?.name),
                    lastchangedby: sessionUserOrUnknown(session?.user?.name),
                    speciesid: id,
                    default: false,
                    caption: '',
                    small: '',
                    medium: '',
                    large: '',
                    xlarge: '',
                    original: '',
                });
            }
        }
        // update the database with the new image(s)
        const dbres = await fetch('../api/images/upsert', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(images),
        });

        const newImages: ImageApi[] = await dbres.json();
        onChange(newImages);

        setUploading(false);
    };

    return (
        <>
            {/* eslint-disable-next-line prettier/prettier */}
            {uploading && (
                <ProgressBar
                    animated
                    striped
                    variant="info"
                    now={progress}
                    min={0}
                    max={100}
                    label={`${progress}%`}
                />
            )}
            <Row>
                <Col className="">
                    <label
                        className="form-label bg-light"
                        style={{
                            border: '1px solid #ccc',
                            borderRadius: '2px',
                            display: 'inline-block',
                            padding: '4px 8px',
                            cursor: 'pointer',
                        }}
                    >
                        <input
                            type="file"
                            name="file"
                            className="form-control"
                            multiple
                            accept={'image/jpg, image/jpeg, image/png'}
                            onChange={selectFiles}
                            style={{
                                display: 'none',
                            }}
                        />
                        Upload New Image(s)
                    </label>
                </Col>
            </Row>
        </>
    );
};

export default AddImage;
