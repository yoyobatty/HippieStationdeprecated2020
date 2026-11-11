/**
 * The components to drag in, by group, with a filter box. A click adds
 * one after the selected item instead of dragging.
 */

import { Component } from 'inferno';
import { COMPONENTS, GROUPS, labelOf } from '../shared/registry';

const HIDDEN = ['Grid.Column', 'Table.Cell', 'Flex.Item'];

export class Palette extends Component {
  constructor(props) {
    super(props);
    this.state = { filter: '' };
  }

  render() {
    const { onStartDrag, onAdd } = this.props;
    const filter = this.state.filter.trim().toLowerCase();
    const types = Object.keys(COMPONENTS).filter(type => {
      if (filter) {
        return (labelOf(type) + ' ' + type).toLowerCase().includes(filter);
      }
      return !HIDDEN.includes(type);
    });
    return (
      <div className="palette">
        <input
          className="palette__filter"
          placeholder="Find a component"
          value={this.state.filter}
          onInput={e => this.setState({ filter: e.target.value })} />
        {GROUPS.map(group => {
          const list = types.filter(t => COMPONENTS[t].group === group);
          if (!list.length) {
            return null;
          }
          return (
            <div key={group} className="palette__group">
              <div className="palette__groupTitle">{group}</div>
              <div className="palette__items">
                {list.map(type => (
                  <div
                    key={type}
                    className="palette__item"
                    title={'Drag into the window, or click to add after '
                      + 'the selection'}
                    onMouseDown={e => {
                      if (e.button === 0) {
                        e.preventDefault();
                        onStartDrag({ kind: 'new', type }, e.clientX,
                          e.clientY);
                      }
                    }}>
                    <i className={'fas fa-' + COMPONENTS[type].icon} />
                    <span>{labelOf(type)}</span>
                  </div>
                ))}
              </div>
            </div>
          );
        })}
      </div>
    );
  }
}
