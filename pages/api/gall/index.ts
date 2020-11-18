import { NextApiRequest, NextApiResponse } from 'next';
import { GallRes } from '../../../libs/apitypes';
import db from '../../../libs/db/db';

export default async (req: NextApiRequest, res: NextApiResponse): Promise<void> => {
    try {
        if (!req.query.speciesid) {
            res.status(400).end('Failed to provide the species_id as a query param.');
        } else {
            const speciesid = req.query.speciesid as string;

            const gall = await db.gall.findFirst({
                include: {
                    alignment: true,
                    cells: true,
                    color: true,
                    galllocation: { include: { location: true } },
                    galltexture: { include: { texture: true } },
                    shape: true,
                    walls: true,
                    species: { include: { hosts: true } },
                },
                where: { species_id: { equals: parseInt(speciesid) } },
            });

            const retGall: GallRes = {
                id: gall?.id as number,
                species_id: gall?.species_id as number,
                detachable: gall?.detachable as number,
                taxoncode: gall?.taxoncode as string,
                alignment_id: gall?.alignment?.id,
                cells_id: gall?.cells?.id,
                color_id: gall?.color?.id,
                locations: gall?.galllocation.map((l) => l.location_id),
                textures: gall?.galltexture.map((t) => t.texture_id),
                shape_id: gall?.shape?.id,
                walls_id: gall?.walls?.id,
                hosts: gall?.species.hosts.map((h) => h.host_species_id),
            };

            res.status(200).json(retGall);
        }
    } catch (e) {
        res.status(500).json({ error: e.message });
    }
};
