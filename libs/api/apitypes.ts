/**
 * Types for calling the APIs. These are to be used by browser code when it calls the APIs so all database stuff
 * must stay out of here.
 */
import * as Eq from 'fp-ts/lib/Eq.js';
import * as O from 'fp-ts/lib/Option.js';
import { Option } from 'fp-ts/lib/Option.js';
import * as t from 'io-ts';
import * as tt from 'io-ts-types';
import { fromEnum } from '../utils/io-ts.js';

export type Deletable = {
    delete?: boolean;
};

export const GALL_FAMILY_TYPES = [
    'Aphid',
    'Bacteria',
    'Beetle',
    'Fly',
    'Fungus',
    'Midge',
    'Mite',
    'Moth',
    'Nematode',
    'Oomycete',
    'Psyllid',
    'Sawfly',
    'Scale',
    'Thrips',
    'True Bug',
    'Virus',
    'Wasp',
    'Unknown',
] as const;
export const HOST_FAMILY_TYPES = ['Plant'] as const;
export const ALL_FAMILY_TYPES = [
    'Aphid',
    'Bacteria',
    'Beetle',
    'Fly',
    'Fungus',
    'Midge',
    'Mite',
    'Moth',
    'Nematode',
    'Oomycete',
    'Plant',
    'Psyllid',
    'Sawfly',
    'Scale',
    'Thrips',
    'True Bug',
    'Virus',
    'Wasp',
    'Unknown',
] as const;
export type FamilyTypesTuple = typeof ALL_FAMILY_TYPES;
export type FamilyType = FamilyTypesTuple[number];
export type FamilyGallTypesTuples = typeof GALL_FAMILY_TYPES;
export type FamilyGallType = FamilyGallTypesTuples[number];
export type FamilyHostTypesTuple = typeof HOST_FAMILY_TYPES;
export type FamilyHostType = FamilyHostTypesTuple[number];

export type SpeciesUpsertFields = {
    id: number;
    name: string;
    datacomplete: boolean;
    aliases: AliasApi[];
    abundance: string | null | undefined;
    fgs: FGS;
    places: PlaceNoTreeApi[];
};

export type GallUpsertFields = SpeciesUpsertFields & {
    gallid: number; // if less than 0 then new
    hosts: number[];
    locations: number[];
    colors: number[];
    seasons: number[];
    shapes: number[];
    textures: number[];
    alignments: number[];
    walls: number[];
    cells: number[];
    forms: number[];
    detachable: DetachableValues;
    undescribed: boolean;
};

export type AbundanceApi = {
    id: number;
    abundance: string;
    description: string;
    reference: Option<string>;
};
export const AbundanceApiSchema = t.type({
    id: t.number,
    abundance: t.string,
    description: t.string,
    reference: tt.option(t.string),
});

export const EmptyAbundance: AbundanceApi = {
    id: -1,
    abundance: '',
    description: '',
    reference: O.none,
};

////////////////////////////////////////////////////////////////////
// Place Schemas and Types

// For now only these two until we support the Place hierarchy.
export const PLACE_TYPES = ['state', 'province'];

export const placeNoTreeApiEq: Eq.Eq<PlaceNoTreeApi> = {
    equals: (a, b) => a.code === b.code,
};

export const PlaceNoTreeApiSchema = t.type({
    id: t.number,
    name: t.string,
    code: t.string,
    type: t.string,
});

export type PlaceNoTreeApi = t.TypeOf<typeof PlaceNoTreeApiSchema>;
// export type PlaceNoTreeApi = {
//     id: number;
//     name: string;
//     code: string;
//     type: string;
// };

export type PlaceNoTreeUpsertFields = PlaceNoTreeApi & Deletable;

export type PlaceApi = PlaceNoTreeApi & {
    parent: PlaceApi[];
    children: PlaceApi[];
};

export type PlaceWithHostsApi = PlaceApi & {
    hosts: HostSimple[];
};

