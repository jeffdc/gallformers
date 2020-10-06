import { Container, Toast, Spinner } from 'react-bootstrap';
import useSearch from '../hooks/use-search';
import { useRouter } from 'next/router';

const Search = () => {
    const router = useRouter();
    let search = {
        host: router.query.host,
        location: router.query.location,
        detachable: router.query.detachable,
        texture: router.query.texture,
        alignment: router.query.alignment,
        walls: router.query.walls,
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

    return (<Container>{data}</Container>)
}

// Need this, apparently, for next.js 9.5, I suffered a lot to find this "answer".
// see: https://github.com/facebook/react/issues/13991#issuecomment-669171027
const S = () => <Search />;
export default S;