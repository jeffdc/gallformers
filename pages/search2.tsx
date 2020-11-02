import { HostDistinctFieldEnum, PrismaClient } from '@prisma/client';
import { GetServerSideProps } from 'next';
import { Container } from 'next/app';
import React from 'react';
import { Col, Row } from 'react-bootstrap';
import { SearchFacets, SearchInitialProps, SearchQuery, SearchProps } from './layouts/searchfacets';

const Search2 = (props: SearchInitialProps): JSX.Element => {
    const facetsProps: SearchProps = {
        doSearch: (q: SearchQuery) => { console.log(`doSearch with ${JSON.stringify(q)}`) },
        ...props
    };

    return (
        <Container>
            <Row>
                <Col xs={3}>
                    <SearchFacets {...facetsProps}/>
                </Col>
                <Col className='border mt-2'>
                    <Row className='border m-2'><p className='text-right'>Pager TODO</p></Row>
                    <Row className= 'border m-2'>Results TODO</Row>
                </Col>
            </Row>
        </Container>
    )
}



export const getServerSideProps: GetServerSideProps = async() => {
    const newdb = new PrismaClient();

    const h = await newdb.host.findMany({
        include: {
          hostspecies: {
          },
        },
        distinct: [HostDistinctFieldEnum.host_species_id]
      });
    const hosts = h.flatMap ( (h) => {
        if (h.hostspecies != null)
            return [h.hostspecies.name, h.hostspecies.commonnames]
        else 
            return []
    }).filter(h => h).sort();

    return { props: {
            hosts: hosts,
            locations: ((await newdb.location.findMany({})).map(l => l.location).sort()),
            colors: ((await newdb.color.findMany({})).map(l => l.color).sort()),
            shapes: ((await newdb.shape.findMany({})).map(l => l.shape).sort()),
            textures: ((await newdb.texture.findMany({})).map(l => l.texture).sort()),
            alignments: ((await newdb.alignment.findMany({})).map(l => l.alignment).sort()),
            walls: ((await newdb.walls.findMany({})).map(l => l.walls).sort()),
            cells: ((await newdb.cells.findMany({})).map(l => l.cells).sort()),
        }
    }
}

export default Search2;