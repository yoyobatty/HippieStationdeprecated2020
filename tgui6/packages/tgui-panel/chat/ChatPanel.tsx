/**
 * @file
 * @copyright 2020 Aleksej Komarov
 * @license MIT
 */

import { useAtom, useAtomValue } from 'jotai';
import { useEffect, useRef } from 'react';
import { Button } from 'tgui-core/components';
import {
  chatPagesRecordAtom,
  currentPageIdAtom,
  scrollTrackingAtom,
} from './atom';
import { hippieNewCountAtom, setTimestampsShown } from '../hippie/extras';
import { chatRenderer } from './renderer';
import type { Page } from './types';

type Props = {
  fontSize?: string;
  lineHeight: string | number;
  timestamps?: boolean;
};

export function ChatPanel(props: Props) {
  const ref = useRef<HTMLDivElement>(null);
  const scrollTracking = useAtomValue(scrollTrackingAtom);
  // Page stuff
  const currentPageId = useAtomValue(currentPageIdAtom);
  const [pagesRecord, setPagesRecord] = useAtom(chatPagesRecordAtom);

  /** Mounts the renderer */
  useEffect(() => {
    if (ref.current) {
      chatRenderer.mount(ref.current);
    }
  }, []);

  /** Resets unread count when scroll tracking is enabled */
  useEffect(() => {
    if (scrollTracking) {
      const draft: Page = {
        ...pagesRecord[currentPageId],
        unreadCount: 0,
      };

      setPagesRecord({
        ...pagesRecord,
        [currentPageId]: draft,
      });
    }
  }, [scrollTracking]);

  /** Updates the style of the chat panel */
  useEffect(() => {
    chatRenderer.assignStyle({
      width: '100%',
      'white-space': 'pre-wrap',
      'font-size': props.fontSize,
      'line-height': props.lineHeight,
    });
  }, [props.fontSize, props.lineHeight]);

  // hippie -- time stamps, from the setting
  useEffect(() => {
    setTimestampsShown(chatRenderer.rootNode, !!props.timestamps);
  }, [props.timestamps]);

  // hippie -- "12 new" while scrolled up; nothing scrolls away while reading
  const newCount = useAtomValue(hippieNewCountAtom);

  return (
    <>
      <div className="Chat" ref={ref} />
      {!scrollTracking && (
        <Button
          className={`Chat__scrollButton${newCount ? ' Hippie__newPill' : ''}`}
          icon="arrow-down"
          onClick={() => chatRenderer.scrollToBottom()}
        >
          {newCount ? `${newCount} new` : 'Scroll to bottom'}
        </Button>
      )}
    </>
  );
}
