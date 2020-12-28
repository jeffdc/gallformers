import { useSession } from 'next-auth/client';
import React, { ChangeEvent, useState } from 'react';
import { Col, ProgressBar, Row } from 'react-bootstrap';
import axios from 'axios';
import { ImageApi } from '../libs/api/apitypes';

type Props = {
    id: number;
};

const AddImage = ({ id }: Props): JSX.Element => {
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
            const res = await fetch(`../api/images/uploadurl?path=${path}`);
            const url = await res.text();

            console.log(url);

            // upload file
            const resp = await axios.put(url, file, {
                headers: {
                    'Content-Type': file.type,
                    'x-amz-acl': 'public-read',
                },
                onUploadProgress: (e) => setProgress(Math.round((100 * e.loaded) / e.total)),
            });
            console.log('Got response: ' + JSON.stringify(resp));
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
        // update the database with the new image(s)
        const dbres = await fetch('../api/images/', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(images),
        });

        console.log(JSON.stringify(dbres));

        setUploading(false);
    };

    return (
        <>
            {uploading && (
                <ProgressBar
                    className="progress-bar-info progress-bar-striped"
                    aria-valuenow={progress}
                    aria-valuemin={0}
                    aria-valuemax={100}
                    style={{ width: progress + '%' }}
                >
                    {progress}%
                </ProgressBar>
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
                            title="foo"
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
