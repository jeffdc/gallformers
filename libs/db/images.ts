import { image, Prisma, source, speciessource } from '@prisma/client';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { ImageApi, ImageLicenseValues, ImageLicenseValuesSchema, ImageNoSourceApi } from '../api/apitypes';
import {
    createOtherSizes,
    deleteImagesByPaths,
    getImagePaths,
    LARGE,
    makePath,
    MEDIUM,
    ORIGINAL,
    SMALL,
    XLARGE,
} from '../images/images';
import { ExtractTFromPromise } from '../utils/types';
import { handleError } from '../utils/util';
import db from './db';
import { connectIfNotNull } from './utils';
import { decodeWithDefault } from '../utils/io-ts';

export const addImages = (images: ImageApi[]): TaskEither<Error, ImageApi[]> => {
    // N.B. - the default will also be false for new images, only later can it be changed. So we do not need to worry about
    // the logic of maintaining only a single default here, only on update.
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
                    caption: image.caption,
                    species: { connect: { id: image.speciesid } },
                    source: connectIfNotNull<Prisma.sourceCreateNestedOneWithoutImageInput, number>(
                        'source',
                        O.getOrElseW(constant(undefined))(image.source)?.id,
                    ),
                },
            }),
        );

        return db.$transaction(creates);
    };

    // The create will not return the related images so we need to requery to get them
    const requeryWithSource = (images: image[]) => () =>
        db.image.findMany({
            include: {
                source: {
                    include: {
                        speciessource: {
                            where: { species_id: images[0].species_id },
                        },
                    },
                },
            },
            where: { id: { in: images.map((i) => i.id) } },
        });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(add, handleError),
        TE.map(createOtherSizes),
        TE.chain((images) => TE.tryCatch(requeryWithSource(images), handleError)),
        TE.map(adaptMany),
    );
};

export const updateImage = (theImage: ImageApi): TaskEither<Error, readonly ImageApi[]> => {
    const connectSource = pipe(
        theImage.source,
        O.fold(constant({}), (s) => ({ connect: { id: s.id } })),
    );

    const update = (image: ImageApi) =>
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
                caption: image.caption,
                source: connectSource,
            },
        });

    const setAsNewDefault = (image: ImageApi) => {
        const spId = image.default ? image.speciesid : -999;
        return db.image.updateMany({
            where: {
                AND: [{ species_id: { equals: spId } }, { id: { not: image.id } }],
            },
            data: {
                default: false,
            },
        });
    };

    const doTx = (image: ImageApi) => {
        return db.$transaction([
            update(image),
            setAsNewDefault(image),
            // refetch all of the images since some may have been updated by resetting defaults
            db.image.findMany({
                where: {
                    species_id: { equals: image.speciesid },
                },
                include: {
                    source: {
                        include: {
                            speciessource: true,
                        },
                    },
                },
            }),
        ]);
    };

    type TxRetType = ExtractTFromPromise<ReturnType<typeof doTx>>;

    return pipe(
        TE.tryCatch<Error, TxRetType>(() => doTx(theImage), handleError),
        TE.map<TxRetType, ImageApi[]>(([, , images]) => images.map(adaptImage)),
    );
};

export const adaptImage = <T extends ImageWithSource>(img: T): ImageApi => ({
    ...img,
    speciesid: img.species_id,
    small: makePath(img.path, SMALL),
    medium: makePath(img.path, MEDIUM),
    large: makePath(img.path, LARGE),
    xlarge: makePath(img.path, XLARGE),
    original: makePath(img.path, ORIGINAL),
    source: O.fromNullable(img.source),
    license: decodeWithDefault(ImageLicenseValuesSchema.decode(img.license), ImageLicenseValues.NONE),
});

export const adaptImageNoSource = <T extends image>(img: T): ImageNoSourceApi => ({
    ...img,
    speciesid: img.species_id,
    small: makePath(img.path, SMALL),
    medium: makePath(img.path, MEDIUM),
    large: makePath(img.path, LARGE),
    xlarge: makePath(img.path, XLARGE),
    original: makePath(img.path, ORIGINAL),
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
            include: { source: { include: { speciessource: { where: { species_id: speciesid } } } } },
            where: { species_id: speciesid },
        });

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(get, handleError),
        TE.map(adaptMany),
    );
};

/**
 * Deletes images from the database and from S3.
 * N.B. the function is meant to be curried with the species then applied with the imageids.
 * @param speciesid
 */
export const deleteImages =
    (speciesid: number) =>
    (ids: number[]): TaskEither<Error, number> => {
        const deleteImages = () =>
            db.image.deleteMany({
                where: { id: { in: ids } },
            });

        return pipe(
            TE.tryCatch(() => getImagePaths(speciesid, ids), handleError),
            TE.chain((paths) => TE.tryCatch(() => deleteImagesByPaths(paths), handleError)),
            TE.chain(() => TE.tryCatch(deleteImages, handleError)),
            TE.map((pp) => pp.count),
        );
    };