////////////////////////////////////////////////////////////////////
// SimpleSpecies Schema and Type
export enum TaxonCodeValues {
    GALL = 'gall',
    PLANT = 'plant',
}
export const TaxonCodeSchema = fromEnum<TaxonCodeValues>('TaxonCodeValues', TaxonCodeValues);
/** Given a string value, look up the proper TaxonCode. If the value is not one of the valid values then an error will be thrown. */
export const taxonCodeAsStringToValue = (tc?: string | null): TaxonCodeValues => {
    if (tc === TaxonCodeValues.GALL) {
        return TaxonCodeValues.GALL;
    } else if (tc === TaxonCodeValues.PLANT) {
        return TaxonCodeValues.PLANT;
    } else {
        throw new Error(`Invalid TaxonCode value detected: '${tc}'.`);
    }
};

export const SimpleSpeciesSchema = t.type({
    id: t.number,
    taxoncode: TaxonCodeSchema,
    name: t.string, //.matches(SPECIES_NAME_REGEX).required(),
});
export type SimpleSpecies = t.TypeOf<typeof SimpleSpeciesSchema>;

////////////////////////////////////////////////////////////////////
// Source Schemas and Types
export const SourceApiSchema = t.type({
    id: t.number,
    title: t.string,
    author: t.string,
    pubyear: t.string,
    link: t.string,
    citation: t.string,
    datacomplete: t.boolean,
    license: t.string,
    licenselink: t.string,
});

export type SourceApi = t.TypeOf<typeof SourceApiSchema>;

// export type SourceApi = {
//     id: number;
//     title: string;
//     author: string;
//     pubyear: string;
//     link: string;
//     citation: string;
//     datacomplete: boolean;
//     license: string;
//     licenselink: string;
// };
export const SpeciesSourceNoSourceApiSchema = t.type({
    id: t.number,
    species_id: t.number,
    source_id: t.number,
    description: t.string,
    useasdefault: t.number,
    externallink: t.string,
});
export type SpeciesSourceNoSourceApi = t.TypeOf<typeof SpeciesSourceNoSourceApiSchema>;

export const SpeciesSourceApiSchema = t.intersection([SpeciesSourceNoSourceApiSchema, t.type({ source: SourceApiSchema })]);
export type SpeciesSourceApi = t.TypeOf<typeof SpeciesSourceApiSchema>;

export const SourceWithSpeciesApiSchema = t.intersection([SourceApiSchema, t.type({ species: t.array(SimpleSpeciesSchema) })]);
export type SourceWithSpeciesApi = t.TypeOf<typeof SourceWithSpeciesApiSchema>;
// export type SourceWithSpeciesApi = SourceApi & {
//     species: SimpleSpecies[];
// };

export const SourceWithSpeciesSourceApiSchema = t.intersection([
    SourceApiSchema,
    t.type({ speciessource: t.array(SpeciesSourceNoSourceApiSchema) }),
]);
export type SourceWithSpeciesSourceApi = t.TypeOf<typeof SourceWithSpeciesSourceApiSchema>;
// export type SourceWithSpeciesSourceApi = SourceApi & {
//     speciessource: Omit<SpeciesSourceApi, 'source'>[];
// };

////////////////////////////////////////////////////////////////////
// SpeciesSource Schemas and Types

// export type SpeciesSourceApi = {
//     id: number;
//     species_id: number;
//     source_id: number;
//     description: string;
//     useasdefault: number;
//     externallink: string;
//     source: SourceApi;
// };

export const SpeciesWithPlacesSchema = t.intersection([SimpleSpeciesSchema, t.type({ places: t.array(PlaceNoTreeApiSchema) })]);

export type SpeciesWithPlaces = SimpleSpecies & {
    places: PlaceNoTreeApi[];
};

// const Schema = yup.object().shape({
//     default: yup.boolean().required(),
//     creator: yup.string().required('You must provide a reference to the creator.'),
//     attribution: yup.string().when('license', {
//         is: (l: string) => l === ALLRIGHTS,
//         then: () =>
//             yup
//                 .string()
//                 .required(
//                     'You must document proof that we are allowed to use the image when using an All Rights Reserved license.',
//                 ),
//     }),
//     sourcelink: yup
//         .string()
//         .url()
//         .when('source', {
//             is: (s: []) => s.length === 0,
//             then: () => yup.string().required('You must provide a link to the source.'),
//         }),
//     source: yup.array<SourceWithSpeciesSourceApi>().required(),
//     license: yup.string<LicenseType>().required('You must select a license.'),
//     licenselink: yup
//         .string()
//         .url()
//         .when('license', {
//             is: (l: string) => l === CCBY,
//             then: () => yup.string().url().required('The CC-BY license requires that you provide a link to the license.'),
//         }),
//     caption: yup.string().required(),
// });

