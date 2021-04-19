import { source as DBSource, species } from '@prisma/client';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import { useRouter } from 'next/router';
import { ParsedUrlQuery } from 'querystring';
import React, { useState } from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import * as yup from 'yup';
import Auth from '../../components/auth';
import { RenameEvent } from '../../components/editname';
import Picker from '../../components/picker';
import Typeahead from '../../components/Typeahead';
import useAdmin from '../../hooks/useadmin';
import { AdminFormFields } from '../../hooks/useAPIs';
import { extractQueryParam } from '../../libs/api/apipage';
import { SpeciesSourceApi, SpeciesSourceInsertFields } from '../../libs/api/apitypes';
import { allSources } from '../../libs/db/source';
import { allSpecies } from '../../libs/db/species';
import Admin from '../../libs/pages/admin';
import { defaultSource, sourceToDisplay } from '../../libs/pages/renderhelpers';
import { mightFailWithArray } from '../../libs/utils/util';

type Props = {
    speciesid: string;
    allSpecies: species[];
    allSources: DBSource[];
};

const schema = yup.object().shape({
    mainField: yup.array().required(),
    sources: yup.array().required(),
});

type FormFields = AdminFormFields<species> & {
    sources: SpeciesSourceApi[];
    description: string;
    externallink: string;
    useasdefault: boolean;
};

