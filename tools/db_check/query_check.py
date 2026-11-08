"""Static half of the every-query check.

Finds every SSdbcore.NewQuery("...") / NewQuery({"..."}) in the DM code, turns the DM string into SQL MariaDB can
PREPARE (tables get the prefix, interpolations become stand-in values, :named parameters become ?), and PREPAREs
each one against a real database. PREPARE parses the statement and resolves every table and column, so a typo, a
missing column or a dropped table fails here without running anything.

  python tools/db_check/query_check.py --mariadb <mariadb.exe> --port 3307 --user root --password ... --db hippie_check
  python tools/db_check/query_check.py --list        just print what it found

Queries whose text comes from a variable (NewQuery(some_var)) are listed as "dynamic": the live half covers those.
Exit code 1 if any query fails to prepare.
"""
import argparse
import json
import os
import re
import subprocess
import sys

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ROOTS = ["code", "hippiestation/code"]
CALL = re.compile(r"\bNewQuery\(")


def read_dm_string(src, i):
	"""src[i] is '"' or '{' (of {"). Returns (parts, end) where parts is a list of ('text', s) / ('expr', s)."""
	multiline = src.startswith('{"', i)
	i += 2 if multiline else 1
	parts = []
	buf = []
	while i < len(src):
		c = src[i]
		if multiline and src.startswith('"}', i):
			i += 2
			break
		if not multiline and c == '"':
			i += 1
			break
		if not multiline and c == "\n":
			raise ValueError("unterminated string")
		if c == "\\" and i + 1 < len(src):
			n = src[i + 1]
			buf.append({"n": "\n", "t": "\t", '"': '"', "[": "[", "]": "]", "\\": "\\"}.get(n, n))
			i += 2
			continue
		if c == "[":
			if buf:
				parts.append(("text", "".join(buf)))
				buf = []
			expr, i = read_expr(src, i + 1)
			parts.append(("expr", expr))
			continue
		buf.append(c)
		i += 1
	if buf:
		parts.append(("text", "".join(buf)))
	return parts, i


def read_expr(src, i):
	"""Reads an embedded [expression] up to its matching ], skipping nested strings and brackets."""
	depth = 1
	start = i
	while i < len(src):
		c = src[i]
		if c == '"' or src.startswith('{"', i):
			_, i = read_dm_string(src, i)
			continue
		if c == "'":
			i = src.index("'", i + 1) + 1
			continue
		if c == "[":
			depth += 1
		elif c == "]":
			depth -= 1
			if depth == 0:
				return src[start:i], i + 1
		i += 1
	raise ValueError("unterminated [expression]")


def line_of(src, i):
	return src.count("\n", 0, i) + 1


def find_queries():
	found = []
	for root in ROOTS:
		for dirpath, _, files in os.walk(os.path.join(REPO, root)):
			for f in files:
				if not f.endswith(".dm"):
					continue
				path = os.path.join(dirpath, f)
				rel = os.path.relpath(path, REPO).replace("\\", "/")
				with open(path, encoding="utf-8", errors="replace") as fh:
					src = fh.read()
				for m in CALL.finditer(src):
					i = m.end()
					line = line_of(src, m.start())
					# skip the proc definition itself and commented-out lines
					ls = src.rfind("\n", 0, m.start()) + 1
					head = src[ls:m.start()]
					if "proc/" in head or "//" in head:
						continue
					while src[i] in " \t":
						i += 1
					if src[i] == '"' or src.startswith('{"', i):
						try:
							parts, _ = read_dm_string(src, i)
						except ValueError as e:
							found.append({"file": rel, "line": line, "kind": "unparsed", "error": str(e)})
							continue
						found.append({"file": rel, "line": line, "kind": "literal", "parts": parts})
					else:
						arg = src[i:src.find("\n", i)].strip()
						found.append({"file": rel, "line": line, "kind": "dynamic", "arg": arg})
	return found


TABLE = re.compile(r'^\s*format_table_name\(\s*"([A-Za-z0-9_]+)"\s*\)\s*$')


def to_sql(parts, prefix):
	"""Stand-ins: a table name gets the prefix; an expression inside '...' becomes x; anywhere else 1.
	Named parameters (:ckey) outside quotes become ?.
	Returns (sql, templated): templated means an unquoted [expression] that may be a piece of SQL (a clause, a
	column list) rather than a value, so a failure there may be the stand-in's fault, not the query's."""
	out = []
	in_quote = False
	templated = False
	for kind, s in parts:
		if kind == "text":
			# track whether we're inside a SQL '...' string, honouring \' and ''
			j = 0
			text = []
			while j < len(s):
				c = s[j]
				if c == "\\" and j + 1 < len(s):
					text.append(s[j:j + 2])
					j += 2
					continue
				if c == "'":
					in_quote = not in_quote
					text.append(c)
					j += 1
					continue
				if not in_quote and c == ":" and j + 1 < len(s) and (s[j + 1].isalpha() or s[j + 1] == "_") and (j == 0 or not s[j - 1].isalnum()):
					k = j + 1
					while k < len(s) and (s[k].isalnum() or s[k] == "_"):
						k += 1
					text.append("?")
					j = k
					continue
				text.append(c)
				j += 1
			out.append("".join(text))
		else:
			m = TABLE.match(s)
			if m:
				out.append(prefix + m.group(1))
			elif in_quote:
				out.append("x")
			else:
				out.append("1")
				templated = True
	return "".join(out), templated