////////////////////////////////////////////////////////////////////////////////
// Taxonomy Types
/**
 * There are three valid types in the taxonomy.
 */
export enum TaxonomyTypeValues {
    FAMILY = 'family',
    SECTION = 'section',
    GENUS = 'genus',
}
export const TaxonomyTypeSchema = fromEnum<TaxonomyTypeValues>('TaxonomyTypeValues', TaxonomyTypeValues);
export type TaxonomyType = t.TypeOf<typeof TaxonomyTypeSchema>;
/**
 * A general Taxonomy entry from the database. It can be recursive and this can lead to trouble with certain libraries etc.
 * So look at @see {TaxonomyEntryNoParent} as well.
 */
export interface TaxonomyEntry {
    id: number;
    name: string;
    type: TaxonomyType;
    description: string;
    parent: O.Option<TaxonomyEntry>;
}
export const TaxonomyEntrySchema: t.Type<TaxonomyEntry> = t.recursion('TaxonomyEntry', () =>
    t.type({
        id: t.number,
        name: t.string,
        type: TaxonomyTypeSchema,
        description: t.string,
        parent: tt.option(TaxonomyEntrySchema),
    }),
);

export const TaxonomyEntryNoParentSchema = t.type({
    id: t.number,
    name: t.string,
    type: TaxonomyTypeSchema,
    description: t.string,
});
export type TaxonomyEntryNoParent = t.TypeOf<typeof TaxonomyEntryNoParentSchema>;

export const EMPTY_TAXONOMYENTRY: TaxonomyEntry = {
    description: '',
    id: -1,
    name: '',
    type: TaxonomyTypeValues.FAMILY,
    parent: O.none,
};

export const EMPTY_GENUS: TaxonomyEntry = { ...EMPTY_TAXONOMYENTRY, type: TaxonomyTypeValues.GENUS };

export const FGSSchema = t.type({
    family: TaxonomyEntrySchema,
    genus: TaxonomyEntrySchema,
    section: tt.option(TaxonomyEntrySchema),
});
export type FGS = t.TypeOf<typeof FGSSchema>;

export const GenusSchema = TaxonomyEntryNoParentSchema;
export type Genus = TaxonomyEntryNoParent;

export const FamilyAPISchema = t.intersection([TaxonomyEntryNoParentSchema, t.type({ genera: t.array(GenusSchema) })]);
export type FamilyAPI = TaxonomyEntryNoParent & {
    genera: Genus[];
};

export type SectionApi = Omit<TaxonomyEntryNoParent, 'type'> & {
    species: SimpleSpecies[];
    aliases: AliasApi[];
};
/**
 * The id should be set to any number less than 0 to indicate a new record.
 */

export type TaxonomyUpsertFields = TaxonomyEntry & {
    species: number[];
};

export type FamilyUpsertFields = Omit<TaxonomyUpsertFields, 'species' | 'parent'> & {
    genera: Genus[];
};

export type GeneraMoveFields = {
    oldFamilyId: number;
    newFamilyId: number;
    genera: number[];
};

////////////////////////////////////////////////////////////////////////////////////
// Image types
export const ImageBaseSchema = t.type({
    default: t.boolean,
    creator: tt.withMessage(t.string, () => 'You must provide a reference to the creator.'),
    attribution: t.string, // if license is ALLRIGHTS must fill in
    caption: t.string,
});
export type ImageBase = t.TypeOf<typeof ImageBaseSchema>;

export enum ImageLicenseValues {
    NONE = '',
    PUBLIC_DOMAIN = 'Public Domain / CC0',
    CC_BY = 'CC-BY',
    ALL_RIGHTS = 'All Rights Reserved',
}
export const ImageLicenseValuesSchema = fromEnum<ImageLicenseValues>('ImageLicenseValues', ImageLicenseValues);
export type ImageLicenseValuesType = t.TypeOf<typeof ImageLicenseValuesSchema>;

export const ImageSourceSchema = t.type({
    license: tt.withMessage(ImageLicenseValuesSchema, () => 'You must select a license.'),
    licenselink: t.string, // if license CCBY must provide a link to it
    sourcelink: t.string, // if source selected then must provide a link to it
    source: tt.option(SourceWithSpeciesSourceApiSchema),
});
export type ImageSource = t.TypeOf<typeof ImageSourceSchema>;

