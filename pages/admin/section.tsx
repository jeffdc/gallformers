import { yupResolver } from '@hookform/resolvers/yup';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Head from 'next/head';
import { useRouter } from 'next/router';
import { ParsedUrlQuery } from 'querystring';
import React, { useCallback, useEffect, useState } from 'react';
import { Alert, Col, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import Auth from '../../components/auth';
import ControlledTypeahead from '../../components/controlledtypeahead';
import { AdminFormFields, useAPIs } from '../../hooks/useAPIs';
import { extractQueryParam } from '../../libs/api/apipage';
import { DeleteResult, SimpleSpecies } from '../../libs/api/apitypes';
import { TaxonomyEntry, TaxonomyUpsertFields } from '../../libs/api/taxonomy';
import { allSpeciesSimple } from '../../libs/db/species';
import { allSections, getAllSpeciesForSection } from '../../libs/db/taxonomy';
import { mightFailWithArray } from '../../libs/utils/util';

const Schema = yup.object().shape({
    value: yup.mixed().required(),
    description: yup.string().required(),
});

type Props = {
    id: string;
    sectSpecies: SimpleSpecies[];
    sections: TaxonomyEntry[];
    species: SimpleSpecies[];
};

type FormFields = AdminFormFields<TaxonomyEntry> & Omit<TaxonomyEntry, 'id' | 'name'>;

const Section = ({ id, sectSpecies, sections, species }: Props): JSX.Element => {
    if (!sections) throw new Error(`The input props for families can not be null or undefined.`);
    const [secs, setSecs] = useState(sections);
    const [error, setError] = useState('');
    const [existingId, setExistingId] = useState<number | undefined>(id && id !== '' ? parseInt(id) : undefined);
    const [deleteResults, setDeleteResults] = useState<DeleteResult>();

    const { register, handleSubmit, errors, control, reset } = useForm<FormFields>({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });

    const router = useRouter();

    const onSectionChange = useCallback(
        (id: number | undefined) => {
            if (id == undefined) {
                reset({
                    value: [],
                    description: '',
                });
            } else {
                try {
                    const sec = secs.find((f) => f.id === id);
                    if (sec == undefined) {
                        throw new Error(`Somehow we have a section selection that does not exist?! sectionid: ${id}`);
                    }
                    reset({
                        value: [sec],
                        species: sectSpecies,
                        description: sec.description,
                    });
                } catch (e) {
                    setError(e);
                    console.error(e);
                }
            }
        },
        [secs, reset],
    );

    useEffect(() => {
        onSectionChange(existingId);
    }, [existingId, onSectionChange]);

    const { doDeleteOrUpsert } = useAPIs<TaxonomyEntry, TaxonomyUpsertFields>('name', '../api/section/', '../api/section/upsert');

    const onSubmit = async (data: FormFields) => {
        const postDelete = (id: number | string, result: DeleteResult) => {
            setSecs(secs.filter((s) => s.id !== id));
            setDeleteResults(result);
        };

        const postUpdate = (res: Response) => {
            router.push(res.url);
        };

        // eslint-disable-next-line @typescript-eslint/no-unused-vars
        const convertFormFieldsToUpsert = (fields: FormFields, name: string, id: number): TaxonomyUpsertFields => ({
            ...fields,
            name: name,
            type: 'section',
            id: typeof fields.value[0].id === 'number' ? fields.value[0].id : parseInt(fields.value[0].id),
        });

        await doDeleteOrUpsert(data, postDelete, postUpdate, convertFormFieldsToUpsert)
            .then(() => reset())
            .catch((e: unknown) => setError(`Failed to save changes. ${e}.`));
    };

    return (
        <Auth>
            <>
                <Head>
                    <title>Add/Edit Sections</title>
                </Head>

                {error.length > 0 && (
                    <Alert variant="danger" onClose={() => setError('')} dismissible>
                        <Alert.Heading>Uh-oh</Alert.Heading>
                        <p>{error}</p>
                    </Alert>
                )}

                <form onSubmit={handleSubmit(onSubmit)} className="m-4 pr-4">
                    <h4>Add or Edit a Section</h4>
                    <Row className="form-group">
                        <Col>
                            Name:
                            <ControlledTypeahead
                                control={control}
                                name="value"
                                placeholder="Name"
                                options={secs}
                                labelKey="name"
                                clearButton
                                isInvalid={!!errors.value}
                                newSelectionPrefix="Add a new Section: "
                                allowNew={true}
                                onChangeWithNew={(e, isNew) => {
                                    if (isNew || !e[0]) {
                                        setExistingId(undefined);
                                        router.replace(``, undefined, { shallow: true });
                                    } else {
                                        setExistingId(e[0].id);
                                        router.replace(`?id=${e[0].id}`, undefined, { shallow: true });
                                    }
                                }}
                            />
                            {errors.value && <span className="text-danger">The Name is required.</span>}
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            Description:
                            <textarea name="description" className="form-control" ref={register} rows={1} />
                        </Col>
                    </Row>
                    <Row className="form-group">
                        <Col>
                            Species:
                            <ControlledTypeahead
                                control={control}
                                name="species"
                                placeholder="Mapped Species"
                                options={species}
                                labelKey="name"
                                clearButton
                                multiple
                            />
                        </Col>
                    </Row>
                    <Row className="fromGroup" hidden={!existingId}>
                        <Col xs="1">Delete?:</Col>
                        <Col className="mr-auto">
                            <input name="del" type="checkbox" className="form-check-input" ref={register} />
                        </Col>
                    </Row>
                    <Row className="form-input">
                        <Col>
                            <input type="submit" className="button" value="Submit" />
                        </Col>
                    </Row>
                    <Row hidden={!deleteResults}>
                        <Col>{`Deleted ${deleteResults?.name}.`}</Col>☹️
                    </Row>
                </form>
            </>
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
            id: id,
            sectSpecies: await mightFailWithArray<SimpleSpecies>()(getAllSpeciesForSection(parseInt(id))),
            sections: await mightFailWithArray<TaxonomyEntry>()(allSections()),
            species: await mightFailWithArray<SimpleSpecies>()(allSpeciesSimple()),
        },
    };
};
export default Section;
