import Link from 'next/link';
import { Toast, Spinner, Card, CardColumns } from 'react-bootstrap';
import useSearch from '../hooks/use-search';
import { useRouter } from 'next/router';
import CardTextCollapse from './components/cardcollapse';
import SearchBar from './components/searchbar';

const Search = () => {
    const router = useRouter();
    let search = {
        host: router.query.host,
        location: router.query.location,
        detachable: router.query.detachable,
        texture: router.query.texture,
        alignment: router.query.alignment,
        walls: router.query.walls,
        color: router.query.color,
        shape: router.query.shape,
        cells: router.query.cells,
    };

    const { data, error } = useSearch(search);
    if (error) {
        return ( 
            <Toast>
                <Toast.Header>Crap</Toast.Header>
                <Toast.Body>
                    Failed to search for galls. Might be time to go outside for a bit.
                    {JSON.stringify(error)}
                </Toast.Body>
            </Toast>
        )
    }
    if (!data) {
        return (
            <Spinner animation="border" role="status">
                <span className="sr-only">Loading...</span>
            </Spinner>
        )
    }

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
            <SearchBar search={search}></SearchBar>
        </div>
    )
}

// Need this, apparently, for next.js 9.5, I "suffered" a lot to find this "answer".
// see: https://github.com/facebook/react/issues/13991#issuecomment-669171027
const S = () => <Search />;
export default S;