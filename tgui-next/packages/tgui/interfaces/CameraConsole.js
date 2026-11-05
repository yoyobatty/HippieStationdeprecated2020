import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, ByondUi, Icon, Input } from '../components';

// hippie -- the camera console (hippiestation/code/game/machinery/computer/
// camera_tgui.dm), after tgstation's of 2020: the cameras down the left,
// grouped by area and searchable by name or area, and the picture from the one
// picked in a map drawn in the window. The old console asked in a pop-up
// list and moved your whole view to the camera.

export class CameraConsole extends Component {
  constructor() {
    super();
    this.state = { search: '' };
  }

  render() {
    const { act, data, config } = useBackend(this.props);
    const { search } = this.state;
    const { mapRef, activeCamera } = data;
    const term = search.toLowerCase();
    const cameras = (data.cameras || [])
      .filter(camera => !term
        || camera.name.toLowerCase().includes(term)
        || (camera.area || '').toLowerCase().includes(term))
      .sort((a, b) => (a.area || '').localeCompare(b.area || '')
        || a.name.localeCompare(b.name));
    const groups = [];
    const byName = {};
    for (let camera of cameras) {
      const group = camera.area || 'Elsewhere';
      if (!byName[group]) {
        byName[group] = [];
        groups.push(group);
      }
      byName[group].push(camera);
    }
    const ordered = groups.reduce((all, group) => all.concat(byName[group]),
      []);
    const index = activeCamera
      ? ordered.findIndex(camera => camera.name === activeCamera.name)
      : -1;
    const step = offset => {
      if (!ordered.length) {
        return;
      }
      const next = ordered[(index + offset + ordered.length)
        % ordered.length];
      act('switch_camera', { name: next.name });
    };
    return (
      <Fragment>
        <div className="CameraConsole__left">
          <Input
            fluid
            mb={1}
            placeholder="Search cameras..."
            value={search}
            onInput={(e, value) => this.setState({ search: value })} />
          {cameras.length === 0 && (
            <Box color="label">No cameras match that.</Box>
          )}
          {groups.map(group => (
            <Box key={group} mb={1}>
              <Box bold color="label" mb={0.5}>{group}</Box>
              {byName[group].map(camera => (
                <Button
                  key={camera.name}
                  fluid
                  ellipsis
                  icon={camera.on ? 'video' : 'video-slash'}
                  color="transparent"
                  selected={activeCamera && activeCamera.name === camera.name}
                  content={camera.name}
                  onClick={() => act('switch_camera', { name: camera.name })} />
              ))}
            </Box>
          ))}
        </div>
        <div className="CameraConsole__right">
          <div className="CameraConsole__toolbar">
            {activeCamera && (
              <Fragment>
                <Icon
                  name="circle"
                  mr={1}
                  color={activeCamera.status ? 'bad' : 'label'} />
                <b>{activeCamera.name}</b>
                {!activeCamera.status && (
                  <Box inline color="bad" ml={1}>No signal</Box>
                )}
              </Fragment>
            ) || (
              <Box inline color="label">Pick a camera</Box>
            )}
            <span className="CameraConsole__toolbarRight">
              <Button
                icon="chevron-left"
                tooltip="Previous camera"
                onClick={() => step(-1)} />
              <Button
                icon="chevron-right"
                tooltip="Next camera"
                onClick={() => step(1)} />
            </span>
          </div>
          <ByondUi
            className="CameraConsole__map"
            params={{
              id: mapRef,
              parent: config.window,
              type: 'map',
              'background-color': '#000000',
            }} />
        </div>
      </Fragment>
    );
  }
}