const update = async (s: species, e: RenameEvent) => ({
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

    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const toUpsertFields = (fields: FormFields, name: string, id: number): SpeciesSourceInsertFields => {
        const selSo = selectedSource[0];
        return {
            id: selSo?.id != undefined ? selSo.id : -1,
            species: id,
            source: selSo?.source_id != undefined ? selSo.source_id : -1,
            description: fields.description,
            externallink: fields.externallink,
            useasdefault: fields.useasdefault,
            delete: fields.del,
        };
    };

    const updatedFormFields = async (sp: species | undefined): Promise<FormFields> => {
        try {
            if (sp != undefined) {
                const sources = await fetchSources(sp.id);
                setSourcesForSpecies(sources);

                const so = defaultSource(sources);
                setSelectedSource(so ? [so] : []);

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
            return {
                mainField: [],
                description: '',
                externallink: '',
                sources: [],
                useasdefault: false,
                del: false,
            };
        } catch (e) {
            console.error(e);
            setError(e);
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

    // eslint-disable-next-line prettier/prettier
    const {
        selected,
        setSelected,
        error,
        setError,
        deleteResults,
        setDeleteResults,
        form,
        postUpdate,
        postDelete,
        mainField,
        deleteButton,
    } = useAdmin<species, FormFields, SpeciesSourceInsertFields>(
        'Species-Source Mapping',
        speciesid,
        allSpecies,
        update,
        toUpsertFields,
        {
            keyProp: 'name',
            delEndpoint: '../api/speciessource/',
            upsertEndpoint: '../api/speciessource/insert',
            delQueryString: buildDelQueryString,
        },
        schema,
        updatedFormFields,
    );

    const router = useRouter();

    const addMappedSource = (so: DBSource | undefined) => {
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

            form.setValue('sources', [newSpSo], { shouldDirty: true });
            form.setValue('description', '');
            form.setValue('externallink', '');
            form.setValue('useasdefault', false);
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
                const res = await fetch(`../api/speciessource?speciesid=${selected.id}&sourceid=${selectedSource[0].source_id}`, {
                    method: 'DELETE',
                });

                if (res.status === 200) {
                    setSelectedSource([]);
                    const dr = await res.json();
                    setDeleteResults(dr);
                    // kludge: postDelete makes assumptions that are not good for this screen...
                    const sp = selected;
                    postDelete(fields.mainField[0].id, dr);
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
                source: selSo.source_id,
                description: fields.description ? fields.description : '',
                useasdefault: fields.useasdefault,
                externallink: fields.externallink,
            };

            const res = await fetch('../api/speciessource/upsert', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(insertData),
            });

            if (res.status == 200) {
                postUpdate(res);
                setSelectedSource([selSo]);
            } else {
                throw new Error(await res.text());
            }
        } catch (e) {
            console.error(e);
            setError(e);
        }
    };

    return (
        <Auth>
            <Admin
                type="Species & Source Mappings"
                keyField="name"
                setError={setError}
                error={error}
                setDeleteResults={setDeleteResults}
                deleteResults={deleteResults}
                selected={selected}
            >
                <form onSubmit={form.handleSubmit(onSubmit)} className="m-4 pr-4">
                    <h4>Map Species & Sources</h4>
                    <p>
                        First select a species. This will load any existing source mappings. You can then select one and edit the
                        mapping. If there are no existing mappings or you want to add a new source mapping to the species just
                        press the Add source mapping button. If you want to delete a Source-
                    </p>

                    <Picker
                        size="lg"
                        data={allSources.sort((a, b) => sourceToDisplay(a).localeCompare(sourceToDisplay(b)))}
                        toLabel={sourceToDisplay}
                        title="Add Mapped Source"
                        placeholder="Choose a new source to map"
                        onClose={addMappedSource}
                        show={showNewMapping}
                    />

                    <Row className="form-group">
                        <Col>
                            Species:
                            {mainField('name', 'Species')}
                        </Col>
                    </Row>
                    <Row>
                        <Col xs={1} className="p-0 m-0 mx-auto">
                            <h2>⇅</h2>
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            <Row className="form-group">
                                <Col>
                                    Mapped Source:
                                    <Typeahead
                                        name="sources"
                                        control={form.control}
                                        clearButton
                                        options={sourcesForSpecies}
                                        labelKey={(s) => sourceToDisplay(s.source)}
                                        disabled={!selected}
                                        selected={selectedSource}
                                        onChange={(s) => {
                                            setSelectedSource(s);
                                            form.setValue('description', s[0] ? s[0].description : '');
                                            form.setValue('externallink', s[0] ? s[0].externallink : '');
                                            form.setValue('useasdefault', s[0] ? s[0].useasdefault > 0 : false);
                                        }}
                                    />
                                    {form.formState.errors.sources && (
                                        <span className="text-danger">You must provide a source to map.</span>
                                    )}
                                </Col>
                            </Row>
                            <Row className="form-group">
                                <Col>
                                    <Button onClick={() => setShowNewMapping(true)} disabled={!selected}>
                                        Add New Mapped Source
                                    </Button>
                                </Col>
                            </Row>
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            Description (this is the relevant info from the selected Source about the selected Species):
                            <textarea {...form.register('description')} disabled={!selected} className="form-control" rows={8} />
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            Direct Link to Description Page (if available, eg at BHL or HathiTrust. Do not duplicate main
                            source-level link or link to a pdf):
                            <input {...form.register('externallink')} type="text" disabled={!selected} className="form-control" />
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            <input
                                {...form.register('useasdefault')}
                                type="checkbox"
                                disabled={!selected}
                                className="form-check-inline"
                            />
                            <label className="form-check-label">Use as Default?</label>
                        </Col>
                    </Row>
                    <Row className="formGroup">
                        <Col>
                            <input
                                type="submit"
                                className="button"
                                value="Submit"
                                disabled={!selected || selectedSource.length <= 0}
                            />
                        </Col>
                        <Col>{deleteButton('Caution. The selected Species Source mapping will be deleted.', onSubmit)}</Col>
                    </Row>
                </form>
            </Admin>
        </Auth>
    );
};

export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery }) => {
    const queryParam = 'id';
    // eslint-disable-next-line prettier/prettier
    const id = pipe(
        extractQueryParam(context.query, queryParam),
        O.getOrElse(constant('')),
    );

    return {
        props: {
            speciesid: id,
            allSpecies: await mightFailWithArray<species>()(allSpecies()),
            allSources: await mightFailWithArray<DBSource>()(allSources()),
        },
    };
};

export default SpeciesSource;
