"""Fetch the parts of tg's tgui workspace that the chat (tgui-panel) needs into tgui6/, pinned to one tg commit.

    python tools/tgui6_sync/fetch.py [sha]

Uses the GitHub tree API once and raw.githubusercontent.com for the files (sparse clones of tg fail here).
Skipped: tg's own windows (packages/tgui/interfaces), stories, tests, and the packages the chat doesn't use.
Files we changed afterwards are listed in tgui6/HIPPIE_CHANGES.md: re-fetching overwrites them, so diff first.
"""
import concurrent.futures
import json
import os
import sys
import subprocess

SHA = sys.argv[1] if len(sys.argv) > 1 else '928bb812756f507eaa7251ab1df07977697c7164'
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'tgui6')
SKIP_PREFIX = (
    'packages/tgui/interfaces/', 'packages/tgui/stories', 'packages/tgui/__mocks__', 'packages/tgfont/',
    'packages/tgui-say/', 'packages/tgui-lobby/', 'packages/tgui-escape-menu/', 'packages/tgui-chat-dark/',
    'packages/tgui-setup/', 'docs/', 'public/iframe.html', 'happydom.ts',
)


def get(url):
    # curl, not urllib: Python's own certificate store here can't verify GitHub's chain; curl uses Windows' store
    r = subprocess.run(['curl', '-sSfL', '--retry', '3', '-A', 'hippie-tgui6-sync', url], capture_output=True)
    if r.returncode:
        raise RuntimeError('%s: %s' % (url, r.stderr.decode(errors='replace').strip()))
    return r.stdout


def main():
    root = json.loads(get('https://api.github.com/repos/tgstation/tgstation/git/trees/' + SHA))
    tgui_sha = [e['sha'] for e in root['tree'] if e['path'] == 'tgui'][0]
    tree = json.loads(get('https://api.github.com/repos/tgstation/tgstation/git/trees/%s?recursive=1' % tgui_sha))
    files = [e['path'] for e in tree['tree'] if e['type'] == 'blob']
    files = [f for f in files if not f.startswith(SKIP_PREFIX) and not f.endswith(('.test.ts', '.test.tsx'))]

    def one(path):
        data = get('https://raw.githubusercontent.com/tgstation/tgstation/%s/tgui/%s' % (SHA, path))
        dest = os.path.join(ROOT, *path.split('/'))
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, 'wb') as fh:
            fh.write(data)
        return path

    with concurrent.futures.ThreadPoolExecutor(16) as pool:
        done = list(pool.map(one, files))
    with open(os.path.join(ROOT, 'TG_COMMIT'), 'w') as fh:
        fh.write(SHA + '\n')
    print('%d files from tg %s into %s' % (len(done), SHA[:8], os.path.normpath(ROOT)))


if __name__ == '__main__':
    main()
