import { ListObjectsCommand, S3Client, S3ClientConfig } from '@aws-sdk/client-s3';

const config: S3ClientConfig = {
    region: 'nyc3',
    endpoint: 'https://nyc3.digitaloceanspaces.com',
};

const host = 'https://static.gallformers.org/';

const client = new S3Client(config);

export type ImagePaths = {
    small: string[];
    medium: string[];
    large: string[];
    original: string[];
    all: string[];
};

export const getImagePaths = async (speciesId: number, size = 'small'): Promise<ImagePaths> => {
    try {
        const files = await client.send(
            new ListObjectsCommand({ Bucket: 'gallformers', Prefix: `gall/${speciesId}/${speciesId}` }),
        );
        const ps = files.Contents
            ? files.Contents.sort((a, b) => {
                  if (a.LastModified == undefined) return 1;
                  if (b.LastModified == undefined) return -1;
                  return b.LastModified.getTime() - a.LastModified.getTime();
              }).map((f) => `${host}${f.Key}`)
            : [];

        const paths: ImagePaths = {
            all: ps,
            small: ps.filter((p) => p.includes('small')),
            medium: ps.filter((p) => p.includes('medium')),
            large: ps.filter((p) => p.includes('large')),
            original: ps.filter((p) => p.includes('original')),
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
        all: [],
    };
};

export const addImage = (speciesId: number, size = 'small') => {};
