INSERT INTO task  (
  `id`,
  `title`,
  `task_state_id`,
  `date`,
  `start`,
  `backlink`,
  `project_id`,
  `issue_link`,
  `urgency_id`
)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);

INSERT INTO task_log (task_id, state_id)
SELECT
  ? AS task_id,
  (SELECT id FROM task_log_state WHERE name = 'created')
