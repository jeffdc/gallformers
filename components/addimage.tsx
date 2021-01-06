import { useSession } from 'next-auth/client';
import React, { ChangeEvent, useState } from 'react';
import { Col, ProgressBar, Row } from 'react-bootstrap';
import axios from 'axios';
import { ImageApi, ImagePaths } from '../libs/api/apitypes';

type Props = {
    id: number;
    onChange: (imagePaths: ImagePaths) => void;
};

const AddImage = ({ id, onChange }: Props): JSX.Element => {
    const [uploading, setUploading] = useState(false);
    const [progress, setProgress] = useState(0);

    const [session] = useSession();
    if (!session) return <></>;

    const selectFiles = async (e: ChangeEvent<HTMLInputElement>) => {
        e.preventDefault();

        if (e.target.files == null) return;

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

            console.log(`Pre-signed URL: ${url}`);

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
                    attribution: '',
                    creator: '',
                    license: '',
                    path: path,
                    source: '',
                    uploader: session.user.name,
                    speciesid: id,
                });
            }
        }
        // update the database with the new image(s)
        const dbres = await fetch('../api/images/', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(images),
        });

        const imagePaths: ImagePaths = await dbres.json();

        console.log(JSON.stringify(dbres));

        onChange(imagePaths);

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
                <Col className="text-center">
                    <label
                        className="form-label"
                        style={{
                            border: '1px solid #ccc',
                            display: 'inline-block',
                            padding: '2px 8px',
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
                        +
                    </label>
                </Col>
            </Row>
        </>
    );
};

export default AddImage;
