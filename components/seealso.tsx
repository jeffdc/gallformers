import React from 'react';
import { Col, Row } from 'react-bootstrap';

// we allow species names to contain subspecies of the form 'Genus species subspecies' and for gallformers
// sexual generation info 'Genus species (sexgen)'. For external linking we want to only link to the main species.
function parseSpecies(species: string): string {
    const p = species.split(' ');

    return encodeURI(`${p[0]} ${p[1]}`);
}

const parseUndescribed = (species: string) => {
    return encodeURI(species.split(' ')[1]);
};

function bugguideUrl(species: string): string {
    return `https://bugguide.net/index.php?q=search&keys=${parseSpecies(species)}&search=Search`;
}

function iNatUrl(species: string, undescribed: boolean): string {
    if (undescribed) {
        return `https://www.inaturalist.org/observations?verifiable=any&place_id=any&field:Gallformers%20Code=${parseUndescribed(
            species,
        )}`;
    } else {
        return `https://www.inaturalist.org/search?q=${parseSpecies(species)}`;
    }
}

function gScholarUrl(species: string): string {
    return `https://scholar.google.com/scholar?hl=en&q=${parseSpecies(species)}`;
}

function bhlUrl(species: string): string {
    return `https://www.biodiversitylibrary.org/search?SearchTerm=${parseSpecies(species)}&SearchCat=M&return=ADV#/names`;
}

type Props = {
    name: string;
    undescribed?: boolean;
};

const SeeAlso = ({ name, undescribed }: Props): JSX.Element => {
    return (
        <Row className="">
            <Col xs={12} md={6} lg={3} className="align-self-center">
                <a
                    href={iNatUrl(name, !!undescribed)}
                    target="_blank"
                    rel="noreferrer"
                    aria-label="Search for more information about this species on iNaturalist."
                >
                    <img src="/images/inatlogo-small.png" alt="iNaturalist logo" />
                </a>
            </Col>
            <Col xs={12} md={6} lg={3} className="align-self-center">
                <a
                    href={bugguideUrl(name)}
                    target="_blank"
                    rel="noreferrer"
                    aria-label="Search for more information about this species on BugGuide."
                >
                    <img src="/images/bugguide-small.png" alt="BugGuide logo" />
                </a>
            </Col>
            <Col xs={12} md={6} lg={3} className="align-self-center">
                <a
                    href={gScholarUrl(name)}
                    target="_blank"
                    rel="noreferrer"
                    aria-label="Search for more information about this species on Google Scholar."
                >
                    <img src="/images/gscholar-small.png" alt="Google Scholar logo" />
                </a>
            </Col>
            <Col xs={12} md={6} lg={3} className="align-self-center">
                <a
                    href={bhlUrl(name)}
                    target="_blank"
                    rel="noreferrer"
                    aria-label="Search for more information about this species at the Biodiversity Heritage Library."
                >
                    <img src="/images/bhllogo.png" alt="Biodiversity Heritage Library logo" />
                </a>
            </Col>
        </Row>
    );
};

export default SeeAlso;
