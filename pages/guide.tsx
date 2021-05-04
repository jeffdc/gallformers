import Head from 'next/head';
import Link from 'next/link';
import React from 'react';
import { Container } from 'react-bootstrap';

export default function Guide(): JSX.Element {
    return (
        <React.Fragment>
            <Head>
                <title>Guide</title>
            </Head>
            <Container className="mt-4 m-2">
                <h1>Introduction to Gall ID</h1>
                <br />
                <p>
                    A <Link href="/glossary#gall">gall</Link> is a novel organ grown by a plant when another organism alters the
                    way the plant expresses its genes. Gall-inducers are found in a wide range of taxa. Insects, mites, and fungi
                    are the most common, but nematodes, bacteria, and even plants can also induce galls.
                </p>
                <p>
                    Because gall induction is a biochemical alteration of the growth pattern of a plant, galls are highly
                    targeted, usually specific to a single part of one or several closely related{' '}
                    <Link href="/glossary#host">host</Link> species. Some gall-inducing species form distinct galls on different
                    hosts or, in different portions of their lifecycle, on different parts of the same host. These galls are
                    listed separately in the database.
                </p>
                <p>
                    Galls typically have unique, recognizable exterior features that are distinct from galls formed by their close
                    relatives. This means that identifying a gall-inducer to species requires no taxon-specific anatomical
                    knowledge and is generally much easier than identifying other fungi or arthropods.
                </p>
                <p>
                    Galls are created to feed and protect their inducers, and these conditions are attractive to other organisms.
                    Many galls are targeted by predators, parasitoids, and <Link href="/glossary#inquiline">inquilines</Link> that
                    live within the gall, some of which do not harm the gall-inducer. In most cases this database does not include
                    these organisms, but a few inquilines modify developing galls and create distinct galls, and in these cases
                    the gall is listed as a separate entry in the database.
                </p>
                <h3 className="mb-3">Using our ID tool</h3>
                <p>
                    The most important step in gall ID is the correct identification of the host plant. If you’re not sure what
                    your plant is, you can take a photo and make an observation on iNaturalist. The site’s computer vision
                    algorithm will give you a plausible suggestion, which you can confirm yourself with other resources and will
                    likely be confirmed or corrected by other users. There are many plant ID resources available online:
                </p>
                <ul>
                    <li>
                        <a href="https://gobotany.nativeplanttrust.org/advanced/">New England</a>
                    </li>
                    <li>
                        <a href="https://michiganflora.net/">Michigan</a>
                    </li>
                    <li>
                        <a href="http://efloras.org/flora_page.aspx?flora_id=1">North America</a>
                    </li>
                    <li>
                        <a href="http://tchester.org/plants/analysis/salix/key.html#picture">California (willows only)</a>
                    </li>
                </ul>
                <p>
                    For plants with few galls, host ID alone will likely filter the possibilities enough that your gall is
                    recognizable. However, most galls are found on plant species with many galls. In those cases, select
                    additional traits, starting with location and detachable, until the results are manageable. See the gall{' '}
                    <Link href="/filterguide">filter term guide</Link> for more info on what these selections mean.
                </p>
                <p>
                    Once you find a plausible set of options, you may want to confirm your ID by checking the original
                    descriptions of the gall, available on its page. Additional information about taxonomic shifts and ID tips is
                    also available on each gall page.
                </p>
                <p>
                    Be aware that this database is a work in progress and many galls may not be added yet. The database is
                    complete for plants and galls marked as such. However, many gall-inducing species are not yet described, and
                    if you find a gall that is not listed on a host that is marked complete, please contact us at
                    gallformers@gmail.com.
                </p>
                <h3 className="mb-3" id="troubleshooting">
                    ID tips and troubleshooting
                </h3>
                <p>
                    If you’re not finding a match, try using only host, location, and detachable before you give up. Common issues
                    using these filters include
                </p>
                <ul>
                    <li>Wrong host ID (try moving up to the genus level or checking your second or third guesses)</li>
                    <li>
                        Host not included in the database. Many hybrids or rare species, especially among highly speciose host
                        groups like oaks or goldenrods, may not appear in the database at all or may not have comprehensive gall
                        associations. Try searching a close relative or hybrid parent instead, or the section for Quercus or
                        Carya.
                    </li>
                    <li>
                        Whether a gall is “Between veins” or “on leaf veins” can occasionally be ambiguous or misleading; try
                        choosing the opposite or avoiding these terms entirely
                    </li>
                    <li>Bud galls are often mistaken for stem galls</li>
                    <li>
                        Acorn galls on red oaks can be mistaken for bud galls (red-group oaks have small overwintering acorns with
                        similar size and placement as their buds)
                    </li>
                    <li>A gall looks detachable but is not (or vice versa); check the results for the opposite option</li>
                    <li>
                        If your gall is only found on the leaf midrib, it may be a species that could theoretically be found on
                        any of the leaf veins; check “on leaf veins” instead
                    </li>
                    <li>
                        Gall-inducers, especially cynipid wasps, occasionally form galls on the opposite side of the leaf from
                        their normal habit; check the results for the opposite option
                    </li>
                    <li>
                        Wrong season selected. Galls often persist long after their season of appearance. Only use this filter if
                        the gall is obviously fresh
                    </li>
                </ul>
                <p>
                    Generally speaking, it’s a good idea to try sequentially removing filters to make sure you’re not missing
                    relevant possibilities.
                </p>
                <p>
                    Other traits, including color, walls, cells, alignment, shape, and texture, may not be added comprehensively
                    or at all. Check the gall <Link href="/filterguide">filter term guide</Link> to make sure you’re applying the
                    terms consistently with our usage.
                </p>
                <p>
                    Note that if you search by host at the section or genus level, you are likely to encounter galls from other
                    parts of the country than your observation. Be sure to confirm the range makes sense before making an ID.
                </p>
            </Container>
        </React.Fragment>
    );
}
