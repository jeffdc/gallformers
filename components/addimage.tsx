import axios from 'axios';
import { useSession } from 'next-auth/react';
import { ChangeEvent, useState, JSX } from 'react';
import { Alert, Col, ProgressBar, Row } from 'react-bootstrap';
import { toast } from 'react-hot-toast';
import { ImageApi, ImageLicenseValues } from '../libs/api/apitypes';
import { sessionUserOrUnknown } from '../libs/utils/util';

type Props = {
    id: number;
    onChange: (images: ImageApi[]) => void;
};

const AddImage = ({ id, onChange }: Props): JSX.Element => {
    const [uploading, setUploading] = useState(false);
    const [progress, setProgress] = useState(0);
    const [error, setError] = useState<Error | null>(null);

    const { data: session } = useSession();
    if (!session) return <></>;

    async function selectFiles(e: ChangeEvent) {
        try {
            e.preventDefault();

            const target = e.target as HTMLInputElement;
            if (target.files == null) return;

            if (target.files.length > 4) {
                toast.error('You can currently only upload 4 or fewer images at one time.');
                return;
            }

            setProgress(0);
            setUploading(true);

            const files = target.files;
            const images = new Array<ImageApi>();

            let filesRemaining = files.length;
            const uploadMaxPercent = 0.6;

            for (const file of files) {
                // get presigned URL from server so that we can upload without needing secrets
                const d = new Date();
                const t = `${d.getUTCFullYear()}${d.getUTCMonth() + 1}${d.getUTCDate()}${d.getUTCHours()}${d.getUTCMinutes()}${d.getUTCMilliseconds()}`;
                const ext = file.name.split('.').pop();
                const path = `gall/${id}/${id}_${t}_original.${ext}`;
                const res = await fetch(`../api/images/uploadurl?path=${path}&mime=${file.type}`);
                // this is a hack and something changed to put double quotes around the response
                // i have no idea what and I am out of time trying to figure it out :(
                const url = (await res.text()).split('"').join('');

                // upload file
                const resp = await axios
                    .put<Response>(url, file, {
                        headers: {
                            'Content-Type': file.type,
                        },
                        onUploadProgress: (e) =>
                            setProgress(Math.round((100 * e.loaded) / (e.total ?? 4) / filesRemaining) * uploadMaxPercent),
                    })
                    .catch((e) => {
                        if (axios.isAxiosError(e)) {
                            if (e.response) {
                                // The request was made and the server responded with a status code
                                // that falls out of the range of 2xx
                                console.error('Axios request: ', e.request);
                                console.error('Axios status: ', e.response.status);
                                console.error('Axios headers: ', e.response.headers);
                                console.error('Axios response: ', e.response.data);
                            } else if (e.request) {
                                // The request was made but no response was received
                                // `error.request` is an instance of XMLHttpRequest in the browser and an instance of
                                // http.ClientRequest in node.js
                                console.error('Axios request: ', e.request);
                            } else {
                                // Something happened in setting up the request that triggered an Error
                                console.error('Axios Error:', e.message);
                            }
                            console.log('Axios config: ', e.config);
                        } else {
                            console.error(`Image upload failed with non Axios error: ${JSON.stringify(e, null, ' ')}`);
                        }
                        setError(e as Error);
                        return undefined;
                    });

                if (!resp || error) {
                    break;
                }

                filesRemaining -= 1;

                if (resp) {
                    images.push({
                        id: -1,
                        attribution: '',
                        creator: '',
                        license: ImageLicenseValues.NONE,
                        licenselink: '',
                        path: path,
                        sourcelink: '',
                        source: null,
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
                        source_id: null,
                    });
                }
            }

            if (!error) {
                // update the database with the new image(s)
                const dbResponse = await fetch('../api/images/upsert', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                    },
                    body: JSON.stringify(images),
                });

                const newImages = (await dbResponse.json()) as ImageApi[];

                //hack: add a delay here to hopefully give a chance for the image to be picked up by the CDN
                const steps = 100;
                const waitPercent = 100 - uploadMaxPercent * 100;
                for (let i = 1; i <= steps; ++i) {
                    await new Promise((r) => setTimeout(r, 100));
                    setProgress(Math.round(uploadMaxPercent * 100 + (waitPercent / steps) * i));
                }

                onChange(newImages);
            }
        } catch (e) {
            console.error(`Image upload failed with error: ${e as string}`);
        } finally {
            setUploading(false);
        }
    }

    return (
        <>
            {error && (
                <Alert variant="danger" onClose={() => setError(null)} dismissible>
                    <Alert.Heading>Uh-oh</Alert.Heading>
                    <p>{JSON.stringify(error)}</p>
                    <p>
                        If you need to create an issue please do so in{' '}
                        <a href="https://github.com/jeffdc/gallformers/issues/new" target="_blank" rel="noreferrer">
                            Github
                        </a>
                        . Grabbing info from the browser console will help with solving the issue. If you are unsure how to to do
                        that you can find instructions{' '}
                        <a href="https://appuals.com/open-browser-console/" target="_blank" rel="noreferrer">
                            here
                        </a>
                        .
                    </p>
                </Alert>
            )}
            {uploading && <ProgressBar animated striped variant="info" now={progress} min={0} max={100} label={`${progress}%`} />}
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
                            onChange={(e) => {
                                void (async () => await selectFiles(e))();
                            }}
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
