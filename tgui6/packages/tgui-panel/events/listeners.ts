import { loadStyleSheet } from 'common/assets';
import { EventBus } from 'tgui-core/eventbus';
import { playMusic, stopMusic } from '../audio/handlers';
import { chatMessage } from '../chat/handlers';
import { openNameMenu } from '../hippie/extras';
import { hippieAdmin, hippieHistory, hippieMessages } from '../hippie/handlers';
import { pingReply, pingSoft } from '../ping/handlers';
import {
  handleTelemetryData,
  telemetryRequest,
  testTelemetryCommand,
} from '../telemetry/handlers';
import {
  handleAddVerbs,
  handleClearCommandBar,
  handleFocusCommandBar,
  handleHotkeyMode,
  handleRemoveVerbs,
  handleTargets,
  handleVerbsInit,
} from '../verbs/handlers';
import { handleLoadAssets } from './handlers/assets';
import { playerSet } from './handlers/player';
import { roundrestart } from './handlers/roundrestart';

const listeners = {
  'hippie/messages': hippieMessages,
  'hippie/history': hippieHistory,
  'hippie/admin': hippieAdmin,
  'hippie/nameMenu': openNameMenu,
  'verbs/add': handleAddVerbs,
  'verbs/clear': handleClearCommandBar,
  'verbs/focus': handleFocusCommandBar,
  'verbs/init': handleVerbsInit,
  'verbs/remove': handleRemoveVerbs,
  'verbs/targets': handleTargets,
  'verbs/hotkey_mode': handleHotkeyMode,
  'asset/stylesheet': loadStyleSheet,
  'asset/mappings': handleLoadAssets,
  'audio/playMusic': playMusic,
  'audio/stopMusic': stopMusic,
  'chat/message': chatMessage,
  'player/set': playerSet,
  'ping/reply': pingReply,
  'ping/soft': pingSoft,
  roundrestart,
  'telemetry/request': telemetryRequest,
  testTelemetryCommand,
  update: handleTelemetryData,
} as const;

export const bus = new EventBus(listeners);