export const ImageAdditionalSchema = t.type({
    id: t.number,
    path: t.string,
    uploader: t.string,
    lastchangedby: t.string,
    speciesid: t.number,
    small: t.string,
    medium: t.string,
    large: t.string,
    xlarge: t.string,
    original: t.string,
});
export type ImageAdditional = t.TypeOf<typeof ImageAdditionalSchema>;

export const ImageNoSourceApiSchema = t.intersection([ImageBaseSchema, ImageAdditionalSchema]);
export type ImageNoSourceApi = t.TypeOf<typeof ImageNoSourceApiSchema>;

export const ImageApiSchema = t.intersection([ImageNoSourceApiSchema, ImageSourceSchema]);
export type ImageApi = t.TypeOf<typeof ImageApiSchema>;

export type ImagePaths = {
    small: string[];
    medium: string[];
    large: string[];
    xlarge: string[];
    original: string[];
};

export const WithImagesSchema = t.type({
    images: t.array(t.union([ImageApiSchema, ImageNoSourceApiSchema])),
});
export type WithImages = t.TypeOf<typeof WithImagesSchema>;
// export type WithImages = {
//     images: ImageApi[] | ImageNoSourceApi[];
// };

export const COMMON_NAME = 'common';
export const SCIENTIFIC_NAME = 'scientific';

export const AliasApiSchema = t.type({
    id: t.number,
    name: t.string,
    type: t.string,
    description: t.string,
});

export type AliasApi = t.TypeOf<typeof AliasApiSchema>;

// export type AliasApi = {
//     id: number;
//     name: string;
//     type: string;
//     description: string;
// };

export const EmptyAlias: AliasApi = {
    id: -1,
    name: '',
    type: SCIENTIFIC_NAME,
    description: '',
};

export const SpeciesApiSchema = t.intersection([
    SimpleSpeciesSchema,
    WithImagesSchema,
    t.type({
        datacomplete: t.boolean,
        abundance: tt.option(AbundanceApiSchema),
        description: tt.option(t.string),
        speciessource: t.array(SpeciesSourceApiSchema),
        aliases: t.array(AliasApiSchema),
        fgs: FGSSchema,
    }),
]);

export type SpeciesApi = t.TypeOf<typeof SpeciesApiSchema>;
// export type SpeciesApi = SimpleSpecies &
//     WithImages & {
//         datacomplete: boolean;
//         abundance: Option<AbundanceApi>;
//         description: Option<string>; // to make the caller's life easier we will load the default if we can
//         speciessource: SpeciesSourceApi[];
//         aliases: AliasApi[];
//         fgs: FGS;
//     };

// export const FILTER_FIELD_ALIGNMENTS = 'alignments';
// export const FILTER_FIELD_CELLS = 'cells';
// export const FILTER_FIELD_COLORS = 'colors';
// export const FILTER_FIELD_FORMS = 'forms';
// export const FILTER_FIELD_LOCATIONS = 'locations';
// export const FILTER_FIELD_SEASONS = 'seasons';
// export const FILTER_FIELD_SHAPES = 'shapes';
// export const FILTER_FIELD_TEXTURES = 'textures';
// export const FILTER_FIELD_WALLS = 'walls';
// export const FILTER_FIELD_TYPES = [
//     FILTER_FIELD_ALIGNMENTS,
//     FILTER_FIELD_CELLS,
//     FILTER_FIELD_COLORS,
//     FILTER_FIELD_FORMS,
//     FILTER_FIELD_LOCATIONS,
//     FILTER_FIELD_SEASONS,
//     FILTER_FIELD_SHAPES,
//     FILTER_FIELD_TEXTURES,
//     FILTER_FIELD_WALLS,
// ] as const;
// export type FilterFieldTypeTuple = typeof FILTER_FIELD_TYPES;
// export type FilterFieldType = FilterFieldTypeTuple[number];
// export const asFilterFieldType = (f: string): FilterFieldType => {
//     // Seems like there should be a better way to handle this and maintain types.
//     switch (f) {
//         case FILTER_FIELD_ALIGNMENTS:
//             return FILTER_FIELD_ALIGNMENTS;
//         case FILTER_FIELD_CELLS:
//             return FILTER_FIELD_CELLS;
//         case FILTER_FIELD_COLORS:
//             return FILTER_FIELD_COLORS;
//         case FILTER_FIELD_FORMS:
//             return FILTER_FIELD_FORMS;
//         case FILTER_FIELD_LOCATIONS:
//             return FILTER_FIELD_LOCATIONS;
//         case FILTER_FIELD_SEASONS:
//             return FILTER_FIELD_SEASONS;
//         case FILTER_FIELD_SHAPES:
//             return FILTER_FIELD_SHAPES;
//         case FILTER_FIELD_TEXTURES:
//             return FILTER_FIELD_TEXTURES;
//         case FILTER_FIELD_WALLS:
//             return FILTER_FIELD_WALLS;
//         default:
//             throw new Error(`Invalid filter field type: '${f}'.`);
//     }
// };

