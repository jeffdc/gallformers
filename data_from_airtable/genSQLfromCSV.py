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
db = sqlite3.connect('gallformers.sqlite')

def lookupfamily(family):
    cursor = db.cursor()
    tup = family, # sure is hacky
    cursor.execute("SELECT family_id from family WHERE name LIKE ?", tup)
    r = cursor.fetchone()
    if r == None:
        print(f'Failed to lookup family_id for {family}')

    return r[0]
    
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
    #TODO need to move location to a many=to-many
    return 0
    # cursor = db.cursor()
    # tup = loc, # sure is hacky
    # cursor.execute("SELECT loc_id from location WHERE loc LIKE ?", tup)
    # r = cursor.fetchone()
    # if r == None:
    #     print(f'Failed to lookup loc_id for {loc}')

    # return r[0]

def lookupspeciesid(sp):
    cursor = db.cursor()
    tup = sp, # sure is hacky
    cursor.execute("SELECT species_id from species WHERE name = ?", tup)
    r = cursor.fetchone()
    if r == None:
        print(f'Failed to lookup species_id for {sp}')

    return r[0]

def lookupsourceid(s):
    cursor = db.cursor()
    tup = s,
    cursor.execute("SELECT source_id FROM source WHERE title LIKE ?", tup)
    r = cursor.fetchone()
    if r == None:
        print(f'Failed to lookup source_id for {s}')

    return r[0]

familyvals = [(None, family[i]["Family"], family[i]["Type"]) for i in family if family[i]["Family"] != ""]
db.executemany('INSERT INTO family VALUES(?,?,?)', familyvals)
print(f'Adding {len(familyvals)} families...')

def familyfromhost(i):
    return hosts[i]["Family (from Taxonomy)"]

familiesfromhosts = set(map(familyfromhost, hosts))
familyvals = [(None, f, "Plant") for f in familiesfromhosts]
db.executemany('INSERT INTO family VALUES(?,?,?)', familyvals)
print(f'Adding {len(familiesfromhosts)} families from hosts records...')
#################
db.commit()
#################
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

gallgallvals = [(lookupspeciesid(galls[i]["Gall"]), 'gall', galls[i]["Detachable"], None, galls[i]["Alignment"], galls[i]["Walls"], None, lookuplocid(galls[i]["Location"]), None, None) for i in galls]
db.executemany('INSERT INTO gall VALUES(?,?,?,?,?,?,?,?,?,?)', gallgallvals)
print(f'Adding {len(gallgallvals)} galls as galls...')

totalgallhosts = 0
for i in galls:
    g = galls[i]
    speciesid = lookupspeciesid(g["Gall"])
    hs = filter(None, g["Host associations mentioned (from Descriptions)"].split(','))
    totalgallhosts = totalgallhosts + len(list(hs))

    vals = [(lookupspeciesid(h), speciesid) for h in hs]
    db.executemany('INSERT INTO host VALUES(?,?)', vals)

print(f'added {totalgallhosts} host-gall relationships')

totalgallsources = 0
for i in galls:
    g = galls[i]
    speciesid = lookupspeciesid(g["Gall"])
    rawsources = g["Source (from Source Contents)"]
    reader = csv.reader([rawsources], delimiter=',', quotechar='"')
    for sources in reader:
        totalgallsources = totalgallsources + 1
        vals = [(speciesid, lookupsourceid(s)) for s in filter(None, sources)]
        db.executemany('INSERT INTO speciessource VALUES(?,?)', vals)

print(f'added {totalgallsources} source-gall relationships')

db.commit()
db.close()
