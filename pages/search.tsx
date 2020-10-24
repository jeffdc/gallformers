import { alignment, cells, color, gall, GallDistinctFieldEnum, location, PrismaClient, shape, species, texture, walls } from '@prisma/client';
import Link from 'next/link';
import { Card, CardColumns } from 'react-bootstrap';
import CardTextCollapse from '../components/cardcollapse';
import { SearchBar, SearchQuery } from '../components/searchbar';

type GallProp = gall & {
    alignment: alignment,
    cells: cells,
    color: color,
    location: location,
    shape: shape,
    species: species,
    texture: texture,
    walls: walls,
};

type Props = {
    data: GallProp[],
    query: SearchQuery
};

const Search = ({ data, query }: Props) => {
    return (
        <div>
            <CardColumns className='m-2 p-2'>
                {data.map((gall) =>
                    <Card key={gall.gall_id} className="shadow-sm">
                        <Card.Img variant="top" width="200px" src="/images/gall.jpg" />
                        <Card.Body>
                            <Card.Title>
                                <Link href={"gall/[id]"} as={`gall/${gall.species_id}`}><a>{gall.species.name}</a></Link>
                            </Card.Title>
                            <CardTextCollapse text={gall.species.description as any} />
                        </Card.Body>
                    </Card>
                )}
            </CardColumns>
            <SearchBar query={ {...query} }></SearchBar>
        </div>
    )
}

export async function getServerSideProps(context: { query: any; }) {
    const newdb = new PrismaClient({log: ['query']});
    const q = context.query;
    function dontCare(field: string) {
        return field === null || field === undefined || field === ''
    }
    // detachable is odd case since it is Int (boolean)
    const detachableWhere =  
        (q.detachable !== '0' && q.detachable !== '1') ?
            {}
        :
            { OR: [ {detachable: { equals: null }}, {detachable: { equals: parseInt(q.detachable) }} ] };
    const data = await newdb.gall.findMany({
        include: {
            alignment: {},
            cells: {},
            color: {},
            location: {},
            shape: {},
            species: {
                include: {
                    hosts: true,
                }
            },
            texture: {},
            walls: {},
        },
        where: {
            AND: [
                detachableWhere,
                dontCare(q.color) ? {} : { color: { color: { equals: q.color } } },
                dontCare(q.alignment) ? {} : { alignment: { alignment: { equals: q.alignemnt } } },
                dontCare(q.shape) ? {} : { shape: { shape: { equals: q.shape } } },
                dontCare(q.cells) ? {} : { cells: { cells: { equals: q.cells } } },
                dontCare(q.walls) ? {} : { walls: { walls: { equals: q.walls } } },
                dontCare(q.texture) ? {} : { texture: { texture: { equals: q.texture } } },
                dontCare(q.location) ? {} : { location: { loc: { equals: q.location } } },
                { 
                    species : {
                        hosts: {
                            every: {
                                hostspecies: {
                                    name : { equals: q.host } 
                                }
                            }
                        }
                    } 
                },
            ]
        },
        distinct: [GallDistinctFieldEnum.species_id]
    });
    console.log(`Data Yo: ${data.length}`);
    return {
        props: {
            data: data,
            query: {...context.query},
        }
    }
}

export default Search;


/*
    `SELECT DISTINCT v_gall.*, hostsp.name as host_name, hostsp.species_id AS host_species_id
    FROM v_gall
    INNER JOIN host ON (v_gall.species_id = host.species_id)
    INNER JOIN species AS hostsp ON (hostsp.species_id = host.host_species_id)
    WHERE (detachable = ? OR detachable is NOT NULL) AND 
        (texture LIKE ? OR texture IS NULL) AND 
        (alignment LIKE ? OR alignment IS NULL) AND 
        (walls LIKE ? OR walls IS NULL) AND 
        hostsp.name LIKE ? AND 
        (loc LIKE ? OR loc IS NULL)
    ORDER BY v_gall.name ASC`;

*/