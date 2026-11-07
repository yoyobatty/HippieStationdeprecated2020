import { Component } from 'inferno';

// hippie -- every name is a link: a player's name in an admin window opens
// the same small menu (Profile, PP, VV, FLW, PM, SM, Logs, Jump). The
// window's ui_act hands "player_menu" to player_menu_act()
// (hippiestation/code/modules/admin/player_menu.dm). who: { name, ckey,
// ref, mob }: a ckey alone is enough (the server finds their body).

const ITEMS = [
  ['profile', 'Profile', w => !!w.ckey],
  ['pp', 'Player panel', w => !!w.mob || (!w.ref && !!w.ckey)],
  ['vv', 'View variables', w => !!w.ref || !!w.ckey],
  ['flw', 'Follow', w => !!w.ref || !!w.ckey],
  ['pm', 'PM', w => !!w.ckey],
  ['sm', 'Subtle message', w => !!w.mob || (!w.ref && !!w.ckey)],
  ['logs', 'Logs', w => !!w.ckey || !!w.name],
  ['jmp', 'Jump to', w => !!w.ref || !!w.ckey],
];

const MENU_WIDTH = 150;
const MENU_HEIGHT = 230;

// One menu open at a time, whichever window part it's in
let openLink = null;

// Esc in the admin hub (AdminHub.js)
export const closePlayerMenus = () => {
  if (openLink) {
    openLink.close();
  }
};

export class PlayerLink extends Component {
  constructor() {
    super();
    this.state = { open: false, x: 0, y: 0 };
    this.onDocDown = e => {
      if (this.menu && this.menu.contains(e.target)) {
        return;
      }
      if (this.link && this.link.contains(e.target)) {
        return;
      }
      this.close();
    };
  }

  componentWillUnmount() {
    document.removeEventListener('mousedown', this.onDocDown);
    if (openLink === this) {
      openLink = null;
    }
  }

  open(e) {
    const rect = e.currentTarget.getBoundingClientRect();
    if (openLink && openLink !== this) {
      openLink.close();
    }
    openLink = this;
    const below = rect.bottom + 2;
    const y = below + MENU_HEIGHT > window.innerHeight
      ? Math.max(4, rect.top - MENU_HEIGHT - 2)
      : below;
    const x = Math.max(4, Math.min(rect.left, window.innerWidth - MENU_WIDTH));
    this.setState({ open: true, x, y });
    document.addEventListener('mousedown', this.onDocDown);
  }

  close() {
    document.removeEventListener('mousedown', this.onDocDown);
    if (openLink === this) {
      openLink = null;
    }
    this.setState({ open: false });
  }

  render() {
    const { act, who, showCkey, className } = this.props;
    if (!who || (!who.name && !who.ckey)) {
      return null;
    }
    const { open, x, y } = this.state;
    const label = (who.name || who.ckey)
      + (showCkey && who.ckey && who.name ? ' (' + who.ckey + ')' : '');
    return (
      <span className={'PlayerLink' + (className ? ' ' + className : '')}>
        <span
          ref={el => {
            this.link = el;
          }}
          className={'PlayerLink__name'
            + (open ? ' PlayerLink__name--open' : '')}
          title="Click for Profile, PP, VV, FLW, PM, Logs..."
          onClick={e => {
            e.stopPropagation();
            if (open) {
              this.close();
            }
            else {
              this.open(e);
            }
          }}>
          {label}
        </span>
        {open && (
          <div
            ref={el => {
              this.menu = el;
            }}
            className="PlayerLink__menu"
            style={{ left: x + 'px', top: y + 'px' }}
            onClick={e => e.stopPropagation()}>
            <div className="PlayerLink__head">
              {who.name || who.ckey}
              {!!who.ckey && !!who.name && (
                <span className="PlayerLink__ckey">{who.ckey}</span>
              )}
            </div>
            {ITEMS.filter(item => item[2](who)).map(item => (
              <div key={item[0]}
                className="PlayerLink__item"
                onClick={() => {
                  act('player_menu', {
                    what: item[0],
                    ckey: who.ckey || '',
                    ref: who.ref || '',
                  });
                  this.close();
                }}>
                {item[1]}
              </div>
            ))}
          </div>
        )}
      </span>
    );
  }
}
