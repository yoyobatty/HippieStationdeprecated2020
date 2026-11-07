import { useBackend } from '../backend';
import { ColorBox, Icon } from '../components';

// hippie -- the NtOS desktop: programs as tiles (a dot on the ones running,
// an x to close them), and the flashlight as quick settings. Data and
// actions from code/modules/modular_computers/computers/item/computer_ui.dm.

const PROGRAM_ICONS = {
  compconfig: 'cog',
  ntndownloader: 'download',
  filemanager: 'folder-open',
  smmonitor: 'radiation',
  alarmmonitor: 'bell',
  cardmod: 'id-card',
  ntnrc_client: 'comment-alt',
  nttransfer: 'exchange-alt',
  powermonitor: 'plug',
  aidiag: 'robot',
  contract: 'file-signature',
  uplink: 'user-secret',
  ntmonitor: 'network-wired',
  ntn_dos: 'bug',
  revelation: 'skull',
  stationmap: 'map',
  trafficctrl: 'broadcast-tower',
  trafficctrl_x: 'broadcast-tower',
};

export const NtosMain = props => {
  const { act, data } = useBackend(props);
  const {
    programs = [],
    has_light,
    light_on,
    comp_light_color,
  } = data;
  return (
    <div className="NtosDesk">
      {!!has_light && (
        <div className="NtosDesk__quick">
          <div
            className={'NtosDesk__quickTile'
              + (light_on ? ' NtosDesk__quickTile--on' : '')}
            onClick={() => act('PC_toggle_light')}>
            <Icon name="lightbulb" mr={1} />
            Flashlight
          </div>
          <div
            className="NtosDesk__quickTile"
            onClick={() => act('PC_light_color')}>
            <ColorBox mr={1} color={comp_light_color} />
            Colour
          </div>
        </div>
      )}
      <div className="NtosDesk__grid">
        {programs.map(program => (
          <div
            key={program.name}
            className={'NtosDesk__app'
              + (program.running ? ' NtosDesk__app--running' : '')}
            onClick={() => act('PC_runprogram', { name: program.name })}>
            <div className="NtosDesk__icon">
              <Icon name={PROGRAM_ICONS[program.name] || 'window-maximize'} />
            </div>
            <div className="NtosDesk__label">{program.desc}</div>
            {!!program.running && (
              <div
                className="NtosDesk__close"
                title="Close"
                onClick={e => {
                  e.stopPropagation();
                  act('PC_killprogram', { name: program.name });
                }}>
                <Icon name="times" />
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
};
