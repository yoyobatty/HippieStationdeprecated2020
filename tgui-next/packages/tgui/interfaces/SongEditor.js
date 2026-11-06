import { decodeHtmlEntities } from 'common/string';
import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Collapsible, Input, LabeledList, NumberInput, Section } from '../components';

// hippie -- the instrument song editor moved off its old HTML window: Play
// and Stop with repeats, the tempo in BPM, each line typed in place, a song
// pasted in whole. Data from hippiestation/code/game/objects/structures/
// song_tgui.dm.

export class SongEditor extends Component {
  constructor() {
    super();
    this.state = { newLine: '', importing: false, importText: '' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const { newLine, importing, importText } = this.state;
    const lines = data.lines || [];
    return (
      <Fragment>
        <Section
          title="Playback"
          buttons={(
            <Fragment>
              <Button
                icon="play"
                content="Play"
                color="good"
                disabled={data.playing || !lines.length}
                onClick={() => act('play')} />
              <Button
                icon="stop"
                content="Stop"
                color={data.playing ? 'bad' : 'default'}
                disabled={!data.playing}
                onClick={() => act('stop')} />
            </Fragment>
          )}>
          <LabeledList>
            <LabeledList.Item label="Tempo">
              <NumberInput
                width="70px"
                unit="BPM"
                value={data.bpm}
                minValue={1}
                maxValue={600}
                step={5}
                stepPixelSize={2}
                onChange={(e, value) => act('bpm', { bpm: value })} />
            </LabeledList.Item>
            <LabeledList.Item label={data.playing ? 'Repeats left' : 'Repeat'}>
              {data.playing && (
                <b>{data.repeat}</b>
              ) || (
                <NumberInput
                  width="50px"
                  value={data.repeat}
                  minValue={0}
                  maxValue={data.max_repeats}
                  onChange={(e, value) => act('repeat', { repeat: value })} />
              )}
            </LabeledList.Item>
          </LabeledList>
        </Section>
        <Section
          title={'Lines (' + lines.length + '/' + data.max_lines + ')'}
          buttons={(
            <Fragment>
              <Button
                icon="file-import"
                content="Import"
                selected={importing}
                onClick={() => this.setState({ importing: !importing })} />
              <Button
                icon="file"
                content="New Song"
                onClick={() => act('newsong')} />
            </Fragment>
          )}>
          {importing && (
            <Box mb={1}>
              <textarea
                className="SongEditor__import"
                value={importText}
                placeholder="BPM: 120"
                onInput={e => this.setState({ importText: e.target.value })} />
              <Button
                icon="check"
                content="Load"
                disabled={!importText}
                onClick={() => {
                  act('import', { text: importText });
                  this.setState({ importing: false, importText: '' });
                }} />
            </Box>
          )}
          {lines.map((line, i) => (
            <Box key={i} className="SongEditor__line">
              <Box inline width="34px" color="label">{i + 1}</Box>
              <Input
                width="400px"
                className="SongEditor__notes"
                value={decodeHtmlEntities(line)}
                onChange={(e, value) => act('editline', {
                  line: i + 1,
                  text: value,
                })} />
              <Button
                icon="times"
                color="bad"
                onClick={() => act('deleteline', { line: i + 1 })} />
            </Box>
          ))}
          <Box mt={1}>
            <Box inline width="34px" color="label">+</Box>
            <Input
              width="400px"
              className="SongEditor__notes"
              placeholder="C,D,E-G,,A/2"
              value={newLine}
              onInput={(e, value) => this.setState({ newLine: value })} />
            <Button
              icon="plus"
              content="Add"
              disabled={!newLine || lines.length >= data.max_lines}
              onClick={() => {
                act('addline', { text: newLine });
                this.setState({ newLine: '' });
              }} />
          </Box>
        </Section>
        <Collapsible title="Help">
          <Box fontSize="11px" p={1}>
            Lines are a series of chords, separated by commas (,), each with
            notes separated by hyphens (-). Every note in a chord will play
            together, with chord timed by the tempo.<br />
            Notes are played by the names of the note, and optionally, the
            accidental, and/or the octave number. By default, every note is
            natural and in octave 3. Defining otherwise is remembered for each
            note.<br />
            Example: <i>C,D,E,F,G,A,B</i> will play a C major scale.<br />
            After a note has an accidental placed, it will be remembered:
            <i> C,C4,C,C3</i> is <i>C3,C4,C4,C3</i><br />
            Chords can be played simply by seperating each note with a
            hyphon: <i>A-C#,Cn-E,E-G#,Gn-B</i><br />
            A pause may be denoted by an empty chord: <i>C,E,,C,G</i><br />
            To make a chord be a different time, end it with /x, where the
            chord length will be length defined by tempo / x:
            <i> C,G/2,E/4</i><br />
            Combined, an example is: <i>E-E4/4,F#/2,G#/8,B/8,E3-E4/4</i><br />
            Lines may be up to {data.max_chars} characters. A song may only
            contain up to {data.max_lines} lines.
          </Box>
        </Collapsible>
      </Fragment>
    );
  }
}
