PRAGMA foreign_keys = 1;
-- sqlite supports ddls inside of transactions

BEGIN;

CREATE TABLE urgency (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT,
  `name` varchar(255) NOT NULL,
  `value` int unsigned NOT NULL,
  `added` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (`name` BETWEEN 'a' AND 'z'),
  CHECK (`value` BETWEEN 0 AND 10)
);
CREATE UNIQUE INDEX urgency_name ON urgency (name);

CREATE TABLE tag (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT,
  `name` varchar(255) NOT NULL,
  `added` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CHECK (`name` BETWEEN 'a' AND 'z')
);
CREATE UNIQUE INDEX tag_name ON tag (name);

CREATE TABLE task (
  `id` integer PRIMARY KEY AUTOINCREMENT,
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
  `id` INTEGER PRIMARY KEY AUTOINCREMENT,
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
  `id` INTEGER PRIMARY KEY AUTOINCREMENT,
  `name` varchar(255) NOT NULL,
  `value` varchar(255)
);
CREATE UNIQUE INDEX setting_name ON setting (name);

CREATE TABLE task_log (
  `id` INTEGER PRIMARY KEY AUTOINCREMENT,
  `task_id` int NOT NULL,
  `change` varchar(255) NOT NULL,
  `value` varchar(255),
  CHECK (`change` IN ('created', 'started', 'paused', 'finished', 'duration_updated')),
  FOREIGN KEY (`task_id`) REFERENCES task(`id`)
);
CREATE INDEX task_log_task_id ON task_log (`task_id`);

INSERT INTO setting (`name`, `value`)
VALUES
  ('version', 1),
  ('db_created', CURRENT_TIMESTAMP);

INSERT INTO urgency (`name`, `value`)
VALUES
  ('backlog', 0),
  ('low', 3),
  ('normal', 5),
  ('high', 7),
  ('immediate', 10);

COMMIT;
