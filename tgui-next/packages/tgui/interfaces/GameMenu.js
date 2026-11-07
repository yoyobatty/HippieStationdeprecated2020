import { useBackend } from '../backend';
import { Icon } from '../components';

// hippie -- the game menu: Esc with the chat bar empty, or the stat panel's
// Menu button. Data and actions from
// hippiestation/code/modules/client/game_menu.dm.

const Item = props => {
  const { act, action, icon, label, hint, bad } = props;
  return (
    <div className={'GameMenu__item' + (bad ? ' GameMenu__item--bad' : '')}
      onClick={() => act(action)}>
      <Icon name={icon} className="GameMenu__icon" />
      <span className="GameMenu__label">{label}</span>
      {!!hint && <span className="GameMenu__hint">{hint}</span>}
    </div>
  );
};

export const GameMenu = props => {
  const { act, data } = useBackend(props);
  return (
    <div className="GameMenu">
      <Item act={act} action="setup" icon="user" label="Character Setup" />
      <Item act={act} action="keybindings" icon="keyboard"
        label="Keybindings" />
      <Item act={act} action="preferences" icon="cog" label="Preferences" />
      <div className="GameMenu__rule" />
      <Item act={act} action="help" icon="question-circle"
        label={data.has_ticket ? 'Your ticket' : 'Ask for help'} hint="F1" />
      {!!data.admin && (
        <Item act={act} action="hub" icon="shield-alt" label="Admin hub"
          hint="F9" />
      )}
      <Item act={act} action="who" icon="users" label="Who" />
      <div className="GameMenu__rule" />
      {!!data.has_rules && (
        <Item act={act} action="rules" icon="gavel" label="Rules" />
      )}
      {!!data.has_wiki && (
        <Item act={act} action="wiki" icon="book" label="Wiki" />
      )}
      <Item act={act} action="changelog" icon="newspaper" label="Changelog" />
      <div className="GameMenu__rule" />
      <Item act={act} action="disconnect" icon="power-off" bad
        label={data.disconnect_armed ? 'Disconnect?' : 'Disconnect'}
        hint={data.disconnect_armed ? 'click again' : null} />
    </div>
  );
};
