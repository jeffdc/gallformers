import React from 'react';
import { Col, Row } from 'react-bootstrap';
import { bhlUrl, bugguideUrl, gScholarUrl, iNatUrl } from '../libs/utils/util';

type Props = {
    name: string;
};

const SeeAlso = ({ name }: Props): JSX.Element => {
    return (
        <Row className="">
            <Col xs={12} md={6} lg={3} className="align-self-center">
                <a
                    href={iNatUrl(name)}
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
