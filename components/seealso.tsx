import React from 'react';
import { Col, Row } from 'react-bootstrap';
import Image from 'next/image';
import iNatLogo from '../public/images/inatlogo-small.png';
import BugGuideLogo from '../public/images/bugguide-small.png';
import GScholarLogo from '../public/images/gscholar-small.png';
import BHLLogo from '../public/images/bhllogo.png';

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
        <>
            {!undescribed ? (
                <Row className="">
                    <Col xs={12} md={6} lg={3} className="align-self-center">
                        <a
                            href={iNatUrl(name, !!undescribed)}
                            target="_blank"
                            rel="noreferrer"
                            aria-label="Search for more information about this species on iNaturalist."
                        >
                            <Image src={iNatLogo} alt="iNaturalist logo" />
                        </a>
                    </Col>
                    <Col xs={12} md={6} lg={3} className="align-self-center">
                        <a
                            href={bugguideUrl(name)}
                            target="_blank"
                            rel="noreferrer"
                            aria-label="Search for more information about this species on BugGuide."
                        >
                            <Image src={BugGuideLogo} alt="BugGuide logo" />
                        </a>
                    </Col>
                    <Col xs={12} md={6} lg={3} className="align-self-center">
                        <a
                            href={gScholarUrl(name)}
                            target="_blank"
                            rel="noreferrer"
                            aria-label="Search for more information about this species on Google Scholar."
                        >
                            <Image src={GScholarLogo} alt="Google Scholar logo" />
                        </a>
                    </Col>
                    <Col xs={12} md={6} lg={3} className="align-self-center">
                        <a
                            href={bhlUrl(name)}
                            target="_blank"
                            rel="noreferrer"
                            aria-label="Search for more information about this species at the Biodiversity Heritage Library."
                        >
                            <Image src={BHLLogo} alt="Biodiversity Heritage Library logo" />
                        </a>
                    </Col>
                </Row>
            ) : (
                <Row>
                    <Col xs={12} md={10}>
                        <span className="smaller">
                            Unless noted otherwise in the ID Notes, observations of this gall are collected in the Observation
                            Field <i>Gallformers Code</i> with value <i>{`${parseUndescribed(name)}`}</i> on iNaturalist. You can
                            view them here:
                        </span>
                    </Col>
                    <Col className="align-self-center">
                        <a
                            href={iNatUrl(name, !!undescribed)}
                            target="_blank"
                            rel="noreferrer"
                            aria-label="Search for more information about this species on iNaturalist."
                        >
                            <Image src={iNatLogo} alt="iNaturalist logo" />
                        </a>
                    </Col>
                </Row>
            )}
        </>
    );
};

export default SeeAlso;
