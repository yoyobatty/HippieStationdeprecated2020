import { Component } from 'inferno';
import { useBackend } from '../backend';
import { Icon, NumberInput } from '../components';
import {
  ConfirmKey, Key, ProgramChip, ProgramDetail, SwarmMeter,
} from './NaniteParts';

// hippie -- the chamber console: the occupant's swarm as a meter with its
// safety line, its settings, and its programs as chips
// with the picked one's details beside them (as much as the chamber's scan
// level shows). Data and actions as before
// (code/modules/research/nanites/nanite_chamber_computer.dm, nanite_ui_data()
// in code/datums/components/nanites.dm).
export class NaniteChamberControl extends Component {
  constructor() {
    super();
    this.state = { picked: null };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const {
      status_msg,
      locked,
      occupant_name,
      has_nanites,
      nanite_volume,
      max_nanites,
      regen_rate,
      safety_threshold,
      cloud_id,
      scan_level,
    } = data;
    const programs = data.mob_programs || [];
    if (status_msg) {
      return (
        <div className="Nanites">
          <div className="Nanites__bar">
            <div className="Nanites__title">Nanite Chamber</div>
          </div>
          <div className="Nanites__notice">{status_msg}</div>
        </div>
      );
    }
    let picked = programs.find(program => program.id === this.state.picked);
    if (!picked && programs.length) {
      picked = programs[0];
    }
    return (
      <div className="Nanites">
        <div className="Nanites__bar">
          <div className="Nanites__title">
            {occupant_name}
            <span className="Nanites__subtitle">scan level {scan_level}</span>
          </div>
          <Key
            icon={locked ? 'lock' : 'lock-open'}
            content={locked ? 'Locked' : 'Unlocked'}
            on={locked}
            onClick={() => act('toggle_lock')} />
        </div>
        {!has_nanites ? (
          <div className="Nanites__notice">
            <div style={{ 'margin-bottom': '10px' }}>No nanites</div>
            <Key
              icon="syringe"
              content="Implant nanites"
              onClick={() => act('nanite_injection')} />
          </div>
        ) : (
          <div className="Nanites__body" style={{ 'flex-direction': 'column' }}>
            <div style={{ padding: '10px 10px 4px' }}>
              <SwarmMeter
                volume={nanite_volume}
                max={max_nanites || 500}
                safety={safety_threshold}
                regen={regen_rate} />
              <div className="Nanites__settings">
                <div className="Nanites__setting">
                  Safety
                  <NumberInput
                    value={safety_threshold}
                    minValue={0}
                    maxValue={500}
                    width="48px"
                    onChange={(e, value) => act('set_safety', { value })} />
                </div>
                <div className="Nanites__setting">
                  Cloud
                  <NumberInput
                    value={cloud_id}
                    minValue={0}
                    maxValue={100}
                    step={1}
                    stepPixelSize={3}
                    width="40px"
                    format={value => (value ? value : 'off')}
                    onChange={(e, value) => act('set_cloud', { value })} />
                </div>
                <div className="Nanites__setting Nanites__setting--right">
                  <ConfirmKey
                    icon="radiation"
                    content="Purge"
                    armedContent="Purge all nanites?"
                    onClick={() => act('remove_nanites')} />
                </div>
              </div>
            </div>
            <div
              className="Nanites__body"
              style={{ 'border-top': '1px solid #26343c' }}>
              <div className="Nanites__col Nanites__col--side">
                <div className="Nanites__heading">
                  Programs
                  <span className="Nanites__headingRight">
                    {programs.length}
                  </span>
                </div>
                {programs.length === 0 && (
                  <div className="Nanites__desc">None</div>
                )}
                <div className="Nanites__chips">
                  {programs.map(program => (
                    <ProgramChip
                      key={program.id}
                      program={program}
                      selected={picked && picked.id === program.id}
                      onClick={() => this.setState({ picked: program.id })} />
                  ))}
                </div>
              </div>
              <div className="Nanites__col Nanites__col--main">
                <ProgramDetail
                  program={picked}
                  rules={picked && picked.rules && picked.rules.length > 0 && (
                    <div>
                      <div className="Nanites__heading">Rules</div>
                      {picked.rules.map(rule => (
                        <div key={rule.id} className="Nanites__rule">
                          <Icon name="filter" />
                          {rule.display}
                        </div>
                      ))}
                    </div>
                  )} />
              </div>
            </div>
          </div>
        )}
      </div>
    );
  }
}
