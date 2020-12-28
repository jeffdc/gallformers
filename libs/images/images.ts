import { PutObjectCommand, S3Client, S3ClientConfig } from '@aws-sdk/client-s3';
import { S3RequestPresigner } from '@aws-sdk/s3-request-presigner';
import { createRequest } from '@aws-sdk/util-create-request';
import { formatUrl } from '@aws-sdk/util-format-url';
import { image } from '@prisma/client';
import Jimp from 'jimp';
import db from '../db/db';
import { tryBackoff } from '../utils/network';

const ENDPOINT = 'https://nyc3.digitaloceanspaces.com';
const config: S3ClientConfig = {
    // logger: console,
    region: 'nyc3',
    endpoint: ENDPOINT,
    credentials: {
        accessKeyId: process.env.AWS_ACCESS_KEY_ID == undefined ? '' : process.env.AWS_ACCESS_KEY_ID,
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY == undefined ? '' : process.env.AWS_SECRET_ACCESS_KEY,
    },
};

const EDGE = 'https://static.gallformers.org/';
const BUCKET = 'gallformers';
const client = new S3Client(config);

// add a middleware to work around bug. See: https://github.com/aws/aws-sdk-js-v3/issues/1800
client.middlewareStack.add(
    (next) => async (args) => {
        // eslint-disable-next-line @typescript-eslint/ban-ts-comment
        // @ts-ignore
        delete args.request.headers['content-type'];
        return next(args);
    },
    { step: 'build' },
);

export type ImagePaths = {
    small: string[];
    medium: string[];
    large: string[];
    original: string[];
};

export const getImagePaths = async (speciesId: number): Promise<ImagePaths> => {
    try {
        const images = await db.image.findMany({
            where: { speciesimage: { every: { species_id: speciesId } } },
            orderBy: { id: 'asc' },
        });
        const ps = images.map((i) => `${EDGE}/${i.path}`);

        const paths: ImagePaths = {
            small: ps.map((p) => p.replace('original', 'small')),
            medium: ps.map((p) => p.replace('original', 'medium')),
            large: ps.map((p) => p.replace('original', 'large')),
            original: ps,
        };

        return paths;
    } catch (e) {
        console.error(e);
    }

    return {
        small: [],
        medium: [],
        large: [],
        original: [],
    };
};

const EXPIRE_SECONDS = 60 * 5;

export const getPresignedUrl = async (path: string): Promise<string> => {
    console.log(`${new Date().toString()}: Spaces API Call PRESIGNED URL GET for ${path}.`);

    const signer = new S3RequestPresigner({ ...client.config });
    const request = await createRequest(client, new PutObjectCommand({ Key: path, Bucket: BUCKET }));

    return formatUrl(await signer.presign(request, { expiresIn: EXPIRE_SECONDS }));
};

const sizes = new Map([
    ['small', 300],
    ['medium', 800],
    ['large', 1200],
]);

export const createOtherSizes = (images: image[]): image[] => {
    try {
        images.map(async (image) => {
            const path = `${ENDPOINT}/${BUCKET}/${image.path}`;
            const img = await Jimp.read(path);
            const mime = img.getMIME();
            sizes.forEach(async (value, key) => {
                img.resize(value, Jimp.AUTO);
                img.quality(90);
                const newPath = image.path.replace('original', key);
                const buffer = await img.getBufferAsync(mime);
                await uploadImage(newPath, buffer, mime);
            });
        });

        return images;
    } catch (e) {
        console.error('Err in createOtherSizes: ' + e);
        return [];
    }
};

const uploadImage = async (key: string, buffer: Buffer, mime: string) => {
    const uploadParams = {
        Bucket: BUCKET,
        Key: key,
        Body: buffer,
        ContentType: mime,
        ACL: 'public-read',
    };

    try {
        await tryBackoff(
            3,
            () => client.send(new PutObjectCommand(uploadParams)),
            (t) => t.$metadata.httpStatusCode !== 503,
        );
    } catch (e) {
        console.log('Err in uploadImage: ' + JSON.stringify(e));
    }
};
