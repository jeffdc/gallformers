import Link from 'next/link';
import { Card, CardColumns } from 'react-bootstrap';
import CardTextCollapse from '../components/cardcollapse';
import SearchBar from '../components/searchbar';
import { search } from '../database';

const Search = ({ data, query }) => {
    return (
        <div>
            <CardColumns className='m-2 p-2'>
                {data.map((gall) =>
                    <Card key={gall.species_id} className="shadow-sm">
                        <Card.Img variant="top" width="200px" src="/images/gall.jpg" />
                        <Card.Body>
                            <Card.Title><Link href={"gall/[id]"} as={`gall/${gall.species_id}`}><a>{gall.name}</a></Link></Card.Title>
                            <CardTextCollapse text={gall.description} />
                        </Card.Body>
                    </Card>
                )}
            </CardColumns>
            <SearchBar search={query}></SearchBar>
        </div>
    )
}

export async function getServerSideProps(context) {
    const data = await search(context.query);
    return {
        props: {
            data: data,
            query: context.query,
        }
    }
}

export default Search;