import csv
import pprint
import re
import sqlite3

def csvtodict(filename):
    with open(filename, mode='r', encoding='utf-8-sig') as f:
        data = csv.reader(f)
        headers = next(data)
        stuff = [dict(zip(headers, i)) for i in data]
        d = dict()
        for thing in stuff:
            # every type from CSV has a Record column that is the old ID, use that as the key so we can do lookups later
            rec = thing['Record']
            d[rec] = thing

        return d

galls = csvtodict('data_from_airtable/galls.csv') # Record	Gall	All BHL descriptions added	Gallformer Species	Host Plant	Host genus	References	Host associations mentioned (from Descriptions)	Description (from Source Contents)	Photos (from Source Contents)	Taxonomic Info (from Source Contents)	Source (from Source Contents)	Location	Detachable		Alignment	Walls
hosts = csvtodict('data_from_airtable/host-species.csv') # Specific Name	Record	Plant specific name	Regions	Galls	Genus	Family (from Taxonomy)	Descriptions																		
descriptions = csvtodict('data_from_airtable/descriptions.csv') # Record	Current name (from Valid Names)	Galls	Name in record	Source	Description	Host associations mentioned	Photos	Page link	Taxonomic Info	Biology Note	Phenology	Range	Original Description?
family = csvtodict('data_from_airtable/family-upper-level.csv') # Family	Record	Type	Genus-Family
genusfamily = csvtodict('data_from_airtable/genus-family.csv') # Genus Name	Record	Gallformer Taxonomy	Host species	Family	Galls
sources = csvtodict('data_from_airtable/sources.csv') # Title	Record	Author	Year of publication	Hyperlink	Citation (MLA)	Source Contents
taxnames = csvtodict('data_from_airtable/taxonomic-names.csv') # Name	Record	Descriptions	Gallformer species
validnames = csvtodict('data_from_airtable/valid-names.csv') # Current Name	Record	Synonyms (including current name)	Galls	Genus	Species																				

# pprint.PrettyPrinter(indent=2).pprint(sources)
db = sqlite3.connect('prisma/gallformers.sqlite')

# blow away any data that exists
for table in ['speciessource', 'host', 'gall', 'source', 'species', 'family']:
    # if db.execute(f'SELECT count(*) FROM sqlite_master WHERE type=\'table\' AND name=\'{table}\'').rowcount > 0:
    db.execute(f'DELETE FROM {table}')
db.commit()

def lookup(table, idfield, compfield, compvalue):
    cursor = db.cursor()
    tup = compvalue, # sure is hacky
    cursor.execute(f'SELECT {idfield} from {table} WHERE {compfield} LIKE ?', tup)
    r = cursor.fetchone()
    if r == None:
        # print(f'Failed to lookup {idfield} in {table} for {compvalue}')
        return None

    return r[0]

def lookupfamily(family):
    return lookup('family', 'family_id', 'name', family)
    
def lookupfamilyfromgenus(genus):
    # look in the 2 csv files, hopefully we find the family name given the genus
    for i in family:
        if genus in family[i]["Genus-Family"].split(','):
            return lookupfamily(family[i]["Family"])

    for i in genusfamily:
        if genus is genusfamily[i]["Genus-Family"] and len(genusfamily[i]["Family"]) > 0:
            return lookupfamily(genusfamily[i]["Family"])

    print(f'Failed to lookup Family (and the id) for {genus}')

    
def lookuplocid(loc):
    return lookup('location', 'loc_id', 'loc', loc)

def lookupspeciesid(sp):
    return lookup('species', 'species_id', 'name', sp)

def lookupsourceid(s):
    return lookup('source', 'source_id', 'title', s)

def lookupcolorid(c):
    return lookup('color', 'color_id', 'color', c)

def lookupshapeid(s):
    return lookup('shape', 'shape_id', 'shape', s)

def lookupwallsid(w):
    return lookup('walls', 'walls_id', 'walls', w)

def lookupcellsid(c):
    return lookup('cells', 'cells_id', 'cells', c)

def lookuptextureid(t):
    return lookup('texture', 'texture_id', 'texture', t)

def lookupalignmentid(a):
    return lookup('alignment', 'alignment_id', 'alignment', a)

