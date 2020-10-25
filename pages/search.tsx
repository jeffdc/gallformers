import { alignment, cells, color, gall, GallDistinctFieldEnum, location, PrismaClient, shape, species, texture, walls } from '@prisma/client';
import { GetServerSideProps } from 'next';
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

const Search = ({ data, query }: Props): JSX.Element => {
    return (
        <div>
            <CardColumns className='m-2 p-2'>
                {data.map((gall) =>
                    <Card key={gall.id} className="shadow-sm">
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

export const getServerSideProps: GetServerSideProps = async (context: { query: any; }) => {
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
            galllocation: {},
            shape: {},
            species: {
                include: {
                    hosts: true,
                }
            },
            galltexture: {},
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
                dontCare(q.texture) ? {} : { galltexture: { some: { texture: { is: q.texture } } } },
                dontCare(q.location) ? {} : { galllocation: { some: { location: { is: q.location } } } },
                {
                    species: {
                        host_galls: {
                            every: {
                                hostspecies: {
                                    name: { equals: q.host }
                                }
                            }
                        }
                    }                            
                },
            ]
        },
        distinct: [GallDistinctFieldEnum.species_id],
    });

    // due to a limitation in Prisma it is not possible to sort on a related field, so we have to sort now
    data.sort((g1,g2) => {
        if (g1.species.name < g2.species.name) return -1
        if (g1.species.name > g2.species.name) return 1
        return 0
    });

    return {
        props: {
            data: data,
            query: {...context.query},
        }
    }
}

export default Search;