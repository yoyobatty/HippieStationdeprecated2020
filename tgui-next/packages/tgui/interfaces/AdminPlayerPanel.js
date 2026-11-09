import { Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Icon, LabeledList, NoticeBox, Section } from '../components';

// hippie -- the admin player options panel: who it is, then the old page's
// links in sections. Each button is the link it was (admin token added on the
// server). Data from hippiestation/code/modules/admin/player_panel_tgui.dm.

const LinkButton = props => {
  const { item, act } = props;
  if (!item.params) {
    return (
      <Button content={item.label} icon={item.icon} disabled
        className="AdminPP__current" />
    );
  }
  return (
    <Button
      content={item.label}
      icon={item.icon}
      color={item.color || null}
      onClick={() => act('link', { kind: item.kind, params: item.params })} />
  );
};

export const AdminPlayerPanel = props => {
  const { act, data } = useBackend(props);
  if (data.gone) {
    return <NoticeBox>That mob doesn&#39;t exist any more.</NoticeBox>;
  }
  const sections = data.sections || [];
  const player = sections.find(s => s.name === 'Player');
  const rest = sections.filter(s => s.name !== 'Player');
  return (
    <Fragment>
      <div className="AdminPP__head">
        <div className="AdminPP__name">
          {data.name}
          {data.real_name && data.real_name !== data.name && (
            <span className="AdminPP__muted"> ({data.real_name})</span>
          )}
        </div>
        <div className="AdminPP__line">
          {data.client
            ? (
              <Fragment>
                <Icon name="user" /> {data.client}
              </Fragment>
            )
            : (
              <span className="AdminPP__muted">
                <Icon name="user-slash" />
                {data.key ? ' ' + data.key + ' (disconnected)' : ' No key'}
              </span>
            )}
          {!!data.job && <span> · {data.job}</span>}
          {!!data.special_role && (
            <span className="AdminPP__role"> · {data.special_role}</span>
          )}
          {!!data.newplayer && (
            <span className="AdminPP__muted"> · in the lobby</span>
          )}
          {!!data.dead && <span className="AdminPP__dead"> · dead</span>}
        </div>
        <div className="AdminPP__type">{data.type}</div>
      </div>
      {!!data.related && (
        <NoticeBox danger>Player has related accounts</NoticeBox>
      )}
      {player && (
        <Section title="Player">
          {!!data.client && (
            <LabeledList>
              <LabeledList.Item label="First seen">
                {data.first_seen}
              </LabeledList.Item>
              <LabeledList.Item label="BYOND account">
                {data.account_date}
              </LabeledList.Item>
              <LabeledList.Item label="Country">
                {data.country}
              </LabeledList.Item>
              <LabeledList.Item label="BYOND version">
                {data.byond}
              </LabeledList.Item>
              <LabeledList.Item label="Antag reputation">
                <Box inline bold mr={1}>{data.antag_rep}</Box>
                {(data.rep_links || []).map(item => (
                  <LinkButton key={item.label} item={item} act={act} />
                ))}
              </LabeledList.Item>
            </LabeledList>
          )}
          <Box mt={1}>
            {player.links.map(item => (
              <LinkButton key={item.label} item={item} act={act} />
            ))}
          </Box>
        </Section>
      )}
      {rest.map(section => (
        <Section key={section.name} title={section.name}>
          {!!section.note && (
            <Box color="label" mb={1}>{section.note}</Box>
          )}
          {section.style === 'mutes'
            ? section.links.map(item => (
              item.on === undefined
                ? <LinkButton key={item.label} item={item} act={act} />
                : (
                  <Button.Checkbox
                    key={item.label}
                    checked={item.on}
                    color={item.on ? 'bad' : null}
                    content={item.label}
                    onClick={() => act('link',
                      { kind: item.kind, params: item.params })} />
                )
            ))
            : section.links.map(item => (
              <LinkButton key={item.label} item={item} act={act} />
            ))}
        </Section>
      ))}
    </Fragment>
  );
};
