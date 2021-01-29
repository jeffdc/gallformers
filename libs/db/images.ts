import { image, Prisma } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { ImageApi, ImagePaths } from '../api/apitypes';
import { createOtherSizes, LARGE, makePath, MEDIUM, ORIGINAL, SMALL, toImagePaths } from '../images/images';
import { handleError } from '../utils/util';
import db from './db';
import { connectIfNotNull } from './utils';

export const addImages = (images: ImageApi[]): TaskEither<Error, ImagePaths> => {
    const add = () => {
        const creates = images.map((image) =>
            db.image.create({
                data: {
                    attribution: image.attribution,
                    creator: image.creator,
                    license: image.license,
                    path: image.path,
                    sourcelink: image.sourcelink,
                    uploader: image.uploader,
                    default: image.default,
                    species: { connect: { id: image.speciesid } },
                    source: connectIfNotNull<Prisma.sourceCreateOneWithoutImageInput, number>('source', image.sourceid),
                },
            }),
        );
        return db.$transaction(creates);
    };

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(add, handleError), 
        TE.map(createOtherSizes),
        TE.map(toImagePaths));
};

export const updateImage = (image: ImageApi): TaskEither<Error, ImageApi> => {
    console.log(`Updating image: ${JSON.stringify(image, null, ' ')}`);
    const update = () =>
        db.image.update({
            where: { id: image.id },
            data: {
                attribution: image.attribution,
                creator: image.creator,
                license: image.license,
                sourcelink: image.sourcelink,
                default: image.default,
                source: connectIfNotNull<Prisma.sourceCreateOneWithoutImageInput, number>('source', image.sourceid),
            },
        });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(update, handleError),
        TE.map(adapt),
    );
};

const adapt = (img: image): ImageApi => ({
    ...img,
    speciesid: img.species_id,
    small: makePath(img.path, SMALL),
    medium: makePath(img.path, MEDIUM),
    large: makePath(img.path, LARGE),
    original: makePath(img.path, ORIGINAL),
    sourceid: img.source_id ? img.source_id : undefined,
});

const adaptMany = (imgs: image[]): ImageApi[] => imgs.map(adapt);

export const getImages = (speciesid: number): TaskEither<Error, ImageApi[]> => {
    const get = () => db.image.findMany({ where: { species_id: speciesid } });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(get, handleError),
        TE.map(adaptMany),
    );
};
