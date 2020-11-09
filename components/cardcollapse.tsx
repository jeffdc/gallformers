import { Card, Button, Collapse, Container } from 'react-bootstrap';
import { useState } from 'react';

//TODO This component is kind of janky and was really just a quick hack. We should make it better.
type Props = {
    text: string | undefined
}
const CardTextCollapse = ( { text }:Props ): JSX.Element => {
    const [open, setOpen] = useState(false);
    const noCollapse = (
        <Container>
            <Card.Text>{text}</Card.Text>
        </Container>
    );
    if (text === null || text === undefined || text.length === 0) {
        return noCollapse
    }

    const truncated = text.split(' ').splice(0, 40).join(' ');
    const start = text.substring(truncated.length, text.length + 1)

    if (text.length - 40 <= truncated.length) {
        return noCollapse
    } else {
        return (
            <Container>
                <Card.Text>{truncated + '...'}</Card.Text>
                <Collapse in={open}>
                    <Card.Text>{ start }</Card.Text>
                </Collapse>
                <Button 
                    onClick={() => setOpen(!open)} 
                    aria-controls='' 
                    aria-expanded={open}>
                        { open ? 'Show Less...' : 'Show More...' }
                    </Button>
            </Container>
        )
    }
};
  
export default CardTextCollapse;