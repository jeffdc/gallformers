import { GetServerSideProps } from 'next';
import Link from 'next/link';
import { ParsedUrlQuery } from 'querystring';
import React from 'react';
import { Card, CardColumns, ListGroup } from 'react-bootstrap';
import CardTextCollapse from '../components/cardcollapse';
import { SpeciesApi } from '../libs/apitypes';
import { GallTaxon } from '../libs/db/dbinternaltypes';
import { getSpecies } from '../libs/db/species';
import { entriesWithLinkedDefs, EntryLinked } from '../libs/glossary';
import { deserialize } from '../libs/reactserialize';

type Props = {
    species: SpeciesApi[];
    glossary: EntryLinked[];
};

const speciesLink = (species: SpeciesApi) => {
    if (species.taxoncode === GallTaxon) {
        return (
            <Link href={`gall/${species.id}`}>
                <a>{species.name}</a>
            </Link>
        );
    } else {
        return (
            <Link href={`host/${species.id}`}>
                <a>{species.name}</a>
            </Link>
        );
    }
};

const glossaryEntries = (entries: EntryLinked[]) => {
    if (entries.length > 0) {
        return (
            <ListGroup>
                {entries.map((e) => (
                    <ListGroup.Item key={e.word}>
                        {e.word} - {deserialize(e.linkedDefinition)}
                    </ListGroup.Item>
                ))}
            </ListGroup>
        );
    } else {
        return undefined;
    }
};

const GlobalSearch = ({ species, glossary }: Props): JSX.Element => {
    if (species.length == 0 && glossary.length == 0) {
        return <h1>No results</h1>;
    }

    return (
        <div>
            {glossaryEntries(glossary)}
            <CardColumns className="m-2 p-2">
                {species.map((species) => (
                    <Card key={species.id} className="shadow-sm">
                        <Card.Img variant="top" width="200px" src="/images/gall.jpg" />
                        <Card.Body>
                            <Card.Title>{speciesLink(species)}</Card.Title>
                            <CardTextCollapse text={species.description === null ? '' : species.description} />
                        </Card.Body>
                    </Card>
                ))}
            </CardColumns>
        </div>
    );
};

export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery }) => {
    const search = context.query.searchText as string;
    // add wildcards to search phrase
    const q = `%${search}%`;

    const species = await getSpecies(
        [
            { name: { contains: q } },
            { speciessource: { some: { description: { contains: q } } } },
            { commonnames: { contains: q } },
            { synonyms: { contains: q } },
        ],
        false,
    );

    const glossary = (await entriesWithLinkedDefs()).filter((e) => {
        return e.word === search || e.definition.includes(search);
    });

    return {
        props: {
            species: species,
            glossary: glossary,
        },
    };
};

export default GlobalSearch;