export const FilterFieldSchema = t.type({
    id: t.number,
    field: t.string,
    description: tt.option(t.string),
});

export type FilterField = t.TypeOf<typeof FilterFieldSchema>;

export enum FilterFieldTypeValue {
    ALIGNMENTS = 'alignments',
    CELLS = 'cells',
    COLORS = 'colors',
    FORMS = 'forms',
    LOCATIONS = 'locations',
    SEASONS = 'seasons',
    SHAPES = 'shapes',
    TEXTURES = 'textures',
    WALLS = 'walls',
}
export const FilterFieldTypeSchema = fromEnum<FilterFieldTypeValue>('FilterFieldTypeValue', FilterFieldTypeValue);
// export type FilterFieldType = t.TypeOf<typeof FilterFieldTypeSchema>;
export const asFilterType = (possibleFilterType?: string | null): FilterFieldTypeValue =>
    FilterFieldTypeValue[possibleFilterType?.toUpperCase() as keyof typeof FilterFieldTypeValue];

export const FilterFieldWithTypeSchema = t.intersection([FilterFieldSchema, t.type({ fieldType: FilterFieldTypeSchema })]);

export type FilterFieldWithType = t.TypeOf<typeof FilterFieldWithTypeSchema>;

// export type FilterFieldWithType = FilterField & {
//     fieldType: FilterFieldType;
// };

export const GallHostSchema = t.type({
    id: t.number,
    name: t.string,
    places: t.array(PlaceNoTreeApiSchema),
});
export type GallHost = t.TypeOf<typeof GallHostSchema>;

// export type GallHost = {
//     id: number;
//     name: string;
//     places: PlaceNoTreeApi[];
// };

export type RandomGall = {
    id: number;
    name: string;
    undescribed: boolean;
    imagePath: string;
    creator: string;
    license: string;
    sourceLink: string;
    licenseLink: string;
};

// a cut down structure for the ID page
export type GallIDApi = WithImages & {
    id: number;
    name: string;
    datacomplete: boolean;
    alignments: string[];
    cells: string[];
    colors: string[];
    detachable: DetachableApi;
    forms: string[];
    locations: string[];
    places: string[];
    seasons: string[];
    shapes: string[];
    textures: string[];
    undescribed: boolean;
    walls: string[];
    family: string;
};

export type SourceUpsertFields = Deletable & {
    id: number;
    title: string;
    author: string;
    pubyear: string;
    link: string;
    citation: string;
    datacomplete: boolean;
    license: string;
    licenselink: string;
};

export type SpeciesSourceInsertFields = Deletable & {
    id: number;
    species: number;
    source: number;
    description: string;
    useasdefault: boolean;
    externallink: string;
};

export type GallHostUpdateFields = {
    gall: number;
    hosts: number[];
    rangeExclusions: PlaceNoTreeApi[];
};

export type DeleteResult = {
    type: string;
    name: string;
    count: number;
};

export type GlossaryEntryUpsertFields = Deletable & {
    id: number;
    word: string;
    definition: string;
    urls: string; // newline separated
};

export enum DetachableValues {
    NONE = '',
    INTEGRAL = 'integral',
    DETACHABLE = 'detachable',
    BOTH = 'both',
}

export const DetachableValuesSchema = fromEnum<DetachableValues>('DetachableValues', DetachableValues);

export const DetachableApiSchema = t.type({
    id: t.number,
    value: DetachableValuesSchema,
});

