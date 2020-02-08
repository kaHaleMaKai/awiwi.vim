PRAGMA foreign_keys = 1;
-- sqlite supports ddls inside of transactions

BEGIN;

CREATE TABLE urgency (
  `id` int NOT NULL PRIMARY KEY,
  `name` varchar(255) NOT NULL,
  `value` int unsigned NOT NULL,
  `added` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (`name` BETWEEN 'a' AND 'z'),
  CHECK (`value` BETWEEN 0 AND 10)
);
CREATE UNIQUE INDEX urgency_name ON urgency (name);

CREATE TABLE tag (
  `id` int NOT NULL PRIMARY KEY,
  `name` varchar(255) NOT NULL,
  `added` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (`name` BETWEEN 'a' AND 'z')
);
CREATE UNIQUE INDEX tag_name ON tag (name);

CREATE TABLE task (
  `id` int NOT NULL PRIMARY KEY,
  `title` varchar(255) NOT NULL,
  `state` varchar(255) NOT NULL DEFAULT 'started',
  `date` date NOT NULL,
  `start` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `end` timestamp DEFAULT NULL,
  `backlink` integer DEFAULT NULL,
  `forwardlink` integer DEFAULT NULL,
  `urgency_id` int unsigned NOT NULL,
  `updated` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `duration` int unsigned NOT NULL DEFAULT '0',
  CHECK (`state` IN ('started', 'paused', 'done')),
  FOREIGN KEY (`urgency_id`) REFERENCES urgency(`id`)
);
CREATE UNIQUE INDEX task_title ON task (title, date);
CREATE INDEX task_state ON task (state);

CREATE TABLE task_tags (
  `id` int NOT NULL PRIMARY KEY,
  `task_id` int NOT NULL,
  `tag_id` int NOT NULL,
  FOREIGN KEY (`task_id`) REFERENCES task(`id`),
  FOREIGN KEY (`tag_id`) REFERENCES tag(`id`)
);

CREATE TRIGGER update_task_timestamp
  AFTER UPDATE
  ON task
FOR EACH ROW
BEGIN
  UPDATE task
  SET
    updated = CURRENT_TIMESTAMP
  WHERE
    new.id = old.id;
END;

CREATE TABLE setting (
  `id` int NOT NULL PRIMARY KEY,
  `name` varchar(255) NOT NULL,
  `value` varchar(255)
);
CREATE UNIQUE INDEX setting_name ON setting (name);

CREATE TABLE task_log (
  `id` integer PRIMARY KEY AUTOINCREMENT,
  `timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `task_id` int NOT NULL,
  `change` varchar(255) NOT NULL,
  CHECK (`change` IN (
    'created', 'restarted', 'paused', 'done', 'duration_updated',
    'forwardlink_added', 'backlink_added')),
  FOREIGN KEY (`task_id`) REFERENCES task(`id`)
);
CREATE INDEX task_log_task_id ON task_log (`task_id`);

INSERT INTO setting (`id`, `name`, `value`)
VALUES
  (1, 'version', 1),
  (2, 'db_created', CURRENT_TIMESTAMP);

INSERT INTO urgency (`id`, `name`, `value`)
VALUES
  (1, 'backlog', 0),
  (2, 'low', 3),
  (3, 'normal', 5),
  (4, 'high', 7),
  (5, 'immediate', 10);

COMMIT;
