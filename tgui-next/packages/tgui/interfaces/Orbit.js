import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Section } from '../components';
import { Searchable } from './common/Searchable';

// [data key, section title, button colour]
const SECTIONS = [
  ['antagonists', 'Antagonists', 'bad'],
  ['alive', 'Alive', 'good'],
  ['npcs', 'Bots and NPCs', 'average'],
  ['misc', 'Points of interest', null],
  ['dead', 'Dead', 'transparent'],
  ['ghosts', 'Ghosts', 'transparent'],
];

export const Orbit = props => {
  const { act, data } = useBackend(props);
  return (
    <Fragment>
      <Box textAlign="right" mb={-3}>
        <Button
          icon="sync"
          content="Refresh"
          onClick={() => act('refresh')} />
      </Box>
      <Searchable placeholder="Search names...">
        {matches => {
          const sections = SECTIONS.map(([key, title, color]) => {
            const entries = (data[key] || [])
              .filter(entry => matches(entry.name, entry.antag));
            if (!entries.length) {
              return null;
            }
            return (
              <Section key={key} title={title + ' (' + entries.length + ')'}>
                {entries.map(entry => (
                  <Button
                    key={entry.ref}
                    color={color}
                    content={entry.name}
                    title={entry.antag}
                    onClick={() => act('orbit', { ref: entry.ref })} />
                ))}
              </Section>
            );
          }).filter(section => section);
          if (!sections.length) {
            return (
              <Box color="label">
                Nothing matches that search.
              </Box>
            );
          }
          return sections;
        }}
      </Searchable>
    </Fragment>
  );
};
