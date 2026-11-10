-- hippie -- a round's runtimes, one row a file and line (hippiestation/code/modules/stats/round_history.dm)
CREATE TABLE IF NOT EXISTS `runtime` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `round_id` int(11) unsigned NOT NULL,
  `file` varchar(255) NOT NULL,
  `line` int(11) unsigned NOT NULL,
  `message` varchar(512) NOT NULL,
  `count` int(11) unsigned NOT NULL,
  `first_seen` int(11) unsigned NOT NULL COMMENT 'seconds into the round',
  PRIMARY KEY (`id`),
  KEY `idx_runtime_round` (`round_id`),
  KEY `idx_runtime_site` (`file`(191), `line`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