def to_pattern(parts):
	"""A regex matching what the site sends, whatever its [expressions] held (whitespace collapsed on both sides)."""
	out = []
	for kind, s in parts:
		if kind == "text":
			t = re.sub(r"\s+", " ", s)
			out.append(re.escape(t).replace("\\ ", "\\s*"))
		else:
			out.append(".*?")
	return "".join(out)


def norm(sql):
	return re.sub(r"\s+", " ", sql).strip()


def coverage(ran_path, static_path):
	"""Maps what the live round ran back to the sites. Exit 1 if any query failed."""
	with open(static_path, encoding="utf-8") as fh:
		qs = json.load(fh)
	with open(ran_path, encoding="utf-8") as fh:
		ran = json.load(fh)
	sites = [q for q in qs if q["kind"] == "literal"]
	for q in sites:
		q["re"] = re.compile(r"\s*" + q["pattern"] + r"\s*", re.S)
		q["ran"] = 0
		q["errors"] = []
	unmatched = []
	bad = 0
	for sql, status in ran.items():
		s = norm(sql)
		# the most specific site that matches: the one with the most literal text
		best = None
		for q in sites:
			if q["re"].fullmatch(s) and (best is None or len(q["pattern"]) > len(best["pattern"])):
				best = q
		if status != "ok":
			bad += 1
		if best is None:
			unmatched.append((s, status))
			continue
		best["ran"] += 1
		if status != "ok":
			best["errors"].append((s, status))
	for q in sites:
		for s, status in q["errors"]:
			print(f'FAIL {q["file"]}:{q["line"]}  {status}\n     {s[:400]}')
	for s, status in unmatched:
		if status != "ok":
			print(f"FAIL (built in a variable)  {status}\n     {s[:400]}")
	hit = [q for q in sites if q["ran"]]
	tmpl = [q for q in hit if q.get("templated")]
	print(f"live: {len(ran)} distinct queries ran, {bad} failed; {len(hit)}/{len(sites)} sites ran"
		f" ({len(tmpl)} of them templated), plus {len(unmatched)} built in variables")
	for q in tmpl:
		print(f'  templated, ran {"ok" if not q["errors"] else "with errors"}: {q["file"]}:{q["line"]}')
	return 1 if bad else 0


def sql_literal(s):
	# one line per statement, so mariadb's "at line N" maps back to the query
	return "'" + s.replace("\\", "\\\\").replace("'", "\\'").replace("\r", "").replace("\n", "\\n") + "'"


def main():
	ap = argparse.ArgumentParser()
	ap.add_argument("--mariadb")
	ap.add_argument("--host", default="127.0.0.1")
	ap.add_argument("--port", default="3307")
	ap.add_argument("--user", default="root")
	ap.add_argument("--password", default="")
	ap.add_argument("--db", default="hippie_check")
	ap.add_argument("--prefix", default="SS13_")
	ap.add_argument("--list", action="store_true")
	ap.add_argument("--json", help="write the per-query results here (with --ran: read the sites from here)")
	ap.add_argument("--ran", help="the live half's ran.json: map what ran back to the sites")
	a = ap.parse_args()
	if a.ran:
		return coverage(a.ran, a.json)

	qs = find_queries()
	literal = [q for q in qs if q["kind"] == "literal"]
	for q in literal:
		q["sql"], q["templated"] = to_sql(q["parts"], a.prefix)
		q["pattern"] = to_pattern(q["parts"])
		del q["parts"]
	if a.list:
		for q in qs:
			print(f'{q["file"]}:{q["line"]} [{q["kind"]}] {q.get("sql", q.get("arg", q.get("error")))}')
		return 0

	# One mariadb session, one PREPARE per query, each preceded by a marker so errors map back to their query.
	script = []
	for n, q in enumerate(literal):
		script.append(f"SELECT 'Q{n}';")
		script.append(f"PREPARE q FROM {sql_literal(q['sql'])};")
	p = subprocess.run([a.mariadb, f"-h{a.host}", f"-P{a.port}", f"-u{a.user}", f"-p{a.password}", "--force", "-N", "-B",
		"--default-character-set=utf8mb4", a.db], input="\n".join(script) + "\n", capture_output=True, text=True, encoding="utf-8")
	# --force keeps going after errors; stdout has the markers and stderr the errors, so interleave by the
	# "at line N" mariadb puts on each error (script line 2n+2 is query n's PREPARE).
	errors = {}
	for line in p.stderr.splitlines():
		m = re.match(r"ERROR \d+ \(\w+\) at line (\d+): (.*)", line)
		if m:
			errors[(int(m.group(1)) - 2) // 2] = m.group(2)
	bad = 0
	unsure = 0
	for n, q in enumerate(literal):
		if n in errors:
			q["error"] = errors[n]
			if q["templated"]:
				unsure += 1
				print(f'TEMPLATED {q["file"]}:{q["line"]}  {errors[n][:160]}  (pieces of SQL spliced in: live half)')
			else:
				bad += 1
				print(f'FAIL {q["file"]}:{q["line"]}  {errors[n]}\n     {q["sql"][:400]}')
	dynamic = [q for q in qs if q["kind"] != "literal"]
	for q in dynamic:
		print(f'DYNAMIC {q["file"]}:{q["line"]}  NewQuery({q.get("arg", "?")}  (live half)')
	print(f"query_check: {len(literal) - bad - unsure}/{len(literal)} prepared, {bad} failed, {unsure} templated, {len(dynamic)} dynamic")
	if a.json:
		with open(a.json, "w", encoding="utf-8") as fh:
			json.dump(qs, fh, indent=1)
	return 1 if bad else 0


if __name__ == "__main__":
	sys.exit(main())
