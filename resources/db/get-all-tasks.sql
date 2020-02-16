SELECT
  id@n,
  title@s,
  task_state.name AS state@n,
  date@s,
  start@s,
  end@s,
  backlink AS backlink_id@n,
  forwardlink AS forwardlink_id@n,
  project.name AS project@s,
  issue_id@n,
  urgency@s,
  updated@s,
  duration@n,
  GROUP_CONCAT(tag.name) AS tags@ls
FROM
  task
  JOIN
    urgency
    ON (task.urgency_id = urgency.id)
  JOIN
    task_state
    ON (task.task_state_id = task_state.id)
  LEFT JOIN
    project
    ON (task.project_id = project.id)
  LEFT JOIN
    task_tags
    ON (task.id = task_tags.task_id)
  LEFT JOIN
    tag
    ON (tag.id = task_tags.tag_id)
GROUP BY
  task.id
LIMIT 10000
