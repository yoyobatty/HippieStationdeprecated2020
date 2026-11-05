import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, LabeledList, NoticeBox, NumberInput, ProgressBar, Section } from '../components';

// hippie -- the arcade machines (hippiestation/code/game/machinery/computer/
// arcade_tgui.dm), where they were old browser pages

export const ArcadeBattle = props => {
  const { act, data } = useBackend(props);
  const {
    enemyName,
    message,
    playerHp,
    playerMp,
    enemyHp,
    gameover,
    blocked,
    emagged,
  } = data;
  return (
    <Fragment>
      <Section textAlign="center">
        <Box
          fontSize="20px"
          bold
          color={emagged ? 'bad' : 'average'}>
          {enemyName}
        </Box>
        <Box mt={1} fontSize="14px" style={{ 'min-height': '20px' }}>
          {message}
        </Box>
      </Section>
      <Section>
        <LabeledList>
          <LabeledList.Item label="Your health">
            <ProgressBar
              value={playerHp}
              minValue={0}
              maxValue={45}
              color={playerHp > 10 ? 'good' : 'bad'}>
              {playerHp}
            </ProgressBar>
          </LabeledList.Item>
          <LabeledList.Item label="Your magic">
            <ProgressBar
              value={playerMp}
              minValue={0}
              maxValue={20}
              color="blue">
              {playerMp}
            </ProgressBar>
          </LabeledList.Item>
          <LabeledList.Item label={'Enemy health'}>
            <ProgressBar
              value={enemyHp}
              minValue={0}
              maxValue={45}
              color="bad">
              {enemyHp}
            </ProgressBar>
          </LabeledList.Item>
        </LabeledList>
      </Section>
      {!!gameover && (
        <Button
          fluid
          icon="redo"
          color="good"
          textAlign="center"
          content="New game"
          onClick={() => act('newgame')} />
      ) || (
        <Box textAlign="center">
          <Button
            icon="fist-raised"
            disabled={blocked}
            content="Attack"
            onClick={() => act('attack')} />
          <Button
            icon="heart"
            disabled={blocked}
            content="Heal"
            tooltip="Costs magic"
            onClick={() => act('heal')} />
          <Button
            icon="bolt"
            disabled={blocked}
            content="Recharge power"
            onClick={() => act('charge')} />
        </Box>
      )}
    </Fragment>
  );
};

// Minesweeper's board values (arcade_tgui.dm): -10 to -1 flagged, 0 a hidden
// mine, 1 to 9 hidden, 10 the mine hit, 11 empty, 12 to 19 a revealed 1 to 8
const NUMBER_COLORS = ['', '#1976d2', '#388e3c', '#d32f2f', '#7b1fa2',
  '#ff8f00', '#0097a7', '#424242', '#9e9e9e'];

const Square = props => {
  const { value, playing, onReveal, onFlag } = props;
  const hidden = value < 10;
  let content = null;
  let className = 'Minesweeper__square';
  if (value < 0) {
    content = <Icon name="flag" color="bad" />;
  }
  else if (value === 0 && !playing) {
    content = <Icon name="bomb" />;
  }
  else if (value === 10) {
    content = <Icon name="bomb" />;
    className += ' Minesweeper__square--hit';
  }
  else if (value >= 12) {
    content = (
      <span style={{ color: NUMBER_COLORS[value - 11] }}>
        {value - 11}
      </span>
    );
  }
  if (!hidden) {
    className += ' Minesweeper__square--open';
  }
  return (
    <div
      className={className}
      onClick={() => playing && hidden && onReveal()}
      onContextMenu={e => {
        e.preventDefault();
        if (playing && hidden) {
          onFlag();
        }
      }}>
      {content}
    </div>
  );
};

