import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, ProgressBar, Section } from '../components';

// hippie -- the gun locker and the janitorial cart moved off their old HTML
// windows: what's inside as item cards with pictures; click one to take it.
// Data from hippiestation/code/game/objects/structures/storage_tgui.dm.

const ItemCard = props => {
  const { icon, name, info, empty, onClick } = props;
  return (
    <div
      className={'Storage__card' + (empty ? ' Storage__card--empty' : '')}
      title={empty ? null : 'Take ' + name}
      onClick={() => !empty && onClick()}>
      <div className="Storage__picture">
        {!!icon && (
          <img src={icon} width="64px" height="64px" />
        )}
      </div>
      <div className="Storage__name">{name}</div>
      <Box fontSize="11px" color={empty ? 'label' : 'average'}>
        {info || ' '}
      </Box>
    </div>
  );
};

export const GunLocker = props => {
  const { act, data } = useBackend(props);
  const guns = data.guns || [];
  return (
    <Section
      title={guns.length + ' / ' + data.capacity}
      buttons={(
        <Button
          icon="door-closed"
          content="Shut"
          onClick={() => act('shut')} />
      )}>
      <div className="Storage__grid">
        {guns.map(gun => (
          <ItemCard
            key={gun.ref}
            icon={gun.icon}
            name={gun.name}
            info={gun.ammo}
            onClick={() => act('take', { ref: gun.ref })} />
        ))}
      </div>
    </Section>
  );
};

export const JaniCart = props => {
  const { act, data } = useBackend(props);
  const slots = data.slots || [];
  return (
    <Fragment>
      <Section>
        <div className="Storage__grid">
          {slots.map(slot => (
            <ItemCard
              key={slot.key}
              icon={slot.icon}
              name={slot.name || slot.label}
              info={slot.name ? slot.info : 'Empty'}
              empty={!slot.name}
              onClick={() => act('take', { key: slot.key })} />
          ))}
        </div>
      </Section>
      <Section title="Water">
        <ProgressBar
          value={data.water_max ? data.water / data.water_max : 0}
          color="blue">
          {data.water} / {data.water_max} u
        </ProgressBar>
      </Section>
    </Fragment>
  );
};
