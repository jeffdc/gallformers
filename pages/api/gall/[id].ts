import { NextApiRequest, NextApiResponse } from 'next';
import { getSession } from 'next-auth/client';
import db from '../../../libs/db/db';
import { DeleteResults } from '../../../libs/apitypes';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    try {
        const session = await getSession({ req });
        if (!session) {
            res.status(401).end();
        }

        if (req.method === 'DELETE') {
            const id = parseInt(
                Array.isArray(req.query.id) && req.query.id.length > 1 ? req.query.id[0] : (req.query.id as string),
            );

            const results = await db.species.delete({
                where: { id: id },
            });

            // const name = (await db.species.findFirst({ where: { id: id } }))?.name;
            // // So... CASCADE DELETE does not work on a mandatory relation like we have with Species-Gall.
            // // Therefore we have to bypass Prisma to deal with this. We could use Prisma but it would involve
            // // multiple queries and deletions which would amount to a bunch of code. :(
            // // See: https://github.com/prisma/prisma/issues/2057
            // const gallid = (
            //     await db.species.findFirst({
            //         include: { gall: { select: { id: true } } },
            //         where: { id: id },
            //     })
            // )?.gall[0].id;
            // // we have to turn foreign_keys OFF in Sqlite for this to work :(
            // db.$transaction([
            //     db.$executeRaw('PRAGMA foreign_keys = OFF'),
            //     db.$executeRaw(`DELETE FROM gall where id = ${gallid}`),
            //     db.$executeRaw(`DELETE FROM species where id = ${id}`),
            //     db.$executeRaw('PRAGMA foreign_keys = ON'),
            // ]);

            const deleteResult = { name: results.name } as DeleteResults;
            res.status(200).json(deleteResult);
        } else {
            res.status(405).end();
        }
    } catch (e) {
        console.error(e);
        res.status(500).json({ error: 'Failed to Delete.' });
    }
};
