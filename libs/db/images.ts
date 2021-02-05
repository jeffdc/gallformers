import { image, Prisma, source, speciessource } from '@prisma/client';
import { constant, pipe } from 'fp-ts/lib/function';
import * as A from 'fp-ts/lib/Array';
import * as O from 'fp-ts/lib/Option';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { ImageApi, ImagePaths, LicenseType } from '../api/apitypes';
import {
    createOtherSizes,
    deleteImagesByPaths,
    getImagePaths,
    LARGE,
    makePath,
    MEDIUM,
    ORIGINAL,
    SMALL,
    toImagePaths,
} from '../images/images';
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
                // source: connectSource, // See below for why we can not do this here.
            },
        });

    // more Prisma bugs causing more hacks: https://github.com/prisma/prisma/issues/3069
    // TL;DR - prisma throws if trying to disconnect a record that is not connected even though the outcome
    // is as intended and not really an error at all. This means that we either have to track state around the
    // Source relationship being removed or we have to query before update. To keep it simple we will
    // do the update of all but the relationship with a regular Prisma update, then raw SQL to update the Source.
    // The intent here is that in teh near future Prisma will fix this and we can get rid of the transaction and
    // the executeRaw call. If it were not on the immediate horizon it would be simpler to just have one raw
    // update call.
    const sourceid = pipe(
        image.source,
        O.fold(constant('NULL'), (s) => s.id.toString()),
    );
    const updateSourceRel = () =>
        db.$executeRaw(
            `UPDATE image 
             SET source_id = ${sourceid}
             WHERE image.id = ${image.id}`,
        );

    const doTx = () => db.$transaction([update(), updateSourceRel()]).then((rs) => rs[0]);

    // eslint-disable-next-line prettier/prettier
    return pipe(
        TE.tryCatch(doTx, handleError),
        TE.map((img) => ({
            ...img,
            speciesid: img.species_id,
            small: makePath(img.path, SMALL),
            medium: makePath(img.path, MEDIUM),
            large: makePath(img.path, LARGE),
            original: makePath(img.path, ORIGINAL),
            source: image.source,
            license: img.license as LicenseType,
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
    license: img.license as LicenseType,
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
export const deleteImages = (speciesid: number) => (ids: number[]): TaskEither<Error, number> => {
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
