import { Component, Fragment } from 'inferno';
import { useBackend } from '../backend';
import { Box, Button, Dropdown, Icon, LabeledList, NoticeBox, Section, Table } from '../components';

// hippie -- the library's computers
// (hippiestation/code/modules/library/library_tgui.dm)

const FIELD = {
  'background-color': 'rgba(0, 0, 0, 0.4)',
  'color': '#ffffff',
  'border': '1px solid #404b6e',
  'padding': '3px',
  'box-sizing': 'border-box',
};

const ROW = { 'display': 'flex', 'align-items': 'center' };

const ENTRY = Object.assign({ 'padding': '3px 2px' }, ROW);

const BADGE = {
  'background-color': '#bd2020',
  'color': '#ffffff',
  'border-radius': '8px',
  'padding': '0 5px',
};

const TextBox = props => (
  <input
    value={props.value}
    placeholder={props.placeholder}
    maxLength={props.maxLength || 64}
    onInput={e => props.onInput(e.target.value)}
    onKeyDown={e => {
      if (e.keyCode === 13 && props.onEnter) {
        props.onEnter();
      }
    }}
    style={Object.assign({ 'width': props.width || '100%' }, FIELD)} />
);

const NoArchive = () => (
  <NoticeBox>
    Unable to contact the External Archive. Please contact your system
    administrator for assistance.
  </NoticeBox>
);

const BookTable = props => {
  const { books, act } = props;
  return (
    <Table>
      <Table.Row header>
        <Table.Cell>Title</Table.Cell>
        <Table.Cell>Author</Table.Cell>
        <Table.Cell>Category</Table.Cell>
        <Table.Cell collapsing>SS13BN</Table.Cell>
        {!!act && <Table.Cell collapsing />}
      </Table.Row>
      {books.map(book => (
        <Table.Row key={book.id} className="candystripe">
          <Table.Cell>{book.title}</Table.Cell>
          <Table.Cell color="label">{book.author}</Table.Cell>
          <Table.Cell color="label">{book.category}</Table.Cell>
          <Table.Cell collapsing>{book.id}</Table.Cell>
          {!!act && (
            <Table.Cell collapsing>
              <Button
                icon="print"
                content="Order"
                onClick={() => act('order', { id: book.id })} />
            </Table.Cell>
          )}
        </Table.Row>
      ))}
    </Table>
  );
};

// ---------------------------------------------------------------------------
// The librarian's console
// ---------------------------------------------------------------------------

class Checkouts extends Component {
  constructor() {
    super();
    this.state = { book: '', who: '' };
  }

  render() {
    const { data, act } = this.props;
    const out = data.checkouts || [];
    const commit = () => {
      if (!this.state.book || !this.state.who) {
        return;
      }
      act('checkout', { book: this.state.book, who: this.state.who });
      this.setState({ book: '', who: '' });
    };
    return (
      <Fragment>
        <Section title="Check out a book">
          <LabeledList>
            <LabeledList.Item label="Book">
              <TextBox
                value={this.state.book}
                placeholder="The book's title"
                onInput={book => this.setState({ book })} />
            </LabeledList.Item>
            <LabeledList.Item label="Recipient">
              <TextBox
                value={this.state.who}
                placeholder="Who's borrowing it"
                maxLength={42}
                onInput={who => this.setState({ who })}
                onEnter={commit} />
            </LabeledList.Item>
            <LabeledList.Item label="For">
              <Button
                icon="minus"
                disabled={data.period <= 1}
                onClick={() => act('period', { by: -1 })} />
              <Box inline mx={1} bold>
                {data.period + ' minute' + (data.period === 1 ? '' : 's')}
              </Box>
              <Button icon="plus" onClick={() => act('period', { by: 1 })} />
            </LabeledList.Item>
          </LabeledList>
          <Button
            mt={1}
            icon="book"
            content="Commit entry"
            disabled={!this.state.book || !this.state.who}
            onClick={commit} />
        </Section>
        <Section title={'Checked out (' + out.length + ')'}>
          {out.length === 0 && <Box color="label">Nothing is out.</Box>}
          {out.map(entry => (
            <Box key={entry.ref} className="candystripe" style={ENTRY}>
              <Box style={{ 'flex-grow': 1 }}>
                <Box bold>{'"' + entry.book + '"'}</Box>
                <Box color="label" fontSize="11px">
                  {'To ' + entry.who + ', ' + entry.taken + ' min ago. '}
                  {!entry.overdue && 'Due in ' + entry.due + ' min.'}
                  {!!entry.overdue && (
                    <Box inline color="bad" bold>OVERDUE</Box>
                  )}
                </Box>
              </Box>
              <Button
                icon="undo"
                content="Check in"
                onClick={() => act('checkin', { ref: entry.ref })} />
            </Box>
          ))}
        </Section>
      </Fragment>
    );
  }
}

class Archive extends Component {
  constructor() {
    super();
    this.state = { search: '', id: '' };
  }

