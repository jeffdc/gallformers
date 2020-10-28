import { gall, PrismaClient, species } from '@prisma/client';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import { ParsedUrlQuery } from 'querystring';
import { Card, CardColumns } from 'react-bootstrap';
import CardTextCollapse from '../components/cardcollapse';
import { SearchBar, SearchQuery } from '../components/searchbar';

type SpeciesProp = species & {
    gall: gall[],
    hosts: species[],
    host_galls: species[]
}

type Props = {
    species: SpeciesProp[],
    query: SearchQuery
};

const speciesLink = (species: SpeciesProp) => {
    if (species.taxoncode === 'gall') {
        return <Link href={"gall/[id]"} as={`gall/${species.id}`}><a>{species.name}</a></Link>
    } else {
        return <Link href={"host/[id]"} as={`host/${species.id}`}><a>{species.name}</a></Link>
    }

}
const GlobalSearch = ({ species, query }: Props): JSX.Element => {
    return (
        <div>
            <CardColumns className='m-2 p-2'>
                {species.map( species =>
                    <Card key={species.id} className="shadow-sm">
                        <Card.Img variant="top" width="200px" src="/images/gall.jpg" />
                        <Card.Body>
                            <Card.Title>
                                { speciesLink(species) }
                            </Card.Title>
                            <CardTextCollapse text={species.description === null ? '' : species.description} />
                        </Card.Body>
                    </Card>
                )}
            </CardColumns>
            <SearchBar query={ {...query} }></SearchBar>
        </div>
    )
}

export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery; }) => {
    // add wildcards to search phrase
    const q = `%${context.query.searchText as string}%`;
    // Useful for logging SQL that is genereated for debugging the search
    // const newdb = new PrismaClient({log: ['query']}); 
    const newdb = new PrismaClient();

    const species = await newdb.species.findMany({
        include: {
            host_galls: true,
            hosts: true,
            gall: true,
        },
        where: {
            OR: [
                { name: { contains: q} },
                { description: { contains: q } },
                { commonnames: { contains: q } },
                { synonyms: { contains: q } },
            ]
        }
    });

    return {
        props: {
            species: species,
            query: q,
        }
    }
}

export default GlobalSearch;