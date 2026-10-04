import json, re, sqlite3, sys
db = sys.argv[1]
rows = json.load(open('catalog.json'))['rows']
keep = [r for r in rows if r['license'] == 'PD' and r['language'] == 'English'
        and (r['year'] or 9999) <= 1929 and not r.get('parentSongId') and r['chordPro']]
def clean(cp):
    t = re.sub(r'\[[^\]]*\]', '', cp)
    t = re.sub(r'^\{[^}]*\}\s*$', '', t, flags=re.M)
    t = re.sub(r'\{c:[^}]*\}', '', t)
    t = re.sub(r'[ \t]+$', '', t, flags=re.M)
    t = re.sub(r'(?<=\S) {2,}', ' ', t)
    t = re.sub(r'\n{3,}', '\n\n', t).strip()
    return t
seen = set(); out = []
for r in sorted(keep, key=lambda r: r['title'].lower()):
    key = (r['title'].lower(), (r['writer'] or '').lower())
    if key in seen: continue
    seen.add(key)
    ly = clean(r['chordPro'])
    if len(ly) < 40: continue
    out.append(r | {'lyrics': ly})
con = sqlite3.connect(db)
con.executescript('''
DROP TABLE IF EXISTS hymns_fts; DROP TABLE IF EXISTS hymns;
CREATE TABLE hymns(n INTEGER PRIMARY KEY, title TEXT, writer TEXT, year INTEGER, themes TEXT, meter TEXT, scripture TEXT, pop INTEGER, lyrics TEXT);
''')
for i, r in enumerate(out, 1):
    con.execute('INSERT INTO hymns VALUES(?,?,?,?,?,?,?,?,?)', (i, r['title'], r['writer'], r['year'], r['themes'], r['meter'], r['scripture'], r['hymnalCount'] or 0, r['lyrics']))
con.execute("CREATE VIRTUAL TABLE hymns_fts USING fts5(title, lyrics, content='hymns', content_rowid='n', tokenize='porter unicode61 remove_diacritics 2')")
con.execute("INSERT INTO hymns_fts(rowid,title,lyrics) SELECT n,title,lyrics FROM hymns")
con.execute("INSERT OR REPLACE INTO meta(key,value) VALUES('hymns_source','WorshipCommons (ChurchApps) public-domain catalog, songs first published 1929 or earlier')")
con.commit(); con.execute('VACUUM'); con.close()
print(len(out), 'hymns')
