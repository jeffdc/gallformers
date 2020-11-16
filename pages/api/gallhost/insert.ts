import { NextApiRequest, NextApiResponse } from 'next';
import { HostInsertFields } from '../../../libs/apitypes';
import db from '../../../libs/db/db';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    try {
        const gallhost = req.body as HostInsertFields;

        // ugh this is awful - there is no way to "createMany" and sometimes SQlite will timeout if stuff
        // is inserted too quickly in succession, so...
        const statements = gallhost.galls
            .map((gall) => {
                return gallhost.hosts.map((host) => {
                    try {
                        return db.host.create({
                            data: {
                                gallspecies: { connect: { id: gall } },
                                hostspecies: { connect: { id: host } },
                            },
                        });
                    } catch (e) {
                        throw new AggregateError([e], `Failed to add gall-host mapping for gall(${gall}) and host(${host}).`);
                    }
                });
            })
            .flatMap((x) => x);

        const results = await db.$transaction(statements);

        res.status(200).send(JSON.stringify(results));
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
};
