import { useBackend } from '../backend';
import { Icon } from '../components';

// hippie -- a silicon's laws as a law board: each law a module in its kind's
// colour (law 0, hacked, ion, core, added, the devil's), with a switch for
// whether State Laws says it, then State Laws. Data and actions from
// hippiestation/code/modules/mob/living/silicon/laws_tgui.dm.

const KINDS = {
  devil: 'Infernal',
  zeroth: 'Zeroth',
  hacked: 'Hacked',
  ion: 'Ion',
  inherent: 'Core',
  supplied: 'Added',
};

export const SiliconLaws = props => {
  const { act, data } = useBackend(props);
  const laws = data.laws || [];
  const stated = laws.filter(law => law.stated).length;
  return (
    <div className="Laws">
      <div className="Laws__head">
        <div className="Laws__title">
          <Icon name="microchip" />
          {data.lawset && data.lawset !== 'Unknown Laws' ? data.lawset : 'Laws'}
        </div>
        <div className="Laws__count">{stated} of {laws.length} to state</div>
      </div>
      <div className="Laws__list">
        {laws.length === 0 && (
          <div className="Laws__none">No laws</div>
        )}
        {laws.map(law => (
          <div
            key={law.key + law.index}
            className={'Laws__law Laws__law--' + law.kind
              + (law.stated ? '' : ' Laws__law--quiet')}>
            <div className="Laws__number">{law.number}</div>
            <div className="Laws__text">
              <div className="Laws__kind">{KINDS[law.kind]}</div>
              {law.text}
            </div>
            <div
              className={'Laws__switch'
                + (law.stated ? ' Laws__switch--on' : '')}
              title={law.stated ? 'Stated' : 'Kept quiet'}
              onClick={() => act('toggle', { key: law.key, index: law.index })}>
              <div className="Laws__knob" />
            </div>
          </div>
        ))}
      </div>
      <div className="Laws__foot">
        {!!data.radio && (
          <span className="Laws__radio">
            <Icon name="broadcast-tower" /> {data.radio}
          </span>
        )}
        <div className="Laws__state" onClick={() => act('state')}>
          <Icon name="bullhorn" /> State Laws
        </div>
      </div>
    </div>
  );
};
