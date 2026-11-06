import { decodeHtmlEntities } from 'common/string';
import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Section } from '../components';

// hippie -- books, the codex gigas's findings, photos, the chaplain's bible
// style and the mime's book moved off their old HTML windows. Data from
// hippiestation/code/modules/library/books_tgui.dm.

// The same HTML the old book window showed, on a page
const Page = props => (
  <div
    className="Books__page"
    // eslint-disable-next-line react/no-danger
    dangerouslySetInnerHTML={{ __html: props.html }} />
);

export const BookReader = props => {
  const { data } = useBackend(props);
  return (
    <Fragment>
      <Box className="Books__title">
        {decodeHtmlEntities(data.title || '')}
      </Box>
      {!!data.author && (
        <Box className="Books__author">
          Penned by {decodeHtmlEntities(data.author)}.
        </Box>
      )}
      <Page html={data.html} />
    </Fragment>
  );
};

export const PhotoViewer = props => {
  const { data } = useBackend(props);
  return (
    <Section>
      <div className="Books__photo">
        {!!data.image && (
          <img src={data.image} width="480px" />
        )}
      </div>
      {!!data.scribble && (
        <Box mt={1} textAlign="center">
          <Box color="label">Written on the back:</Box>
          <Box italic>{decodeHtmlEntities(data.scribble)}</Box>
        </Box>
      )}
    </Section>
  );
};

export const BibleStyle = props => {
  const { act, data } = useBackend(props);
  return (
    <Section title="Pick a bible style">
      <div className="Books__styles">
        {(data.styles || []).map(style => (
          <div
            key={style.index}
            className="Books__style"
            onClick={() => act('pick', { index: style.index })}>
            <img src={style.icon} width="64px" height="64px" />
            <Box fontSize="11px">{style.name}</Box>
          </div>
        ))}
      </div>
    </Section>
  );
};

const ROUTINES = [
  ['invisible_wall', 'Invisible Wall'],
  ['invisible_chair', 'Invisible Chair'],
  ['invisible_box', 'Invisible Box'],
];

export const MimeBook = props => {
  const { act } = useBackend(props);
  return (
    <Section>
      <Box className="Books__page" mb={1}>
        Teaches one of three classic pantomime routines, allowing a practiced
        mime to conjure invisible objects into corporeal existence.<br />
        Once you have mastered your routine, this book will have no more to
        say to you.
      </Box>
      {ROUTINES.map(routine => (
        <div
          key={routine[0]}
          className="Books__routine"
          onClick={() => act(routine[0])}>
          {routine[1]}
        </div>
      ))}
    </Section>
  );
};