export type DetachableApi = t.TypeOf<typeof DetachableApiSchema>;

export const DetachableNone: DetachableApi = {
    id: 0,
    value: DetachableValues.NONE,
};

export const DetachableIntegral: DetachableApi = {
    id: 1,
    value: DetachableValues.INTEGRAL,
};

export const DetachableDetachable: DetachableApi = {
    id: 2,
    value: DetachableValues.DETACHABLE,
};

export const DetachableBoth: DetachableApi = {
    id: 3,
    value: DetachableValues.BOTH,
};

export const Detachables = [DetachableNone, DetachableIntegral, DetachableDetachable, DetachableBoth];
// there has got to be a better way of doing this...
export const detachableFromString = (s: string): DetachableApi => {
    switch (s) {
        case DetachableValues.NONE:
            return DetachableNone;
        case DetachableValues.INTEGRAL:
            return DetachableIntegral;
        case DetachableValues.DETACHABLE:
            return DetachableDetachable;
        case DetachableValues.BOTH:
            return DetachableBoth;
        default:
            console.error(`Received invalid value '${s}' for Detachable.`);
            return DetachableNone;
    }
};

export const detachableFromId = (id: null | undefined | number): DetachableApi => {
    if (id == undefined || id == null) return DetachableNone;

    const d = Detachables.find((d) => d.id === id);
    if (d == undefined) {
        throw new Error(`Received invalid id '${id}' for Detachable.`);
    }
    return d;
};

export const HostSimpleSchema = t.type({
    id: t.number,
    name: t.string,
    aliases: t.array(AliasApiSchema),
    datacomplete: t.boolean,
    places: t.array(PlaceNoTreeApiSchema),
});
export type HostSimple = t.TypeOf<typeof HostSimpleSchema>;

export const GallSimpleSchema = t.type({
    id: t.number,
    name: t.string,
});
export type GallSimple = t.TypeOf<typeof GallSimpleSchema>;

export const HostApiSchema = t.intersection([
    SpeciesApiSchema,
    t.type({
        galls: t.array(GallSimpleSchema),
        places: t.array(PlaceNoTreeApiSchema),
    }),
]);
export type HostApi = SpeciesApi & {
    galls: GallSimple[];
    places: PlaceNoTreeApi[];
};
export const GallPropertiesSchema = t.type({
    alignment: t.array(FilterFieldSchema),
    cells: t.array(FilterFieldSchema),
    color: t.array(FilterFieldSchema),
    form: t.array(FilterFieldSchema),
    season: t.array(FilterFieldSchema),
    shape: t.array(FilterFieldSchema),
    walls: t.array(FilterFieldSchema),
    texture: t.array(FilterFieldSchema),
    location: t.array(FilterFieldSchema),
    detachable: DetachableApiSchema,
    undescribed: t.boolean,
    hosts: t.array(GallHostSchema),
});
export type GallPropertiesType = t.TypeOf<typeof GallPropertiesSchema>;

export const GallApiSchema = t.intersection([
    SpeciesApiSchema,
    GallPropertiesSchema,
    t.type({
        gall_id: t.number,
        excludedPlaces: t.array(PlaceNoTreeApiSchema),
    }),
]);
export type GallApi = t.TypeOf<typeof GallApiSchema>;

export const TaxSectionSchema = t.intersection([TaxonomyEntryNoParentSchema, t.type({ species: t.array(SimpleSpeciesSchema) })]);
export type TaxSection = t.TypeOf<typeof TaxSectionSchema>;

/**
 *
 */
export type SearchQuery = {
    detachable: DetachableApi[];
    alignment: string[];
    walls: string[];
    locations: string[];
    textures: string[];
    color: string[];
    season: string[];
    shape: string[];
    cells: string[];
    form: string[];
    undescribed: boolean;
    place: string[];
    family: string[];
};

export const EMPTYSEARCHQUERY: SearchQuery = {
    detachable: [DetachableNone],
    alignment: [],
    walls: [],
    locations: [],
    textures: [],
    color: [],
    shape: [],
    cells: [],
    season: [],
    form: [],
    undescribed: false,
    place: [],
    family: [],
};

export const EntrySchema = t.type({
    id: t.number,
    word: t.string,
    definition: t.string,
    urls: t.string, // /n separated
});

export type Entry = t.TypeOf<typeof EntrySchema>;
