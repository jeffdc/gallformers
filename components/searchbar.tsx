import { Container, Col, Row } from 'react-bootstrap';

function anyIfEmptyString(x) {
    return x == null || x === undefined || x.length <= 0 ? 'Any' : x
}

export type SearchQuery = {
    host: string,
    detachable?: string,
    alignment?: string,
    walls?: string,
    texture?: string,
    color?: string,
    shape?: string,
    cells?: string
};

export type Props = {
    query: SearchQuery
}

export const SearchBar = ( {query}: Props) => {
    return (
        <Container fluid className='m-1'>
            <Row className='small border border-secondary bg-dark rounded-sm fixed-bottom text-light text-center mt-5'>
                <Col className="border align-items-center d-flex">Host: <i>{query.host}</i></Col>
                <Col className="border align-items-center d-flex">Detachable: {anyIfEmptyString(query.detachable)}</Col>
                <Col className="border align-items-center d-flex">Alignment: {anyIfEmptyString(query.alignment)}</Col>
                <Col className="border align-items-center d-flex">Walls: {anyIfEmptyString(query.walls)}</Col>
                <Col className="border align-items-center d-flex">Texture: {anyIfEmptyString(query.texture)}</Col>
                <Col className="border align-items-center d-flex">Color: {anyIfEmptyString(query.color)}</Col>
                <Col className="border align-items-center d-flex">Shape: {anyIfEmptyString(query.shape)}</Col>
                <Col className="border align-items-center d-flex">Cells: {anyIfEmptyString(query.cells)}</Col>
            </Row>
        </Container>
    )
};
  
export default SearchBar;