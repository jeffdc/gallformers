import { image } from '@prisma/client';
import { pipe } from 'fp-ts/lib/function';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { ImageApi } from '../api/apitypes';
import { createOtherSizes } from '../images/images';
import { handleError } from '../utils/util';
import db from './db';

export const addImages = (images: ImageApi[]): TaskEither<Error, image[]> => {
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
                    speciesimage: { create: { species: { connect: { id: image.speciesid } } } },
                },
            }),
        );
        return db.$transaction(creates);
    };

    return pipe(TE.tryCatch(add, handleError), TE.map(createOtherSizes));
};
