import { Container, Col, Row } from 'react-bootstrap';

function anyIfEmptyString(x) {
    return x == null || x === undefined || x.length <= 0 ? 'Any' : x
}

const SearchBar = props => {

    return (
        <Container fluid className='m-1'>
            <Row className='small border border-secondary bg-dark rounded-sm fixed-bottom text-light text-center mt-5'>
                <Col className="border align-items-center d-flex">Host: <i>{anyIfEmptyString(props.search.host)}</i></Col>
                <Col className="border align-items-center d-flex">Detachable: {anyIfEmptyString(props.search.detachable)}</Col>
                <Col className="border align-items-center d-flex">Alignment: {anyIfEmptyString(props.search.alignment)}</Col>
                <Col className="border align-items-center d-flex">Walls: {anyIfEmptyString(props.search.walls)}</Col>
                <Col className="border align-items-center d-flex">Texture: {anyIfEmptyString(props.search.texture)}</Col>
                <Col className="border align-items-center d-flex">Color: {anyIfEmptyString(props.search.color)}</Col>
                <Col className="border align-items-center d-flex">Shape: {anyIfEmptyString(props.search.shape)}</Col>
                <Col className="border align-items-center d-flex">Cells: {anyIfEmptyString(props.search.cells)}</Col>
            </Row>
        </Container>
    )
};
  
export default SearchBar;