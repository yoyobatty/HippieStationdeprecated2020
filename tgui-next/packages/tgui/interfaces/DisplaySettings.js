import { act } from '../byond';
import { Button, LabeledList, Section } from '../components';

const Choices = props => {
  const { ref, action, choices } = props;
  return choices.map(choice => (
    <Button
      key={choice.path}
      content={choice.name}
      selected={choice.picked}
      onClick={() => act(ref, action, { path: choice.path })} />
  ));
};

export const DisplaySettings = props => {
  const { state } = props;
  const { config, data } = state;
  const { ref } = config;
  return (
    <div>
      <Section title="Map">
        <LabeledList>
          <LabeledList.Item label="Icon size">
            <Choices ref={ref} action="size" choices={data.sizes} />
          </LabeledList.Item>
          <LabeledList.Item label="Scaling">
            <Choices ref={ref} action="scaling" choices={data.scalings} />
          </LabeledList.Item>
          <LabeledList.Item label="Viewport">
            <Button
              content="Fit now"
              onClick={() => act(ref, 'fit')} />
            <Button.Checkbox
              content="Keep fitted"
              checked={data.auto_fit}
              onClick={() => act(ref, 'auto_fit')} />
          </LabeledList.Item>
        </LabeledList>
      </Section>
      <Section title="Window">
        <LabeledList>
          <LabeledList.Item label="Fullscreen">
            <Button.Checkbox
              content="No title bar (F11)"
              checked={data.fullscreen}
              onClick={() => act(ref, 'fullscreen')} />
          </LabeledList.Item>
          <LabeledList.Item label="Theme">
            <Button.Checkbox
              content="Dark"
              checked={data.dark}
              onClick={() => act(ref, 'dark')} />
          </LabeledList.Item>
          <LabeledList.Item label="Screenshot">
            <Button
              content="Quick (F2)"
              onClick={() => act(ref, 'screenshot')} />
            <Button
              content="Save as... (Shift+F2)"
              onClick={() => act(ref, 'screenshot', { ask: 1 })} />
          </LabeledList.Item>
        </LabeledList>
      </Section>
    </div>
  );
};
