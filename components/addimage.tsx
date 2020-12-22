import { useSession } from 'next-auth/client';
import React, { ChangeEvent, useState } from 'react';
import { Button, Col, ProgressBar, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';

type FormFields = {
    files: string[];
};

const AddImage = (): JSX.Element => {
    const [session] = useSession();
    if (!session) return <></>;

    const { register, handleSubmit } = useForm<FormFields>({
        mode: 'onBlur',
    });

    const [files, setFiles] = useState<string[]>([]);
    const [currentFile, setCurrentFile] = useState('');
    const [progress, setProgress] = useState(0);
    const [msg, setMsg] = useState('');

    const onSubmit = () => {};

    const selectFiles = (e: ChangeEvent<HTMLInputElement>) => setFiles(e.target.files);

    return (
        <>
            <Row>
                <Col className="text-center">
                    <form onSubmit={handleSubmit(onSubmit)} className="">
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
                                onChange={selectFiles}
                                style={{
                                    display: 'none',
                                }}
                            />
                            +
                        </label>
                    </form>
                </Col>
            </Row>
            <Row>
                {currentFile && (
                    <ProgressBar
                        className="progress-bar-info progress-bar-striped"
                        aria-valuenow={progress}
                        aria-valuemin={0}
                        aria-valuemax={100}
                    >
                        {progress}%
                    </ProgressBar>
                )}
            </Row>
        </>
    );
};

export default AddImage;
