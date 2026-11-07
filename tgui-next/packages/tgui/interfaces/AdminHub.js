import { useBackend } from '../backend';
import { Icon } from '../components';
import { AdminAlerts } from './AdminAlerts';
import { AdminFind } from './AdminFind';
import { BanWindow } from './BanWindow';
import { LogSearch } from './LogSearch';
import { PlayerProfile } from './PlayerProfile';
import { Questions } from './Questions';
import { Tickets } from './Tickets';

// hippie -- the admin hub: the admin tools as tabs across the top, with
// counts, and a player's profile as a panel at the right. Each tab is the
// same tool its own window shows: the server hands over that tool's data,
// and passes the tab's actions to it (the profile panel's go with "p:" in
// front). Data and actions from hippiestation/code/modules/admin/admin_hub.dm.

const TABS = [
  ['tickets', 'Tickets', 'question-circle', Tickets],
  ['questions', 'Questions', 'comments', Questions],
  ['alerts', 'Alerts', 'bell', AdminAlerts],
  ['logs', 'Logs', 'stream', LogSearch],
  ['find', 'Find', 'search-location', AdminFind],
  ['bans', 'Bans', 'gavel', BanWindow],
];

export const AdminHub = props => {
  const { act, data } = useBackend(props);
  const counts = data.counts || {};
  const current = TABS.find(t => t[0] === data.tab) || TABS[0];
  const Tool = current[3];
  // a tool's own props: the same window, its own part of the data
  const withData = part => ({
    ...props,
    state: { ...props.state, data: part || {} },
  });
  return (
    <div className="AdminHub">
      <div className="AdminHub__tabs">
        {TABS.map(t => {
          const c = counts[t[0]];
          return (
            <span key={t[0]}
              className={'AdminHub__tab'
                + (t[0] === current[0] ? ' AdminHub__tab--on' : '')}
              title={c ? c.title : ''}
              onClick={() => act('hub_tab', { tab: t[0] })}>
              <Icon name={t[2]} mr={1} />
              {t[1]}
              {!!c && c.count > 0 && (
                <span className={'AdminHub__count'
                  + (c.hot > 0 ? ' AdminHub__count--hot' : '')}>
                  {c.count}
                </span>
              )}
            </span>
          );
        })}
        <span className="AdminHub__spacer" />
      </div>
      <div className="AdminHub__body">
        <div className="AdminHub__tool">
          <Tool key={current[0]} {...withData(data.tool)} />
        </div>
        {!!data.profile && (
          <div className="AdminHub__side">
            <span className="AdminHub__close" title="Close the profile"
              onClick={() => act('hub_profile_close')}>
              <Icon name="times" />
            </span>
            <PlayerProfile {...withData(data.profile)} actPrefix="p:" compact />
          </div>
        )}
      </div>
    </div>
  );
};
