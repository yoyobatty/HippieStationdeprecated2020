import { Component } from 'inferno';
import { useBackend } from '../backend';
import { Button, Input } from '../components';
import { PlayerLink } from './common/PlayerLink';

// hippie -- Find: things searched by name, type, ref or player, everywhere,
// on this z-level, near the admin or on one tile (everything there), with
// Jump, VV, Get, Follow, Mark and Delete on each. Data and actions from
// hippiestation/code/modules/admin/admin_find.dm.

const MODES = [
  ['name', 'Name', 'Part of its name'],
  ['type', 'Type', 'A type path; its subtypes too'],
  ['ref', 'Ref', 'A ref, like [0x2000123] or [mob_42]'],
  ['player', 'Player', 'A ckey (part of one is enough)'],
];

const SCOPES = [
  ['everywhere', 'Everywhere'],
  ['z', 'This z-level'],
  ['near', 'Near me'],
  ['tile', 'One tile'],
];

const PLACEHOLDERS = {
  name: 'Part of a name: crowbar, Bob, toolbox',
  type: 'A type path: /obj/item/gun',
  ref: 'A ref: [0x2000123] or [mob_42]',
  player: 'A ckey',
};

export class AdminFind extends Component {
  constructor() {
    super();
    // typed values, until the server's change (a tile picked elsewhere)
    this.typed = {};
    this.seen = {};
    this.picked = {};
  }

  field(data, key) {
    if (this.seen[key] !== data[key]) {
      this.seen[key] = data[key];
      delete this.typed[key];
    }
    if (this.typed[key] !== undefined) {
      return this.typed[key];
    }
    return data[key] === null || data[key] === undefined
      ? ''
      : String(data[key]);
  }

  search(change) {
    const { act, data } = useBackend(this.props);
    const choice = Object.assign({
      mode: this.picked.mode || data.mode,
      scope: this.picked.scope || data.scope,
      inside: this.picked.inside !== undefined
        ? this.picked.inside
        : data.inside,
    }, change || {});
    this.picked = {};
    act('search', {
      mode: choice.mode,
      scope: choice.scope,
      inside: choice.inside ? 1 : 0,
      query: choice.query !== undefined
        ? choice.query
        : this.field(data, 'query'),
      radius: this.field(data, 'radius'),
      tile: this.field(data, 'tile'),
    });
  }

  render() {
    const { act, data } = useBackend(this.props);
    const rows = data.rows || [];
    const mode = this.picked.mode || data.mode;
    const scope = this.picked.scope || data.scope;
    return (
      <div className="AdminFind">
        <div className="AdminFind__bar">
          {MODES.map(m => (
            <Button
              key={m[0]}
              content={m[1]}
              title={m[2]}
              selected={mode === m[0]}
              onClick={() => this.search({ mode: m[0] })} />
          ))}
          <Input
            className="AdminFind__query"
            value={this.field(data, 'query')}
            placeholder={PLACEHOLDERS[mode]}
            onInput={(e, value) => {
              this.typed.query = value;
            }}
            onChange={() => this.search()} />
          <Button icon="search" content="Find" onClick={() => this.search()} />
        </div>
        <div className="AdminFind__bar">
          <span className="AdminFind__label">Where</span>
          {SCOPES.map(s => (
            <Button
              key={s[0]}
              content={s[1]}
              selected={scope === s[0]}
              onClick={() => this.search({ scope: s[0] })} />
          ))}
          {scope === 'near' && (
            <span className="AdminFind__sub">
              within
              <Input
                className="AdminFind__small"
                value={this.field(data, 'radius')}
                onInput={(e, value) => {
                  this.typed.radius = value;
                }}
                onChange={() => this.search()} />
              tiles
            </span>
          )}
          {scope === 'tile' && (
            <span className="AdminFind__sub">
              x, y, z
              <Input
                className="AdminFind__tile"
                value={this.field(data, 'tile')}
                onInput={(e, value) => {
                  this.typed.tile = value;
                }}
                onChange={() => this.search()} />
              <Button content="Mine" title="The tile you're on"
                onClick={() => act('here')} />
              <Button.Checkbox
                content="Inside things too"
                checked={data.inside}
                onClick={() => this.search({ inside: !data.inside })} />
            </span>
          )}
        </div>
        {(data.counts || []).length > 1 && (
          <div className="AdminFind__counts">
            {data.counts.map(c => (
              <span
                key={c.type}
                className="AdminFind__count"
                title="Find this type"
                onClick={() => this.search({ mode: 'type', query: c.type })}>
                {c.type} <b>{c.count}</b>
              </span>
            ))}
          </div>
        )}
        <div className="AdminFind__status">
          {!data.searched && 'Pick what to look for and where, then Find.'}
          {!!data.searched && (data.matched === 0
            ? 'Nothing found.'
            : data.matched + ' found' + (data.matched > rows.length
              ? ', the first ' + rows.length + ' shown'
              : ''))}
          {!!data.searched && (
            <span className="AdminFind__muted"> in {data.took} s</span>
          )}
        </div>
        <div className="AdminFind__rows">
          {rows.map(row => (
            <div key={row.ref} className="AdminFind__row">
              <div className="AdminFind__what">
                <div>
                  <b>
                    {row.ckey
                      ? (
                        <PlayerLink act={act} who={{
                          name: row.name,
                          ckey: row.ckey,
                          ref: row.ref,
                          mob: true,
                        }} />
                      )
                      : row.name}
                  </b>
                  {!!row.ckey && (
                    <span className="AdminFind__muted"> ({row.ckey})</span>
                  )}
                  {!!row.invisible && (
                    <span className="AdminFind__tag">unseen</span>
                  )}
                  {!!row.underfloor && (
                    <span className="AdminFind__tag">under floor</span>
                  )}
                </div>
                <div className="AdminFind__muted">
                  {row.type}
                  {!!row.where && ' · ' + row.where}
                  {!!row.carrier && ' · carried by ' + row.carrier}
                </div>
              </div>
              <div className="AdminFind__acts">
                <a onClick={() => act('vv', { ref: row.ref })}>VV</a>
                {!!row.where && row.where !== 'nullspace' && (
                  <a onClick={() => act('jmp', { ref: row.ref })}>JMP</a>
                )}
                {!!row.movable && (
                  <a onClick={() => act('flw', { ref: row.ref })}>FLW</a>
                )}
                {!!row.movable && (
                  <a onClick={() => act('get', { ref: row.ref })}
                    title="Bring it to you">GET
                  </a>
                )}
                <a onClick={() => act('mark', { ref: row.ref })}>MARK</a>
                {!!row.where && row.where !== 'nullspace' && (
                  <a onClick={() => act('tile', { ref: row.ref })}
                    title="Everything on its tile">TILE
                  </a>
                )}
                <a className="AdminFind__del"
                  onClick={() => act('del', { ref: row.ref })}>DEL
                </a>
              </div>
            </div>
          ))}
        </div>
      </div>
    );
  }
}
