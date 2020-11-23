import { GetStaticPaths, GetStaticProps } from 'next';
import Link from 'next/link';
import React, { MouseEvent, useState } from 'react';
import { Col, Container, ListGroup, Media, Row } from 'react-bootstrap';
import { GallApi, GallHost } from '../../../libs/apitypes';
import { allGallIds, gallById } from '../../../libs/db/gall';
import { formatCSV } from '../../../libs/db/utils';
import { linkTextFromGlossary } from '../../../libs/glossary';
import { deserialize, serialize } from '../../../libs/reactserialize';
import { bugguideUrl, gScholarUrl, iNatUrl } from '../../../libs/utils/util';

type Props = {
    gall: GallApi;
};

function hostAsLink(h: GallHost) {
    return (
        <Link key={h.host_species_id} href={`/host/${h.host_species_id}`}>
            <a>{h.hostspecies?.name} </a>
        </Link>
    );
}

const Gall = ({ gall }: Props): JSX.Element => {
    if (!gall) {
        console.error('Failed to fetch gall from backend.');
        return <div>Oops</div>;
    }

    const source = gall.species.speciessource.find((s) => s.useasdefault !== 0);
    const [selectedSource, setSelectedSource] = useState(source);

    const changeDescription = (e: MouseEvent<HTMLButtonElement>) => {
        e.preventDefault();
        const id = e.currentTarget.id;
        const s = gall.species.speciessource.find((s) => s.source_id.toString() === id);
        setSelectedSource(s);
    };

    return (
        <div
            style={{
                marginBottom: '5%',
                marginRight: '5%',
            }}
        >
            <Media>
                <img width={170} height={128} className="mr-3" src="/images/gall.jpg" alt={gall.species.name} />
                <Media.Body>
                    <Container className="p-3 border">
                        <Row>
                            <Col>
                                <h2>{gall.species.name}</h2>
                                {gall.species.commonnames ? `(${formatCSV(gall.species.commonnames)})` : ''}
                            </Col>
                            <Col className="text-right font-italic">
                                Family:
                                <Link key={gall.species.family.id} href={`/family/${gall.species.family.id}`}>
                                    <a> {gall.species.family.name}</a>
                                </Link>
                            </Col>
                        </Row>
                        <Row>
                            <Col id="description" className="lead p-3">
                                {deserialize(selectedSource?.description)}
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                <strong>Hosts:</strong> {gall.species.hosts.map(hostAsLink)}
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                <strong>Detachable:</strong> {gall.detachable == 1 ? 'yes' : 'no'}
                            </Col>
                            <Col>
                                <strong>Texture:</strong> {gall.galltexture.map((t) => t.texture?.texture).join(',')}
                            </Col>
                            <Col>
                                <strong>Color:</strong> {gall.color?.color}
                            </Col>
                            <Col>
                                <strong>Alignment:</strong> {gall.alignment?.alignment}
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                <strong>Location:</strong> {gall.galllocation.map((l) => l.location?.location).join(', ')}
                            </Col>
                            <Col>
                                <strong>Walls:</strong> {gall.walls?.walls}
                            </Col>
                            <Col>
                                <strong>Abdundance:</strong> {gall.species?.abundance?.abundance}
                            </Col>
                            <Col>
                                <strong>Shape:</strong> {gall.shape?.shape}
                            </Col>
                        </Row>
                        <Row>
                            <Col>
                                <strong>Further Information:</strong>
                                <ListGroup variant="flush" defaultActiveKey={selectedSource?.source_id}>
                                    {gall.species.speciessource
                                        .sort((a, b) => a.source.citation.localeCompare(b.source.citation))
                                        .map((speciessource) => (
                                            <ListGroup.Item
                                                key={speciessource.source_id}
                                                id={speciessource.source_id.toString()}
                                                action
                                                onClick={changeDescription}
                                                variant={speciessource.source_id === selectedSource?.source_id ? 'dark' : ''}
                                            >
                                                <Link href={`/source/${speciessource.source?.id}`}>
                                                    <a>{speciessource.source?.citation}</a>
                                                </Link>
                                            </ListGroup.Item>
                                        ))}
                                </ListGroup>
                                <hr />
                                <Row className="">
                                    <Col className="align-self-center">
                                        <strong>See Also:</strong>
                                    </Col>
                                    <Col className="align-self-center">
                                        <a href={iNatUrl(gall.species.name)} target="_blank" rel="noreferrer">
                                            <img src="/images/inatlogo-small.png" />
                                        </a>
                                    </Col>
                                    <Col className="align-self-center">
                                        <a href={bugguideUrl(gall.species.name)} target="_blank" rel="noreferrer">
                                            <img src="/images/bugguide-small.png" />
                                        </a>
                                    </Col>
                                    <Col className="align-self-center">
                                        <a href={gScholarUrl(gall.species.name)} target="_blank" rel="noreferrer">
                                            <img src="/images/gscholar-small.png" />
                                        </a>
                                    </Col>
                                </Row>
                            </Col>
                        </Row>
                    </Container>
                </Media.Body>
            </Media>
        </div>
    );
};

// Use static so that this stuff can be built once on the server-side and then cached.
export const getStaticProps: GetStaticProps = async (context) => {
    if (context === undefined || context.params === undefined || context.params.id === undefined) {
        throw new Error('An id must be passed to gall/[id]!');
    }

    const id = context.params.id as string;
    const gall: GallApi = await gallById(id);

    if (gall != null || gall != undefined) {
        // markup the descriptions with glossary links
        for (const s of gall.species.speciessource) {
            s.description = serialize(await linkTextFromGlossary(s.description));
        }
    }

    return {
        props: {
            gall: gall,
        },
        revalidate: 1,
    };
};

export const getStaticPaths: GetStaticPaths = async () => {
    const galls = await allGallIds();

    const paths = galls.map((id) => ({
        params: { id: id },
    }));

    return { paths, fallback: false };
};

export default Gall;