export class ArcadeMinesweeper extends Component {
  constructor() {
    super();
    this.state = { rows: 12, columns: 12, mines: 20 };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const { rows, columns, mines } = this.state;
    const {
      status,
      emagged,
      iteration,
      difficulty,
      flagging,
      board = [],
    } = data;
    const menu = (
      <Box>
        <Button content="Easy (9x9, 10 mines)"
          onClick={() => act('Easy')} />
        <Button content="Intermediate (16x16, 40 mines)"
          onClick={() => act('Intermediate')} />
        <Button content="Hard (16x30, 99 mines)"
          onClick={() => act('Hard')} />
        <Box mt={1}>
          Custom:
          <NumberInput value={rows} minValue={4} maxValue={30} width="40px"
            ml={1} onChange={(e, value) => this.setState({ rows: value })} />
          {' rows '}
          <NumberInput value={columns} minValue={4} maxValue={50}
            width="40px"
            onChange={(e, value) => this.setState({ columns: value })} />
          {' columns '}
          <NumberInput value={mines} minValue={1} maxValue={1275}
            width="50px"
            onChange={(e, value) => this.setState({ mines: value })} />
          {' mines '}
          <Button content="Play"
            onClick={() => act('custom', { rows, columns, mines })} />
        </Box>
      </Box>
    );
    const title = emagged
      ? 'Minesweeper EXTREME EDITION: iteration #' + iteration
      : 'Minesweeper';
    if (status === 0) {
      return (
        <Section title={title}>
          <Box mb={1} color={emagged ? 'bad' : 'label'}>
            {emagged
              ? 'Explode in the game, explode in real life!'
              : 'Reveal all the squares without hitting a mine!'}
          </Box>
          {menu}
        </Section>
      );
    }
    const playing = status === 1;
    return (
      <Section
        title={title + ' · ' + difficulty + ' · ' + data.mines + ' mines'}
        buttons={(
          <Fragment>
            {playing && (
              <Button
                icon="flag"
                selected={flagging}
                content={'Flagging ' + (flagging ? 'on' : 'off')}
                tooltip="Or right-click a square"
                onClick={() => act('Flag')} />
            )}
            <Button
              icon="bars"
              content="Menu"
              onClick={() => act('Main_Menu')} />
          </Fragment>
        )}>
        {status === 3 && (
          <NoticeBox success>You cleared the board!</NoticeBox>
        )}
        {status === 2 && (
          <NoticeBox danger>Boom! You hit a mine.</NoticeBox>
        )}
        <div className="Minesweeper__board">
          {board.map((row, y) => (
            <div key={y} className="Minesweeper__row">
              {row.map((value, x) => (
                <Square
                  key={x}
                  value={value}
                  playing={playing}
                  onReveal={() => act(flagging ? 'flagsquare' : 'square',
                    { y: y + 1, x: x + 1 })}
                  onFlag={() => act('flagsquare', { y: y + 1, x: x + 1 })} />
              ))}
            </div>
          ))}
        </div>
        {!playing && (
          <Box mt={1}>
            <Button
              icon="redo"
              content="Play the same board"
              onClick={() => act('same_board')} />
            {menu}
          </Box>
        )}
      </Section>
    );
  }
}

// The Orion Trail's screens are the game's own HTML (arcade_tgui.dm). Its
// links are sent back as moves: "byond://?src=...;continue=1" -> continue.
const linkParams = href => {
  const params = {};
  const query = href.substring(href.indexOf('?') + 1);
  for (let pair of query.split(/[;&]/)) {
    const eq = pair.indexOf('=');
    if (eq > 0) {
      params[decodeURIComponent(pair.substring(0, eq))]
        = decodeURIComponent(pair.substring(eq + 1));
    }
  }
  delete params.src;
  return params;
};

export const ArcadeOrion = props => {
  const { act, data } = useBackend(props);
  const handleClick = e => {
    let node = e.target;
    while (node && node.tagName !== 'A') {
      node = node.parentNode;
    }
    if (!node || !node.getAttribute('href')) {
      return;
    }
    e.preventDefault();
    act('link', linkParams(node.getAttribute('href')));
  };
  return (
    <Section>
      <div
        className={'OrionTrail' + (data.emagged ? ' OrionTrail--emagged' : '')}
        onClick={handleClick}
        // eslint-disable-next-line react/no-danger
        dangerouslySetInnerHTML={{ __html: data.screen }} />
    </Section>
  );
};
