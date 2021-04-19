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
      <Container fluid className="ml-2">
        <h1>ID Tool Filter Guide</h1>
        <br/>
        <Accordion>
          <Card>
            <Card.Header>
              <Accordion.Toggle as={Button} variant="light" eventKey="0">
                Location
              </Accordion.Toggle>
            </Card.Header>
            <Accordion.Collapse eventKey="0">
              <ListGroup>
                <Item key="at leaf vein angles">
                  <b>At leaf vein angles -</b> galls located exclusively in
                  the inside of the intersection between the lateral veins and
                  main veins of the leaf.
                </Item>
                <Item key="between leaf veins">
                  <b>Between leaf veins -</b> galls are not specifically
                  located only on leaf veins. Galls with this term may sometimes
                  incidentally appear close to veins.
                </Item>
                <Item key="bud">
                  <b>Bud -</b> galls are located in buds (often found where
                  branches intersect the stem, can be mistaken for stem galls).
                </Item>
                <Item key="flower">
                  <b>Flower -</b> galls are located in flowers. Note this is a
                  botanical term referring to reproductive structures, and some
                  flowers (eg oak catkins) may not be obviously recognizable as such.
                </Item>
                <Item key="fruit">
                  <b>Fruit -</b> galls are located in fruit. This is a botanical
                  term referring to seed-bearing structures, and some fruit (eg
                  maple samaras) may not be obviously recognizable as such.
                </Item>
                <Item key="leaf midrib">
                  <b>Leaf midrib -</b> galls are located exclusively on the
                  thickest, central vein of the leaf.
                </Item>
                <Item key="lower leaf">
                  <b>Lower leaf -</b> galls are located on the lower (abaxial) side
                  of the leaf.
                </Item>
                <Item key="on leaf veins">
                  <b>On leaf veins -</b> galls are located exclusively on or very
                  close to the veins of the leaf, including but not limited to the
                  midrib.
                </Item>
                <Item key="petiole">
                  <b>Petiole -</b> galls are located on the part of the midrib
                  between the leaf and the stem.
                </Item>
                <Item key="root">
                  <b>Root -</b> galls are located on the roots of the plant or
                  near the base of the stem.
                </Item>
                <Item key="stem">
                  <b>Stem -</b> galls are located anywhere in or on the stem
                  (except within buds, which are occasionally deformed by gall
                  inducers enough to appear as stem galls).
                </Item>
                <Item key="upper leaf">
                  <b>Upper leaf -</b> galls are located on the upper (adaxial)
                  side of the leaf.
                </Item>
                <Item key="leaf edge">
                  <b>Leaf edge -</b> galls are exclusively located around the edge
                  of the leaf, often curled or folded.
                </Item>
              </ListGroup>
            </Accordion.Collapse>
          </Card>
          <Card>
            <Card.Header>
              <Accordion.Toggle as={Button} variant="light" eventKey="1">
                Detachable
              </Accordion.Toggle>
            </Card.Header>
          </Card>
          <Accordion.Collapse eventKey="1">
            <ListGroup>
              <Item key="yes">
                <b>Yes -</b> the gall could be removed from the plant without
                destroying the tissue it’s attached to (detachable).
              </Item>
              <Item key="no">
                <b>No -</b> the gall could only be removed from the plant by
                destroying the tissue it’s attached to (integral).
              </Item>
              <Item key="note">
                NOTE: Galls that have detachable parts but leave some galled
                tissue behind (more than a scar or blister), are only detachable
                in some parts of the season, or may be detachable or not, are
                included in both terms.
              </Item>
            </ListGroup>
          </Accordion.Collapse>
          <Card>
            <Card.Header>
              <Accordion.Toggle as={Button} variant="light" eventKey="2">
                Texture
              </Accordion.Toggle>
            </Card.Header>
          </Card>
          <Accordion.Collapse eventKey="2">
            <ListGroup>
              <Item key="hairy">
                <b>Hairy -</b> the gall has some hairs, whether that's only a sparse
                pubescence of short hairs or a dense coat of long wool that obscures
                the gall or stiff bristles (as in Acraspis erinacei).
              </Item>
              <Item key="hairless">
                <b>Hairless -</b> the gall has no visible hairs at all. Note that
                late in hte season, hairs may wear off some galls.
              </Item>
              <Item key="erineum">
                <b>Erineum -</b> the distinctive "sugary" crystalline texture
                formed by many eriophyid mites.
              </Item>
              <Item key="sticky">
                <b>Sticky -</b> the gall exudes some kind of sticky fluid. In some 
                cases this fluid is attractive to ants and is often visible as a wet
                sheen in photos, but ideally it should be tested by touch in the field.
              </Item>
            </ListGroup>
          </Accordion.Collapse>
          <Card>
            <Card.Header>
              <Accordion.Toggle as={Button} variant="light" eventKey="3">
                Alignment
              </Accordion.Toggle>
            </Card.Header>
          </Card>
          <Accordion.Collapse eventKey="3">
            <ListGroup>
              <Item key="leaning">
                <b>Leaning -</b> the gall is at an angle from the surface it is
                attached to.
              </Item>
              <Item key="erect">
                <b>Erect -</b> the gall stands at nearly 90 degrees from the surface
                it is attached to. Includes the majority of detachable galls.
              </Item>
              <Item key="integral">
                <b>Integral -</b> the gall is integral with the surface it is
                attached to. It may not be flat, but it doesn't protrude out
                from the surface leaving an angled gap. Includes nearly all
                non-detachable galls.
              </Item>
              <Item key="supine">
                <b>Supine -</b> the gall is only attached at its base but lays nearly
                flat along the surface it is attached to for most of its length.
              </Item>
            </ListGroup>
          </Accordion.Collapse>
          <Card>
            <Card.Header>
              <Accordion.Toggle as={Button} variant="light" eventKey="4">
                Walls
              </Accordion.Toggle>
            </Card.Header>
          </Card>
          <Accordion.Collapse eventKey="4">
            <ListGroup>
              <Item key="thin">
                <b>Thin -</b> when the gall is cut open, it reveals an interior
                matching the shape of the exterior. The walls are not thick enough
                to conceal the shape of the chamber within.
              </Item>
              <Item key="thick">
                <b>Thick -</b> when the gall is cut open, the interior is full of
                tissue except for the small chamber containing the larvae. The walls
                are thick enough that the shape of this chamber could (but may not
                necessarily) differ from the shape of the exterior.
              </Item>
              <Item key="false-chamber">
                <b>False chamber -</b> when the gall is cut open, there are two
                chambers, only one of which contains larvae.
              </Item>
            </ListGroup>
          </Accordion.Collapse>
          <Card>
            <Card.Header>
              <Accordion.Toggle as={Button} variant="light" eventKey="5">
                Cells
              </Accordion.Toggle>
            </Card.Header>
          </Card>
          <Accordion.Collapse eventKey="5">
            <ListGroup>
              <Item key="single">
                <b>Single -</b> the gall's structure is built to accomodate only a
                single space for a gall-inducer larva, pupa, or adult. 
              </Item>
              <Item key="multiple">
                <b>Multiple -</b> the gall's structure is built to accomodate spaces
                for multiple gall-inducer larvae, pupae, or adults.
              </Item>
              <Item>
                NOTE: If multiple larvae are found in one space, these may
                be <Link href="/glossary#inquiline">inquilines</Link> rather than
                gall-inducers.
              </Item>
            </ListGroup>
          </Accordion.Collapse>
        </Accordion>
      </Container>
    </React.Fragment>
  );
}