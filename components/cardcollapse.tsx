import { Card, Button, Collapse, Container } from 'react-bootstrap';
import { useState } from 'react';
import * as O from 'fp-ts/lib/Option';
import { constant, pipe } from 'fp-ts/lib/function';
import { truncateAtWord } from '../libs/utils/util';

//TODO This component is kind of janky and was really just a quick hack. We should make it better.
type Props = {
    text: O.Option<string>;
};
const CardTextCollapse = ({ text }: Props): JSX.Element => {
    const [open, setOpen] = useState(false);
    const noCollapse = (t: string) => (
        <Container>
            <Card.Text>{t}</Card.Text>
        </Container>
    );

    const t = pipe(text, O.getOrElse(constant('')));

    const truncated = truncateAtWord(40)(t);
    const start = t.substring(truncated.length, t.length + 1);

    if (t.length - 40 <= truncated.length) {
        return noCollapse(t);
    } else {
        return (
            <Container>
                <Card.Text>{truncated}</Card.Text>
                <Collapse in={open}>
                    <Card.Text>{start}</Card.Text>
                </Collapse>
                <Button onClick={() => setOpen(!open)} aria-controls="" aria-expanded={open}>
                    {open ? 'Show Less...' : 'Show More...'}
                </Button>
            </Container>
        );
    }
};

export default CardTextCollapse;