  render() {
    const { data, act } = this.props;
    const archive = data.archive;
    if (!archive) {
      return (
        <Section>
          <NoArchive />
          <Button
            icon="sync"
            content="Try again"
            onClick={() => act('refresh_archive')} />
        </Section>
      );
    }
    const search = this.state.search.trim().toLowerCase();
    let shown = archive;
    if (search) {
      shown = archive.filter(book => (
        (book.title || '').toLowerCase().includes(search)
        || (book.author || '').toLowerCase().includes(search)
        || (book.category || '').toLowerCase().includes(search)));
    }
    const total = shown.length;
    shown = shown.slice(0, 100);
    return (
      <Section
        title={'External Archive (' + archive.length + ' books)'}
        buttons={(
          <Button
            icon="sync"
            content="Refresh"
            onClick={() => act('refresh_archive')} />
        )}>
        <Box mb={1} style={ROW}>
          <Icon name="search" mr={0.5} />
          <TextBox
            value={this.state.search}
            placeholder="Search titles, authors and categories..."
            onInput={value => this.setState({ search: value })} />
        </Box>
        <Box mb={1} style={ROW}>
          <Box color="label" mr={1}>Order by SS13BN</Box>
          <TextBox
            width="80px"
            value={this.state.id}
            maxLength={8}
            onInput={value => this.setState({ id: value })} />
          <Button
            ml={0.5}
            icon="print"
            content="Order"
            disabled={!/^\d+$/.test(this.state.id)}
            onClick={() => act('order', { id: this.state.id })} />
          {data.cooldown > 0 && (
            <Box ml={1} color="average">
              {'Printer ready in ' + data.cooldown + 's'}
            </Box>
          )}
        </Box>
        {total === 0 && <Box color="label">Nothing matches.</Box>}
        {total > 0 && <BookTable books={shown} act={act} />}
        {total > 100 && (
          <Box color="label" mt={0.5}>
            {'Showing 100 of ' + total + '. Search to narrow it down.'}
          </Box>
        )}
      </Section>
    );
  }
}

class Publishing extends Component {
  constructor() {
    super();
    this.state = { author: '', sure: false };
  }

  render() {
    const { data, act } = this.props;
    const scanned = data.scanned;
    if (!data.scanner) {
      return (
        <Section>
          <NoticeBox>No scanner found within wireless network range.</NoticeBox>
        </Section>
      );
    }
    if (!scanned) {
      return (
        <Section>
          <Box color="label">
            No data in the scanner&apos;s memory. Put a book in the scanner and
            scan it.
          </Box>
        </Section>
      );
    }
    return (
      <Section title={'Scanned: ' + scanned.title}>
        <LabeledList>
          <LabeledList.Item label="Author">
            <Box style={ROW}>
              <TextBox
                value={this.state.author}
                placeholder={scanned.author}
                maxLength={42}
                onInput={author => this.setState({ author })}
                onEnter={() => act('author', { author: this.state.author })} />
              <Button
                ml={0.5}
                content="Set"
                disabled={!this.state.author}
                onClick={() => act('author', { author: this.state.author })} />
            </Box>
          </LabeledList.Item>
          <LabeledList.Item label="Category">
            <Dropdown
              key={data.upload_category}
              width="160px"
              options={data.upload_categories || []}
              selected={data.upload_category}
              onSelected={category => act('category', { category })} />
          </LabeledList.Item>
        </LabeledList>
        <Box mt={1}>
          {!data.connected && <NoArchive />}
          {!this.state.sure && (
            <Button
              icon="upload"
              content="Upload to the Archive"
              disabled={!data.connected}
              onClick={() => this.setState({ sure: true })} />
          )}
          {!!this.state.sure && (
            <Button
              icon="exclamation-triangle"
              color="average"
              content="Sure? Upload it"
              onClick={() => {
                act('upload');
                this.setState({ sure: false });
              }} />
          )}
          <Button
            icon="newspaper"
            content="Post to the newscasters"
            tooltip="As a story on the Nanotrasen Book Club channel"
            onClick={() => act('newspost')} />
        </Box>
      </Section>
    );
  }
}

const Printing = props => {
  const { data, act } = props;
  const waiting = data.cooldown > 0;
  return (
    <Section title="NTGanda(tm) Universal Printing Module">
      {waiting && (
        <Box mb={1} color="average">
          {'The printer will be ready in ' + data.cooldown + 's.'}
        </Box>
      )}
      <Button
        icon="bible"
        content="Print a Bible"
        disabled={waiting}
        onClick={() => act('printbible')} />
      <Button
        icon="scroll"
        content="Print a poster"
        disabled={waiting}
        onClick={() => act('printposter')} />
      {!!data.emagged && (
        <Box mt={2}>
          <Box bold color="bad" mb={0.5}>
            Forbidden Lore Vault v 1.3
          </Box>
          <Box color="label" mb={0.5}>
            EldritchRelics Inc. takes no responsibility for loss of sanity
            resulting from this action.
          </Box>
          <Button
            icon="skull"
            color="bad"
            content="Access the vault"
            onClick={() => act('forbidden')} />
        </Box>
      )}
    </Section>
  );
};

