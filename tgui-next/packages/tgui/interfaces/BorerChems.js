import { useBackend } from '../backend';
import { Icon } from '../components';

// hippie -- the borer's Secrete Chemicals: its reservoir, its host, and each
// chemical as a vial in its reagent's colour with what it costs and does.
// Data and actions from hippiestation/code/game/gamemodes/miniantags/borer/
// borer_tgui.dm; a squirt goes through the borer's Topic().

export const BorerChems = props => {
  const { act, data } = useBackend(props);
  const { chemicals, max, host, can_secrete, docile } = data;
  const chems = data.chems || [];
  const pct = Math.max(0, Math.min(100, chemicals / Math.max(max, 1) * 100));
  return (
    <div className="Borer">
      <div className="Borer__head">
        <div className="Borer__reservoir">
          <div className="Borer__fluid" style={{ height: pct + '%' }} />
          <div className="Borer__amount">{chemicals}</div>
        </div>
        <div className="Borer__headText">
          <div className="Borer__title">Chemical reservoir</div>
          <div className="Borer__host">
            {host ? (
              <span><Icon name="brain" /> in {host}</span>
            ) : (
              <span className="Borer__warn">No host</span>
            )}
          </div>
          {!!docile && <div className="Borer__warn">Too docile</div>}
        </div>
      </div>
      <div className="Borer__list">
        {chems.map(chem => {
          const off = !can_secrete || chemicals < chem.cost;
          return (
            <div key={chem.id} className="Borer__chem">
              <div className="Borer__vial">
                <div
                  className="Borer__vialFluid"
                  style={{ 'background-color': chem.color }} />
              </div>
              <div className="Borer__chemText">
                <div className="Borer__chemName">
                  {chem.name}
                  <span className="Borer__chemDose">{chem.dose}u</span>
                </div>
                <div className="Borer__chemDesc">{chem.desc}</div>
              </div>
              <div
                className={'Borer__squirt' + (off ? ' Borer__squirt--off' : '')}
                onClick={off ? null : () => act('secrete', { id: chem.id })}>
                {chem.cost}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
};
