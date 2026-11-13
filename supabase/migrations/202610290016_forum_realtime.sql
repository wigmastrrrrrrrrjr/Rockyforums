-- this was created by an AI agent
-- Enable Supabase Realtime change feeds for forum tables so clients can receive
-- live updates when new threads or replies are created, edited, or removed.
-- RLS continues to apply: subscribers only receive rows they are allowed to read.
alter publication supabase_realtime add table forum_private.threads, forum_private.replies;
