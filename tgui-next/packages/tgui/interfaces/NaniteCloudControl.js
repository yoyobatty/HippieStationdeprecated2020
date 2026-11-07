import { Component } from 'inferno';
import { useBackend } from '../backend';
import { Icon, NumberInput } from '../components';
import { DiskSlot, Key, ProgramChip, ProgramDetail } from './NaniteParts';

// hippie -- the cloud controller: the disk slot and the backups down one side,
// the open backup's programs as chips with the
// picked one's details and rules beside them. Data and actions as before
// (code/modules/research/nanites/nanite_cloud_controller.dm).
export class NaniteCloudControl extends Component {
  constructor() {
    super();
    this.state = { picked: null };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const {
      has_disk,
      has_program,
      disk,
      current_view,
      new_backup_id,
      cloud_backup,
    } = data;
    const backups = data.cloud_backups || [];
    const programs = data.cloud_programs || [];
    const canRule = !!(disk && disk.can_rule);
    let picked = programs.find(program => program.id === this.state.picked);
    if (!picked && programs.length) {
      picked = programs[0];
    }
    return (
      <div className="Nanites">
        <div className="Nanites__bar">
          <div className="Nanites__title">
            Nanite Cloud
            {!!current_view && (
              <span className="Nanites__subtitle">backup #{current_view}</span>
            )}
          </div>
          {!!current_view && (
            <Key
              icon="arrow-left"
              content="Backups"
              onClick={() => act('set_view', { view: 0 })} />
          )}
        </div>
        <div className="Nanites__body">
          <div className="Nanites__col Nanites__col--side">
            <div className="Nanites__heading">Disk</div>
            <DiskSlot has_disk={has_disk} has_program={has_program} disk={disk}>
              {!!has_disk && (
                <Key icon="eject" title="Eject" onClick={() => act('eject')} />
              )}
            </DiskSlot>
            <div className="Nanites__heading" style={{ 'margin-top': '12px' }}>
              Backups
              <span className="Nanites__headingRight">
                <NumberInput
                  value={new_backup_id}
                  minValue={1}
                  maxValue={100}
                  stepPixelSize={4}
                  width="38px"
                  onChange={(e, value) => act('update_new_backup_value', {
                    value,
                  })} />
                <Key
                  icon="plus"
                  title="New backup"
                  onClick={() => act('create_backup')} />
              </span>
            </div>
            {!current_view && backups.length === 0 && (
              <div className="Nanites__desc">None</div>
            )}
            {!current_view && backups.map(backup => (
              <div
                key={backup.cloud_id}
                className="Nanites__backup"
                onClick={() => {
                  this.setState({ picked: null });
                  act('set_view', { view: backup.cloud_id });
                }}>
                <Icon name="cloud" />
                <span className="Nanites__backupId">#{backup.cloud_id}</span>
              </div>
            ))}
            {!!current_view && (
              <div className="Nanites__backup Nanites__backup--selected">
                <Icon name="cloud" />
                <span className="Nanites__backupId">#{current_view}</span>
                <span
                  className="Nanites__headingRight"
                  style={{ color: '#71838f', 'font-size': '11px' }}>
                  {programs.length} program{programs.length === 1 ? '' : 's'}
                </span>
              </div>
            )}
          </div>
          <div className="Nanites__col Nanites__col--main">
            {!current_view ? (
              <div className="Nanites__notice">Open a backup</div>
            ) : !cloud_backup ? (
              <div className="Nanites__notice">Backup not found</div>
            ) : (
              <div>
                <div className="Nanites__heading">
                  Programs
                  <span className="Nanites__headingRight">
                    <Key
                      icon="upload"
                      content="Upload disk"
                      disabled={!has_program}
                      onClick={() => act('upload_program')} />
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
                      onClick={() => this.setState({ picked: program.id })}
                      onRemove={() => act('remove_program', {
                        program_id: program.id,
                      })} />
                  ))}
                </div>
                {!!picked && (
                  <div style={{
                    'margin-top': '10px',
                    'padding-top': '8px',
                    'border-top': '1px solid #26343c',
                  }}>
                    <ProgramDetail
                      program={picked}
                      rules={(
                        <div>
                          <div className="Nanites__heading">
                            Rules
                            {canRule && (
                              <span className="Nanites__headingRight">
                                <Key
                                  icon="plus"
                                  content="Add from disk"
                                  onClick={() => act('add_rule', {
                                    program_id: picked.id,
                                  })} />
                              </span>
                            )}
                          </div>
                          {!(picked.rules && picked.rules.length) && (
                            <div className="Nanites__desc">None</div>
                          )}
                          {(picked.rules || []).map(rule => (
                            <div key={rule.id} className="Nanites__rule">
                              <Icon name="filter" />
                              <span style={{ flex: 1 }}>{rule.display}</span>
                              <div
                                className="Nanites__chipRemove"
                                title="Remove"
                                onClick={() => act('remove_rule', {
                                  program_id: picked.id,
                                  rule_id: rule.id,
                                })}>
                                <Icon name="times" />
                              </div>
                            </div>
                          ))}
                        </div>
                      )} />
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      </div>
    );
  }
}
