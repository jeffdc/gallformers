import { image } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { ImageApi, ImagePaths } from '../api/apitypes';
import { createOtherSizes, LARGE, makePath, MEDIUM, ORIGINAL, SMALL, toImagePaths } from '../images/images';
import { handleError } from '../utils/util';
import db from './db';

export const addImages = (images: ImageApi[]): TaskEither<Error, ImagePaths> => {
    const add = () => {
        const creates = images.map((image) =>
            db.image.create({
                data: {
                    attribution: image.attribution,
                    creator: image.creator,
                    license: image.license,
                    path: image.path,
                    source: image.source,
                    uploader: image.uploader,
                    default: image.default,
                    species: { connect: { id: image.speciesid } },
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
    const update = () =>
        db.image.update({
            where: { id: image.id },
            data: {
                attribution: image.attribution,
                creator: image.creator,
                license: image.license,
                source: image.source,
                default: image.default,
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
