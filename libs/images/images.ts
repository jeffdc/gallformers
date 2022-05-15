import {
    DeleteObjectsCommand,
    DeleteObjectsRequest,
    ObjectIdentifier,
    PutObjectCommand,
    S3,
    S3ClientConfig,
} from '@aws-sdk/client-s3';
import { S3RequestPresigner } from '@aws-sdk/s3-request-presigner';
import { createRequest } from '@aws-sdk/util-create-request';
import { formatUrl } from '@aws-sdk/util-format-url';
import { image } from '@prisma/client';
import Jimp from 'jimp';
import { ImagePaths } from '../api/apitypes';
import db from '../db/db';
import { logger } from '../utils/logger';
import { tryBackoff } from '../utils/network';

const checkCred = (cred: string | undefined): string => {
    if (process.env.NODE_ENV === 'production') {
        if (cred == undefined) logger.error('AWS credentials are not configured!');
    }

    return cred == undefined ? '' : cred;
};

const config: S3ClientConfig = {
    // logger: console,
    region: 'us-east-2',
    credentials: {
        accessKeyId: checkCred(process.env.AWS_ACCESS_KEY_ID),
        secretAccessKey: checkCred(process.env.AWS_SECRET_ACCESS_KEY),
    },
};

// const EDGE = 'https://static.gallformers.org';
const EDGE = 'https://dhz6u1p7t6okk.cloudfront.net';
const BUCKET = 'gallformers';
const client = new S3(config);

export const ORIGINAL = 'original';
export const SMALL = 'small';
export const MEDIUM = 'medium';
export const LARGE = 'large';
export const XLARGE = 'xlarge';
export type ImageSize = typeof ORIGINAL | typeof SMALL | typeof MEDIUM | typeof LARGE | typeof XLARGE;

export const getImagePaths = async (speciesId: number, imageids: number[] = []): Promise<ImagePaths> => {
    try {
        const imageidsWhere = imageids.length > 0 ? { id: { in: imageids } } : {};
        const images = await db.image.findMany({
            where: { AND: [{ species_id: { in: speciesId } }, imageidsWhere] },
            orderBy: { id: 'asc' },
        });

        return toImagePaths(images);
    } catch (e) {
        /* eslint-disable @typescript-eslint/no-explicit-any */
        logger.error(e as never);
    }

    return {
        small: [],
        medium: [],
        large: [],
        xlarge: [],
        original: [],
    };
};

export const makePath = (path: string, size: ImageSize): string => `${EDGE}/${path.replace(ORIGINAL, size)}`;

export const toImagePaths = (images: image[]): ImagePaths => {
    return images.reduce(
        (paths, image) => {
            paths.small.push(makePath(image.path, SMALL));
            paths.medium.push(makePath(image.path, MEDIUM));
            paths.large.push(makePath(image.path, LARGE));
            paths.xlarge.push(makePath(image.path, XLARGE));
            paths.original.push(makePath(image.path, ORIGINAL));

            return paths;
        },
        {
            small: new Array<string>(),
            medium: new Array<string>(),
            large: new Array<string>(),
            xlarge: new Array<string>(),
            original: new Array<string>(),
        } as ImagePaths,
    );
};

const EXPIRE_SECONDS = 60 * 5;

export const getPresignedUrl = async (path: string, mime: string): Promise<string> => {
    // we will use different credentials for the S3 upload. these credentials can only upload.
    const signer = new S3RequestPresigner({
        ...client.config,
        credentials: {
            accessKeyId: checkCred(process.env.S3_PUT_AWS_ACCESS_KEY_ID),
            secretAccessKey: checkCred(process.env.S3_PUT_AWS_SECRET_ACCESS_KEY),
        },
    });
    const request = await createRequest(client, new PutObjectCommand({ Key: path, Bucket: BUCKET, ContentType: mime }));

    const url = formatUrl(await signer.presign(request, { expiresIn: EXPIRE_SECONDS }));
    return url;
};

const sizes = new Map([
    [SMALL, 300],
    [MEDIUM, 800],
    [LARGE, 1200],
    [XLARGE, 2000],
]);

export const createOtherSizes = (images: image[]): image[] => {
    try {
        images.map(async (image) => {
            const path = `${EDGE}/${image.path}`;
            const img = await tryBackoff(3, () => Jimp.read(path)).catch((reason: Error) =>
                logger.error(`Failed to load file ${path} with Jimp. Received error: ${reason}.`),
            );
            if (!img) return [];

            const mime = img.getMIME();
            sizes.forEach(async (value, key) => {
                img.resize(value, Jimp.AUTO);
                img.quality(100);
                const newPath = image.path.replace(ORIGINAL, key);
                logger.info(`Will write ${newPath}`);
                const buffer = await img.getBufferAsync(mime);
                await uploadImage(newPath, buffer, mime);
            });
        });

        return images;
    } catch (e) {
        logger.error('Err in createOtherSizes: ' + e);
        return [];
    }
};

const uploadImage = async (key: string, buffer: Buffer, mime: string) => {
    const uploadParams = {
        Bucket: BUCKET,
        Key: key,
        Body: buffer,
        ContentType: mime,
    };

    try {
        logger.info(`Uploading new image ${key}`);
        await tryBackoff(
            3,
            () => client.send(new PutObjectCommand(uploadParams)),
            (t) => t.$metadata.httpStatusCode !== 503,
        );
    } catch (e) {
        logger.error(`Err in uploadImage: ${JSON.stringify(e)}`);
    }
};

/**
 * Deletes all images from S3 that are stored with the key relating to the passed in Species ID.
 * @param id
 */
export const deleteImagesBySpeciesId = async (id: number): Promise<void> => deleteImagesByPaths(await getImagePaths(id));

/**
 * Deletes all images form S3 at the given paths.
 * @param paths
 */
export const deleteImagesByPaths = async (paths: ImagePaths): Promise<void> => {
    const objects = new Array<ObjectIdentifier>();
    const pushObjectIdentifier = (p: string) => objects.push({ Key: p.replace(`${EDGE}/`, '') });
    paths.original.forEach(pushObjectIdentifier);
    paths.small.forEach(pushObjectIdentifier);
    paths.medium.forEach(pushObjectIdentifier);
    paths.large.forEach(pushObjectIdentifier);
    paths.xlarge.forEach(pushObjectIdentifier);

    // nothing to do
    if (objects.length <= 0) return Promise.resolve();

    logger.info(`About to delete images: ${objects.map((o) => o.Key)}`);

    const deleteParams: DeleteObjectsRequest = {
        Bucket: BUCKET,
        Delete: { Objects: objects },
    };

    try {
        await tryBackoff(3, () => client.send(new DeleteObjectsCommand(deleteParams)));
    } catch (e) {
        logger.error(`Err in deleteImagesBySpeciesId: ${JSON.stringify(e)}.`);
    }
};
