import * as O from 'fp-ts/lib/Option';
import { constant, pipe } from 'fp-ts/lib/function';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import { useRouter } from 'next/router';
import { ParsedUrlQuery } from 'querystring';
import { useState } from 'react';
import { Button, Col, Row, Tab, Tabs } from 'react-bootstrap';
import ReactMarkdown from 'react-markdown';
import externalLinks from 'rehype-external-links';
import rehypeRaw from 'rehype-raw';
import remarkBreaks from 'remark-breaks';
import Auth from '../../components/auth';
import { RenameEvent } from '../../components/editname';
import Picker from '../../components/picker';
import useAdmin, { AdminFormFields } from '../../hooks/useadmin';
import { extractQueryParam } from '../../libs/api/apipage';
import { SimpleSpecies, SourceApi, SpeciesSourceApi, SpeciesSourceInsertFields, TaxonCodeValues } from '../../libs/api/apitypes';
import { allSources } from '../../libs/db/source';
import { allSpeciesSimple } from '../../libs/db/species';
import Admin from '../../libs/pages/admin';
import { defaultSource, sourceToDisplay } from '../../libs/pages/renderhelpers';
import { mightFailWithArray } from '../../libs/utils/util';
import { Typeahead } from 'react-bootstrap-typeahead';

type Props = {
    speciesid: string;
    allSpecies: SimpleSpecies[];
    allSources: SourceApi[];
};

type FormFields = AdminFormFields<SimpleSpecies> & {
    sources: SpeciesSourceApi[];
    description: string;
    externallink: string;
    useasdefault: boolean;
};

const update = async (s: SimpleSpecies, e: RenameEvent) => ({
    ...s,
    name: e.new,
});

const fetchSources = async (id: number): Promise<SpeciesSourceApi[]> => {
    if (id == undefined) return [];

    const res = await fetch(`../api/speciessource?speciesid=${id}`);
    if (res.status === 200) {
        return (await res.json()) as SpeciesSourceApi[];
    } else {
        console.error(await res.text());
        throw new Error('Failed to fetch sources for the selected species. Check console.');
    }
};

