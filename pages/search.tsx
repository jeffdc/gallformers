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
    const newdb = new PrismaClient();
    const q = context.query;
    const detachableWhere =  
        q.detachable != 0 || q.detachable != 1 ?
            null
        :
            { OR: [ {detachable: { not: null }}, {detachable: { equals: q.detachable }} ] };
    const data = await newdb.gall.findMany({
        include: {
            alignment: {},
            cells: {},
            color: {},
            location: {},
            shape: {},
            species: {},
            texture: {},
            walls: {},
        },
        where: {
            // AND: [
                // detachableWhere,
                // { OR: [ {color: { is: q.color } }, { color: { isNot: null } } ] },
                // { OR: [ {shape: { is: q.shape } }, { shape: { isNot: null } } ] },
                // { OR: [ {alignment: { is: q.alignment } }, { alignment: { isNot: null } } ] },
                // { OR: [ {cells: { is: q.cells } }, { cells: { isNot: null } } ] },
                // { OR: [ {walls: { is: q.walls } }, { walls: { isNot: null } } ] },
                // { OR: [ {location: { is: q.loc } }, { location: { isNot: null } } ] },
                // { 
                    // species: { name : { equals: q.host } } 
                // },
            // ]
        },
        distinct: [GallDistinctFieldEnum.species_id]
    });
    // console.log(`Data Yo: ${JSON.stringify(data, null, '  ')}`);
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