import { Component } from 'inferno';
import { useBackend } from '../backend';
import { Button, Input } from '../components';

// hippie -- Grief undo: a part of the station scanned against the map, every
// changed tile ticked (click it on the map or here to skip it), Apply puts the
// ticked ones back, Undo takes back the last Apply. Things that aren't in the
// map are only listed. Data and actions from
// hippiestation/code/modules/admin/grief_undo.dm.

const MAX_AREA_HITS = 8;

export class GriefUndo extends Component {
  constructor() {
    super();
    this.state = {
      areaText: '',
      ckey: null,
      minutes: null,
      filter: '',
      confirmDel: null,
    };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const rows = data.rows || [];
    const adds = data.adds || [];
    const areaText = this.state.areaText.toLowerCase();
    const areaHits = areaText
      ? (data.areas || [])
        .filter(a => a.toLowerCase().includes(areaText))
        .slice(0, MAX_AREA_HITS)
      : [];
    const ckey = this.state.ckey !== null ? this.state.ckey : data.player_ckey;
    const minutes = this.state.minutes !== null
      ? this.state.minutes
      : String(data.minutes);
    const filter = this.state.filter.toLowerCase();
    const shown = filter
      ? rows.filter(r => r.area.toLowerCase().includes(filter)
        || r.what.join(' ').toLowerCase().includes(filter))
      : rows;
    const anyNear = rows.some(r => r.near);
    const scanPlayer = () => {
      act('player', { ckey, minutes });
      this.setState({ ckey: null, minutes: null });
    };
    return (
      <div className="GriefUndo">
        <div className="GriefUndo__bar">
          <Button icon="map-marker-alt" content="Here"
            title="The area you're in"
            onClick={() => act('here')} />
          <Button icon="vector-square" content="Box"
            selected={data.box_step > 0}
            title="Click two corners on the map"
            onClick={() => act('box')} />
          <span className="GriefUndo__area">
            <Input
              className="GriefUndo__areaInput"
              value={this.state.areaText}
              placeholder="Area"
              onInput={(e, value) => this.setState({ areaText: value })} />
            {areaHits.length > 0 && (
              <div className="GriefUndo__hits">
                {areaHits.map(name => (
                  <div key={name} className="GriefUndo__hit"
                    onClick={() => {
                      act('area', { name });
                      this.setState({ areaText: '' });
                    }}>
                    {name}
                  </div>
                ))}
              </div>
            )}
          </span>
          <span className="GriefUndo__gap" />
          <span className="GriefUndo__label">Player</span>
          <Input
            className="GriefUndo__ckey"
            value={ckey}
            placeholder="ckey"
            onInput={(e, value) => this.setState({ ckey: value })}
            onChange={scanPlayer} />
          <span className="GriefUndo__label">last</span>
          <Input
            className="GriefUndo__minutes"
            value={minutes}
            onInput={(e, value) => this.setState({ minutes: value })}
            onChange={scanPlayer} />
          <span className="GriefUndo__label">min</span>
          <Button icon="search" content="Scan" onClick={scanPlayer} />
          <Button icon="sync" content="Rescan"
            disabled={!data.scanned}
            onClick={() => act('rescan')} />
        </div>
        <div className="GriefUndo__status">
          {data.scanned
            ? (
              <span>
                <b>{data.source}</b>
                <span className="GriefUndo__muted">
                  {' · '}{data.turfs} tiles
                </span>
                {' · '}
                <span className="GriefUndo__restore">
                  {data.restore} to restore
                </span>
                {' · '}
                <span className="GriefUndo__air">{data.air} air</span>
                {' · '}
                <span className="GriefUndo__added">
                  {adds.length} added
                </span>
              </span>
            )
            : <span className="GriefUndo__muted">Nothing scanned.</span>}
          {!!data.message && (
            <div className="GriefUndo__message">{data.message}</div>
          )}
        </div>
        <div className="GriefUndo__bar">
          <Button.Checkbox content="Air" checked={data.do_air}
            title="Refill air and put out fires on ticked tiles"
            onClick={() => act('toggle_air')} />
          <Button.Checkbox content="Map clicks" checked={data.click_ticks}
            title="Clicking a changed tile on the map ticks or skips it"
            onClick={() => act('toggle_clicks')} />
          <Button.Checkbox content="Preview" checked={data.show_preview}
            onClick={() => act('toggle_preview')} />
          <span className="GriefUndo__gap" />
          <span className="GriefUndo__label">Tick</span>
          <Button content="All" onClick={() => act('tick_all', { on: 1 })} />
          <Button content="None" onClick={() => act('tick_all', { on: 0 })} />
          {anyNear && (
            <Button content="Near player"
              title="Only tiles within 3 of their logged actions"
              onClick={() => act('tick_near')} />
          )}
          <Input
            className="GriefUndo__filter"
            value={this.state.filter}
            placeholder="Filter"
            onInput={(e, value) => this.setState({ filter: value })} />
        </div>
        <div className="GriefUndo__body">
          <div className="GriefUndo__tiles">
            {shown.length === 0 && (
              <div className="GriefUndo__empty">
                {data.scanned ? 'Matches the map.' : ''}
              </div>
            )}
            {shown.map(row => (
              <div key={row.key}
                className={'GriefUndo__row'
                  + (row.ticked ? '' : ' GriefUndo__row--skipped')}>
                <Button.Checkbox
                  checked={row.ticked}
                  onClick={() => act('tick', { key: row.key })} />
                <div className="GriefUndo__what">
                  <div>
                    <span className={row.air_only
                      ? 'GriefUndo__air'
                      : 'GriefUndo__restore'}>
                      {row.what.join(' · ')}
                    </span>
                  </div>
                  <div className="GriefUndo__muted">
                    {row.area} ({row.x}, {row.y})
                    {!!row.near && (
                      <span className="GriefUndo__tag">near player</span>
                    )}
                  </div>
                </div>
                <Button icon="arrow-right" content="JMP"
                  onClick={() => act('jump', { key: row.key })} />
              </div>
            ))}
          </div>
          <div className="GriefUndo__adds">
            <div className="GriefUndo__head">Not in the map</div>
            {adds.length === 0 && (
              <div className="GriefUndo__empty">None.</div>
            )}
            {adds.map(add => (
              <div key={add.ref} className="GriefUndo__row">
                <div className="GriefUndo__what">
                  <div className="GriefUndo__added">{add.name}</div>
                  <div className="GriefUndo__muted" title={add.type}>
                    {add.area} ({add.x}, {add.y})
                  </div>
                </div>
                <Button content="JMP"
                  onClick={() => act('add_jump', { ref: add.ref })} />
                <Button content="VV"
                  onClick={() => act('add_vv', { ref: add.ref })} />
                <Button icon="trash"
                  content={this.state.confirmDel === add.ref ? 'Sure?' : 'Del'}
                  color="bad"
                  onClick={() => {
                    if (this.state.confirmDel === add.ref) {
                      this.setState({ confirmDel: null });
                      act('add_delete', { ref: add.ref });
                    }
                    else {
                      this.setState({ confirmDel: add.ref });
                    }
                  }} />
              </div>
            ))}
          </div>
        </div>
        <div className="GriefUndo__foot">
          <Button icon="check" color="good"
            content={'Apply ' + data.ticked
              + ' tile' + (data.ticked === 1 ? '' : 's')}
            disabled={!data.ticked}
            onClick={() => act('apply')} />
          <Button icon="undo"
            content="Undo last"
            disabled={!data.undo}
            title={data.undo || ''}
            onClick={() => act('undo')} />
          {!!data.undo && (
            <span className="GriefUndo__muted GriefUndo__undoWhat">
              {data.undo}
            </span>
          )}
        </div>
      </div>
    );
  }
}
