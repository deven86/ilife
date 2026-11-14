#!/usr/bin/env python3
"""Generate cloudkit/schema.ckdb from iLife/Models/Models.swift.

SwiftData syncs through Core Data's CloudKit mirroring: every @Model becomes a record type CD_<Model>
whose fields are CD_<property>. Strings, binary data and arrays also get a CD_<property>_ckAsset field,
used when a value is too large to store inline. Run this again whenever Models.swift changes.
"""
import re, sys, pathlib

src = pathlib.Path("iLife/Models/Models.swift").read_text()
models = {}
for m in re.finditer(r"@Model final class (\w+) \{(.*?)(?=\n@Model |\nenum |\Z)", src, re.S):
    models[m.group(1)] = m.group(2)
names = set(models)

SCALARS = {"String": "STRING", "Double": "DOUBLE", "Int": "INT64", "Bool": "INT64", "Date": "TIMESTAMP"}
out = ["DEFINE SCHEMA", ""]
for name in sorted(models):
    fields = []
    for line in models[name].splitlines():
        m = re.match(r"^    (?:@Attribute\([^)]*\) )?(?:@Relationship\([^)]*\) )?var (\w+): ([\w\[\]\?]+)(.*)$", line)
        if not m:
            continue
        prop, typ, rest = m.groups()
        if "{" in rest and "=" not in rest.split("{")[0]:
            continue                      # computed property
        base = typ.rstrip("?")
        if base.startswith("["):
            inner = base.strip("[]")
            if inner in names:
                continue                  # to-many relationship lives on the other side
            fields += [(f"CD_{prop}", "BYTES"), (f"CD_{prop}_ckAsset", "ASSET")]
        elif base in names:
            fields.append((f"CD_{prop}", "STRING"))          # to-one relationship
        elif base == "Data":
            fields += [(f"CD_{prop}", "BYTES"), (f"CD_{prop}_ckAsset", "ASSET")]
        elif base == "String":
            fields += [(f"CD_{prop}", "STRING"), (f"CD_{prop}_ckAsset", "ASSET")]
        elif base in SCALARS:
            fields.append((f"CD_{prop}", SCALARS[base]))
        else:
            sys.exit(f"{name}.{prop}: unhandled type {typ}")
    out.append(f"    RECORD TYPE CD_{name} (")
    out += ['        "___createTime" TIMESTAMP,', '        "___createdBy"  REFERENCE,', '        "___etag"       STRING,',
            '        "___modTime"    TIMESTAMP,', '        "___modifiedBy" REFERENCE,', '        "___recordID"   REFERENCE QUERYABLE,',
            "        CD_entityName STRING QUERYABLE,"]
    out += [f"        {f} {t}," for f, t in sorted(fields)]
    out += ['        GRANT WRITE TO "_creator",', '        GRANT CREATE TO "_icloud",', '        GRANT READ TO "_world"', "    );", ""]
out += ["    RECORD TYPE Users (", '        "___createTime" TIMESTAMP,', '        "___createdBy"  REFERENCE,', '        "___etag"       STRING,',
        '        "___modTime"    TIMESTAMP,', '        "___modifiedBy" REFERENCE,', '        "___recordID"   REFERENCE,', "        roles LIST<INT64>,",
        '        GRANT WRITE TO "_creator",', '        GRANT READ TO "_world"', "    );", ""]
pathlib.Path("cloudkit/schema.ckdb").write_text("\n".join(out))
print(f"{len(models)} record types written")
