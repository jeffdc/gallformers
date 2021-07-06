import Head from 'next/head';
import React from 'react';
import Link from 'next/link';
import { ListGroup, Container, Accordion, Card, Button } from 'react-bootstrap';

const { Item } = ListGroup;

export default function FilterGuide(): JSX.Element {
    return (
        <React.Fragment>
            <Head>
                <title>Filter Guide</title>
            </Head>
            <Container fluid className="mt-4 m-2">
                <h1>ID Tool Filter Guide</h1>
                <br />
                <Accordion>
                    <Card>
                        <Card.Header>
                            <Accordion.Toggle as={Button} variant="light" eventKey="alignment">
                                Alignment
                            </Accordion.Toggle>
                        </Card.Header>
                    </Card>
                    <Accordion.Collapse eventKey="alignment">
                        <ListGroup>
                            <Item key="leaning">
                                <b>Leaning -</b> the gall is at an angle from the surface it is attached to.
                            </Item>
                            <Item key="erect">
                                <b>Erect -</b> the gall stands at nearly 90 degrees from the surface it is attached to. Includes
                                the majority of detachable galls.
                            </Item>
                            <Item key="integral">
                                <b>Integral -</b> the gall is integral with the surface it is attached to. It may not be flat, but
                                it doesn&apos;t protrude out from the surface leaving an angled gap. Includes nearly all non-detachable
                                galls.
                            </Item>
                            <Item key="supine">
                                <b>Supine -</b> the gall is only attached at its base but lays nearly flat along the surface it is
                                attached to for most of its length.
                            </Item>
                            <Item key="drooping">
                                <b>Drooping -</b> the gall may have any alignment, but its tip is conspicuously curved toward the
                                ground from whatever the primary orientation of the gall is.
                            </Item>
                        </ListGroup>
                    </Accordion.Collapse>
                    <Card>
                        <Card.Header>
                            <Accordion.Toggle as={Button} variant="light" eventKey="cells">
                                Cells
                            </Accordion.Toggle>
                        </Card.Header>
                    </Card>
                    <Accordion.Collapse eventKey="cells">
                        <ListGroup>
                            <Item key="monothalamous">
                                <b>Monothalamous -</b> one cell or chamber containing a larva or larvae of the inducing insect
                                is present within the gall if single, or within each gall in a cluster. May include galls with
                                empty false chambers.
                            </Item>
                            <Item key="polythalamous">
                                <b>Polythalamous -</b> more than one cell or chamber containing a single larva of the inducing
                                insect is present within the gall if single, or within each gall in a cluster. Does not
                                include galls with empty false chambers.
                            </Item>
                            <Item key="free-rolling">
                                <b>Free-rolling -</b> the cell containing the larva is loose within an open cavity formed
                                by the walls of the gall, free to roll around when disturbed.
                            </Item>
                            <Item>
                                NOTE: If multiple larvae are found in one space, these may be{' '}
                                <Link href="/glossary#inquiline">inquilines</Link> rather than gall-inducers.
                            </Item>
                        </ListGroup>
                    </Accordion.Collapse>
                    <Card>
                        <Card.Header>
                            <Accordion.Toggle as={Button} variant="light" eventKey="detachable">
                                Detachable
                            </Accordion.Toggle>
                        </Card.Header>
                    </Card>
                    <Accordion.Collapse eventKey="detachable">
                        <ListGroup>
                            <Item key="yes">
                                <b>Yes -</b> the gall could be removed from the plant without destroying the tissue it’s attached
                                to (detachable).
                            </Item>
                            <Item key="no">
                                <b>No -</b> the gall could only be removed from the plant by destroying the tissue it’s attached
                                to (integral).
                            </Item>
                            <Item key="note">
                                NOTE: Galls that have detachable parts but leave some galled tissue behind (more than a scar or
                                blister), are only detachable in some parts of the season, or may be detachable or not, are
                                included in both terms.
                            </Item>
                        </ListGroup>
                    </Accordion.Collapse>
                    <Card>
                        <Card.Header>
                            <Accordion.Toggle as={Button} variant="light" eventKey="forms">
                                Forms
                            </Accordion.Toggle>
                        </Card.Header>
                    </Card>
                    <Accordion.Collapse eventKey="forms">
                        <ListGroup>
                            <Item key="abrupt swelling">
                                <b>Abrupt Swelling -</b> a significant increase in the diameter of a stem, petiole, etc, emerging
                                directly from tissue of normal proportions; ie, without a gradual increase along the length of
                                the affected tissue. Sometimes encircling the stem, other times emerging only from one side.
                            </Item>
                            <Item key="gall">
                                <b>Gall -</b> a novel element of a plant caused by an organism living within the plant.
                            </Item>
                            <Item key="hidden cell">
                                <b>Hidden cell -</b> a gall making no externally visible change to the host (typically in a
                                stem or fruit) until the inducer chews its egress hole.
                            </Item>
                            <Item key="lead edge fold">
                                <b>Leaf edge fold -</b> a single layer of the leaf edge folded back against the leaf.
                            </Item>
                            <Item key="leaf blister">
                                <b>Leaf blister -</b> localized distortions of the leaf lamina, typically creating a cup
                                opening toward the lower side of the leaf.
                            </Item>
                            <Item key="leaf curl">
                                <b>Leaf curl -</b> broad deformation of the lamina of a leaf, pulling the edges in. Typically
                                irregular and sometimes causing entire leaves to roll up. Often accompanied by discoloration.
                            </Item>
                            <Item key="leaf edge roll">
                                <b>Leaf edge roll -</b> a tight roll of tissue only at the edge of a leaf, of varying thickness.
                            </Item>
                            <Item key="leaf spot">
                                <b>Leaf spot -</b> a flat (never more than slightly thicker than the normal leaf), typically
                                circular spot on the lamina of the leaf, sometimes with distinct rings of darker and lighter
                                coloration (eye spots). Fungal leaf spots often have small dots above; midge spots have an
                                exposed larva below
                            </Item>
                            <Item key="non-gall">
                                <b>Non-gall -</b> any gall-adjacent plant symptom or other structure that doesn’t meet the
                                definition of a gall: a novel element of a plant caused by an organism living within the plant.
                                Examples of non-galls include scale insects; leaf curl, spots, or blisters caused by pathogens
                                or external herbivores; and stem swellings caused by miners or borers lacking internal cells.
                            </Item>
                            <Item key="oak apple">
                                <b>Oak apple -</b> a spherical or near-spherical gall with thin outer walls, a single central
                                larval cell surrounded by either spongy tissue or fine radiating fibers.
                            </Item>
                            <Item key="pocket">
                                <b>Pocket -</b> a structure formed by pinching the leaf lamina together into a narrow opening
                                (a point or line) and stretching it into various forms, from beads to sacks to spindles to
                                long purses. The walls may or may not be thickened relative to the normal leaf.
                            </Item>
                            <Item key="rust">
                                <b>Rust -</b> plant deformations caused by fungi in the order Pucciniales. They cause swelling
                                and curling of stems and petioles and blisters on leaves, easily recognizable for their bright
                                orange coloration, seen in characteristic rings.
                            </Item>
                            <Item key="scale">
                                <b>Scale -</b> an herbivorous insect of the superfamily Coccoidea. The post-reproductive
                                females of the family Kermesidae have thin, globular, hollow shells fixed in place on their host.
                            </Item>
                            <Item key="stem club">
                                <b>Stem club -</b> A substantial enlargement of the growing tip of a woody plant, tapering more
                                or less gradually from normal stem width below it, blunt or rounded above.
                            </Item>
                            <Item key="tapered swelling">
                                <b>Tapered swelling -</b> an increase in the diameter of a stem, petiole, etc, gradual from
                                either side of the gall.
                            </Item>
                            <Item key="witches broom">
                                <b>Witches broom -</b> a dense profusion of buds or shoots on woody plants.
                            </Item>
                        </ListGroup>
                    </Accordion.Collapse>
                    <Card>
                        <Card.Header>
                            <Accordion.Toggle as={Button} variant="light" eventKey="location">
                                Location
                            </Accordion.Toggle>
                        </Card.Header>
                        <Accordion.Collapse eventKey="location">
                            <ListGroup>
                                <Item key="at leaf vein angles">
                                    <b>At leaf vein angles -</b> galls located exclusively in the inside of the intersection
                                    between the lateral veins and main veins of the leaf.
                                </Item>
                                <Item key="between leaf veins">
                                    <b>Between leaf veins -</b> galls are not specifically located only on leaf veins. Galls with
                                    this term may sometimes incidentally appear close to veins.
                                </Item>
                                <Item key="bud">
                                    <b>Bud -</b> galls are located in buds (often found where branches intersect the stem, can be
                                    mistaken for stem galls).
                                </Item>
                                <Item key="flower">
                                    <b>Flower -</b> galls are located in flowers. Note this is a botanical term referring to
                                    reproductive structures, and some flowers (eg oak catkins) may not be obviously recognizable
                                    as such.
                                </Item>
                                <Item key="fruit">
                                    <b>Fruit -</b> galls are located in fruit. This is a botanical term referring to seed-bearing
                                    structures, and some fruit (eg maple samaras) may not be obviously recognizable as such.
                                </Item>
                                <Item key="leaf midrib">
                                    <b>Leaf midrib -</b> galls are located exclusively on the thickest, central vein of the leaf.
                                </Item>
                                <Item key="lower leaf">
                                    <b>Lower leaf -</b> galls are located on the lower (abaxial) side of the leaf.
                                </Item>
                                <Item key="on leaf veins">
                                    <b>On leaf veins -</b> galls are located exclusively on or very close to the veins of the
                                    leaf, including but not limited to the midrib.
                                </Item>
                                <Item key="petiole">
                                    <b>Petiole -</b> galls are located on the part of the midrib between the leaf and the stem.
                                </Item>
                                <Item key="root">
                                    <b>Root -</b> galls are located on the roots of the plant or near the base of the stem.
                                </Item>
                                <Item key="stem">
                                    <b>Stem -</b> galls are located anywhere in or on the stem (except within buds, which are
                                    occasionally deformed by gall inducers enough to appear as stem galls).
                                </Item>
                                <Item key="upper leaf">
                                    <b>Upper leaf -</b> galls are located on the upper (adaxial) side of the leaf.
                                </Item>
                                <Item key="leaf edge">
                                    <b>Leaf edge -</b> galls are exclusively located around the edge of the leaf, often curled or
                                    folded.
                                </Item>
                            </ListGroup>
                        </Accordion.Collapse>
                    </Card>
                    <Card>
                        <Card.Header>
                            <Accordion.Toggle as={Button} variant="light" eventKey="shape">
                                Shape
                            </Accordion.Toggle>
                        </Card.Header>
                    </Card>
                    <Accordion.Collapse eventKey="shape">
                        <ListGroup>
                            <Item key="cluster">
                              <b>Cluster -</b> individual galls nearly always found in numbers, often pressing together
                              and flattening against each other.
                            </Item>
                            <Item key="conical">
                              <b>Conical -</b> wide and round at the base, tapering on all sides to a point above.
                            </Item>
                            <Item key="cup">
                              <b>Cup -</b> a circular structure with walls enclosing a volume, open from above.
                            </Item>
                            <Item key="globular">
                              <b>Globular -</b> the gall is rounded but not perfectly spherical (including ovate, ellipsoid,
                              irregular, etc).
                            </Item>
                            <Item key="hemispherical">
                              <b>Hemispherical -</b> perfectly round or nearly so, but only in one half of a full sphere
                              (often divided by a leaf).
                            </Item>
                            <Item key="linear">
                              <b>Linear -</b> the gall is a narrow line in shape for much of its form. Often seen as
                              extensions of leaf veins, sometimes widening at a club or spindle-like end. 
                            </Item>
                            <Item key="numerous">
                              <b>Numerous -</b> typically found in large numbers (>10) scattered across every leaf
                              or other plant part on which they occur, but not clustered together.
                            </Item>
                            <Item key="rosette">
                              <b>Rosette -</b> a layered bunch of leaves or similar.
                            </Item>
                            <Item key="spangle">
                              <b>Spangle -</b> a flat, circular disc-like structure. Often with a central umbo.
                            </Item>
                            <Item key="sphere">
                              <b>Sphere -</b> perfectly round, of equal diameter in every dimension.
                            </Item>
                            <Item key="spindle">
                              <b>Spindle -</b> elongated, round in the middle and narrowed above and below, often pointed above.
                            </Item>
                            <Item key="tuft">
                              <b>Tuft -</b> small galls with structure entirely obscured by long woolly fibers.
                            </Item>
                        </ListGroup>
                    </Accordion.Collapse>
                    <Card>
                        <Card.Header>
                            <Accordion.Toggle as={Button} variant="light" eventKey="texture">
                                Texture
                            </Accordion.Toggle>
                        </Card.Header>
                    </Card>
                    <Accordion.Collapse eventKey="texture">
                        <ListGroup>
                            <Item key="areola">
                                <b>Areola -</b> the upper tip of the gall has a ring, often raised and sometimes containing a
                                central umbo, scar, or nipple.
                            </Item>
                            <Item key="bumpy">
                                <b>Bumpy -</b> the surface of the gall is covered with some kind of slight protrusions.
                            </Item>
                            <Item key="erineum">
                                <b>Erineum -</b> the distinctive "sugary" crystalline texture formed by many eriophyid mites.
                            </Item>
                            <Item key="glaucous">
                                <b>Glaucous -</b> covered in a whitish layer of fine powder or wax that can be easily rubbed off.
                            </Item>
                            <Item key="hairless">
                                <b>Hairless -</b> the gall has no visible hairs at all. Note that late in hte season, hairs may
                                wear off some galls.
                            </Item>
                            <Item key="hairy">
                                <b>Hairy -</b> the gall has some hairs, whether that&apos;s only a sparse pubescence of short hairs or
                                a dense coat of long wool that obscures the gall or stiff bristles (as in Acraspis erinacei).
                            </Item>
                            <Item key="honeydew">
                                <b>Honeydew -</b> galls releasing sugary solution. Often visible as a shiny wetness, but
                                can be more apparent in the ants and wasps it attracts.
                            </Item>
                            <Item key="leafy">
                                <b>Leafy -</b> the gall is surrounded by or composed of a profusion of altered leaves, bud scales,
                                or similar structures.
                            </Item>
                            <Item key="mottled">
                                <b>Mottled -</b> multiple colors on the surface of the gall mix irregularly.
                            </Item>
                            <Item key="pubescent">
                                <b>Pubescent -</b> the hair covering the gall is short, soft, and dense. May or may not
                                obscure the color and texture of the surface, but not concealing its shape.
                            </Item>
                            <Item key="resinous dots">
                                <b>Resinous dots -</b> the surface of the gall is covered in dots, often red, that secret sticky resin.
                            </Item>
                            <Item key="ribbed">
                                <b>Ribbed -</b> the external surface has linear grooves and ridges, typically running from the bottom
                                to the top of the gall.
                            </Item>
                            <Item key="spiky-thorny">
                                <b>Spiky/thorny -</b> the gall is covered in sharp spines, prickles, etc.
                            </Item>
                            <Item key="spotted">
                                <b>Spotted -</b> the gall contains distinct spots of a different color than its primary surface.
                            </Item>
                            <Item key="stiff">
                                <b>Stiff -</b> the gall is hard and incompressable to the touch, generally because they are woody,
                                thick-walled, but sometimes with an almost plastic-like texture.
                            </Item>
                            <Item key="succulent">
                                <b>Succulent -</b> the walls of the gall (when fresh) are juicy if cut.
                            </Item>
                            <Item key="woolly">
                                <b>Woolly -</b> the hair covering the gall is long, soft, and thick, often concealing the surface
                                and structure of the gall completely.
                            </Item>
                            <Item key="wrinkly">
                                <b>Wrinkly -</b> the surface of the gall is often irregular or sunken into folds.
                            </Item>
                        </ListGroup>
                    </Accordion.Collapse>
                    <Card>
                        <Card.Header>
                            <Accordion.Toggle as={Button} variant="light" eventKey="walls">
                                Walls
                            </Accordion.Toggle>
                        </Card.Header>
                    </Card>
                    <Accordion.Collapse eventKey="walls">
                        <ListGroup>
                            <Item key="thin">
                                <b>Thin -</b> when the gall is cut open, it reveals an interior matching the shape of the exterior.
                                The walls are not thick enough to conceal the shape of the chamber within.
                            </Item>
                            <Item key="thick">
                                <b>Thick -</b> when the gall is cut open, the interior is full of tissue except for the small
                                chamber containing the larvae. The walls are thick enough that the shape of this chamber could
                                (but may not necessarily) differ from the shape of the exterior.
                            </Item>
                            <Item key="false-chamber">
                                <b>False chamber -</b> when the gall is cut open, there are two chambers, only one of which
                                contains larvae.
                            </Item>
                            <Item key="radiating-fibers">
                                <b>Radiating fibers -</b> a central larval cell held in place by many thin, thread-like fibers.
                            </Item>
                            <Item key="spongy">
                                <b>Spongy -</b> space between larval cell and outer walls filled by a spongy substance of a
                                distinct composition from either.
                            </Item>
                        </ListGroup>
                    </Accordion.Collapse>
                </Accordion>
            </Container>
        </React.Fragment>
    );
}
