/**
 * Talks to server.js. Every call resolves to the parsed JSON reply, or
 * { error } when the server is gone or said no.
 */

const call = async (method, url, body) => {
  try {
    const res = await fetch(url, {
      method,
      headers: body ? { 'Content-Type': 'application/json' } : {},
      body: body ? JSON.stringify(body) : undefined,
    });
    const json = await res.json();
    if (!res.ok && !json.error) {
      json.error = 'HTTP ' + res.status;
    }
    return json;
  }
  catch (err) {
    return { error: 'The designer server isn\'t answering (' + err.message
      + '). Start it again with yarn designer.' };
  }
};

export const api = {
  designs: () => call('GET', '/api/designs'),
  load: name => call('GET', '/api/design?name=' + encodeURIComponent(name)),
  check: (name, route) => call('GET', '/api/check?name='
    + encodeURIComponent(name) + '&route=' + encodeURIComponent(route)),
  save: body => call('POST', '/api/save', body),
  remove: name => call('POST', '/api/delete', { name }),
  run: what => call('POST', '/api/run', { what }),
  job: (id, since) => call('GET', '/api/job?id=' + id + '&since=' + since),
  types: q => call('GET', '/api/types?q=' + encodeURIComponent(q)),
  typeExists: path => call('GET', '/api/type?path='
    + encodeURIComponent(path)),
  icons: () => call('GET', '/api/icons'),
};