const SpeciesSource = ({ speciesid, allSpecies, allSources }: Props): JSX.Element => {
    const [sourcesForSpecies, setSourcesForSpecies] = useState(new Array<SpeciesSourceApi>());
    const [showNewMapping, setShowNewMapping] = useState(false);
    const [selectedSource, setSelectedSource] = useState<SpeciesSourceApi[]>([]);
    const [description, setDescription] = useState('');

    const toUpsertFields = (fields: FormFields, name: string, id: number): SpeciesSourceInsertFields => {
        const selSo = selectedSource[0];
        return {
            id: selSo?.id != undefined ? selSo.id : -1,
            species: id,
            source: selSo?.source_id != undefined ? selSo.source_id : -1,
            description: description,
            externallink: fields.externallink,
            useasdefault: fields.useasdefault,
            delete: fields.del,
        };
    };

    const updatedFormFields = async (sp: SimpleSpecies | undefined): Promise<FormFields> => {
        try {
            if (sp != undefined) {
                const sources = await fetchSources(sp.id);
                setSourcesForSpecies(sources);

                const so = defaultSource(sources);
                setSelectedSource(so ? [so] : []);

                setDescription(so?.description ?? '');

                return {
                    mainField: [sp],
                    description: so ? so.description : '',
                    externallink: so ? so.externallink : '',
                    sources: [],
                    useasdefault: so ? so.useasdefault != 0 : false,
                    del: false,
                };
            }
            setSourcesForSpecies([]);
            setSelectedSource([]);
            setDescription('');
            return {
                mainField: [],
                description: '',
                externallink: '',
                sources: [],
                useasdefault: false,
                del: false,
            };
        } catch (e) {
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            const err: any = e;
            console.error(err);
            setError(err.toString());
            return {
                mainField: sp ? [sp] : [],
                description: '',
                externallink: '',
                sources: [],
                useasdefault: false,
                del: false,
            };
        }
    };

    const buildDelQueryString = (): string => {
        return `?speciesid=${selected?.id}&sourceid=${selectedSource[0].source.id}`;
    };

    const mainFieldName = 'name';

    const { selected, setSelected, setDeleteResults, setError, ...adminForm } = useAdmin<
        SimpleSpecies,
        FormFields,
        SpeciesSourceInsertFields
    >(
        'Species-Source Mapping',
        mainFieldName,
        speciesid,
        update,
        toUpsertFields,
        {
            delEndpoint: '/api/speciessource/',
            upsertEndpoint: '/api/speciessource/insert',
            delQueryString: buildDelQueryString,
        },
        updatedFormFields,
        false,
        undefined,
        allSpecies,
    );

    const router = useRouter();

    const addMappedSource = (so: SourceApi | undefined) => {
        if (so != undefined && selected != undefined) {
            const newSpSo: SpeciesSourceApi = {
                id: -1,
                description: '',
                externallink: '',
                source: so,
                source_id: so.id,
                species_id: selected.id,
                useasdefault: 0,
            };

            const newSourcesForSpecies = [...sourcesForSpecies, newSpSo];
            setSourcesForSpecies(newSourcesForSpecies);
            setSelectedSource([newSpSo]);
            setDescription('');

            adminForm.form.setValue('sources', [newSpSo], { shouldDirty: true });
            adminForm.form.setValue('externallink', '');
            adminForm.form.setValue('useasdefault', false);
        }
        setShowNewMapping(false);
    };

    const onSubmit = async (fields: FormFields) => {
        // for now we will write a custom form submit since what admin provides is not sufficient
        // TODO - tweak the useAdmin hook to allow for more flexibility in how this works - really a useAPIs issue.
        if (selected == undefined || selectedSource.length < 1) {
            //nothing to do
            console.debug(`Did nothing in onSubmit. selected: '${selected}' | selectedSource: '${selectedSource}'`);
            return;
        }

        try {
            // DELETE
            if (fields.del) {
                const res = await fetch(`/api/speciessource?speciesid=${selected.id}&sourceid=${selectedSource[0].source_id}`, {
                    method: 'DELETE',
                });

                if (res.status === 200) {
                    setSelectedSource([]);
                    const dr = await res.json();
                    setDeleteResults(dr);
                    // kludge: postDelete makes assumptions that are not good for this screen...
                    const sp = selected;
                    adminForm.postDelete(fields.mainField[0].id, dr);
                    //... so we save the old species and re-select it after the delete
                    setSelected(sp);
                    router.replace(`?id=${sp.id}`, undefined, { shallow: true });
                    return;
                } else {
                    throw new Error(await res.text());
                }
            }

            // UPSERT
            const selSo = selectedSource[0];
            const insertData: SpeciesSourceInsertFields = {
                id: selSo.id,
                species: selected.id,
                source: selSo.source_id ?? -1,
                description: description ? description : '',
                useasdefault: fields.useasdefault,
                externallink: fields.externallink,
            };

            const res = await fetch('/api/speciessource/upsert', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(insertData),
            });

            if (res.status == 200) {
                adminForm.postUpdate(res);
                setSelectedSource([selSo]);
            } else {
                throw new Error(await res.text());
            }
        } catch (e) {
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            const err: any = e;
            console.error(err);
            setError(err.toString());
        }
    };

    return (
        <Auth>
            <Admin
                type="Speciessource"
                keyField="name"
                selected={selected}
                setError={setError}
                {...adminForm}
                deleteButton={adminForm.deleteButton('Caution. The selected Species Source mapping will be deleted.', false)}
                saveButton={adminForm.saveButton()}
                formSubmit={onSubmit}
            >
                <>
                    <h4>Map Species & Sources</h4>
                    <p>
                        First select a species. This will load any existing source mappings. You can then select one and edit the
                        mapping. If there are no existing mappings or you want to add a new source mapping to the species just
                        press the Add source mapping button.
                    </p>

                    <Picker
                        size="lg"
                        data={allSources
                            // remove the sources that are already mapped to this species
                            .filter((s) => !sourcesForSpecies.find((sourceSpecies) => sourceSpecies.source_id === s.id))
                            .sort((a, b) => sourceToDisplay(a).localeCompare(sourceToDisplay(b)))}
                        toLabel={sourceToDisplay}
                        title="Add Mapped Source"
                        placeholder="Choose a new source to map"
                        onClose={addMappedSource}
                        show={showNewMapping}
                    />

                    <Row className="my-1">
                        <Col>
                            Species:
                            {adminForm.mainField('name')}
                        </Col>
                    </Row>
                    <Row>
                        <Col xs={1} className="p-0 m-0 mx-auto">
                            <h2>⇅</h2>
                        </Col>
                    </Row>
                    <Row className="my-1">
                        <Col>
                            <Row className="my-1">
                                <Col>
                                    Mapped Source:
                                    <Typeahead
                                        id="sources"
                                        clearButton
                                        options={sourcesForSpecies}
                                        labelKey={(s) => sourceToDisplay((s as SpeciesSourceApi).source)}
                                        disabled={!selected}
                                        selected={selectedSource}
                                        {...adminForm.form.register('sources')}
                                        onChange={(s) => {
                                            if (!s || s.length <= 0) {
                                                setSelectedSource([]);
                                                setDescription('');
                                                adminForm.form.setValue('externallink', '');
                                                adminForm.form.setValue('useasdefault', false);
                                            } else {
                                                const source = s[0] as SpeciesSourceApi;
                                                setSelectedSource([source]);
                                                setDescription(source?.description ?? '');
                                                adminForm.form.setValue('externallink', source ? source.externallink : '');
                                                adminForm.form.setValue('useasdefault', source ? source.useasdefault > 0 : false);
                                            }
                                        }}
                                    />
                                    {adminForm.form.formState.errors.sources && (
                                        <span className="text-danger">You must provide a source to map.</span>
                                    )}
                                </Col>
                            </Row>
                            <Row className="my-1">
                                <Col>
                                    <Button size="sm" onClick={() => setShowNewMapping(true)} disabled={!selected}>
                                        Add New Mapped Source
                                    </Button>
                                </Col>
                            </Row>
                        </Col>
                    </Row>
                    <Row className="my-1">
                        <Col>
                            Description (this is the relevant info from the selected Source about the selected Species):
                            <Tabs defaultActiveKey="edit" className="pt-1">
                                <Tab eventKey="edit" title="Edit">
                                    <textarea
                                        {...adminForm.form.register('description', { required: true, disabled: !selected })}
                                        value={description}
                                        onChange={(d) => {
                                            setDescription(d.currentTarget.value);
                                        }}
                                        disabled={!selected}
                                        className="form-control pt-2"
                                        rows={8}
                                    />
                                </Tab>
                                <Tab eventKey="preview" title="Preview">
                                    <ReactMarkdown
                                        className="markdown-view"
                                        rehypePlugins={[rehypeRaw]}
                                        remarkPlugins={[externalLinks, remarkBreaks]}
                                    >
                                        {description}
                                    </ReactMarkdown>
                                </Tab>
                            </Tabs>
                        </Col>
                    </Row>
                    <Row className="my-1">
                        <Col>
                            Direct Link to Description Page (if available, eg at BHL or HathiTrust. Do not duplicate main
                            source-level link or link to a pdf):
                            <input
                                {...adminForm.form.register('externallink')}
                                type="text"
                                disabled={!selected}
                                className="form-control"
                            />
                        </Col>
                    </Row>
                    <Row className="my-1">
                        <Col>
                            <input
                                {...adminForm.form.register('useasdefault')}
                                type="checkbox"
                                disabled={!selected}
                                className="form-check-inline"
                            />
                            <label className="form-check-label">Use as Default?</label>
                        </Col>
                    </Row>
                    {/* <Row className="formGroup">
                        <Col>
                            <Button
                                variant="primary"
                                type="submit"
                                value="Save Changes"
                                disabled={!selected || selectedSource.length <= 0}
                            >
                                Save Changes
                            </Button>
                        </Col>
                    </Row> */}
                    <Row hidden={!selected} className="formGroup">
                        <Col>
                            <div>
                                Shortcuts:{' '}
                                {selected?.taxoncode === TaxonCodeValues.GALL ? (
                                    <Link href={`./gall?id=${selected?.id}`}>Edit the Species</Link>
                                ) : (
                                    <Link href={`./host?id=${selected?.id}`}>Edit the Species</Link>
                                )}
                                {'  |  '}
                                <Link
                                    href={`./images?speciesid=${selected?.id}`}
                                    legacyBehavior
                                >{`Add/Edit Images for this Species`}</Link>
                            </div>
                            <br />
                        </Col>
                    </Row>
                </>
            </Admin>
        </Auth>
    );
};

export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery }) => {
    const queryParam = 'id';
    const id = pipe(extractQueryParam(context.query, queryParam), O.getOrElse(constant('')));

    return {
        props: {
            speciesid: id,
            allSpecies: await mightFailWithArray<SimpleSpecies>()(allSpeciesSimple()),
            allSources: await mightFailWithArray<SourceApi>()(allSources()),
        },
    };
};

export default SpeciesSource;
