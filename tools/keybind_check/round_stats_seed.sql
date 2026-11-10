-- Round 4's page for tools/keybind_check/round_stats_shots.dm: its antagonists with their objectives, the round-end numbers and its
-- runtimes, as the blackbox and round_history.dm would have left them. Run as root into the shots database (hippie_stats):
--   mariadb -P3307 -uroot -p... hippie_stats < tools/keybind_check/round_stats_seed.sql
CREATE TABLE IF NOT EXISTS `SS13_runtime` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `round_id` int(11) unsigned NOT NULL,
  `file` varchar(255) NOT NULL,
  `line` int(11) unsigned NOT NULL,
  `message` varchar(512) NOT NULL,
  `count` int(11) unsigned NOT NULL,
  `first_seen` int(11) unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_runtime_round` (`round_id`),
  KEY `idx_runtime_site` (`file`(191), `line`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DELETE FROM `SS13_feedback` WHERE round_id = 4 AND key_name IN ('antagonists', 'round_end_stats');
DELETE FROM `SS13_runtime` WHERE round_id IN (3, 4, 9, 12);

INSERT INTO `SS13_feedback` (datetime, round_id, key_name, version, key_type, json) VALUES
(NOW(), 4, 'antagonists', 1, 'associative', '{"data":{"1":{"key":"Shotsplayer","name":"Ray Dubois","antagonist_type":"/datum/antagonist/traitor","antagonist_name":"Traitor","objectives":[{"objective_type":"/datum/objective/assassinate","text":"Assassinate Mira Okafor, the Chemist.","result":"SUCCESS"},{"objective_type":"/datum/objective/steal","text":"Steal the captain''s antique laser gun.","result":"FAIL"},{"objective_type":"/datum/objective/escape","text":"Escape on the shuttle or an escape pod alive and without being in custody.","result":"FAIL"}],"team":[]},"2":{"key":"Otherkey","name":"Vic Sorrento","antagonist_type":"/datum/antagonist/traitor","antagonist_name":"Traitor","objectives":[{"objective_type":"/datum/objective/download","text":"Download at least 20 research nodes on a hacked PDA.","result":"SUCCESS"},{"objective_type":"/datum/objective/survive","text":"Stay alive until the end.","result":"SUCCESS"}],"team":[]}}}'),
(NOW(), 4, 'round_end_stats', 1, 'nested tally', '{"data":{"survivors":{"total":19},"escapees":{"total":14},"players":{"total":24,"dead":5}}}');

INSERT INTO `SS13_runtime` (round_id, file, line, message, count, first_seen) VALUES
(4, 'hippiestation/code/game/objects/effects/effect_system/effects_vapour.dm', 122, 'Cannot read null.volume', 5, 2410),
(4, 'code/modules/mob/living/carbon/human/say.dm', 41, 'list index out of bounds', 2, 1830),
(4, 'code/modules/reagents/chemistry/holder.dm', 512, 'Cannot read null.reagent_state', 1, 640),
(3, 'code/modules/mob/living/carbon/human/say.dm', 41, 'list index out of bounds', 1, 900),
(9, 'code/modules/mob/living/carbon/human/say.dm', 41, 'list index out of bounds', 3, 1205),
(12, 'code/game/objects/items/devices/radio/radio.dm', 360, 'Cannot read null.z', 7, 3010),
(12, 'hippiestation/code/game/objects/effects/effect_system/effects_vapour.dm', 122, 'Cannot read null.volume', 9, 2988);