class LibraryConsoleMenu extends Component {
  constructor() {
    super();
    this.state = { tab: 'inventory' };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const tabs = [
      ['inventory', 'Inventory', 'book'],
      ['checkouts', 'Checked out', 'user-clock'],
      ['archive', 'External Archive', 'archive'],
      ['publish', 'Upload & post', 'upload'],
      ['print', 'Print', 'print'],
    ];
    const inventory = data.inventory || [];
    let body;
    if (this.state.tab === 'inventory') {
      body = (
        <Section title={'Inventory (' + inventory.length + ')'}>
          {inventory.length === 0 && (
            <Box color="label">
              Nothing logged. Scan books in with the barcode scanner.
            </Box>
          )}
          {inventory.map(book => (
            <Box key={book.ref} className="candystripe" style={ENTRY}>
              <Box style={{ 'flex-grow': 1 }}>{book.name}</Box>
              <Button
                icon="trash"
                color="transparent"
                tooltip="Take it off the inventory"
                tooltipPosition="left"
                onClick={() => act('delbook', { ref: book.ref })} />
            </Box>
          ))}
        </Section>
      );
    }
    else if (this.state.tab === 'checkouts') {
      body = <Checkouts data={data} act={act} />;
    }
    else if (this.state.tab === 'archive') {
      body = <Archive data={data} act={act} />;
    }
    else if (this.state.tab === 'publish') {
      body = <Publishing data={data} act={act} />;
    }
    else {
      body = <Printing data={data} act={act} />;
    }
    const overdue = (data.checkouts || []).filter(e => e.overdue).length;
    return (
      <Fragment>
        <Box mb={1}>
          {tabs.map(tab => (
            <Button
              key={tab[0]}
              icon={tab[2]}
              selected={this.state.tab === tab[0]}
              onClick={() => this.setState({ tab: tab[0] })}>
              {tab[1]}
              {tab[0] === 'checkouts' && overdue > 0 && (
                <Box inline ml={0.5} bold style={BADGE}>{overdue}</Box>
              )}
            </Button>
          ))}
        </Box>
        {body}
      </Fragment>
    );
  }
}

export const LibraryConsole = props => (
  <LibraryConsoleMenu state={props.state} dispatch={props.dispatch} />
);

// ---------------------------------------------------------------------------
// The visitor console
// ---------------------------------------------------------------------------

class LibraryVisitorMenu extends Component {
  constructor(props) {
    super(props);
    const { data } = useBackend(props);
    this.state = {
      title: data.title || '',
      author: data.author || '',
      category: data.category || 'Any',
    };
  }

  render() {
    const { act, data } = useBackend(this.props);
    const search = () => act('search', {
      title: this.state.title,
      author: this.state.author,
      category: this.state.category,
    });
    const results = data.results || [];
    return (
      <Fragment>
        <Section title="Search the Archive">
          <LabeledList>
            <LabeledList.Item label="Title">
              <TextBox
                value={this.state.title}
                placeholder="Any"
                onInput={title => this.setState({ title })}
                onEnter={search} />
            </LabeledList.Item>
            <LabeledList.Item label="Author">
              <TextBox
                value={this.state.author}
                placeholder="Any"
                onInput={author => this.setState({ author })}
                onEnter={search} />
            </LabeledList.Item>
            <LabeledList.Item label="Category">
              <Dropdown
                key={this.state.category}
                width="160px"
                options={data.categories || []}
                selected={this.state.category}
                onSelected={category => this.setState({ category })} />
            </LabeledList.Item>
          </LabeledList>
          <Button mt={1} icon="search" content="Search" onClick={search} />
        </Section>
        {!data.connected && <NoArchive />}
        {!!data.searched && !!data.connected && (
          <Section title={'Found ' + results.length}>
            {results.length === 0 && <Box color="label">Nothing.</Box>}
            {results.length > 0 && <BookTable books={results} />}
          </Section>
        )}
      </Fragment>
    );
  }
}

export const LibraryVisitor = props => (
  <LibraryVisitorMenu state={props.state} dispatch={props.dispatch} />
);

// ---------------------------------------------------------------------------
// The book scanner
// ---------------------------------------------------------------------------

export const LibraryScanner = props => {
  const { act, data } = useBackend(props);
  return (
    <Section>
      <LabeledList>
        <LabeledList.Item label="In the scanner">
          {data.inside || <Box inline color="label">Nothing</Box>}
        </LabeledList.Item>
        <LabeledList.Item label="In memory">
          {!data.cache && <Box inline color="label">Nothing</Box>}
          {!!data.cache && (
            <Box inline color="good">
              {data.cache.title + ' by ' + data.cache.author}
            </Box>
          )}
        </LabeledList.Item>
      </LabeledList>
      <Box mt={1}>
        <Button
          icon="barcode"
          content="Scan"
          disabled={!data.inside}
          onClick={() => act('scan')} />
        <Button
          icon="eraser"
          content="Clear memory"
          disabled={!data.cache}
          onClick={() => act('clear')} />
        <Button
          icon="eject"
          content="Remove book"
          disabled={!data.inside}
          onClick={() => act('eject')} />
      </Box>
    </Section>
  );
};
