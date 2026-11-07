import { Component } from 'inferno';
import { useBackend } from '../backend';
import { Button, Icon, Input } from '../components';

// hippie -- Search Logs: everything logged this round, searched. Words (| for
// any of them), a player, kinds of line, the last so many minutes, an area;
// quick starts for the usual questions; each line with buttons for who did
// it, who it was done to and where. Data and actions from
// hippiestation/code/modules/admin/log_search.dm.

const MINUTES = [[0, 'All round'], [5, '5 min'], [15, '15 min'],
  [30, '30 min'], [60, '1 hour']];

// A line's kind as a colour swatch class (the Investigate ones share one)
const kindClass = kind => {
  if (kind.indexOf('Investigate') === 0) {
    return 'LogSearch__kind LogSearch__kind--investigate';
  }
  return 'LogSearch__kind LogSearch__kind--'
    + kind.toLowerCase().replace(/[^a-z]/g, '');
};

const Who = props => {
  const { act, row, prefix, ckey, name, alive, mob } = props;
  if (!ckey && !name) {
    return null;
  }
  return (
    <span className="LogSearch__who">
      <span className="LogSearch__whoName">
        {name}{ckey ? ' (' + ckey + ')' : ''}
      </span>
      {!!alive && (
        <span className="LogSearch__acts">
          {!!mob && (
            <a onClick={() => act(prefix + 'pp', { id: row.id })}
              title="Player panel">PP
            </a>
          )}
          <a onClick={() => act(prefix + 'vv', { id: row.id })}
            title="View variables">VV
          </a>
          <a onClick={() => act(prefix + 'flw', { id: row.id })}
            title="Follow">FLW
          </a>
        </span>
      )}
    </span>
  );
};

export class LogSearch extends Component {
  constructor() {
    super();
    // what's typed in the boxes, until the server sets them (a quick start,
    // a player panel's SEARCH LOGS): then the server's
    this.typed = {};
    this.seen = {};
  }

  field(data, key) {
    if (this.seen[key] !== data[key]) {
      this.seen[key] = data[key];
      delete this.typed[key];
    }
    return this.typed[key] !== undefined ? this.typed[key] : (data[key] || '');
  }

  search(minutes) {
    const { act, data } = useBackend(this.props);
    act('search', {
      text: this.field(data, 'text'),
      who: this.field(data, 'who'),
      area: this.field(data, 'area'),
      minutes: minutes === undefined ? data.minutes : minutes,
    });
  }

  render() {
    const { act, data } = useBackend(this.props);
    const rows = data.rows || [];
    const kinds = data.kinds || [];
    const anyKind = kinds.some(kind => kind.on);
    return (
      <div className="LogSearch">
        <div className="LogSearch__bar">
          <Input
            className="LogSearch__textBox"
            value={this.field(data, 'text')}
            placeholder="Words to find (a | b finds either)"
            onInput={(e, value) => {
              this.typed.text = value;
            }}
            onChange={() => this.search()} />
          <Input
            className="LogSearch__whoBox"
            value={this.field(data, 'who')}
            placeholder="Player: ckey or name"
            onInput={(e, value) => {
              this.typed.who = value;
            }}
            onChange={() => this.search()} />
          <Input
            className="LogSearch__areaBox"
            value={this.field(data, 'area')}
            placeholder="Area"
            onInput={(e, value) => {
              this.typed.area = value;
            }}
            onChange={() => this.search()} />
          <Button icon="search" content="Search"
            onClick={() => this.search()} />
          <Button icon="times" content="Clear"
            onClick={() => act('clear')} />
        </div>
        <div className="LogSearch__row">
          <span className="LogSearch__label">Quick start</span>
          {(data.presets || []).map(preset => (
            <Button
              key={preset.name}
              content={preset.name}
              selected={preset.on}
              title={preset.desc}
              onClick={() => act('preset', { name: preset.name })} />
          ))}
        </div>
        <div className="LogSearch__row">
          <span className="LogSearch__label">When</span>
          {MINUTES.map(m => (
            <Button
              key={m[0]}
              content={m[1]}
              selected={data.minutes === m[0]}
              onClick={() => this.search(m[0])} />
          ))}
          <span className="LogSearch__spacer" />
          <Button
            icon={data.oldest_first ? 'sort-amount-up' : 'sort-amount-down'}
            content={data.oldest_first ? 'Oldest first' : 'Newest first'}
            onClick={() => act('order')} />
          <Button icon="sync" content="Refresh"
            title="Search again: lines logged since are added"
            onClick={() => act('refresh')} />
        </div>
        <div className="LogSearch__kinds">
          <span
            className={'LogSearch__chip'
              + (anyKind ? '' : ' LogSearch__chip--on')}
            onClick={() => act('all_kinds')}>
            Everything
          </span>
          {kinds.filter(kind => kind.count > 0 || kind.on).map(kind => (
            <span
              key={kind.name}
              className={'LogSearch__chip'
                + (kind.on ? ' LogSearch__chip--on' : '')}
              title={kind.desc}
              onClick={() => act('kind', { name: kind.name })}>
              <span className={kindClass(kind.name)} />
              {kind.name} <span className="LogSearch__count">{kind.count}</span>
            </span>
          ))}
        </div>
        <div className="LogSearch__status">
          {data.matched === 0
            ? 'Nothing matches.'
            : data.matched + ' line' + (data.matched === 1 ? '' : 's')
              + (data.matched > data.shown
                ? ', the ' + data.shown + ' '
                  + (data.oldest_first ? 'oldest of the newest' : 'newest')
                  + ' shown'
                : '')}
          <span className="LogSearch__muted">
            {' '}&middot; round time {data.round_time}
            {' '}&middot; {data.total} lines logged
            {data.kept_from && data.total > data.scanned
              ? ', kept from ' + data.kept_from + ' (older ones are in the '
                + 'log files)'
              : ''}
          </span>
        </div>
        <div className="LogSearch__lines">
          {rows.length === 0 && (
            <div className="LogSearch__empty">
              {data.total === 0
                ? 'Nothing has been logged yet.'
                : 'Try fewer words, another spelling, or Everything.'}
            </div>
          )}
          {rows.map(row => (
            <div key={row.id} className="LogSearch__line">
              <div className="LogSearch__time">{row.time}</div>
              <div className="LogSearch__kindCol">
                <span className={kindClass(row.kind)} />
                {row.kind.replace('Investigate: ', '')}
              </div>
              <div className="LogSearch__body">
                <div className="LogSearch__text">{row.text}</div>
                <div className="LogSearch__meta">
                  <Who act={act} row={row} prefix=""
                    ckey={row.ckey} name={row.name}
                    alive={row.actor} mob={row.actor_mob} />
                  {(!!row.tckey || !!row.tname) && (
                    <span className="LogSearch__arrowText">to</span>
                  )}
                  <Who act={act} row={row} prefix="t_"
                    ckey={row.tckey} name={row.tname}
                    alive={row.target} mob={row.target_mob} />
                  {!!row.where && (
                    <span className="LogSearch__where">
                      <Icon name="map-marker-alt" mr={0.5} />
                      {row.area} ({row.where})
                      <span className="LogSearch__acts">
                        <a onClick={() => act('jmp', { id: row.id })}
                          title="Jump there">JMP
                        </a>
                      </span>
                    </span>
                  )}
                </div>
              </div>
            </div>
          ))}
        </div>
      </div>
    );
  }
}
