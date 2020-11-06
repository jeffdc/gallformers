import { GetServerSideProps } from 'next';
import { Container } from 'next/app';
import Link from 'next/link';
import { ParsedUrlQuery } from 'querystring';
import React from 'react';
import { Card, CardColumns, Col, Row } from 'react-bootstrap';
import CardTextCollapse from '../components/cardcollapse';
import { searchGalls } from '../libs/search';
import { Gall, SearchQuery } from '../libs/types';

type Props = {
    data: Gall[],
    query: SearchQuery
};

const Search = ({ data }: Props): JSX.Element => {
    return (
        <div>
            <Container>
                <Row>
                    <Col>
                        <CardColumns className='m-2 p-2'>
                            {data.map((gall) =>
                                <Card key={gall.id} className="shadow-sm">
                                    <Card.Img variant="top" width="200px" src="/images/gall.jpg" />
                                    <Card.Body>
                                        <Card.Title>
                                            <Link href={"gall/[id]"} as={`gall/${gall.species_id}`}><a>{gall.species?.name}</a></Link>
                                        </Card.Title>
                                        <CardTextCollapse text={gall.species?.description === null ? '' : gall.species?.description} />
                                    </Card.Body>
                                </Card>
                            )}
                        </CardColumns>
                    </Col>
                </Row>
            </Container>
         </div>
    )
}

export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery; }) => {
    if (context === undefined || context.query === undefined) {
        throw new Error('Must pass a valid query object to Search!')
    }

    return {
        props: {
            data: await searchGalls(context.query as SearchQuery),
            query: {...context.query},
        }
    }
}

export default Search;