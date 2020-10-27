import { alignment, cells, color, gall, GallDistinctFieldEnum, gallWhereInput, location, PrismaClient, shape, species, texture, walls } from '@prisma/client';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import { ParsedUrlQuery } from 'querystring';
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
                            <CardTextCollapse text={gall.species.description === null ? '' : gall.species.description} />
                        </Card.Body>
                    </Card>
                )}
            </CardColumns>
            <SearchBar query={ {...query} }></SearchBar>
        </div>
    )
}

export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery; }) => {
    if (context === undefined || context.query === undefined) {
        throw new Error('Must pass a valid query object to Search!')
    }

    // Useful for logging SQL that is genereated for debugging the search
    // const newdb = new PrismaClient({log: ['query']}); 
    const newdb = new PrismaClient();

    // the locations and textures come in as encoded JSON arrays so we need to parse them
    context.query.locations = JSON.parse(context.query.locations === undefined ? '' : context.query.locations.toString());
    context.query.textures = JSON.parse(context.query.textures === undefined ? '' : context.query.textures.toString());

    // If we do this cast, then we get type checking thoughtout. Already found 2 bugs becuase of this!
    const q = context.query as SearchQuery;

    // helper to create Where clauses
    function whereDontCare(field: string | string[] | undefined, o: gallWhereInput) {
        if (field === null || field === undefined || field === '' || (Array.isArray(field) && field.length === 0)) {
            return {}
        } else {
            return o
        }
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
            galllocation: {
                include: { location: {} }
            },
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
                whereDontCare(q.color, { color: { color: { equals: q.color } } }),
                whereDontCare(q.alignment, { alignment: { alignment: { equals: q.alignment } } }),
                whereDontCare(q.shape, { shape: { shape: { equals: q.shape } } }),
                whereDontCare(q.cells, { cells: { cells: { equals: q.cells } } }),
                whereDontCare(q.walls, { walls: { walls: { equals: q.walls } } }),
                whereDontCare(q.textures, { galltexture: { some: { texture: { texture: { in: q.textures } } } } }),
                whereDontCare(q.locations, { galllocation: { some: { location: { location: { in: q.locations } } } } }),
                {
                    species: {
                        hosts: {
                            some: {
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