# grab (map) all unique (set) family names, with their type (tuple), that are not an empty string (filter)
familyset = set(filter(lambda f: f[0] != "", map(lambda i: (family[i]["Family"], family[i]["Type"]), family)))
print(f'Starting with {len(familyset)} families from family-upper-level...')

familiesfromhosts = set(map(lambda f: (f, 'Plant'), set(map(lambda i: hosts[i]["Family (from Taxonomy)"], hosts))))
print(f'Checking {len(familiesfromhosts)} more families from hosts...')
familyset = familiesfromhosts.union(familyset)
print(f'Adding {len(familyset)} families...')
db.executemany('INSERT INTO family VALUES(?,?,?)', [(None, f[0], f[1]) for f in familyset])

sourcevals = [(None, sources[i]["Title"], sources[i]["Author"], sources[i]["Year of publication"], sources[i]["Hyperlink"], sources[i]["Citation (MLA)"]) for i in sources]
db.executemany('INSERT INTO source VALUES(?,?,?,?,?,?)', sourcevals)
print(f'Adding {len(sourcevals)} sources...')

    #                                     synonyms, common names                               desc, abundance
hostvals = [(None, None, hosts[i]["Specific Name"], None, None, hosts[i]["Genus"], lookupfamily(hosts[i]["Family (from Taxonomy)"]), None, None) for i in hosts]
db.executemany('INSERT INTO species VALUES(?,?,?,?,?,?,?,?,?)', hostvals)
print(f'Adding {len(hostvals)} hosts...')

#                                   synonyms, common names                                        , abundance
gallvals = [(None, 'gall', galls[i]["Gall"], None, None, galls[i]["Gall"].split(' ')[0], lookupfamilyfromgenus(galls[i]["Gall"].split(' ')[0]), galls[i]["Description (from Source Contents)"], None) for i in galls]
db.executemany('INSERT INTO species VALUES(?,?,?,?,?,?,?,?,?)', gallvals)
print(f'Adding {len(gallvals)} galls as species...')

def formatDetachableForDB(d):
    if d == 'yes': return 1
    else: return 0

# gall_id INTEGER PRIMARY KEY NOT NULL,
# species_id INTEGER NOT NULL,
# taxoncode TEXT NOT NULL CHECK (taxoncode = 'gall'),
# detachable INTEGER, -- boolean: 0 = false; 1 = true, standard sqlite
# texture_id INTEGER,
# alignment_id INTEGER,
# walls_id INTEGER,
# cells_id INTEGER,
# color_id INTEGER,
# shape_id INTEGER,
# loc_id INTEGER,

gallgallvals = [(None, lookupspeciesid(galls[i]["Gall"]), 'gall', \
                formatDetachableForDB(galls[i]["Detachable"]), None, \
                lookupalignmentid(galls[i]["Alignment"]), lookupwallsid(galls[i]["Walls"]), \
                None, None, None, lookuplocid(galls[i]["Location"])) for i in galls]
db.executemany('INSERT INTO gall VALUES(?,?,?,?,?,?,?,?,?,?,?)', gallgallvals)
print(f'Adding {len(gallgallvals)} galls as galls...')

totalgallhosts = 0
for i in galls:
    g = galls[i]
    speciesid = lookupspeciesid(g["Gall"])
    hs = [h for h in g["Host Plant"].split(',') if h]
    hs2 = [h for h in g["Host associations mentioned (from Descriptions)"].split(',') if h]
    hs = set(hs).union(set(hs2))
    totalgallhosts = totalgallhosts + len(list(hs))

    vals = [(None, lookupspeciesid(h), speciesid) for h in hs]
    # print(f'spid = {speciesid} and hosts {list(vals)}')
    db.executemany('INSERT INTO host VALUES(?,?,?)', vals)

print(f'added {totalgallhosts} host-gall relationships')

totalgallsources = 0
for i in galls:
    g = galls[i]
    speciesid = lookupspeciesid(g["Gall"])
    rawsources = g["Source (from Source Contents)"]
    reader = csv.reader([rawsources], delimiter=',', quotechar='"')
    for sources in reader:
        totalgallsources = totalgallsources + 1
        vals = [(None, speciesid, lookupsourceid(s)) for s in filter(None, sources)]
        db.executemany('INSERT INTO speciessource VALUES(?,?,?)', vals)

print(f'added {totalgallsources} source-gall relationships')

db.commit()
db.close()
