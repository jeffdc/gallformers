import * as olddb from '../database';
import { PrismaClient } from '@prisma/client'

const Migrate = ({results}) => {
    return (
        <code><pre>{JSON.stringify(results, null, ' ')}</pre></code>
    )
}

// be forewarned that we can not move helper functions out of this function since next.js calls this from the back-end and
// any helpers that we create outside of this functions scope that depend on the databases will cause compilation issues.
export async function getStaticProps() {
    try {
        const newdb = new PrismaClient();

        function nullpending(x) {
            return x ? x : 'Pending...'
        }
        function check(x, msg) {
            if (!x || Object.keys(x).length === 0) {
                throw new Error(msg);
            }
        }
        async function lookupFamily(id) {
            const old = await olddb.getFamily(id);
            check(old, `Failed to lookup family for = "${id}"!`);
            const newF = await newdb.family.findOne({
                where: {
                    name: old.name,
                }
            });
            check(newF, `Failed to find family with name ${old.name}.`);
            return newF.id
        }

        async function lookupSpecies(id) {
            const old = await olddb.getSpeciesById(id);
            check(old, `Failed to lookup Species for = "${id}"!`);
            const newS = await newdb.species.findOne({
                where: {
                    name: old.name,
                }
            });
            check(newS, `Failed to find species with name ${old.name}.`);
            return newS.id
        }

        async function lookupHosts(id) {
            const old = await olddb.getHostsByGall(id);
            check(old, `Failed to lookup Hosts for = "${id}"!`);
            const newHs = await newdb.species.findMany({
                where: {
                    name: {
                        in: old.map( o => o.name ),
                    },
                }
            });
            check(newHs, `Failed to find species with name ${old.name}.`);
            const hosts = newHs.map( (h) => {
                 return {id: h.id}
            });
            return hosts
        }

        async function migrate(getolddata, newfield, data) {
            const os = await getolddata();
            console.log(`Attempting to process ${os.length} old ${newfield} records...`);
            for (let o of os) {
                const d = await data(o);
                // console.log(`Processing ${JSON.stringify(d, null, '  ')}`);
                try {
                    const t = await newdb[newfield].create(d);
                    check(t, `Failed to create new thang ${d}`);    
                } catch (e) {
                    console.error(
                        `Failed processing record ${JSON.stringify(o, null, '  ')} with input data ${JSON.stringify(d, null, '  ')} error: ${e.message}`);
                }
            }    
            return os.length;
        }
        
        const color = o => { return { data: { color: o.color } } };
        const location = o => { return { data: { loc: o.loc, description: nullpending(o.description) } } };
        const texture = o => { return { data: { texture: o.texture, description: nullpending(o.description) } } };
        const shape = o => { return { data: { shape: o.shape, description: nullpending(o.description) } } };
        const alignment = o => { return { data: { alignment: o.alignment, description: nullpending(o.description) } } };
        const walls = o => { return { data: { walls: o.walls, description: nullpending(o.description) } } };
        const cells = o => { return { data: { cells: o.cells, description: nullpending(o.description) } } };
        const family = o => { return { data: { name: o.name, description: o.description } } };
        const species = async o => { 
            const id = await lookupFamily(o.family_id);
            // console.log(`Trying to process Species ${JSON.stringify(o, null, '  ')}. Looked up familyid ${id}`);
            return { 
                data: { 
                    name: o.name,
                    synonyms: o.synonyms,
                    commonnames: o.commonnames,
                    genus: o.genus,
                    description: nullpending(o.description),
                    family: {
                        connect: { id: id },
                    },
                    sources: { connect: [] },
                }
            }
        };
        const gall = async o => {
            const speciesId = await lookupSpecies(o.species_id);
            const hosts = await lookupHosts(o.species_id);
            const hostsConverted = hosts.map( h => ( {
                where: {
                    id: speciesId,
                },
                create: {
                    species: {id: speciesId },
                }
            }));
            return {
                data: {
                    species: {
                        connect: { id: speciesId }
                    },
                    hosts: {
                        connectOrCreate: hostsConverted,
                    },
                    detachable: o.detachable === 'yes' ? 1 : 0,
                    locations: { connect: [] },
                    textures: { connect: [] },
                }
            }
        };

        return { props: {
            results: {
                // colorCount: await migrate(olddb.getColors, 'color', color),
                // locationCount: await migrate(olddb.getLocations, 'location', location),
                // textureCount: await migrate(olddb.getTextures, 'texture', texture),
                // shapeCount: await migrate(olddb.getShapes, 'shape', shape),
                // alignmentCount: await migrate(olddb.getAlignments, 'alignment', alignment),
                // wallsCount: await migrate(olddb.getWalls, 'walls', walls),
                // cellsCount: await migrate(olddb.getCells, 'cells', cells),
                // familyCount: await migrate(olddb.getFamilies, 'family', family),
                // speciesCount: await migrate(olddb.getSpecies, 'species', species),
                gallCount: await migrate(olddb.getGalls, 'gall', gall),
            },
        }}
    } catch (e) {
        console.error(e.message);

        return { props: {
            results: `WE FAILED! ${e.message}`
        }}
    }
}

export default Migrate;

/*
{
  "data": {
    "species": {
      "connect": {
        "id": 15
      }
    },
    "hosts": {
      "connect": []
    },
    "detachable": null,
    "locations": {
      "connect": [
        {
          "id": 1
        },
        {
          "id": 2
        },
        {
          "id": 3
        },
        {
          "id": 4
        },
        {
          "id": 5
        }
      ]
    },
    "textures": {
      "connect": [
        {
          "id": 1
        },
        {
          "id": 2
        },
        {
          "id": 3
        }
      ]
    }
  },
  "select": {
    "id": true,
    "speciesId": true,
    "species": true,
    "hosts": true,
    "detachable": true,
    "locations": true,
    "textures": true,
    "shape": true,
    "colorId": true,
    "color": true,
    "wallsId": true,
    "walls": true,
    "cellsId": true,
    "cells": true,
    "alignmentId": true,
    "alignment": true,
    "shapeId": true
  }
}*/