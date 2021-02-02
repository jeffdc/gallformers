import { image, Prisma, source, speciessource } from '@prisma/client';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
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
                    licenselink: image.licenselink,
                    path: image.path,
                    sourcelink: image.sourcelink,
                    uploader: image.uploader,
                    lastchangedby: image.lastchangedby,
                    default: image.default,
                    species: { connect: { id: image.speciesid } },
                    source: connectIfNotNull<Prisma.sourceCreateOneWithoutImageInput, number>(
                        'source',
                        O.getOrElseW(constant(undefined))(image.source)?.id,
                    ),
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
    const connectSource = pipe(
        image.source,
        O.fold(constant({}), (s) => ({ connect: { id: s.id } })),
    );

    const update = () =>
        db.image.update({
            where: { id: image.id },
            data: {
                attribution: image.attribution,
                creator: image.creator,
                default: image.default,
                lastchangedby: image.lastchangedby,
                license: image.license,
                licenselink: image.licenselink,
                sourcelink: image.sourcelink,
                source: connectSource,
            },
        });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(update, handleError),
        TE.map((img) => ({
            ...img,
            speciesid: img.species_id,
            small: makePath(img.path, SMALL),
            medium: makePath(img.path, MEDIUM),
            large: makePath(img.path, LARGE),
            original: makePath(img.path, ORIGINAL),
            source: O.none,
        })),
    );
};

export const adaptImage = <T extends ImageWithSource>(img: T): ImageApi => ({
    ...img,
    speciesid: img.species_id,
    small: makePath(img.path, SMALL),
    medium: makePath(img.path, MEDIUM),
    large: makePath(img.path, LARGE),
    original: makePath(img.path, ORIGINAL),
    source: O.fromNullable(img.source),
});

const adaptMany = <T extends ImageWithSource>(imgs: T[]): ImageApi[] => imgs.map(adaptImage);

type ImageWithSource = image & {
    source:
        | (source & {
              speciessource: speciessource[];
          })
        | null;
};

export const getImages = (speciesid: number): TaskEither<Error, ImageApi[]> => {
    const get = () =>
        db.image.findMany({
            include: { source: { include: { speciessource: true } } },
            where: { species_id: speciesid },
        });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(get, handleError),
        TE.map(adaptMany),
    );
};
