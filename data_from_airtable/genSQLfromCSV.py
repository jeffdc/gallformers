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

def lookupfamily(genus):
    for i in family:
        if genus in family[i]["Genus-Family"].split(','):
            return family[i]["Family"]
    return ''

def lookuplocid(loc):
    # TODO how to deal with locations?
    return 1

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
    print(f'trying to lookup {s}')
    tup = s,
    cursor.execute("SELECT source_id FROM source WHERE title LIKE ?", tup)
    r = cursor.fetchone()
    if r == None:
        print(f'Failed to lookup source_id for {s}')

    return r[0]


# sources is a dict so we are just getting the key when map it
# def sourcetosqlvals(i):
#     s = sources[i]
#     return (None, s["Title"], s["Author"], s["Year of publication"], s["Hyperlink"], s["Citation (MLA)"])
# db.executemany('INSERT INTO source VALUES(?,?,?,?,?,?)', map(sourcetosqlvals, sources))

# def hoststosqlvals(i):
#     h = hosts[i]
#     #                                     synonyms, common names                               desc, abundance
#     return (None, None, h["Specific Name"], None, None, h["Genus"], h["Family (from Taxonomy)"], None, None)
# db.executemany('INSERT INTO species VALUES(?,?,?,?,?,?,?,?,?)', map(hoststosqlvals, hosts))

# def gallstospeciessqlvals(i):
#     g = galls[i]
#     name = g["Gall"]
#     genus = name.split(' ')[0]
#     family = lookupfamily(genus)
#     if family == "":
#         print(f'Failed to lookup family for {i} - {name}')

#     #                              synonyms, common names                                        , abundance
#     return (None, 'gall', g["Gall"], None, None, genus, family, g["Description (from Source Contents)"], None)
# db.executemany('INSERT INTO species VALUES(?,?,?,?,?,?,?,?,?)', map(gallstospeciessqlvals, galls))

# def gallstogallsqlvals(i):
#     g = galls[i]
#     speciesid = lookupspeciesid(g["Gall"])
#     locid = lookuplocid(g["Location"])
#     #                                           Texture
#     return (speciesid, 'gall', g["Detachable"], None, g["Alignment"], g["Walls"], locid)
# db.executemany('INSERT INTO gall VALUES(?,?,?,?,?,?,?)', map(gallstogallsqlvals, galls))

# def gallhoststosqlvals(i):
#     g = galls[i]
#     speciesid = lookupspeciesid(g["Gall"])
#     hs = filter(None, g["Host associations mentioned (from Descriptions)"].split(','))

#     vals = [(lookupspeciesid(h), speciesid) for h in hs]
#     db.executemany('INSERT INTO host VALUES(?,?)', vals)

# v = map(gallhoststosqlvals, galls)
# print(len(list(v)))

def sourcetogallsqlvals(i):
    g = galls[i]
    speciesid = lookupspeciesid(g["Gall"])
    rawsources = g["Source (from Source Contents)"]
    reader = csv.reader([rawsources], delimiter=',', quotechar='"')
    for sources in reader:
        vals = [(speciesid, lookupsourceid(s)) for s in filter(None, sources)]
        db.executemany('INSERT INTO speciessource VALUES(?,?)', vals)

v = map(sourcetogallsqlvals, galls)
print(len(list(v)))

db.commit()
db.close()
