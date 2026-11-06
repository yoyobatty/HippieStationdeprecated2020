import { toFixed } from 'common/math';
import { Box } from '../../components';
import { getGasColor, getGasLabel } from '../../constants';

// hippie -- shared by the redone atmos windows (AirAlarm.js, Canister.js,
// PortableAtmos.js): a mixture as one bar split by gas in each gas's colour,
// with a legend. Gases come from tgui_gas_list() in hippiestation/code/
// modules/atmospherics/atmos_tgui.dm.

export const gasColor = id => getGasColor(id) || 'grey';

export const gasLabel = (id, name) => getGasLabel(id, name);

const DANGER_COLORS = ['good', 'average', 'bad'];

export const GasBar = props => {
  const { gases = [], height = '14px' } = props;
  const shown = gases.filter(gas => gas.percent >= 0.05);
  if (!shown.length) {
    return (
      <div className="Atmos__gasBar" style={{ height }}>
        <div className="Atmos__gasBarEmpty">empty</div>
      </div>
    );
  }
  return (
    <div className="Atmos__gasBar" style={{ height }}>
      {shown.map(gas => (
        <div
          key={gas.id}
          className={'Atmos__gasSegment color-bg-' + gasColor(gas.id)}
          title={gas.name + ': ' + toFixed(gas.percent, 2) + '%'}
          style={{ width: gas.percent + '%' }} />
      ))}
    </div>
  );
};

// Each gas as a coloured dot, its label and share; with showMoles, its
// moles too. A gas carrying danger (the air alarm's) is coloured by it.
export const GasLegend = props => {
  const { gases = [], showMoles } = props;
  return (
    <Box mt={0.5}>
      {gases.map(gas => (
        <Box
          key={gas.id}
          inline
          mr={1.5}
          nowrap
          title={gas.name}>
          <span className={'Atmos__dot color-bg-' + gasColor(gas.id)} />
          {gasLabel(gas.id, gas.name)}
          {' '}
          <Box
            inline
            bold
            color={gas.danger !== undefined
              ? DANGER_COLORS[gas.danger]
              : null}>
            {toFixed(gas.percent, gas.percent < 1 ? 2 : 1)}%
          </Box>
          {!!showMoles && (
            <Box inline color="label" ml={0.5}>
              ({toFixed(gas.moles, 1)} mol)
            </Box>
          )}
        </Box>
      ))}
    </Box>
  );
};

export const kelvinToCelsius = kelvin => toFixed(kelvin - 273.15, 1);
