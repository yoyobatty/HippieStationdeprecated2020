// hippie -- debug and mapping reports (admin_reports_tgui.dm)
import { decodeHtmlEntities } from 'common/string';
import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, Input } from '../components';

const text = value => decodeHtmlEntities(String(value || ''));

export class AdminReport extends Component {
  constructor() {
    super();
    this.state = { search: '', only: null };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const groups = data.groups || [];
    const rows = data.rows || [];
    const query = this.state.search.toLowerCase();
    const only = this.state.only;
    const shown = rows.filter(r => (!only || r.group === only)
      && (!query || [r.text, r.detail, r.area]
        .some(v => String(v || '').toLowerCase().includes(query))));
    const labels = {};
    for (let g of groups) {
      labels[g.id] = g;
    }
    return (
      <Fragment>
        <Box className="AdminReports__summary">{text(data.summary)}</Box>
        <Box className="AdminReports__groups">
          {groups.map(g => {
            const count = rows.filter(r => r.group === g.id).length;
            return (
              <span key={g.id}
                className={'AdminReports__group AdminReports__group--'
                  + g.level
                  + (only === g.id ? ' AdminReports__group--on' : '')
                  + (count ? '' : ' AdminReports__group--none')}
                onClick={() => this.setState({
                  only: only === g.id ? null : g.id,
                })}>
                {g.label}
                <b>{' ' + count}</b>
              </span>
            );
          })}
        </Box>
        <Box mb={1}>
          <Input fluid placeholder="Search..."
            value={this.state.search}
            onInput={(e, value) => this.setState({ search: value })} />
        </Box>
        {rows.length === 0 && (
          <Box className="AdminReports__clear">
            <Icon name="check" mr={1} />
            Nothing wrong.
          </Box>
        )}
        {rows.length > 0 && shown.length === 0 && (
          <Box color="label">Nothing matches.</Box>
        )}
        {shown.slice(0, 1000).map((r, i) => (
          <Box key={i} className="AdminReports__row">
            {!only && groups.length > 1 && (
              <span className={'AdminReports__tag AdminReports__tag--'
                + (labels[r.group] ? labels[r.group].level : 'info')}>
                {labels[r.group] ? labels[r.group].label : r.group}
              </span>
            )}
            <Box className="AdminReports__rowMain">
              <b>{text(r.text)}</b>
              {!!r.detail && (
                <Box className="AdminReports__muted">{text(r.detail)}</Box>
              )}
            </Box>
            {!!r.x && (
              <span className="AdminReports__where"
                onClick={() => act('jump', { x: r.x, y: r.y, z: r.z })}>
                {text(r.area) + ' ' + r.x + ',' + r.y + ',' + r.z}
              </span>
            )}
            {!!r.ref && (
              <Button content="VV" onClick={() => act('vv', { ref: r.ref })} />
            )}
          </Box>
        ))}
        {shown.length > 1000 && (
          <Box color="label">{'and ' + (shown.length - 1000) + ' more'}</Box>
        )}
      </Fragment>
    );
  }
}

const DEL_COLUMNS = [
  ['path', 'Type'],
  ['qdels', 'qdel()s'],
  ['destroy_ms', 'Destroy ms'],
  ['failures', 'Failed'],
  ['hard', 'Hard dels'],
  ['hard_ms', 'Hard del ms'],
  ['slept', 'Slept'],
  ['no_force', 'Ignored force'],
  ['no_hint', 'No hint'],
];

export class AdminDelLog extends Component {
  constructor() {
    super();
    this.state = { search: '', sort: 'destroy_ms', desc: true };
  }

  render() {
    const { data } = useBackend(this.props);
    const { sort, desc, search } = this.state;
    const query = search.toLowerCase();
    const items = (data.items || [])
      .filter(i => !query || i.path.toLowerCase().includes(query))
      .sort((a, b) => {
        const x = a[sort];
        const y = b[sort];
        const order = x < y ? -1 : x > y ? 1 : 0;
        return desc ? -order : order;
      });
    return (
      <Fragment>
        <Box mb={1}>
          <Input fluid placeholder="Search types..." value={search}
            onInput={(e, value) => this.setState({ search: value })} />
        </Box>
        <table className="AdminReports__table">
          <thead>
            <tr>
              {DEL_COLUMNS.map(([key, label]) => (
                <th key={key}
                  className={sort === key ? 'AdminReports__sorted' : null}
                  onClick={() => this.setState({
                    sort: key,
                    desc: sort === key ? !desc : key !== 'path',
                  })}>
                  {label}
                  {sort === key && (
                    <Icon name={desc ? 'caret-down' : 'caret-up'} ml={0.5} />
                  )}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {items.slice(0, 1500).map(i => (
              <tr key={i.path}
                className={i.hard ? 'AdminReports__hard' : null}>
                <td className="AdminReports__path">{i.path}</td>
                {DEL_COLUMNS.slice(1).map(([key]) => (
                  <td key={key} className="AdminReports__num">
                    {i[key]
                      ? (key.endsWith('_ms') ? Math.round(i[key]) : i[key])
                      : ''}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </Fragment>
    );
  }
}
