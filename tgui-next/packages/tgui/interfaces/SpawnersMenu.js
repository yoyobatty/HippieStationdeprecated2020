import { useBackend } from '../backend';
import { Icon } from '../components';

// hippie -- the ghost roles out there as cards: who you'd be, what they're
// about, anything you must know, how many are left, Jump and Spawn. Data
// and actions from code/datums/spawners_menu.dm.

export const SpawnersMenu = props => {
  const { act, data } = useBackend(props);
  const spawners = data.spawners || [];
  return (
    <div className="Spawners">
      {spawners.length === 0 && (
        <div className="Spawners__none">No ghost roles open</div>
      )}
      {spawners.map(spawner => (
        <div key={spawner.name} className="Spawners__card">
          <div className="Spawners__head">
            <span className="Spawners__name">{spawner.name}</span>
            <span className="Spawners__left">{spawner.amount_left} left</span>
            <div
              className="Spawners__key"
              onClick={() => act('jump', { name: spawner.name })}>
              <Icon name="eye" mr={0.5} />
              Jump
            </div>
            <div
              className="Spawners__key Spawners__key--go"
              onClick={() => act('spawn', { name: spawner.name })}>
              <Icon name="user-plus" mr={0.5} />
              Spawn
            </div>
          </div>
          {!!(spawner.short_desc || spawner.desc) && (
            <div className="Spawners__short">
              {spawner.short_desc || spawner.desc}
            </div>
          )}
          {!!spawner.flavor_text && (
            <div className="Spawners__flavor">{spawner.flavor_text}</div>
          )}
          {!!spawner.important_info && (
            <div className="Spawners__important">
              <Icon name="exclamation-triangle" mr={1} />
              {spawner.important_info}
            </div>
          )}
        </div>
      ))}
    </div>
  );
};
