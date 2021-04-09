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
import ControlledTypeahead from '../../components/controlledtypeahead';
import Picker from '../../components/picker';
import useAdmin from '../../hooks/useadmin';
import { AdminFormFields } from '../../hooks/useAPIs';
import { extractQueryParam } from '../../libs/api/apipage';
import { SpeciesSourceApi, SpeciesSourceInsertFields } from '../../libs/api/apitypes';
import { allSources } from '../../libs/db/source';
import { allSpecies } from '../../libs/db/species';
import Admin from '../../libs/pages/admin';
import { sourceToDisplay } from '../../libs/pages/renderhelpers';
import { mightFailWithArray } from '../../libs/utils/util';

type Props = {
    speciesid: string;
    allSpecies: species[];
    allSources: DBSource[];
};

const schema = yup.object().shape({
    value: yup.string().required(),
    source: yup.string().required(),
});

type FormFields = AdminFormFields<species> & {
    sources: SpeciesSourceApi[];
    description: string;
    externallink: string;
    useasdefault: boolean;
};

const update = (s: species, newValue: string) => ({
    ...s,
    name: newValue,
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
    const [selectedSource, setSelectedSource] = useState<SpeciesSourceApi>();

    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const toUpsertFields = (fields: FormFields, name: string, id: number): SpeciesSourceInsertFields => {
        return {
            id: selectedSource?.id != undefined ? selectedSource.id : -1,
            species: id,
            source: selectedSource?.source_id != undefined ? selectedSource.source_id : -1,
            description: fields.description,
            externallink: fields.externallink,
            useasdefault: fields.useasdefault,
            delete: fields.del,
        };
    };

    const fieldsFor = (sp: species, so: SpeciesSourceApi | undefined): FormFields => {
        return {
            mainField: [sp],
            description: so ? so.description : '',
            externallink: so ? so.externallink : '',
            sources: sourcesForSpecies,
            useasdefault: so ? so.useasdefault != 0 : false,
            del: false,
        };
    };

    const updatedFormFields = async (sp: species | undefined): Promise<FormFields> => {
        try {
            if (sp != undefined) {
                const sources = await fetchSources(sp.id);
                setSourcesForSpecies(sources);
                // go ahead and select the 1st source
                const firstSource = sources[0];
                setSelectedSource(firstSource);

                return fieldsFor(sp, firstSource);
            }
            setSourcesForSpecies([]);
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

    // eslint-disable-next-line prettier/prettier
    const {
        data,
        selected,
        setSelected,
        error,
        setError,
        deleteResults,
        setDeleteResults,
        form,
        postUpdate,
        postDelete,
    } = useAdmin<species, FormFields, SpeciesSourceInsertFields>(
        'Species-Source Mapping',
        speciesid,
        allSpecies,
        update,
        toUpsertFields,
        { keyProp: 'name', delEndpoint: '../api/speciessource/', upsertEndpoint: '../api/speciessource/insert' },
        schema,
        updatedFormFields,
    );

    const router = useRouter();

    const onSourceChange = async (sp: species | undefined, soid: string | null) => {
        if (sp != undefined && soid != null) {
            const spso = sourcesForSpecies.find((s) => s.source_id == parseInt(soid));
            if (spso == undefined) {
                setSelectedSource(undefined);
                throw new Error('Missing mapping for selected source.');
            }

            setSelectedSource(spso);
            form.setValue('description', spso.description);
            form.setValue('externallink', spso.externallink);
            form.setValue('useasdefault', spso.useasdefault > 0);
        }
    };

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
            setSelectedSource(newSpSo);

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
        if (selected == undefined || selectedSource == undefined) {
            //nothing to do
            return;
        }

        try {
            // DELETE
            if (fields.del) {
                const res = await fetch(`../api/speciessource?speciesid=${selected.id}&sourceid=${selectedSource.source_id}`, {
                    method: 'DELETE',
                });

                if (res.status === 200) {
                    setSelectedSource(undefined);
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
            const insertData: SpeciesSourceInsertFields = {
                id: selectedSource.id,
                species: selected.id,
                source: selectedSource.source_id,
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
                            <ControlledTypeahead
                                control={form.control}
                                name="value"
                                placeholder="Species"
                                options={data}
                                labelKey="name"
                                isInvalid={!!form.errors.value}
                                onChange={(s) => {
                                    if (s.length > 0) {
                                        setSelected(s[0]);
                                        router.replace(`?id=${s[0].id}`, undefined, { shallow: true });
                                    } else {
                                        setSelected(undefined);
                                        router.replace(``, undefined, { shallow: true });
                                    }
                                }}
                                clearButton
                            />
                            {form.errors.value && (
                                <span className="text-danger">You must provide a species or genus to map.</span>
                            )}
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
                                    <select
                                        name="source"
                                        disabled={!selected}
                                        onChange={(s) =>
                                            onSourceChange(
                                                selected,
                                                s.currentTarget.options[s.currentTarget.options.selectedIndex].getAttribute(
                                                    'data-key',
                                                ),
                                            )
                                        }
                                        className="form-control"
                                        ref={form.register}
                                    >
                                        {sourcesForSpecies
                                            .sort((a, b) => a.source.pubyear.localeCompare(b.source.pubyear))
                                            .map((s) => (
                                                <option key={s.source_id} data-key={s.source_id}>
                                                    {sourceToDisplay(s.source)}
                                                </option>
                                            ))}
                                    </select>
                                    {form.errors.sources && (
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
                            <textarea
                                name="description"
                                disabled={!selected}
                                className="form-control"
                                ref={form.register}
                                rows={8}
                            />
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            Direct Link to Description Page (if available, eg at BHL or HathiTrust. Do not duplicate main
                            source-level link or link to a pdf):
                            <input
                                type="text"
                                disabled={!selected}
                                name="externallink"
                                className="form-control"
                                ref={form.register}
                            />
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            <input
                                type="checkbox"
                                name="useasdefault"
                                disabled={!selected}
                                className="form-check-inline"
                                ref={form.register}
                            />
                            <label className="form-check-label">Use as Default?</label>
                        </Col>
                    </Row>
                    <Row className="fromGroup" hidden={!selected}>
                        <Col xs="1">Delete?:</Col>
                        <Col className="mr-auto">
                            <input name="del" type="checkbox" className="form-check-input" ref={form.register} />
                        </Col>
                    </Row>
                    <Row className="formGroup">
                        <Col>
                            <input type="submit" className="button" value="Submit" disabled={!selected} />
                        </Col>
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
