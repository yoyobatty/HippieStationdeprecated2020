import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, LabeledList, ProgressBar, Section } from '../components';

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
