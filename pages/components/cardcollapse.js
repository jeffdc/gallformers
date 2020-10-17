import { Card, Button, Collapse, Container } from 'react-bootstrap';
import { useState } from 'react';

const CardTextCollapse = props => {
    const [open, setOpen] = useState(false);
    const [truncated, setTruncated] = useState(props.text.split(' ').splice(0, 40).join(' '));

    return (
        <Container>
            <Card.Text>{truncated + '...'}</Card.Text>
            <Collapse in={open}>
                <Card.Text>{ props.text.substring(truncated.length, props.text.length + 1)}</Card.Text>
            </Collapse>
            <Button 
                onClick={() => setOpen(!open)} 
                aria-controls='' 
                aria-expanded={open}>
                    { open ? 'Show Less...' : 'Show More...' }
                </Button>
        </Container>
    )
};
  
export default CardTextCollapse;