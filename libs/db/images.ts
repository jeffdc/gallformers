import { pipe } from 'fp-ts/lib/function';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { ImageApi, ImagePaths } from '../api/apitypes';
import { createOtherSizes, toImagePaths } from '../images/images';
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
