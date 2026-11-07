import { Component } from 'inferno';
import { useBackend } from '../backend';
import { Icon } from '../components';
import { DiskSlot, Key } from './NaniteParts';

// hippie -- the program hub: the disk slot, then the researched programs by
// category as cards, each with Download. The old
// window's detailed/compact switch is gone: every card has its description.
// Data and actions as before
// (code/modules/research/nanites/nanite_program_hub.dm).

const CATEGORY_ICONS = {
  Utility: 'tools',
  Medical: 'medkit',
  Sensor: 'satellite-dish',
  Augmentation: 'dumbbell',
  Suppression: 'hand-paper',
  Weaponized: 'skull-crossbones',
  Protocols: 'project-diagram',
};

// The backend's categories end in " Nanites"
const categoryLabel = category => category.replace(/ Nanites$/, '');

export class NaniteProgramHub extends Component {
  constructor() {
    super();
    this.state = { tab: null };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const {
      disk,
      has_disk,
      has_program,
    } = data;
    const programs = data.programs || {};
    const categories = Object.keys(programs);
    let tab = this.state.tab;
    if (!tab || !programs[tab]) {
      tab = categories[0];
    }
    const shown = (tab && programs[tab]) || [];
    return (
      <div className="Nanites">
        <div className="Nanites__bar">
          <div className="Nanites__title">Program Hub</div>
          <Key
            icon="sync"
            content="Sync research"
            onClick={() => act('refresh')} />
        </div>
        <div style={{ padding: '8px 10px' }}>
          <DiskSlot has_disk={has_disk} has_program={has_program} disk={disk}>
            {!!has_program && (
              <Key
                icon="eraser"
                title="Wipe the disk"
                onClick={() => act('clear')} />
            )}
            {!!has_disk && (
              <Key icon="eject" title="Eject" onClick={() => act('eject')} />
            )}
          </DiskSlot>
        </div>
        {categories.length === 0 ? (
          <div className="Nanites__notice">No programs researched</div>
        ) : (
          <div className="Nanites__tabs">
            {categories.map(category => (
              <div
                key={category}
                className={'Nanites__tab'
                  + (category === tab ? ' Nanites__tab--on' : '')}
                onClick={() => this.setState({ tab: category })}>
                <Icon
                  name={CATEGORY_ICONS[categoryLabel(category)] || 'microchip'}
                  mr={1} />
                {categoryLabel(category)}
                <span className="Nanites__tabCount">
                  {(programs[category] || []).length}
                </span>
              </div>
            ))}
          </div>
        )}
        <div className="Nanites__scroll">
          {shown.map(program => (
            <div key={program.id} className="Nanites__card">
              <div className="Nanites__cardText">
                <b>{program.name}</b>
                <span>{program.desc}</span>
              </div>
              <div className="Nanites__cardAction">
                <Key
                  icon="download"
                  content="Download"
                  disabled={!has_disk}
                  onClick={() => act('download', { program_id: program.id })} />
              </div>
            </div>
          ))}
        </div>
      </div>
    );
  }
}
